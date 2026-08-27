import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:esp_provisioning_ble/esp_provisioning_ble.dart';
import 'package:esw_device_sdk/esw_device_sdk.dart' show DeviceSetupStep;
import 'package:esw_device_sdk/src/errors.dart';
import 'package:esw_device_sdk/src/provisioning_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delegates in package order and disposes once', () async {
    final calls = <String>[];
    final transport = _FakeTransport(calls);
    final client = _FakeClient(calls);
    final steps = <DeviceSetupStep>[];

    final result = await ProvisioningWorkflow.run(
      pop: 'device-pop',
      wifiSsid: 'wifi',
      wifiPassword: 'password',
      transport: transport,
      createClient: (_, _) => client,
      onProgress: steps.add,
      pollInterval: Duration.zero,
    );

    expect(result, '192.0.2.10');
    expect(calls, [
      'connect',
      'proto-ver',
      'session',
      'wifi-set',
      'wifi-apply',
      'wifi-status',
      'dispose',
    ]);
    expect(steps.last, DeviceSetupStep.waitingForWifi);
    expect(client.disposeCalls, 1);
  });

  test('maps key mismatch and still disposes once', () async {
    final calls = <String>[];
    final client = _FakeClient(
      calls,
      sessionStatus: EstablishSessionStatus.keymismatch,
    );
    await expectLater(
      ProvisioningWorkflow.run(
        pop: 'device-pop',
        wifiSsid: 'wifi',
        wifiPassword: 'password',
        transport: _FakeTransport(calls),
        createClient: (_, _) => client,
      ),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningFailureCode.wrongPop,
        ),
      ),
    );
    expect(client.disposeCalls, 1);
  });

  test('maps Wi-Fi authentication failure and disposes once', () async {
    final calls = <String>[];
    final client = _FakeClient(
      calls,
      connectionStatus: ConnectionStatus(
        state: WifiConnectionState.ConnectionFailed,
        failedReason: WifiConnectFailedReason.AuthError,
      ),
    );
    await expectLater(
      ProvisioningWorkflow.run(
        pop: 'device-pop',
        wifiSsid: 'wifi',
        wifiPassword: 'password',
        transport: _FakeTransport(calls),
        createClient: (_, _) => client,
      ),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningFailureCode.wifiAuthentication,
        ),
      ),
    );
    expect(client.disposeCalls, 1);
  });

  test('maps missing Wi-Fi network and disposes once', () async {
    final calls = <String>[];
    final client = _FakeClient(
      calls,
      connectionStatus: ConnectionStatus(
        state: WifiConnectionState.ConnectionFailed,
        failedReason: WifiConnectFailedReason.NetworkNotFound,
      ),
    );
    await expectLater(
      ProvisioningWorkflow.run(
        pop: 'device-pop',
        wifiSsid: 'wifi',
        wifiPassword: 'password',
        transport: _FakeTransport(calls),
        createClient: (_, _) => client,
      ),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningFailureCode.wifiNotFound,
        ),
      ),
    );
    expect(client.disposeCalls, 1);
  });

  test('maps operation timeout and disposes once', () async {
    final calls = <String>[];
    final client = _FakeClient(calls, sessionCompleter: Completer());
    await expectLater(
      ProvisioningWorkflow.run(
        pop: 'device-pop',
        wifiSsid: 'wifi',
        wifiPassword: 'password',
        transport: _FakeTransport(calls),
        createClient: (_, _) => client,
        operationTimeout: const Duration(milliseconds: 1),
      ),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningFailureCode.timeout,
        ),
      ),
    );
    expect(client.disposeCalls, 1);
  });
}

final class _FakeTransport implements ProvTransport {
  _FakeTransport(this.calls);
  final List<String> calls;

  @override
  Future<bool> connect() async {
    calls.add('connect');
    return true;
  }

  @override
  Future<bool> checkConnect() async => true;

  @override
  Future<bool> disconnect() async {
    calls.add('transport-dispose');
    return true;
  }

  @override
  Future<Uint8List> sendReceive(String epName, Uint8List data) async {
    calls.add(epName);
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'prov': {
            'sec_ver': 1,
            'cap': ['wifi_prov', 'wifi_scan'],
          },
          'esw': {'ver': '2', 'cap': <String>[]},
        }),
      ),
    );
  }
}

final class _FakeClient implements ProvisioningClient {
  _FakeClient(
    this.calls, {
    this.sessionStatus = EstablishSessionStatus.connected,
    ConnectionStatus? connectionStatus,
    this.sessionCompleter,
  }) : connectionStatus =
           connectionStatus ??
           ConnectionStatus(
             state: WifiConnectionState.Connected,
             deviceIp: '192.0.2.10',
           );

  final List<String> calls;
  final EstablishSessionStatus sessionStatus;
  final ConnectionStatus connectionStatus;
  final Completer<EstablishSessionStatus>? sessionCompleter;
  int disposeCalls = 0;

  @override
  Future<EstablishSessionStatus> establishSession() {
    calls.add('session');
    return sessionCompleter?.future ?? Future.value(sessionStatus);
  }

  @override
  Future<List<WifiAP>> scanWifi() async => const [];

  @override
  Future<bool> sendWifiConfig({
    required String ssid,
    required String password,
    String? bssid,
  }) async {
    calls.add('wifi-set');
    return true;
  }

  @override
  Future<bool> applyWifiConfig() async {
    calls.add('wifi-apply');
    return true;
  }

  @override
  Future<ConnectionStatus> getStatus() async {
    calls.add('wifi-status');
    return connectionStatus;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    calls.add('dispose');
  }
}
