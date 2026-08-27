// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:esw_device_sdk/src/control_transport.dart';
import 'package:esw_device_sdk/src/provisioning.dart';
import 'package:esw_device_sdk/src/sdk.dart' show SdkTestHarness;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR setup selects exact device and wraps Wi-Fi models', () async {
    final backend = _FakeProvisioningBackend();
    final sdk = SdkTestHarness.create(
      transport: _FakeControlTransport(),
      provisioning: backend,
    );
    addTearDown(sdk.dispose);

    final setup = await sdk.startDeviceSetup(_qr);
    final networks = await setup.scanWifi();

    expect(setup.device.name, 'PROV-MOTOR-12EF');
    expect(networks.single.ssid, 'contest-wifi');
    expect(networks.single.bssid, 'aa:bb:cc:dd:ee:ff');
  });

  test('setup requires fresh matching domain data after Wi-Fi', () async {
    final transport = _FakeControlTransport();
    final backend = _FakeProvisioningBackend();
    final sdk = SdkTestHarness.create(
      transport: transport,
      provisioning: backend,
    );
    addTearDown(sdk.dispose);
    await sdk.connect(_config);
    final setup = await sdk.startDeviceSetup(_qr);
    final network = (await setup.scanWifi()).single;
    final steps = <DeviceSetupStep>[];

    var completed = false;
    final resultFuture = setup
        .complete(network: network, password: 'password', onProgress: steps.add)
        .then((value) {
          completed = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);
    transport.receive(
      'v1/devices/motor-aabb12ef/presence',
      '{"status":"online"}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    transport.receive('v1/devices/motor-aabb12ef/state', _motorState);
    final result = await resultFuture;

    expect(result.device, isA<MotorDeviceSnapshot>());
    expect(result.deviceIp, '192.0.2.10');
    expect(steps.last, DeviceSetupStep.completed);
  });

  test('presence without domain data times out', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(
      transport: transport,
      provisioning: _FakeProvisioningBackend(),
    );
    addTearDown(sdk.dispose);
    await sdk.connect(_config);
    final setup = await sdk.startDeviceSetup(_qr);
    final network = (await setup.scanWifi()).single;

    final request = setup.complete(
      network: network,
      password: 'password',
      availabilityTimeout: const Duration(milliseconds: 5),
    );
    transport.receive(
      'v1/devices/motor-aabb12ef/presence',
      '{"status":"online"}',
    );

    await expectLater(
      request,
      throwsA(isA<DeviceAvailabilityTimeoutException>()),
    );
  });

  test('completed setup cannot be reused', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(
      transport: transport,
      provisioning: _FakeProvisioningBackend(),
    );
    addTearDown(sdk.dispose);
    await sdk.connect(_config);
    final setup = await sdk.startDeviceSetup(_qr);
    final network = (await setup.scanWifi()).single;
    final request = setup.complete(network: network, password: 'password');
    await Future<void>.delayed(Duration.zero);
    transport.receive(
      'v1/devices/motor-aabb12ef/presence',
      '{"status":"online"}',
    );
    transport.receive('v1/devices/motor-aabb12ef/state', _motorState);
    await request;

    await expectLater(setup.scanWifi(), throwsStateError);
  });

  test('SDK rejects concurrent setup operations', () async {
    final pendingScan = Completer<List<SetupDevice>>();
    final backend = _FakeProvisioningBackend(scanResult: pendingScan.future);
    final sdk = SdkTestHarness.create(
      transport: _FakeControlTransport(),
      provisioning: backend,
    );
    addTearDown(sdk.dispose);

    final first = sdk.discoverSetupDevices();
    await Future<void>.delayed(Duration.zero);
    await expectLater(sdk.discoverSetupDevices(), throwsStateError);
    pendingScan.complete(backend.devices);
    await first;
  });
}

const _config = EswConnectionConfig(
  server: 'control.example.com',
  account: 'app',
  secret: 'secret',
);

final _qr = ProvisioningQrPayload.parse(
  '{"ver":"v1","name":"PROV-MOTOR-12EF",'
  '"pop":"device-pop","transport":"ble"}',
);

const _motorState = '''
{"mainState":"idle","currentPosition100ths":2500,
 "targetPosition100ths":2500,"positionValid":true,"errors":0,
 "calibrationState":"complete","protectionState":0,"revision":3}
''';

final class _FakeProvisioningBackend implements ProvisioningBackend {
  _FakeProvisioningBackend({this.scanResult});

  final Future<List<SetupDevice>>? scanResult;
  final devices = const [
    SetupDevice(id: 'ble-motor', name: 'PROV-MOTOR-12EF', rssi: -35),
    SetupDevice(id: 'ble-sensor', name: 'PROV-SENSOR-C4A0', rssi: -45),
  ];

  @override
  Future<List<SetupDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) => scanResult ?? Future.value(devices);

  @override
  Future<List<SetupWifiNetwork>> scanWifi({
    required SetupDevice device,
    required String pop,
  }) async => const [
    SetupWifiNetwork(
      ssid: 'contest-wifi',
      rssi: -42,
      bssid: 'aa:bb:cc:dd:ee:ff',
      isPrivate: true,
    ),
  ];

  @override
  Future<String?> provision({
    required SetupDevice device,
    required String pop,
    required SetupWifiNetwork network,
    required String password,
    void Function(DeviceSetupStep step)? onProgress,
  }) async {
    for (final step in DeviceSetupStep.values.where(
      (step) =>
          step != DeviceSetupStep.waitingForDevice &&
          step != DeviceSetupStep.completed,
    )) {
      onProgress?.call(step);
    }
    return '192.0.2.10';
  }

  @override
  Future<void> dispose() async {}
}

final class _FakeControlTransport implements ControlTransport {
  final _states = StreamController<ControlTransportState>.broadcast();
  final _messages = StreamController<ControlEnvelope>.broadcast();

  @override
  Stream<ControlEnvelope> get messages => _messages.stream;
  @override
  Stream<ControlTransportState> get states => _states.stream;

  @override
  Future<void> connect(EswConnectionConfig config) async {
    _states.add(ControlTransportState.connected);
  }

  void receive(String channel, String payload) {
    _messages.add(ControlEnvelope(channel: channel, payload: payload));
  }

  @override
  Future<void> disconnect() async {
    _states.add(ControlTransportState.disconnected);
  }

  @override
  Future<void> send(String channel, String payload) async {}

  @override
  Future<void> dispose() async {
    await _states.close();
    await _messages.close();
  }
}
