part of 'sdk.dart';

final class _DeviceSetupImpl implements DeviceSetup {
  _DeviceSetupImpl(this._sdk, this.device, this._pop);

  final EswDeviceSdk _sdk;
  String? _pop;
  bool _completed = false;

  @override
  final SetupDevice device;

  @override
  Future<List<SetupWifiNetwork>> scanWifi() =>
      _sdk._runSetupOperation(() async {
        _checkUsable();
        return _sdk._provisioning.scanWifi(device: device, pop: _pop!);
      });

  @override
  Future<DeviceSetupResult> complete({
    required SetupWifiNetwork network,
    required String password,
    void Function(DeviceSetupStep step)? onProgress,
    Duration availabilityTimeout = const Duration(seconds: 20),
  }) => _sdk._runSetupOperation(() async {
    _checkUsable();
    if (_sdk.currentState.connection != EswConnectionState.connected) {
      throw const ConnectionException(
        'Connect the control service before completing device setup.',
      );
    }
    final deviceIp = await _sdk._provisioning.provision(
      device: device,
      pop: _pop!,
      network: network,
      password: password,
      onProgress: onProgress,
    );
    final baselineSequence = _sdk._domainSequence;
    onProgress?.call(DeviceSetupStep.waitingForDevice);
    final ready = await _sdk._waitForReadyDevice(
      device.name,
      baselineSequence,
      availabilityTimeout,
    );
    _completed = true;
    _pop = null;
    onProgress?.call(DeviceSetupStep.completed);
    return DeviceSetupResult(device: ready, deviceIp: deviceIp);
  });

  void _checkUsable() {
    _sdk._checkNotDisposed();
    if (_completed) throw StateError('DeviceSetup has already completed.');
  }
}
