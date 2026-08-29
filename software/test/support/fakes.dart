import 'dart:async';

import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:safe_smart_window_system/app/app_storage.dart';
import 'package:safe_smart_window_system/environment/environment_models.dart';

final class MemoryAppStorage implements AppStorage {
  MemoryAppStorage({
    this.onboardingSeen = false,
    this.credentials,
    this.location,
    this.selectedDevices = const SelectedDeviceIds(),
    this.indoorEnvironmentOverride,
    this.outdoorEnvironmentOverride,
  });

  bool onboardingSeen;
  EswConnectionConfig? credentials;
  InstallationLocation? location;
  SelectedDeviceIds selectedDevices;
  IndoorEnvironmentOverride? indoorEnvironmentOverride;
  OutdoorEnvironmentOverride? outdoorEnvironmentOverride;

  @override
  Future<void> clearCredentials() async => credentials = null;

  @override
  Future<EswConnectionConfig?> readCredentials() async => credentials;

  @override
  Future<bool> readOnboardingSeen() async => onboardingSeen;

  @override
  Future<void> writeCredentials(EswConnectionConfig config) async =>
      credentials = config;

  @override
  Future<void> writeOnboardingSeen(bool value) async => onboardingSeen = value;

  @override
  Future<InstallationLocation?> readInstallationLocation() async => location;

  @override
  Future<void> writeInstallationLocation(InstallationLocation value) async =>
      location = value;

  @override
  Future<HouseProfile> readHouseProfile() async => const HouseProfile();

  @override
  Future<void> writeHouseProfile(HouseProfile value) async {}

  @override
  Future<SelectedDeviceIds> readSelectedDeviceIds() async => selectedDevices;

  @override
  Future<void> writeSelectedDeviceIds(SelectedDeviceIds value) async =>
      selectedDevices = value;

  @override
  Future<IndoorEnvironmentOverride?> readIndoorEnvironmentOverride() async =>
      indoorEnvironmentOverride;

  @override
  Future<void> writeIndoorEnvironmentOverride(
    IndoorEnvironmentOverride value,
  ) async => indoorEnvironmentOverride = value;

  @override
  Future<void> clearIndoorEnvironmentOverride() async =>
      indoorEnvironmentOverride = null;

  @override
  Future<OutdoorEnvironmentOverride?> readOutdoorEnvironmentOverride() async =>
      outdoorEnvironmentOverride;

  @override
  Future<void> writeOutdoorEnvironmentOverride(
    OutdoorEnvironmentOverride value,
  ) async => outdoorEnvironmentOverride = value;

  @override
  Future<void> clearOutdoorEnvironmentOverride() async =>
      outdoorEnvironmentOverride = null;
}

final class FakeEswDeviceSdk implements EswDeviceSdk {
  FakeEswDeviceSdk({this.completeFailures = 0});

  final _states = StreamController<EswSdkState>.broadcast(sync: true);
  final _errors = StreamController<EswSdkException>.broadcast(sync: true);
  EswSdkState _current = EswSdkState.initial;
  int connectCalls = 0;
  int discoverCalls = 0;
  int completeFailures;
  final List<String> commands = [];

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
  EswSdkState get currentState => _current;

  @override
  Stream<EswSdkState> get states => Stream.multi((controller) {
    controller.add(_current);
    final subscription = _states.stream.listen(controller.add);
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
        devices: _current.devices,
      ),
    );
  }

  @override
  Future<void> disconnect() async => _emit(
    EswSdkState(
      connection: EswConnectionState.disconnected,
      devices: _current.devices,
    ),
  );

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
  }) async => _FakeSetup(
    this,
    SetupDevice(id: 'ble-${qr.name}', name: qr.name, rssi: -35),
    setupNetwork,
  );

  @override
  DeviceSetup startManualDeviceSetup({
    required SetupDevice device,
    required String pop,
  }) => _FakeSetup(this, device, setupNetwork);

  @override
  MotorController motor(String deviceId) => _FakeMotor(deviceId, commands);

  @override
  Future<void> dispose() async {
    await _states.close();
    await _errors.close();
  }

  void _emit(EswSdkState value) {
    _current = value;
    _states.add(value);
  }

  void emitDevices(List<EswDeviceSnapshot> devices) => _emit(
    EswSdkState(connection: EswConnectionState.connected, devices: devices),
  );
}

final class _FakeSetup implements DeviceSetup {
  _FakeSetup(this.sdk, this.device, this.network);

  final FakeEswDeviceSdk sdk;
  @override
  final SetupDevice device;
  final SetupWifiNetwork network;

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
        'timeout',
      );
    }
    onProgress?.call(DeviceSetupStep.applyingWifi);
    onProgress?.call(DeviceSetupStep.waitingForDevice);
    onProgress?.call(DeviceSetupStep.completed);
    return DeviceSetupResult(
      device: MotorDeviceSnapshot(
        id: 'motor-aabb12ef',
        isOnline: true,
        lastSeen: DateTime(2026),
        latestState: null,
      ),
      deviceIp: '192.0.2.10',
    );
  }
}

final class _FakeMotor implements MotorController {
  _FakeMotor(this.id, this.commands);
  @override
  final String id;
  final List<String> commands;

  Future<CommandResult> _accepted(String command) async {
    commands.add(command);
    return const CommandResult(status: CommandStatus.accepted, revision: 1);
  }

  @override
  @override
  Future<CommandResult> close() => _accepted('close');
  @override
  Future<CommandResult> open() => _accepted('open');
  @override
  Future<CommandResult> setPosition({required double percent}) =>
      _accepted('set:$percent');
  @override
  Future<CommandResult> stop() => _accepted('stop');
}

AirQualityReading sensorReading({DateTime? receivedAt, int errorFlags = 0}) =>
    AirQualityReading(
      temperatureC: 25.8,
      humidityPercent: 54,
      pressureHpa: 1013,
      pm1_0: 8,
      pm2_5: 13,
      pm10: 21,
      level: AirQualityLevel.good,
      receivedAt: receivedAt ?? DateTime.now(),
      deviceTimestamp: const Duration(seconds: 1),
      revision: 1,
      errorFlags: errorFlags,
      raw: const AirQualityRaw(
        pmStatus: 0,
        pmMeasurementMode: 1,
        pmCalibration: 0,
        grimmPm1_0: 8,
        grimmPm2_5: 13,
        grimmPm10: 21,
        tsiPm1_0: 7,
        tsiPm2_5: 12,
        tsiPm10: 20,
        particles0_3: 100,
        particles0_5: 80,
        particles1_0: 40,
        particles2_5: 15,
        particles5_0: 4,
        particles10_0: 1,
        bmeStatus: 0,
      ),
    );
