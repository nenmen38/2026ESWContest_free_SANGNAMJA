// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:esw_device_sdk/src/errors.dart';
import 'package:esw_device_sdk/src/models.dart';
import 'package:esw_device_sdk/src/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('motor state maps firmware position units to percent', () {
    final state = parseMotorState('''
      {"mainState":"opening","currentPosition100ths":2500,
       "targetPosition100ths":10000,"positionValid":true,"errors":0,
       "calibrationState":"complete","protectionState":0,"revision":12}
    ''');

    expect(state.mainState, MotorMainState.opening);
    expect(state.currentPositionPercent, 25);
    expect(state.targetPositionPercent, 100);
    expect(state.calibrationState, MotorCalibrationState.complete);
  });

  test('invalid position is rejected without accepting the message', () {
    expect(
      () => parseMotorState('''
        {"mainState":"idle","currentPosition100ths":10001,
         "targetPosition100ths":0,"positionValid":true,"errors":0,
         "calibrationState":"complete","protectionState":0,"revision":1}
      '''),
      throwsA(isA<DeviceDataException>()),
    );
  });

  test(
    'sensor telemetry preserves raw values and nulls invalid normalized data',
    () {
      final reading = parseAirQualityReading('''
      {"timestampUs":42000000,"revision":17,"errorFlags":0,
       "normalized":{"temperatureValid":true,"temperatureC":23.45,
       "humidityValid":false,"humidityPercent":48.12,
       "pressureValid":true,"pressureHpa":1013.25},
       "raw":{"pmStatus":0,"pmMeasurementMode":1,"pmCalibration":0,
       "grimmPm1_0":8,"grimmPm2_5":13,"grimmPm10":21,
       "tsiPm1_0":7,"tsiPm2_5":12,"tsiPm10":20,
       "particles0_3":100,"particles0_5":80,"particles1_0":40,
       "particles2_5":15,"particles5_0":4,"particles10_0":1,
       "bmeStatus":0}}
    ''', DateTime.utc(2026));

      expect(reading.temperatureC, 23.45);
      expect(reading.humidityPercent, isNull);
      expect(reading.pm2_5, 13);
      expect(reading.level, AirQualityLevel.good);
      expect(reading.raw.particles0_3, 100);
    },
  );

  test('AirKorea PM2.5 boundaries remain stable', () {
    expect(airQualityLevel(null), AirQualityLevel.unknown);
    expect(airQualityLevel(15), AirQualityLevel.good);
    expect(airQualityLevel(16), AirQualityLevel.moderate);
    expect(airQualityLevel(36), AirQualityLevel.unhealthy);
    expect(airQualityLevel(76), AirQualityLevel.veryUnhealthy);
  });

  test('only the v1 known-device channel contract is accepted', () {
    final channel = parseDeviceChannel('v1/devices/motor-aabb/state');
    expect(channel?.kind, EswDeviceKind.motor);
    expect(parseDeviceChannel('v2/devices/motor-aabb/state'), isNull);
    expect(parseDeviceChannel('v1/devices/other-aabb/state'), isNull);
  });

  test('generated commands carry schema version', () {
    final json =
        jsonDecode(
              encodeMotorCommand(
                commandId: 'fixture-1',
                action: 'stop',
                ttlMs: 5000,
              ),
            )
            as Map<String, dynamic>;
    expect(json['schemaVersion'], 1);
    expect(json['commandId'], 'fixture-1');
    expect(json.containsKey('position100ths'), isFalse);

    final positioned =
        jsonDecode(
              encodeMotorCommand(
                commandId: 'fixture-2',
                action: 'set_position',
                ttlMs: 5000,
                position100ths: 2500,
              ),
            )
            as Map<String, dynamic>;
    expect(positioned['position100ths'], 2500);
  });

  test('unknown or wrongly typed schema versions are rejected', () {
    const base =
        '"mainState":"idle","currentPosition100ths":0,'
        '"targetPosition100ths":0,"positionValid":true,"errors":0,'
        '"calibrationState":"complete","protectionState":0,"revision":1';
    expect(
      () => parseMotorState('{$base,"schemaVersion":99}'),
      throwsA(isA<DeviceDataException>()),
    );
    expect(
      () => parseMotorState('{$base,"schemaVersion":"1"}'),
      throwsA(isA<DeviceDataException>()),
    );
  });

  test('missing, wrongly typed and invalid null fields are rejected', () {
    const valid =
        '"mainState":"idle","currentPosition100ths":0,'
        '"targetPosition100ths":0,"positionValid":true,"errors":0,'
        '"calibrationState":"complete","protectionState":0,"revision":1';
    for (final payload in [
      '{$valid}'.replaceFirst('"errors":0,', ''),
      '{$valid}'.replaceFirst('"errors":0', '"errors":"0"'),
      '{$valid}'.replaceFirst('"positionValid":true', '"positionValid":null'),
    ]) {
      expect(
        () => parseMotorState(payload),
        throwsA(isA<DeviceDataException>()),
      );
    }
  });
}
