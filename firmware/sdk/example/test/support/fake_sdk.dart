import 'dart:async';

import 'package:esw_device_sdk/esw_device_sdk.dart';

final class FakeEswDeviceSdk implements EswDeviceSdk {
  FakeEswDeviceSdk({
    EswSdkState initial = EswSdkState.initial,
    this.completeFailures = 0,
  }) : _currentState = initial;

  final _stateChanges = StreamController<EswSdkState>.broadcast(sync: true);
  final _errors = StreamController<EswSdkException>.broadcast(sync: true);
  EswSdkState _currentState;
  int connectCalls = 0;
  int discoverCalls = 0;
  int completeFailures;
  final commands = <String>[];

  final setupDevice = const SetupDevice(
    id: 'ble-motor',
    name: 'PROV-MOTOR-12EF',
    rssi: -35,
  );
  final setupNetwork = const SetupWifiNetwork(
    ssid: 'contest-wifi',
    rssi: -42,
    bssid: 'aa:bb:cc:dd:ee:ff',
    isPrivate: true,
  );

  @override
  EswSdkState get currentState => _currentState;

  @override
  Stream<EswSdkState> get states => Stream.multi((controller) {
    controller.add(_currentState);
    final subscription = _stateChanges.stream.listen(controller.add);
    controller.onCancel = subscription.cancel;
  }, isBroadcast: true);

  @override
  Stream<EswSdkException> get errors => _errors.stream;

  @override
  Future<void> connect(EswConnectionConfig config) async {
    config.validate();
    connectCalls += 1;
    _emit(
      EswSdkState(
        connection: EswConnectionState.connected,
        devices: _currentState.devices,
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    _emit(
      EswSdkState(
        connection: EswConnectionState.disconnected,
        devices: _currentState.devices,
      ),
    );
  }

  @override
  MotorController motor(String deviceId) => _FakeMotor(deviceId, commands);

  @override
  Future<List<SetupDevice>> discoverSetupDevices({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    discoverCalls += 1;
    return [setupDevice];
  }

  @override
  Future<DeviceSetup> startDeviceSetup(
    ProvisioningQrPayload qr, {
    Duration scanTimeout = const Duration(seconds: 8),
  }) async => _FakeSetup(this, setupDevice, setupNetwork, _readyDevice);

  @override
  DeviceSetup startManualDeviceSetup({
    required SetupDevice device,
    required String pop,
  }) => _FakeSetup(this, device, setupNetwork, _readyDevice);

  @override
  Future<void> dispose() async {
    await _stateChanges.close();
    await _errors.close();
  }

  MotorDeviceSnapshot get _readyDevice => MotorDeviceSnapshot(
    id: 'motor-aabb12ef',
    isOnline: true,
    lastSeen: DateTime(2026),
    latestState: null,
  );

  void _emit(EswSdkState value) {
    _currentState = value;
    _stateChanges.add(value);
  }
}

final class _FakeMotor implements MotorController {
  _FakeMotor(this.id, this.commands);

  @override
  final String id;
  final List<String> commands;

  Future<CommandResult> _send(String command) async {
    commands.add(command);
    return const CommandResult(status: CommandStatus.accepted, revision: 1);
  }

  @override
  Future<CommandResult> calibrate() => _send('calibrate');
  @override
  Future<CommandResult> close() => _send('close');
  @override
  Future<CommandResult> open() => _send('open');
  @override
  Future<CommandResult> setPosition({required double percent}) =>
      _send('setPosition:$percent');
  @override
  Future<CommandResult> stop() => _send('stop');
  @override
  Future<CommandResult> ventilate() => _send('ventilate');
}

final class _FakeSetup implements DeviceSetup {
  _FakeSetup(this.sdk, this.device, this.network, this.readyDevice);

  final FakeEswDeviceSdk sdk;
  @override
  final SetupDevice device;
  final SetupWifiNetwork network;
  final MotorDeviceSnapshot readyDevice;

  @override
  Future<List<SetupWifiNetwork>> scanWifi() async => [network];

  @override
  Future<DeviceSetupResult> complete({
    required SetupWifiNetwork network,
    required String password,
    void Function(DeviceSetupStep step)? onProgress,
    Duration availabilityTimeout = const Duration(seconds: 20),
  }) async {
    if (sdk.completeFailures > 0) {
      sdk.completeFailures -= 1;
      throw const ProvisioningException(
        ProvisioningFailureCode.timeout,
        'Temporary setup failure.',
      );
    }
    onProgress?.call(DeviceSetupStep.applyingWifi);
    onProgress?.call(DeviceSetupStep.waitingForDevice);
    onProgress?.call(DeviceSetupStep.completed);
    return DeviceSetupResult(device: readyDevice, deviceIp: '192.0.2.10');
  }
}
