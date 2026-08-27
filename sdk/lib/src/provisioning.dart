// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';

import 'package:esp_provisioning_ble/esp_provisioning_ble.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_prov_transport.dart';
import 'device_setup.dart';
import 'errors.dart';
import 'provisioning_workflow.dart';

abstract interface class ProvisioningBackend {
  Future<List<SetupDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  });

  Future<List<SetupWifiNetwork>> scanWifi({
    required SetupDevice device,
    required String pop,
  });

  Future<String?> provision({
    required SetupDevice device,
    required String pop,
    required SetupWifiNetwork network,
    required String password,
    void Function(DeviceSetupStep step)? onProgress,
  });

  Future<void> dispose();
}

final class EswProvisioner implements ProvisioningBackend {
  EswProvisioner({
    ProvTransport Function(BluetoothDevice device)? createTransport,
    ProvisioningClient Function(ProvTransport transport, String pop)?
    createClient,
  }) : _createTransport = createTransport ?? BleProvTransport.new,
       _createClient = createClient ?? EspProvisioningClient.new;

  final ProvTransport Function(BluetoothDevice device) _createTransport;
  final ProvisioningClient Function(ProvTransport transport, String pop)
  _createClient;
  final Map<String, ScanResult> _scanResults = {};
  bool _disposed = false;

  @override
  Future<List<SetupDevice>> scan({
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
              (result) => SetupDevice(
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
  Future<List<SetupWifiNetwork>> scanWifi({
    required SetupDevice device,
    required String pop,
  }) async {
    _checkAvailable();
    try {
      final networks = await scanProvisioningWifi(
        transport: _transportFor(device),
        pop: pop,
        createClient: _createClient,
      );
      final result =
          networks
              .map(
                (network) => SetupWifiNetwork(
                  ssid: network.ssid,
                  rssi: network.rssi,
                  bssid: network.bssid,
                  isPrivate: network.private,
                ),
              )
              .toList()
            ..sort((left, right) => right.rssi.compareTo(left.rssi));
      return List.unmodifiable(result);
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
  }

  @override
  Future<String?> provision({
    required SetupDevice device,
    required String pop,
    required SetupWifiNetwork network,
    required String password,
    void Function(DeviceSetupStep step)? onProgress,
  }) {
    _checkAvailable();
    return ProvisioningWorkflow.run(
      pop: pop,
      wifiSsid: network.ssid,
      wifiPassword: password,
      wifiBssid: network.bssid,
      transport: _transportFor(device),
      createClient: _createClient,
      onProgress: onProgress,
    );
  }

  ProvTransport _transportFor(SetupDevice device) {
    final result = _scanResults[device.id];
    if (result == null) {
      throw const ProvisioningException(
        ProvisioningFailureCode.deviceUnavailable,
        'Scan for the device again before provisioning.',
      );
    }
    return _createTransport(result.device);
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
