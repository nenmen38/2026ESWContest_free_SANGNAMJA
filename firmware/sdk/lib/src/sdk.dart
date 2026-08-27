import 'dart:async';
import 'dart:math';

import 'control_transport.dart';
import 'device_setup.dart';
import 'errors.dart';
import 'models.dart';
import 'mqtt_control_transport.dart';
import 'protocol.dart';
import 'provisioning.dart';
import 'provisioning_qr.dart';

part 'sdk_motor_impl.dart';
part 'sdk_setup_impl.dart';

const _offlineResult = CommandResult(
  status: CommandStatus.deviceOffline,
  revision: null,
);

/// Command-only controller for one motor device.
///
/// Read motor state from [EswDeviceSdk.currentState] or
/// [EswDeviceSdk.states]. Every operation returns the result correlated with
/// its generated command identifier and times out after five seconds.
abstract interface class MotorController {
  /// Stable firmware-generated motor identifier.
  String get id;

  /// Fully opens the device.
  Future<CommandResult> open();

  /// Fully closes the device.
  Future<CommandResult> close();

  /// Requests a controlled stop.
  Future<CommandResult> stop();

  /// Moves to the firmware-configured ventilation position.
  Future<CommandResult> ventilate();

  /// Moves to [percent], which must be between 0 and 100 inclusive.
  Future<CommandResult> setPosition({required double percent});

  /// Starts the firmware calibration routine.
  Future<CommandResult> calibrate();
}

/// High-level entry point for connecting, observing, controlling, and setting
/// up ESW devices.
///
/// Create one instance for the application lifetime. Connection credentials
/// are supplied at runtime and are never persisted by the SDK. Call [dispose]
/// when the owning application scope ends.
interface class EswDeviceSdk {
  /// Creates an SDK backed by the production secure control and BLE adapters.
  factory EswDeviceSdk() => EswDeviceSdk._(
    MqttControlTransport(),
    EswProvisioner(),
    const Duration(seconds: 5),
  );

  EswDeviceSdk._(this._transport, this._provisioning, this._commandTimeout) {
    _transportStateSubscription = _transport.states.listen(_onTransportState);
    _messageSubscription = _transport.messages.listen(_onMessage);
  }

  final ControlTransport _transport;
  final ProvisioningBackend _provisioning;
  final Duration _commandTimeout;
  final _stateChanges = StreamController<EswSdkState>.broadcast(sync: true);
  final _errors = StreamController<EswSdkException>.broadcast(sync: true);
  final Map<String, _DeviceRecord> _records = {};
  final Map<String, _MotorControllerImpl> _motors = {};
  final Map<String, _PendingCommand> _pending = {};
  late final StreamSubscription<ControlTransportState>
  _transportStateSubscription;
  late final StreamSubscription<ControlEnvelope> _messageSubscription;
  EswSdkState _currentState = EswSdkState.initial;
  int _domainSequence = 0;
  ({String server, int port, String account})? _connectionScope;
  bool _setupBusy = false;
  bool _disposed = false;

  /// Latest atomic connection and device snapshot.
  EswSdkState get currentState => _currentState;

  /// Atomic SDK state changes, seeded with [currentState] for every subscriber.
  Stream<EswSdkState> get states => Stream<EswSdkState>.multi((controller) {
    controller.add(_currentState);
    final subscription = _stateChanges.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  }, isBroadcast: true);

  /// Recoverable malformed-data and background processing errors.
  Stream<EswSdkException> get errors => _errors.stream;

  /// Connects to the secure control service and begins automatic discovery.
  Future<void> connect(EswConnectionConfig config) {
    _checkNotDisposed();
    config.validate();
    final nextScope = (
      server: config.server.trim(),
      port: config.port,
      account: config.account,
    );
    if (_connectionScope case final current? when current != nextScope) {
      _records.clear();
      _domainSequence = 0;
      _completePending(_offlineResult);
      _emitState();
    }
    _connectionScope = nextScope;
    return _transport.connect(config);
  }

  /// Disconnects without disposing the SDK so [connect] may be called again.
  Future<void> disconnect() async {
    _checkNotDisposed();
    await _transport.disconnect();
    _markAllOffline();
  }

  /// Returns the command surface for [deviceId].
  ///
  /// Throws [ArgumentError] unless the identifier starts with `motor-`.
  MotorController motor(String deviceId) {
    _checkId(deviceId, 'motor-');
    return _motors.putIfAbsent(
      deviceId,
      () => _MotorControllerImpl(deviceId, this),
    );
  }

  /// Finds nearby devices advertising an ESW setup service.
  Future<List<SetupDevice>> discoverSetupDevices({
    Duration timeout = const Duration(seconds: 8),
  }) => _runSetupOperation(() async {
    final devices = await _provisioning.scan(timeout: timeout);
    return List.unmodifiable(devices);
  });

  /// Finds the BLE device named by [qr] and creates a guided setup session.
  Future<DeviceSetup> startDeviceSetup(
    ProvisioningQrPayload qr, {
    Duration scanTimeout = const Duration(seconds: 8),
  }) async {
    final devices = await discoverSetupDevices(timeout: scanTimeout);
    for (final device in devices) {
      if (device.name == qr.name) {
        return _DeviceSetupImpl(this, device, qr.pop);
      }
    }
    throw ProvisioningException(
      ProvisioningFailureCode.deviceUnavailable,
      'Could not find ${qr.name}.',
    );
  }

  /// Creates a guided setup session for a manually selected [device].
  DeviceSetup startManualDeviceSetup({
    required SetupDevice device,
    required String pop,
  }) {
    _checkNotDisposed();
    if (pop.trim().isEmpty) {
      throw const ProvisioningException(
        ProvisioningFailureCode.wrongPop,
        'PoP must not be empty.',
      );
    }
    return _DeviceSetupImpl(this, device, pop.trim());
  }

  void _onTransportState(ControlTransportState state) {
    if (_disposed) return;
    final connection = switch (state) {
      ControlTransportState.disconnected => EswConnectionState.disconnected,
      ControlTransportState.connecting => EswConnectionState.connecting,
      ControlTransportState.connected => EswConnectionState.connected,
      ControlTransportState.reconnecting => EswConnectionState.reconnecting,
    };
    if (state == ControlTransportState.disconnected ||
        state == ControlTransportState.connecting ||
        state == ControlTransportState.reconnecting) {
      _markAllOffline(connection: connection);
    } else {
      _emitState(connection: connection);
    }
  }

  void _onMessage(ControlEnvelope envelope) {
    if (_disposed) return;
    final channel = parseDeviceChannel(envelope.channel);
    if (channel == null) return;
    final now = DateTime.now();
    try {
      final previous = _records[channel.deviceId];
      switch (channel.suffix) {
        case 'presence':
          _records[channel.deviceId] = _recordFor(
            channel,
            previous,
            online: parsePresence(envelope.payload),
            lastSeen: now,
          );
        case 'state' when channel.kind == EswDeviceKind.motor:
          _domainSequence += 1;
          _records[channel.deviceId] = _recordFor(
            channel,
            previous,
            online: previous?.online ?? false,
            lastSeen: now,
            motorState: parseMotorState(envelope.payload),
            domainSequence: _domainSequence,
          );
        case 'telemetry' when channel.kind == EswDeviceKind.airQualitySensor:
          _domainSequence += 1;
          _records[channel.deviceId] = _recordFor(
            channel,
            previous,
            online: previous?.online ?? false,
            lastSeen: now,
            reading: parseAirQualityReading(envelope.payload, now),
            domainSequence: _domainSequence,
          );
        case 'event' when channel.kind == EswDeviceKind.motor:
          final parsed = parseCommandResult(envelope.payload);
          _records[channel.deviceId] = _recordFor(
            channel,
            previous,
            online: previous?.online ?? false,
            lastSeen: now,
          );
          final pending = _pending[parsed.commandId];
          if (pending?.deviceId == channel.deviceId) {
            _pending.remove(parsed.commandId)?.complete(parsed.result);
          }
        default:
          return;
      }
      _emitState();
    } on EswSdkException catch (error) {
      _errors.add(error);
    } on Object catch (error) {
      _errors.add(DeviceDataException('Could not process device data.', error));
    }
  }

  _DeviceRecord _recordFor(
    DeviceChannel channel,
    _DeviceRecord? previous, {
    required bool online,
    required DateTime lastSeen,
    MotorState? motorState,
    AirQualityReading? reading,
    int? domainSequence,
  }) => _DeviceRecord(
    id: channel.deviceId,
    kind: channel.kind,
    online: online,
    lastSeen: lastSeen,
    motorState: motorState ?? previous?.motorState,
    reading: reading ?? previous?.reading,
    domainSequence: domainSequence ?? previous?.domainSequence ?? 0,
  );

  void _markAllOffline({EswConnectionState? connection}) {
    for (final entry in _records.entries.toList()) {
      _records[entry.key] = entry.value.copyWith(online: false);
    }
    _completePending(_offlineResult);
    _emitState(connection: connection);
  }

  void _emitState({EswConnectionState? connection}) {
    final devices = _records.values.map((record) => record.snapshot).toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    _currentState = EswSdkState(
      connection: connection ?? _currentState.connection,
      devices: List.unmodifiable(devices),
    );
    _stateChanges.add(_currentState);
  }

  Future<CommandResult> _command(
    String deviceId,
    String action, {
    int? position100ths,
  }) async {
    final record = _records[deviceId];
    if (record == null || !record.online) return _offlineResult;
    final id = _newCommandId();
    final pending = _PendingCommand(
      deviceId,
      _commandTimeout,
      () => _pending.remove(id),
    );
    _pending[id] = pending;
    try {
      await _transport.send(
        commandChannel(deviceId),
        encodeMotorCommand(
          commandId: id,
          action: action,
          ttlMs: 5000,
          position100ths: position100ths,
        ),
      );
    } on Object {
      _pending.remove(id);
      pending.complete(_offlineResult);
    }
    return pending.future;
  }

  Future<T> _runSetupOperation<T>(Future<T> Function() operation) async {
    _checkNotDisposed();
    if (_setupBusy) {
      throw StateError('Another device setup operation is active.');
    }
    _setupBusy = true;
    try {
      return await operation();
    } finally {
      _setupBusy = false;
    }
  }

  Future<EswDeviceSnapshot> _waitForReadyDevice(
    String provisioningName,
    int baselineSequence,
    Duration timeout,
  ) async {
    EswDeviceSnapshot? ready() {
      for (final record in _records.values) {
        if (_matchesProvisionedDevice(provisioningName, record.id) &&
            record.online &&
            record.domainSequence > baselineSequence) {
          return record.snapshot;
        }
      }
      return null;
    }

    final current = ready();
    if (current != null) return current;
    try {
      await _stateChanges.stream
          .firstWhere((_) => ready() != null)
          .timeout(timeout);
      return ready()!;
    } on TimeoutException {
      throw const DeviceAvailabilityTimeoutException(
        'Wi-Fi connected, but no fresh device state or reading was observed.',
      );
    }
  }

  void _completePending(CommandResult result) {
    for (final pending in _pending.values) {
      pending.complete(result);
    }
    _pending.clear();
  }

  String _newCommandId() {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = Random.secure().nextInt(1 << 30).toRadixString(36);
    return 'app-$time-$random';
  }

  /// Releases all resources. This method is idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _completePending(_offlineResult);
    await _transportStateSubscription.cancel();
    await _messageSubscription.cancel();
    await _provisioning.dispose();
    await _transport.dispose();
    await _stateChanges.close();
    await _errors.close();
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('EswDeviceSdk has been disposed.');
  }

  static bool _matchesProvisionedDevice(
    String provisioningName,
    String deviceId,
  ) {
    if (provisioningName.startsWith('PROV-MOTOR-')) {
      return deviceId.startsWith('motor-') &&
          deviceId.endsWith(provisioningName.substring(11).toLowerCase());
    }
    if (provisioningName.startsWith('PROV-SENSOR-')) {
      return deviceId.startsWith('sensor-') &&
          deviceId.endsWith(provisioningName.substring(12).toLowerCase());
    }
    return false;
  }

  static void _checkId(String id, String prefix) {
    if (!id.startsWith(prefix) || id.length <= prefix.length) {
      throw ArgumentError.value(
        id,
        'deviceId',
        'Expected an identifier starting with $prefix.',
      );
    }
  }
}

/// Internal construction seam used by this package's deterministic tests.
///
/// This type is intentionally omitted from the public package barrel.
final class SdkTestHarness {
  const SdkTestHarness._();

  /// Builds the SDK around deterministic package-internal dependencies.
  static EswDeviceSdk create({
    required ControlTransport transport,
    ProvisioningBackend? provisioning,
    Duration commandTimeout = const Duration(seconds: 5),
  }) => EswDeviceSdk._(
    transport,
    provisioning ?? EswProvisioner(),
    commandTimeout,
  );
}
