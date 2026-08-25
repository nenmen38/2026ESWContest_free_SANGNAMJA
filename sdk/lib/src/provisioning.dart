// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:esp_provisioning_ble/esp_provisioning_ble.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_prov_transport.dart';
import 'errors.dart';
import 'provisioning_protocol.dart';

/// A nearby ESP device waiting for registration.
final class ProvisioningDevice {
  const ProvisioningDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;
}

/// All values required for one provisioning operation.
final class ProvisioningRequest {
  const ProvisioningRequest({
    required this.device,
    required this.pop,
    required this.wifiSsid,
    required this.wifiPassword,
    this.wifiBssid,
  });

  final ProvisioningDevice device;
  final String pop;
  final String wifiSsid;
  final String wifiPassword;
  final String? wifiBssid;
}

/// Result returned after both MQTT and Wi-Fi settings are accepted.
final class ProvisioningResult {
  const ProvisioningResult({this.deviceIp});
  final String? deviceIp;
}

/// Linear progress steps for one provisioning call.
enum ProvisioningStep {
  connecting,
  checkingProtocol,
  securing,
  applyingWifi,
  waitingForWifi,
  completed,
}

/// Small testable surface delegated to [EspProv] in production.
@visibleForTesting
abstract interface class ProvisioningClient {
  Future<EstablishSessionStatus> establishSession();
  Future<List<WifiAP>> scanWifi();
  Future<bool> sendWifiConfig({
    required String ssid,
    required String password,
    String? bssid,
  });
  Future<bool> applyWifiConfig();
  Future<ConnectionStatus> getStatus();
  Future<void> dispose();
}

final class _EspProvisioningClient implements ProvisioningClient {
  _EspProvisioningClient(ProvTransport transport, String pop)
    : _prov = EspProv(
        transport: transport,
        security: Security1(pop: pop),
      );

  final EspProv _prov;

  @override
  Future<EstablishSessionStatus> establishSession() => _prov.establishSession();
  @override
  Future<List<WifiAP>> scanWifi() => _prov.startScanWiFi();
  @override
  Future<bool> sendWifiConfig({
    required String ssid,
    required String password,
    String? bssid,
  }) => _prov.sendWifiConfig(ssid: ssid, password: password, bssid: bssid);
  @override
  Future<bool> applyWifiConfig() => _prov.applyWifiConfig();
  @override
  Future<ConnectionStatus> getStatus() => _prov.getStatus();
  @override
  Future<void> dispose() => _prov.dispose();
}

Future<T> _withProvisioningSession<T>({
  required ProvTransport transport,
  required String pop,
  required ProvisioningClient Function(ProvTransport, String) createClient,
  required Future<T> Function(ProvisioningClient) operation,
  Duration? timeout,
  void Function(ProvisioningStep)? onProgress,
}) async {
  ProvisioningClient? client;
  Future<R> wait<R>(Future<R> future) =>
      timeout == null ? future : future.timeout(timeout);
  try {
    onProgress?.call(ProvisioningStep.connecting);
    if (!await wait(transport.connect())) {
      throw const ProvisioningException(
        ProvisioningFailureCode.bleConnection,
        'Could not connect to the BLE provisioning service.',
      );
    }
    onProgress?.call(ProvisioningStep.checkingProtocol);
    try {
      verifyProvisioningInfo(
        await wait(
          transport.sendReceive(
            'proto-ver',
            Uint8List.fromList(utf8.encode('ESP')),
          ),
        ),
      );
    } on ProvisioningProtocolError catch (error) {
      throw ProvisioningException(
        ProvisioningFailureCode.incompatibleProtocol,
        error.message,
        error,
      );
    }
    client = createClient(transport, pop);
    onProgress?.call(ProvisioningStep.securing);
    final session = await wait(client.establishSession());
    if (session == EstablishSessionStatus.keymismatch) {
      throw const ProvisioningException(
        ProvisioningFailureCode.wrongPop,
        'The proof of possession is incorrect.',
      );
    }
    if (session != EstablishSessionStatus.connected) {
      throw const ProvisioningException(
        ProvisioningFailureCode.disconnected,
        'The BLE session was disconnected.',
      );
    }
    return await operation(client);
  } finally {
    if (client != null) {
      await client.dispose();
    } else {
      await transport.disconnect();
    }
  }
}

/// Package-driven provisioning workflow, exposed only for deterministic tests.
@visibleForTesting
final class ProvisioningWorkflow {
  const ProvisioningWorkflow._();

  static Future<ProvisioningResult> run({
    required ProvisioningRequest request,
    required ProvTransport transport,
    required ProvisioningClient Function(ProvTransport transport, String pop)
    createClient,
    void Function(ProvisioningStep step)? onProgress,
    Duration operationTimeout = const Duration(seconds: 10),
    Duration wifiTimeout = const Duration(seconds: 20),
    Duration pollInterval = const Duration(milliseconds: 500),
  }) async {
    if (request.pop.isEmpty) {
      throw const ProvisioningException(
        ProvisioningFailureCode.wrongPop,
        'PoP must not be empty.',
      );
    }
    if (request.wifiSsid.isEmpty) {
      throw const ProvisioningException(
        ProvisioningFailureCode.wifiRejected,
        'Wi-Fi SSID must not be empty.',
      );
    }
    try {
      return await _withProvisioningSession(
        transport: transport,
        pop: request.pop,
        createClient: createClient,
        timeout: operationTimeout,
        onProgress: onProgress,
        operation: (client) async {
          onProgress?.call(ProvisioningStep.applyingWifi);
          final accepted = await client
              .sendWifiConfig(
                ssid: request.wifiSsid,
                password: request.wifiPassword,
                bssid: request.wifiBssid,
              )
              .timeout(operationTimeout);
          if (!accepted ||
              !await client.applyWifiConfig().timeout(operationTimeout)) {
            throw const ProvisioningException(
              ProvisioningFailureCode.wifiRejected,
              'The device rejected the Wi-Fi settings.',
            );
          }

          onProgress?.call(ProvisioningStep.waitingForWifi);
          final deadline = DateTime.now().add(wifiTimeout);
          while (DateTime.now().isBefore(deadline)) {
            final status = await client.getStatus().timeout(operationTimeout);
            switch (status.state) {
              case WifiConnectionState.Connected:
                onProgress?.call(ProvisioningStep.completed);
                return ProvisioningResult(deviceIp: status.deviceIp);
              case WifiConnectionState.ConnectionFailed:
                if (status.failedReason == WifiConnectFailedReason.AuthError) {
                  throw const ProvisioningException(
                    ProvisioningFailureCode.wifiAuthentication,
                    'Wi-Fi authentication failed.',
                  );
                }
                if (status.failedReason ==
                    WifiConnectFailedReason.NetworkNotFound) {
                  throw const ProvisioningException(
                    ProvisioningFailureCode.wifiNotFound,
                    'The Wi-Fi network was not found.',
                  );
                }
                throw const ProvisioningException(
                  ProvisioningFailureCode.disconnected,
                  'The device could not join Wi-Fi.',
                );
              case WifiConnectionState.Disconnected:
                throw const ProvisioningException(
                  ProvisioningFailureCode.disconnected,
                  'The device disconnected while joining Wi-Fi.',
                );
              case WifiConnectionState.Connecting:
                await Future<void>.delayed(pollInterval);
            }
          }
          throw const ProvisioningException(
            ProvisioningFailureCode.timeout,
            'Timed out while waiting for Wi-Fi.',
          );
        },
      );
    } on ProvisioningException {
      rethrow;
    } on TimeoutException catch (error) {
      throw ProvisioningException(
        ProvisioningFailureCode.timeout,
        'A provisioning operation timed out.',
        error,
      );
    } on Object catch (error) {
      throw ProvisioningException(
        ProvisioningFailureCode.disconnected,
        'Provisioning communication failed.',
        error,
      );
    }
  }
}

/// Internal provisioning surface used by the high-level setup workflow.
abstract interface class ProvisioningBackend {
  Future<List<ProvisioningDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  });
  Future<List<WifiAP>> scanWifi({
    required ProvisioningDevice device,
    required String pop,
  });
  Future<ProvisioningResult> provision(
    ProvisioningRequest request, {
    void Function(ProvisioningStep step)? onProgress,
  });
  Future<void> dispose();
}

/// BLE discovery and registration adapter kept behind the public SDK facade.
final class EswProvisioner implements ProvisioningBackend {
  EswProvisioner({
    ProvTransport Function(BluetoothDevice device)? createTransport,
    ProvisioningClient Function(ProvTransport transport, String pop)?
    createClient,
  }) : _createTransport = createTransport ?? BleProvTransport.new,
       _createClient = createClient ?? _EspProvisioningClient.new;

  final ProvTransport Function(BluetoothDevice device) _createTransport;
  final ProvisioningClient Function(ProvTransport transport, String pop)
  _createClient;
  final Map<String, ScanResult> _scanResults = {};
  bool _busy = false;
  bool _disposed = false;

  @override
  Future<List<ProvisioningDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _checkAvailable();
    await _requestPermissions();
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    _scanResults.clear();
    final subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName;
        if (name.startsWith('PROV-MOTOR-') || name.startsWith('PROV-SENSOR-')) {
          _scanResults[result.device.remoteId.str] = result;
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        continuousUpdates: true,
        androidUsesFineLocation: false,
      );
      await Future<void>.delayed(timeout);
    } on Object catch (error) {
      throw ProvisioningException(
        ProvisioningFailureCode.bleConnection,
        'Could not scan for BLE devices.',
        error,
      );
    } finally {
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
    }
    final devices =
        _scanResults.values
            .map(
              (result) => ProvisioningDevice(
                id: result.device.remoteId.str,
                name: result.device.platformName,
                rssi: result.rssi,
              ),
            )
            .toList()
          ..sort((left, right) => right.rssi.compareTo(left.rssi));
    return List.unmodifiable(devices);
  }

  @override
  Future<List<WifiAP>> scanWifi({
    required ProvisioningDevice device,
    required String pop,
  }) => _exclusive(() async {
    final transport = _transportFor(device);
    try {
      return await _withProvisioningSession(
        transport: transport,
        pop: pop,
        createClient: _createClient,
        operation: (client) async {
          final networks = await client.scanWifi().timeout(
            const Duration(seconds: 30),
          );
          networks.sort((left, right) => left.compareTo(right));
          return List<WifiAP>.unmodifiable(networks);
        },
      );
    } on ProvisioningException {
      rethrow;
    } on TimeoutException catch (error) {
      throw ProvisioningException(
        ProvisioningFailureCode.timeout,
        'Wi-Fi scanning timed out.',
        error,
      );
    } on Object catch (error) {
      throw ProvisioningException(
        ProvisioningFailureCode.disconnected,
        'Wi-Fi scanning failed.',
        error,
      );
    }
  });

  @override
  Future<ProvisioningResult> provision(
    ProvisioningRequest request, {
    void Function(ProvisioningStep step)? onProgress,
  }) => _exclusive(
    () => ProvisioningWorkflow.run(
      request: request,
      transport: _transportFor(request.device),
      createClient: _createClient,
      onProgress: onProgress,
    ),
  );

  ProvTransport _transportFor(ProvisioningDevice device) {
    final result = _scanResults[device.id];
    if (result == null) {
      throw const ProvisioningException(
        ProvisioningFailureCode.deviceUnavailable,
        'Scan for the device again before provisioning.',
      );
    }
    return _createTransport(result.device);
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    _checkAvailable();
    if (_busy) throw StateError('Another provisioning operation is active.');
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }

  static Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final permissions = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      if (permissions.values.any((status) => !status.isGranted)) {
        throw const ProvisioningException(
          ProvisioningFailureCode.permissionDenied,
          'Bluetooth scan and connection permissions are required.',
        );
      }
      return;
    }
    if (Platform.isIOS) {
      if (!(await Permission.bluetooth.request()).isGranted) {
        throw const ProvisioningException(
          ProvisioningFailureCode.permissionDenied,
          'Bluetooth permission is required.',
        );
      }
      return;
    }
    throw const ProvisioningException(
      ProvisioningFailureCode.permissionDenied,
      'BLE provisioning is supported only on Android and iOS.',
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
  }

  void _checkAvailable() {
    if (_disposed) throw StateError('EswProvisioner has been disposed.');
  }
}
