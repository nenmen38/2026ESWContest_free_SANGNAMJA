// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';

import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:esw_device_sdk/src/control_transport.dart';
import 'package:esw_device_sdk/src/sdk.dart' show SdkTestHarness;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('states is seeded and combines connection with typed devices', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(transport: transport);
    addTearDown(sdk.dispose);

    expect(sdk.currentState.connection, EswConnectionState.disconnected);
    expect((await sdk.states.first).devices, isEmpty);

    await sdk.connect(_config);
    transport.receive('v1/devices/motor-aabb/presence', '{"status":"online"}');
    transport.receive('v1/devices/motor-aabb/state', _motorState);
    await Future<void>.delayed(Duration.zero);

    expect(sdk.currentState.connection, EswConnectionState.connected);
    final motor = sdk.currentState.devices.single as MotorDeviceSnapshot;
    expect(motor.isOnline, isTrue);
    expect(motor.latestState?.currentPositionPercent, 25);
  });

  test('disconnect marks devices offline and preserves domain data', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(transport: transport);
    addTearDown(sdk.dispose);
    transport.receive('v1/devices/sensor-aabb/telemetry', _telemetry);
    await Future<void>.delayed(Duration.zero);

    await sdk.disconnect();

    final sensor = sdk.currentState.devices.single as AirQualityDeviceSnapshot;
    expect(sensor.isOnline, isFalse);
    expect(sensor.latestReading?.pm2_5, 13);
  });

  test('retained motor state cannot override offline presence', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(transport: transport);
    addTearDown(sdk.dispose);

    transport.receive('v1/devices/motor-aabb/presence', '{"status":"offline"}');
    transport.receive('v1/devices/motor-aabb/state', _motorState);
    await Future<void>.delayed(Duration.zero);

    final motor = sdk.currentState.devices.single as MotorDeviceSnapshot;
    expect(motor.isOnline, isFalse);
    expect(motor.latestState?.currentPositionPercent, 25);
  });

  test('application controls a motor without transport concepts', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(transport: transport);
    addTearDown(sdk.dispose);
    transport.receive('v1/devices/motor-aabb/presence', '{"status":"online"}');
    await Future<void>.delayed(Duration.zero);

    final resultFuture = sdk.motor('motor-aabb').open();
    await Future<void>.delayed(Duration.zero);
    final command = jsonDecode(transport.lastPayload!) as Map<String, dynamic>;
    transport.receive(
      'v1/devices/motor-aabb/event',
      jsonEncode({
        'commandId': command['commandId'],
        'result': 'accepted',
        'revision': 4,
      }),
    );

    final result = await resultFuture;
    expect(result.status, CommandStatus.accepted);
    expect(result.revision, 4);
  });

  test('setPosition validates percent before doing any I/O', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(transport: transport);
    addTearDown(sdk.dispose);
    expect(
      () => sdk.motor('motor-aabb').setPosition(percent: 100.1),
      throwsArgumentError,
    );
    expect(transport.lastPayload, isNull);
  });

  test('malformed data is isolated and reported', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(transport: transport);
    addTearDown(sdk.dispose);
    final error = sdk.errors.first;
    transport.receive('v1/devices/motor-aabb/state', '{bad-json');
    expect(await error, isA<DeviceDataException>());
  });

  test('only the matching command result completes a request', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(transport: transport);
    addTearDown(sdk.dispose);
    transport.receive('v1/devices/motor-aabb/presence', '{"status":"online"}');
    await Future<void>.delayed(Duration.zero);

    var completed = false;
    final request = sdk.motor('motor-aabb').setPosition(percent: 25)
      ..then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    final sent = jsonDecode(transport.lastPayload!) as Map<String, dynamic>;
    expect(sent['position100ths'], 2500);
    transport.receive(
      'v1/devices/motor-aabb/event',
      '{"commandId":"different","result":"accepted","revision":1}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    transport.receive(
      'v1/devices/motor-aabb/event',
      jsonEncode({
        'commandId': sent['commandId'],
        'result': 'accepted',
        'revision': 2,
      }),
    );
    expect((await request).status, CommandStatus.accepted);
  });

  test('an event from another device cannot complete a command', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(transport: transport);
    addTearDown(sdk.dispose);
    transport.receive('v1/devices/motor-aabb/presence', '{"status":"online"}');
    await Future<void>.delayed(Duration.zero);

    var completed = false;
    final request = sdk.motor('motor-aabb').open()
      ..then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    final command = jsonDecode(transport.lastPayload!) as Map<String, dynamic>;
    final event = jsonEncode({
      'commandId': command['commandId'],
      'result': 'accepted',
      'revision': 4,
    });
    transport.receive('v1/devices/motor-ccdd/event', event);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    transport.receive('v1/devices/motor-aabb/event', event);
    expect((await request).status, CommandStatus.accepted);
  });

  test('a different connection scope clears known devices', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(transport: transport);
    addTearDown(sdk.dispose);
    await sdk.connect(_config);
    transport.receive('v1/devices/motor-aabb/presence', '{"status":"online"}');
    await Future<void>.delayed(Duration.zero);
    expect(sdk.currentState.devices, hasLength(1));

    await sdk.connect(
      const EswConnectionConfig(
        server: 'other.example.com',
        account: 'other-app',
        secret: 'other-secret',
      ),
    );

    expect(sdk.currentState.devices, isEmpty);
  });

  test('the same connection scope preserves known devices', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(transport: transport);
    addTearDown(sdk.dispose);
    await sdk.connect(_config);
    transport.receive('v1/devices/motor-aabb/presence', '{"status":"online"}');
    await Future<void>.delayed(Duration.zero);

    await sdk.connect(_config);

    expect(sdk.currentState.devices.single.id, 'motor-aabb');
  });

  test('sensor telemetry is exposed in the atomic snapshot', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(transport: transport);
    addTearDown(sdk.dispose);
    transport.receive('v1/devices/sensor-aabb/telemetry', _telemetry);
    await Future<void>.delayed(Duration.zero);

    final sensor = sdk.currentState.devices.single as AirQualityDeviceSnapshot;
    expect(sensor.latestReading?.pm2_5, 13);
    expect(sensor.latestReading?.temperatureC, 23.4);
  });

  test('a command without a correlated result times out', () async {
    final transport = _FakeControlTransport();
    final sdk = SdkTestHarness.create(
      transport: transport,
      commandTimeout: const Duration(milliseconds: 5),
    );
    addTearDown(sdk.dispose);
    transport.receive('v1/devices/motor-aabb/presence', '{"status":"online"}');
    await Future<void>.delayed(Duration.zero);

    final result = await sdk.motor('motor-aabb').open();
    expect(result.status, CommandStatus.timeout);
  });
}

const _config = EswConnectionConfig(
  server: 'control.example.com',
  account: 'app',
  secret: 'secret',
);

const _motorState = '''
{"mainState":"idle","currentPosition100ths":2500,
 "targetPosition100ths":2500,"positionValid":true,"errors":0,
 "calibrationState":"complete","protectionState":0,"revision":3}
''';

const _telemetry = '''
{"timestampUs":1,"revision":1,"errorFlags":0,
 "normalized":{"temperatureValid":true,"temperatureC":23.4,
 "humidityValid":false,"humidityPercent":null,
 "pressureValid":false,"pressureHpa":null},
 "raw":{"pmStatus":0,"pmMeasurementMode":1,"pmCalibration":0,
 "grimmPm1_0":8,"grimmPm2_5":13,"grimmPm10":21,
 "tsiPm1_0":7,"tsiPm2_5":12,"tsiPm10":20,
 "particles0_3":100,"particles0_5":80,"particles1_0":40,
 "particles2_5":15,"particles5_0":4,"particles10_0":1,
 "bmeStatus":-1}}
''';

final class _FakeControlTransport implements ControlTransport {
  final _states = StreamController<ControlTransportState>.broadcast();
  final _messages = StreamController<ControlEnvelope>.broadcast();
  String? lastPayload;

  @override
  Stream<ControlEnvelope> get messages => _messages.stream;
  @override
  Stream<ControlTransportState> get states => _states.stream;

  @override
  Future<void> connect(EswConnectionConfig config) async {
    config.validate();
    _states.add(ControlTransportState.connected);
  }

  void receive(String channel, String payload) {
    _messages.add(ControlEnvelope(channel: channel, payload: payload));
  }

  @override
  Future<void> send(String channel, String payload) async {
    lastPayload = payload;
  }

  @override
  Future<void> disconnect() async {
    _states.add(ControlTransportState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _messages.close();
  }
}
