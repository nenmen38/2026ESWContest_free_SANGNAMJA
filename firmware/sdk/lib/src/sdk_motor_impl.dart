part of 'sdk.dart';

final class _MotorControllerImpl implements MotorController {
  _MotorControllerImpl(this.id, this._sdk);

  @override
  final String id;
  final EswDeviceSdk _sdk;

  @override
  Future<CommandResult> open() => _sdk._command(id, 'open');
  @override
  Future<CommandResult> close() => _sdk._command(id, 'close');
  @override
  Future<CommandResult> stop() => _sdk._command(id, 'stop');
  @override
  Future<CommandResult> ventilate() => _sdk._command(id, 'ventilate');
  @override
  Future<CommandResult> calibrate() => _sdk._command(id, 'calibrate');

  @override
  Future<CommandResult> setPosition({required double percent}) {
    if (!percent.isFinite || percent < 0 || percent > 100) {
      throw ArgumentError.value(
        percent,
        'percent',
        'Must be between 0 and 100.',
      );
    }
    return _sdk._command(
      id,
      'set_position',
      position100ths: (percent * 100).round(),
    );
  }
}

final class _DeviceRecord {
  const _DeviceRecord({
    required this.id,
    required this.kind,
    required this.online,
    required this.lastSeen,
    required this.motorState,
    required this.reading,
    required this.domainSequence,
  });

  final String id;
  final EswDeviceKind kind;
  final bool online;
  final DateTime lastSeen;
  final MotorState? motorState;
  final AirQualityReading? reading;
  final int domainSequence;

  EswDeviceSnapshot get snapshot => switch (kind) {
    EswDeviceKind.motor => MotorDeviceSnapshot(
      id: id,
      isOnline: online,
      lastSeen: lastSeen,
      latestState: motorState,
    ),
    EswDeviceKind.airQualitySensor => AirQualityDeviceSnapshot(
      id: id,
      isOnline: online,
      lastSeen: lastSeen,
      latestReading: reading,
    ),
  };

  _DeviceRecord copyWith({required bool online}) => _DeviceRecord(
    id: id,
    kind: kind,
    online: online,
    lastSeen: lastSeen,
    motorState: motorState,
    reading: reading,
    domainSequence: domainSequence,
  );
}

final class _PendingCommand {
  _PendingCommand(this.deviceId, Duration timeout, void Function() onTimeout) {
    _timer = Timer(timeout, () {
      if (_completer.isCompleted) return;
      onTimeout();
      _completer.complete(
        const CommandResult(status: CommandStatus.timeout, revision: null),
      );
    });
  }

  final _completer = Completer<CommandResult>();
  final String deviceId;
  late final Timer _timer;
  Future<CommandResult> get future => _completer.future;

  void complete(CommandResult result) {
    if (_completer.isCompleted) return;
    _timer.cancel();
    _completer.complete(result);
  }
}
