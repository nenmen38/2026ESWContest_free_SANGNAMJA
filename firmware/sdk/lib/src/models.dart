/// Connection lifecycle exposed by the SDK.
enum EswConnectionState {
  /// No connection is active.
  disconnected,

  /// An initial connection is being established.
  connecting,

  /// The control server connection is ready.
  connected,

  /// A previously connected client is trying to recover.
  reconnecting,
}

/// The device roles understood by this SDK release.
enum EswDeviceKind {
  /// A motorized window or vent controller.
  motor,

  /// An environmental and particulate-matter sensor.
  airQualitySensor,
}

/// Runtime control-server settings supplied by the host application.
///
/// The SDK does not issue or persist these credentials. [server] is a host
/// name without a URI scheme; secure transport is always used.
final class EswConnectionConfig {
  /// Creates control-server settings.
  const EswConnectionConfig({
    required this.server,
    this.port = 8883,
    required this.account,
    required this.secret,
  });

  /// Control-server DNS name or IP address, without a URI scheme.
  final String server;

  /// Secure service port, normally 8883.
  final int port;

  /// Account name supplied by the control-server operator.
  final String account;

  /// Account secret supplied by the control-server operator.
  final String secret;

  /// Throws [ArgumentError] when a required value is unusable.
  void validate() {
    if (server.trim().isEmpty || server.contains('://')) {
      throw ArgumentError.value(
        server,
        'server',
        'Use a host name without a URI scheme.',
      );
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Must be between 1 and 65535.');
    }
    if (account.isEmpty || secret.isEmpty) {
      throw ArgumentError('account and secret must not be empty.');
    }
  }
}

/// One immutable, application-facing snapshot of a known device.
sealed class EswDeviceSnapshot {
  /// Creates the common portion of a device snapshot.
  const EswDeviceSnapshot({
    required this.id,
    required this.kind,
    required this.isOnline,
    required this.lastSeen,
  });

  /// Stable firmware-generated device identifier.
  final String id;

  /// Device role inferred from the firmware identifier.
  final EswDeviceKind kind;

  /// Whether the latest presence message reports the device online.
  final bool isOnline;

  /// Time at which this application most recently received device data.
  final DateTime lastSeen;
}

/// Immutable state of a motor device at one SDK revision.
final class MotorDeviceSnapshot extends EswDeviceSnapshot {
  /// Creates a motor snapshot.
  const MotorDeviceSnapshot({
    required super.id,
    required super.isOnline,
    required super.lastSeen,
    required this.latestState,
  }) : super(kind: EswDeviceKind.motor);

  /// Latest motor state, or `null` until the first state message arrives.
  final MotorState? latestState;
}

/// Immutable state of an air-quality device at one SDK revision.
final class AirQualityDeviceSnapshot extends EswDeviceSnapshot {
  /// Creates an air-quality snapshot.
  const AirQualityDeviceSnapshot({
    required super.id,
    required super.isOnline,
    required super.lastSeen,
    required this.latestReading,
  }) : super(kind: EswDeviceKind.airQualitySensor);

  /// Latest reading, or `null` until the first telemetry message arrives.
  final AirQualityReading? latestReading;
}

/// Atomic application state exposed by the main SDK facade.
///
/// Every instance and its [devices] list are immutable. A new instance is
/// emitted whenever connection or device data changes.
final class EswSdkState {
  /// Creates an SDK state snapshot.
  const EswSdkState({required this.connection, required this.devices});

  /// Initial state before a control-service connection is started.
  static const initial = EswSdkState(
    connection: EswConnectionState.disconnected,
    devices: [],
  );

  /// Current control-service lifecycle state.
  final EswConnectionState connection;

  /// Device snapshots sorted by stable device identifier.
  final List<EswDeviceSnapshot> devices;
}

/// Main operating state of a motor device.
enum MotorMainState {
  /// State has not yet been established.
  unknown,

  /// Motor is stationary and ready.
  idle,

  /// Motor is opening.
  opening,

  /// Motor is closing.
  closing,

  /// Motor is moving to the configured ventilation position.
  ventilating,

  /// A stop is in progress.
  stopping,

  /// Calibration is in progress.
  calibrating,

  /// The controller reports a hardware or service fault.
  fault,

  /// A protection input prevents movement.
  protected,
}

/// Calibration lifecycle reported by a motor device.
enum MotorCalibrationState {
  /// Calibration state is unavailable.
  unknown,

  /// Calibration must be completed before normal movement.
  required,

  /// Calibration is currently running.
  inProgress,

  /// Calibration completed successfully.
  complete,

  /// Calibration failed.
  failed,
}

/// Latest canonical state reported by a motor device.
final class MotorState {
  /// Creates a motor state snapshot.
  const MotorState({
    required this.mainState,
    required this.currentPositionPercent,
    required this.targetPositionPercent,
    required this.positionValid,
    required this.errorFlags,
    required this.calibrationState,
    required this.protectionState,
    required this.revision,
  });

  /// Current high-level motion state.
  final MotorMainState mainState;

  /// Current position in the inclusive range 0–100, or null when invalid.
  final double? currentPositionPercent;

  /// Requested target position in the inclusive range 0–100.
  final double targetPositionPercent;

  /// Whether position feedback is currently trustworthy.
  final bool positionValid;

  /// Firmware-defined error bit field.
  final int errorFlags;

  /// Current calibration lifecycle.
  final MotorCalibrationState calibrationState;

  /// Firmware-defined protection-input bit field.
  final int protectionState;

  /// Monotonically increasing state revision.
  final int revision;

  /// Whether any firmware error bit is set.
  bool get hasError => errorFlags != 0;
}

/// Domain-level outcome of a motor command.
enum CommandStatus {
  /// The device accepted the command.
  accepted,

  /// The device is not currently reachable.
  deviceOffline,

  /// Required safety feedback is unavailable.
  safetyUnavailable,

  /// Required position feedback is unavailable.
  positionUnknown,

  /// The motor hardware rejected the operation.
  hardwareRejected,

  /// The command was invalid or unsupported.
  invalidCommand,

  /// The same command identifier was already processed.
  duplicateCommand,

  /// No matching result arrived before the SDK deadline.
  timeout,
}

/// Result returned by every motor operation.
final class CommandResult {
  /// Creates a command result.
  const CommandResult({required this.status, required this.revision});

  /// Domain-level outcome.
  final CommandStatus status;

  /// Device revision associated with the result, when available.
  final int? revision;

  /// Whether the device accepted the command.
  bool get isAccepted => status == CommandStatus.accepted;
}

/// User-facing particulate-matter quality band.
enum AirQualityLevel {
  /// No valid PM2.5 value is available.
  unknown,

  /// PM2.5 is 0–15 µg/m³.
  good,

  /// PM2.5 is 16–35 µg/m³.
  moderate,

  /// PM2.5 is 36–75 µg/m³.
  unhealthy,

  /// PM2.5 is at least 76 µg/m³.
  veryUnhealthy,
}

/// Detailed raw fields from the PM2008M and BME280 sensors.
final class AirQualityRaw {
  /// Creates raw sensor data.
  const AirQualityRaw({
    required this.pmStatus,
    required this.pmMeasurementMode,
    required this.pmCalibration,
    required this.grimmPm1_0,
    required this.grimmPm2_5,
    required this.grimmPm10,
    required this.tsiPm1_0,
    required this.tsiPm2_5,
    required this.tsiPm10,
    required this.particles0_3,
    required this.particles0_5,
    required this.particles1_0,
    required this.particles2_5,
    required this.particles5_0,
    required this.particles10_0,
    required this.bmeStatus,
  });

  /// PM sensor status code.
  final int pmStatus;

  /// PM sensor measurement mode.
  final int pmMeasurementMode;

  /// PM sensor calibration value.
  final int pmCalibration;

  /// GRIMM PM1.0 concentration in µg/m³.
  final int grimmPm1_0;

  /// GRIMM PM2.5 concentration in µg/m³.
  final int grimmPm2_5;

  /// GRIMM PM10 concentration in µg/m³.
  final int grimmPm10;

  /// TSI PM1.0 concentration in µg/m³.
  final int tsiPm1_0;

  /// TSI PM2.5 concentration in µg/m³.
  final int tsiPm2_5;

  /// TSI PM10 concentration in µg/m³.
  final int tsiPm10;

  /// Particle count at or above 0.3 µm.
  final int particles0_3;

  /// Particle count at or above 0.5 µm.
  final int particles0_5;

  /// Particle count at or above 1.0 µm.
  final int particles1_0;

  /// Particle count at or above 2.5 µm.
  final int particles2_5;

  /// Particle count at or above 5.0 µm.
  final int particles5_0;

  /// Particle count at or above 10.0 µm.
  final int particles10_0;

  /// Environmental sensor status code.
  final int bmeStatus;
}

/// Latest application-ready reading from an air-quality device.
final class AirQualityReading {
  /// Creates an air-quality reading.
  const AirQualityReading({
    required this.temperatureC,
    required this.humidityPercent,
    required this.pressureHpa,
    required this.pm1_0,
    required this.pm2_5,
    required this.pm10,
    required this.level,
    required this.receivedAt,
    required this.deviceTimestamp,
    required this.revision,
    required this.errorFlags,
    required this.raw,
  });

  /// Temperature in °C, or null when the device marks it invalid.
  final double? temperatureC;

  /// Relative humidity in %, or null when invalid.
  final double? humidityPercent;

  /// Atmospheric pressure in hPa, or null when invalid.
  final double? pressureHpa;

  /// GRIMM PM1.0 in µg/m³, or null when the PM sensor is invalid.
  final int? pm1_0;

  /// GRIMM PM2.5 in µg/m³, or null when the PM sensor is invalid.
  final int? pm2_5;

  /// GRIMM PM10 in µg/m³, or null when the PM sensor is invalid.
  final int? pm10;

  /// Air-quality band derived from [pm2_5].
  final AirQualityLevel level;

  /// Local time at which this application received the reading.
  final DateTime receivedAt;

  /// Device monotonic sample timestamp.
  final Duration deviceTimestamp;

  /// Monotonically increasing sample revision.
  final int revision;

  /// Firmware-defined sensor error bit field.
  final int errorFlags;

  /// Detailed firmware sensor fields.
  final AirQualityRaw raw;

  /// Whether either physical sensor reported an error.
  bool get hasSensorError => errorFlags != 0;
}
