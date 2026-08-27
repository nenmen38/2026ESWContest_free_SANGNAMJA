// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:esp_provisioning_ble/esp_provisioning_ble.dart';
import 'device_setup.dart';
import 'errors.dart';
import 'provisioning_protocol.dart';

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

final class EspProvisioningClient implements ProvisioningClient {
  EspProvisioningClient(ProvTransport transport, String pop)
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
  void Function(DeviceSetupStep)? onProgress,
}) async {
  ProvisioningClient? client;
  Future<R> wait<R>(Future<R> future) =>
      timeout == null ? future : future.timeout(timeout);
  try {
    onProgress?.call(DeviceSetupStep.connecting);
    if (!await wait(transport.connect())) {
      throw const ProvisioningException(
        ProvisioningFailureCode.bleConnection,
        'Could not connect to the BLE provisioning service.',
      );
    }
    onProgress?.call(DeviceSetupStep.checkingProtocol);
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
    onProgress?.call(DeviceSetupStep.securing);
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

Future<List<WifiAP>> scanProvisioningWifi({
  required ProvTransport transport,
  required String pop,
  required ProvisioningClient Function(ProvTransport, String) createClient,
}) => _withProvisioningSession(
  transport: transport,
  pop: pop,
  createClient: createClient,
  operation: (client) => client.scanWifi().timeout(const Duration(seconds: 30)),
);

final class ProvisioningWorkflow {
  const ProvisioningWorkflow._();

  static Future<String?> run({
    required String pop,
    required String wifiSsid,
    required String wifiPassword,
    required ProvTransport transport,
    required ProvisioningClient Function(ProvTransport transport, String pop)
    createClient,
    String? wifiBssid,
    void Function(DeviceSetupStep step)? onProgress,
    Duration operationTimeout = const Duration(seconds: 10),
    Duration wifiTimeout = const Duration(seconds: 20),
    Duration pollInterval = const Duration(milliseconds: 500),
  }) async {
    if (pop.isEmpty) {
      throw const ProvisioningException(
        ProvisioningFailureCode.wrongPop,
        'PoP must not be empty.',
      );
    }
    if (wifiSsid.isEmpty) {
      throw const ProvisioningException(
        ProvisioningFailureCode.wifiRejected,
        'Wi-Fi SSID must not be empty.',
      );
    }
    try {
      return await _withProvisioningSession(
        transport: transport,
        pop: pop,
        createClient: createClient,
        timeout: operationTimeout,
        onProgress: onProgress,
        operation: (client) async {
          onProgress?.call(DeviceSetupStep.applyingWifi);
          final accepted = await client
              .sendWifiConfig(
                ssid: wifiSsid,
                password: wifiPassword,
                bssid: wifiBssid,
              )
              .timeout(operationTimeout);
          if (!accepted ||
              !await client.applyWifiConfig().timeout(operationTimeout)) {
            throw const ProvisioningException(
              ProvisioningFailureCode.wifiRejected,
              'The device rejected the Wi-Fi settings.',
            );
          }

          onProgress?.call(DeviceSetupStep.waitingForWifi);
          final deadline = DateTime.now().add(wifiTimeout);
          while (DateTime.now().isBefore(deadline)) {
            final status = await client.getStatus().timeout(operationTimeout);
            switch (status.state) {
              case WifiConnectionState.Connected:
                return status.deviceIp;
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
