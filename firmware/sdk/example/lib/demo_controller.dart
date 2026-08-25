import 'dart:async';

import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => CredentialStore(),
);
final demoControllerProvider = NotifierProvider<DemoController, DemoState>(
  DemoController.new,
);

enum DemoMessageKind { info, success, error }

final class CredentialStore {
  CredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _serverKey = 'broker.server';
  static const _portKey = 'broker.port';
  static const _accountKey = 'broker.account';
  static const _secretKey = 'broker.secret';
  static const _ownedKeys = [_serverKey, _portKey, _accountKey, _secretKey];
  final FlutterSecureStorage _storage;

  Future<void> save(EswConnectionConfig config) => Future.wait([
    _storage.write(key: _serverKey, value: config.server),
    _storage.write(key: _portKey, value: '${config.port}'),
    _storage.write(key: _accountKey, value: config.account),
    _storage.write(key: _secretKey, value: config.secret),
  ]);

  Future<EswConnectionConfig?> load() async {
    final values = await _storage.readAll();
    final port = int.tryParse(values[_portKey] ?? '');
    final server = values[_serverKey];
    final account = values[_accountKey];
    final secret = values[_secretKey];
    if (port == null || server == null || account == null || secret == null) {
      return null;
    }
    return EswConnectionConfig(
      server: server,
      port: port,
      account: account,
      secret: secret,
    );
  }

  Future<void> clear() =>
      Future.wait(_ownedKeys.map((key) => _storage.delete(key: key)));
}

final class DemoState {
  const DemoState({
    this.sdkState = EswSdkState.initial,
    this.nearby = const [],
    this.networks = const [],
    this.selectedDevice,
    this.selectedNetwork,
    this.setup,
    this.status = '서비스에 연결되지 않았습니다.',
    this.messageKind = DemoMessageKind.info,
    this.busy = false,
  });

  final EswSdkState sdkState;
  final List<SetupDevice> nearby;
  final List<SetupWifiNetwork> networks;
  final SetupDevice? selectedDevice;
  final SetupWifiNetwork? selectedNetwork;
  final DeviceSetup? setup;
  final String status;
  final DemoMessageKind messageKind;
  final bool busy;

  EswConnectionState get connection => sdkState.connection;
  List<EswDeviceSnapshot> get devices => sdkState.devices;

  DemoState copyWith({
    EswSdkState? sdkState,
    List<SetupDevice>? nearby,
    List<SetupWifiNetwork>? networks,
    SetupDevice? selectedDevice,
    SetupWifiNetwork? selectedNetwork,
    DeviceSetup? setup,
    String? status,
    DemoMessageKind? messageKind,
    bool? busy,
    bool clearDevice = false,
    bool clearNetwork = false,
    bool clearSetup = false,
  }) => DemoState(
    sdkState: sdkState ?? this.sdkState,
    nearby: nearby ?? this.nearby,
    networks: networks ?? this.networks,
    selectedDevice: clearDevice ? null : selectedDevice ?? this.selectedDevice,
    selectedNetwork: clearNetwork
        ? null
        : selectedNetwork ?? this.selectedNetwork,
    setup: clearSetup ? null : setup ?? this.setup,
    status: status ?? this.status,
    messageKind: messageKind ?? this.messageKind,
    busy: busy ?? this.busy,
  );
}

final class DemoController extends Notifier<DemoState> {
  final EswDeviceSdk sdk = EswDeviceSdk();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  @override
  DemoState build() {
    _subscriptions
      ..add(
        sdk.states
            .skip(1)
            .listen((value) => state = state.copyWith(sdkState: value)),
      )
      ..add(
        sdk.errors.listen(
          (value) => state = state.copyWith(
            status: value.message,
            messageKind: DemoMessageKind.error,
          ),
        ),
      );
    ref.onDispose(() {
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      unawaited(sdk.dispose());
    });
    return DemoState(sdkState: sdk.currentState);
  }

  Future<bool> connect(EswConnectionConfig config) => _run(() async {
    state = state.copyWith(status: '서비스에 연결하는 중입니다...');
    await sdk.connect(config);
    await ref.read(credentialStoreProvider).save(config);
    state = state.copyWith(
      status: '서비스에 연결되었습니다.',
      messageKind: DemoMessageKind.success,
    );
  });

  Future<bool> startQrSetup(ProvisioningQrPayload qr) => _run(() async {
    state = state.copyWith(status: 'QR과 일치하는 기기를 찾는 중입니다...');
    final setup = await sdk.startDeviceSetup(qr);
    state = state.copyWith(
      setup: setup,
      selectedDevice: setup.device,
      nearby: [setup.device],
      status: '기기가 보는 Wi-Fi를 찾는 중입니다...',
    );
    final networks = await setup.scanWifi();
    _setNetworks(networks);
  });

  Future<bool> scanDevices() => _run(() async {
    state = state.copyWith(status: '주변의 등록 대기 기기를 찾는 중입니다...');
    final devices = await sdk.discoverSetupDevices();
    final selected = devices.firstOrNull;
    state = state.copyWith(
      nearby: devices,
      selectedDevice: selected,
      networks: const [],
      clearDevice: selected == null,
      clearNetwork: true,
      clearSetup: true,
      status: '${devices.length}개 등록 대기 기기를 찾았습니다.',
      messageKind: devices.isEmpty
          ? DemoMessageKind.error
          : DemoMessageKind.success,
    );
  });

  Future<bool> scanWifi(String pop) => _run(() async {
    final device = state.selectedDevice;
    if (device == null) throw StateError('먼저 기기를 선택하세요.');
    final setup = sdk.startManualDeviceSetup(device: device, pop: pop);
    state = state.copyWith(setup: setup, status: '기기가 보는 Wi-Fi를 찾는 중입니다...');
    _setNetworks(await setup.scanWifi());
  });

  Future<bool> completeSetup(String wifiPassword) => _run(() async {
    final setup = state.setup;
    final network = state.selectedNetwork;
    if (setup == null || network == null) {
      throw StateError('기기와 Wi-Fi를 먼저 선택하세요.');
    }
    final result = await setup.complete(
      network: network,
      password: wifiPassword,
      onProgress: (step) => state = state.copyWith(
        status: _setupMessage(step),
        messageKind: DemoMessageKind.info,
      ),
    );
    state = state.copyWith(
      status: '기기 등록 완료 (${result.deviceIp ?? 'IP 확인 안 됨'})',
      messageKind: DemoMessageKind.success,
    );
  });

  void selectDevice(SetupDevice? value) => state = state.copyWith(
    selectedDevice: value,
    networks: const [],
    clearDevice: value == null,
    clearNetwork: true,
    clearSetup: true,
  );

  void selectNetwork(SetupWifiNetwork? value) => state = state.copyWith(
    selectedNetwork: value,
    clearNetwork: value == null,
  );

  void resetProvisioning() => state = state.copyWith(
    nearby: const [],
    networks: const [],
    clearDevice: true,
    clearNetwork: true,
    clearSetup: true,
    status: '새 기기를 추가할 준비가 되었습니다.',
    messageKind: DemoMessageKind.info,
  );

  Future<void> clearCredentials() async {
    await ref.read(credentialStoreProvider).clear();
    state = state.copyWith(status: '저장된 제어 서버 자격 증명을 삭제했습니다.');
  }

  void _setNetworks(List<SetupWifiNetwork> networks) {
    state = state.copyWith(
      networks: networks,
      selectedNetwork: networks.firstOrNull,
      clearNetwork: networks.isEmpty,
      status: '${networks.length}개 Wi-Fi 네트워크를 찾았습니다.',
      messageKind: networks.isEmpty
          ? DemoMessageKind.error
          : DemoMessageKind.success,
    );
  }

  Future<bool> _run(Future<void> Function() operation) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, messageKind: DemoMessageKind.info);
    try {
      await operation();
      return true;
    } on Object catch (error) {
      state = state.copyWith(
        status: _friendlyError(error),
        messageKind: DemoMessageKind.error,
      );
      return false;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  static String _setupMessage(DeviceSetupStep step) => switch (step) {
    DeviceSetupStep.connecting => '기기에 연결하는 중입니다...',
    DeviceSetupStep.checkingProtocol => '기기 호환성을 확인하는 중입니다...',
    DeviceSetupStep.securing => '보안 연결을 설정하는 중입니다...',
    DeviceSetupStep.applyingWifi => 'Wi-Fi 정보를 전달하는 중입니다...',
    DeviceSetupStep.waitingForWifi => '기기의 Wi-Fi 연결을 기다리는 중입니다...',
    DeviceSetupStep.waitingForDevice => '기기의 첫 상태를 기다리는 중입니다...',
    DeviceSetupStep.completed => '기기 상태를 확인했습니다.',
  };

  static String _friendlyError(Object error) {
    if (error is ProvisioningException) return error.message;
    if (error is EswSdkException) return error.message;
    if (error is StateError) return error.message;
    return '$error';
  }
}
