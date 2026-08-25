// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'errors.dart';
import 'models.dart';

const _schemaVersion = 1;

final class DeviceChannel {
  const DeviceChannel(this.deviceId, this.kind, this.suffix);
  final String deviceId;
  final EswDeviceKind kind;
  final String suffix;
}

DeviceChannel? parseDeviceChannel(String channel) {
  final parts = channel.split('/');
  if (parts.length != 4 || parts[0] != 'v1' || parts[1] != 'devices') {
    return null;
  }
  final id = parts[2];
  final kind = id.startsWith('motor-')
      ? EswDeviceKind.motor
      : id.startsWith('sensor-')
      ? EswDeviceKind.airQualitySensor
      : null;
  return kind == null ? null : DeviceChannel(id, kind, parts[3]);
}

String commandChannel(String deviceId) => 'v1/devices/$deviceId/command';

bool parsePresence(String payload) {
  return _decode(payload, (json) {
    _checkSchema(json.schemaVersion);
    return switch (json.string('status')) {
      'online' => true,
      'offline' => false,
      _ => throw const DeviceDataException(
        'Presence status must be online or offline.',
      ),
    };
  });
}

MotorState parseMotorState(String payload) => _decode(payload, (json) {
  _checkSchema(json.schemaVersion);
  final current = json.integer('currentPosition100ths');
  final target = json.integer('targetPosition100ths');
  final positionValid = json.boolean('positionValid');
  _checkPosition(current, 'currentPosition100ths');
  _checkPosition(target, 'targetPosition100ths');
  return MotorState(
    mainState: _motorState(json.string('mainState')),
    currentPositionPercent: positionValid ? current / 100 : null,
    targetPositionPercent: target / 100,
    positionValid: positionValid,
    errorFlags: json.integer('errors'),
    calibrationState: _calibrationState(json.string('calibrationState')),
    protectionState: json.integer('protectionState'),
    revision: json.integer('revision'),
  );
});

AirQualityReading parseAirQualityReading(String payload, DateTime receivedAt) =>
    _decode(payload, (json) {
      _checkSchema(json.schemaVersion);
      final raw = json.object('raw');
      final normalized = json.object('normalized');
      final rawModel = AirQualityRaw(
        pmStatus: raw.integer('pmStatus'),
        pmMeasurementMode: raw.integer('pmMeasurementMode'),
        pmCalibration: raw.integer('pmCalibration'),
        grimmPm1_0: raw.integer('grimmPm1_0'),
        grimmPm2_5: raw.integer('grimmPm2_5'),
        grimmPm10: raw.integer('grimmPm10'),
        tsiPm1_0: raw.integer('tsiPm1_0'),
        tsiPm2_5: raw.integer('tsiPm2_5'),
        tsiPm10: raw.integer('tsiPm10'),
        particles0_3: raw.integer('particles0_3'),
        particles0_5: raw.integer('particles0_5'),
        particles1_0: raw.integer('particles1_0'),
        particles2_5: raw.integer('particles2_5'),
        particles5_0: raw.integer('particles5_0'),
        particles10_0: raw.integer('particles10_0'),
        bmeStatus: raw.integer('bmeStatus'),
      );
      final pmValid = json.optionalBool('pmValid') ?? rawModel.pmStatus == 0;
      json.optionalBool('bmeValid');
      final pm2_5 = pmValid ? rawModel.grimmPm2_5 : null;
      return AirQualityReading(
        temperatureC: _reading(
          normalized.boolean('temperatureValid'),
          normalized.numberOrNull('temperatureC'),
          'temperatureC',
        ),
        humidityPercent: _reading(
          normalized.boolean('humidityValid'),
          normalized.numberOrNull('humidityPercent'),
          'humidityPercent',
        ),
        pressureHpa: _reading(
          normalized.boolean('pressureValid'),
          normalized.numberOrNull('pressureHpa'),
          'pressureHpa',
        ),
        pm1_0: pmValid ? rawModel.grimmPm1_0 : null,
        pm2_5: pm2_5,
        pm10: pmValid ? rawModel.grimmPm10 : null,
        level: airQualityLevel(pm2_5),
        receivedAt: receivedAt,
        deviceTimestamp: Duration(microseconds: json.integer('timestampUs')),
        revision: json.integer('revision'),
        errorFlags: json.integer('errorFlags'),
        raw: rawModel,
      );
    });

AirQualityLevel airQualityLevel(int? pm2_5) {
  if (pm2_5 == null) return AirQualityLevel.unknown;
  if (pm2_5 <= 15) return AirQualityLevel.good;
  if (pm2_5 <= 35) return AirQualityLevel.moderate;
  if (pm2_5 <= 75) return AirQualityLevel.unhealthy;
  return AirQualityLevel.veryUnhealthy;
}

({String commandId, CommandResult result}) parseCommandResult(String payload) {
  return _decode(payload, (json) {
    _checkSchema(json.schemaVersion);
    final commandId = json.string('commandId');
    if (commandId.isEmpty) {
      throw const DeviceDataException(
        'A command result has an empty commandId.',
      );
    }
    final result = json.string('result');
    final status = switch (result) {
      'accepted' => CommandStatus.accepted,
      'duplicate_command' => CommandStatus.duplicateCommand,
      'safety_unavailable' => CommandStatus.safetyUnavailable,
      'position_unknown' => CommandStatus.positionUnknown,
      'hardware_rejected' => CommandStatus.hardwareRejected,
      'invalid_command' => CommandStatus.invalidCommand,
      _ => throw DeviceDataException('Unknown command result: $result.'),
    };
    return (
      commandId: commandId,
      result: CommandResult(status: status, revision: json.integer('revision')),
    );
  });
}

String encodeMotorCommand({
  required String commandId,
  required String action,
  required int ttlMs,
  int? position100ths,
}) => jsonEncode({
  'schemaVersion': _schemaVersion,
  'commandId': commandId,
  'action': action,
  'ttlMs': ttlMs,
  'position100ths': ?position100ths,
});

T _decode<T>(String payload, T Function(Map<String, dynamic>) fromJson) {
  try {
    final value = jsonDecode(payload);
    if (value is! Map<String, dynamic>) {
      throw const DeviceDataException('Device payload must be a JSON object.');
    }
    return fromJson(value);
  } on DeviceDataException {
    rethrow;
  } on Object catch (error) {
    throw DeviceDataException('Device payload fields are invalid.', error);
  }
}

extension on Map<String, dynamic> {
  int get schemaVersion => (this['schemaVersion'] as num?)?.toInt() ?? 1;
  int integer(String key) => (this[key] as num).toInt();
  String string(String key) => this[key] as String;
  bool boolean(String key) => this[key] as bool;
  bool? optionalBool(String key) => this[key] as bool?;
  num? numberOrNull(String key) => this[key] as num?;
  Map<String, dynamic> object(String key) => this[key] as Map<String, dynamic>;
}

void _checkSchema(int version) {
  if (version != _schemaVersion) {
    throw DeviceDataException('Unsupported schemaVersion: $version.');
  }
}

double? _reading(bool valid, num? value, String name) {
  if (!valid) return null;
  if (value != null && value.isFinite) return value.toDouble();
  throw DeviceDataException('Device field "$name" must be a finite number.');
}

void _checkPosition(int value, String name) {
  if (value < 0 || value > 10000) {
    throw DeviceDataException('Device field "$name" is outside 0–10000.');
  }
}

MotorMainState _motorState(String value) => switch (value) {
  'idle' => MotorMainState.idle,
  'opening' => MotorMainState.opening,
  'closing' => MotorMainState.closing,
  'ventilating' => MotorMainState.ventilating,
  'stopping' => MotorMainState.stopping,
  'calibrating' => MotorMainState.calibrating,
  'fault' => MotorMainState.fault,
  'protected' => MotorMainState.protected,
  _ => MotorMainState.unknown,
};

MotorCalibrationState _calibrationState(String value) => switch (value) {
  'required' => MotorCalibrationState.required,
  'in_progress' => MotorCalibrationState.inProgress,
  'complete' => MotorCalibrationState.complete,
  'failed' => MotorCalibrationState.failed,
  _ => MotorCalibrationState.unknown,
};
