import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection.dart';
import 'provisioning_qr_scanner.dart';
import 'sdk_scope.dart';

class AddDevicePage extends ConsumerStatefulWidget {
  const AddDevicePage({required this.profile, this.scanQr, super.key});

  final EswConnectionConfig profile;
  final Future<ProvisioningQrPayload?> Function(BuildContext context)? scanQr;

  @override
  ConsumerState<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends ConsumerState<AddDevicePage> {
  final _pop = TextEditingController();
  final _wifiPassword = TextEditingController();
  List<SetupDevice> _devices = const [];
  List<SetupWifiNetwork> _networks = const [];
  SetupDevice? _device;
  SetupWifiNetwork? _network;
  DeviceSetup? _setup;
  int _step = 0;
  bool _busy = false;
  bool _manual = false;
  bool _error = false;
  String _status = 'QR 코드를 스캔하거나 주변 기기를 검색하세요.';

  EswDeviceSdk get _sdk => ref.read(sdkProvider);

  @override
  void dispose() {
    _pop.dispose();
    _wifiPassword.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final payload =
        await (widget.scanQr?.call(context) ??
            Navigator.of(context).push<ProvisioningQrPayload>(
              MaterialPageRoute(
                builder: (_) => const ProvisioningQrScannerPage(),
              ),
            ));
    if (!mounted || payload == null) return;
    await _run('QR과 일치하는 기기를 찾는 중입니다...', () async {
      final setup = await _sdk.startDeviceSetup(payload);
      final networks = await setup.scanWifi();
      _setup = setup;
      _device = setup.device;
      _devices = [setup.device];
      _setNetworks(networks);
      _step = 1;
    });
  }

  Future<void> _scanNearby() async {
    _manual = true;
    await _run('주변 등록 대기 기기를 찾는 중입니다...', () async {
      _devices = await _sdk.discoverSetupDevices();
      _device = _devices.firstOrNull;
      _setup = null;
      _networks = const [];
      _network = null;
      _status = '${_devices.length}개 기기를 찾았습니다.';
    });
  }

  Future<void> _scanWifi() async {
    final device = _device;
    if (device == null) return _notice('먼저 기기를 선택하세요.');
    if (_pop.text.trim().isEmpty) return _notice('기기 인증 코드를 입력하세요.');
    await _run('기기가 보는 Wi-Fi를 찾는 중입니다...', () async {
      final setup = _sdk.startManualDeviceSetup(
        device: device,
        pop: _pop.text.trim(),
      );
      final networks = await setup.scanWifi();
      _setup = setup;
      _setNetworks(networks);
      _step = 1;
    });
  }

  Future<void> _complete() async {
    final setup = _setup;
    final network = _network;
    if (setup == null || network == null) return;
    setState(() {
      _step = 3;
      _busy = true;
      _error = false;
    });
    try {
      final result = await setup.complete(
        network: network,
        password: _wifiPassword.text,
        onProgress: (step) {
          if (mounted) setState(() => _status = _stepMessage(step));
        },
      );
      if (!mounted) return;
      setState(() {
        _setup = null;
        _step = 4;
        _status = '기기 등록 완료 (${result.deviceIp ?? 'IP 확인 안 됨'})';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _step = 2;
        _error = true;
        _status = friendlySdkError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(String status, Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = false;
      _status = status;
    });
    try {
      await operation();
    } on Object catch (error) {
      _error = true;
      _status = friendlySdkError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setNetworks(List<SetupWifiNetwork> networks) {
    _networks = networks;
    _network = networks.firstOrNull;
    _status = '${networks.length}개 Wi-Fi 네트워크를 찾았습니다.';
  }

  void _notice(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: Text(_step == 4 ? '기기 추가 완료' : '기기 추가')),
      body: SafeArea(
        child: Column(
          children: [
            if (_step < 4) LinearProgressIndicator(value: (_step + 1) / 4),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _stepTitle(),
                  const SizedBox(height: 16),
                  if (_step != 4) _statusTile(),
                  ...switch (_step) {
                    0 => _deviceStep(),
                    1 => _wifiStep(),
                    2 => _confirmStep(),
                    3 => _progressStep(),
                    _ => _completeStep(),
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _stepTitle() => Text(switch (_step) {
    0 => '추가할 기기를 선택하세요',
    1 => 'Wi-Fi를 선택하세요',
    2 => '추가할 정보를 확인하세요',
    3 => '기기를 연결하고 있어요',
    _ => '기기가 추가되었습니다',
  }, style: Theme.of(context).textTheme.headlineSmall);

  Widget _statusTile() => Card(
    color: _error ? Theme.of(context).colorScheme.errorContainer : null,
    child: ListTile(
      leading: _busy
          ? const CircularProgressIndicator()
          : Icon(_error ? Icons.error_outline : Icons.info_outline),
      title: Text(_status),
    ),
  );

  List<Widget> _deviceStep() => [
    FilledButton.icon(
      onPressed: _busy ? null : _scanQr,
      icon: const Icon(Icons.qr_code_scanner),
      label: const Text('QR 코드로 기기 찾기'),
    ),
    OutlinedButton(
      onPressed: _busy ? null : _scanNearby,
      child: const Text('QR 코드 없이 찾기'),
    ),
    if (_manual) ...[
      RadioGroup<SetupDevice>(
        groupValue: _device,
        onChanged: _busy
            ? (_) {}
            : (value) => setState(() {
                _device = value;
                _setup = null;
              }),
        child: Column(
          children: _devices
              .map(
                (device) => RadioListTile<SetupDevice>(
                  value: device,
                  title: Text(device.name),
                  subtitle: Text('${device.rssi} dBm'),
                  enabled: !_busy,
                ),
              )
              .toList(),
        ),
      ),
      TextField(
        controller: _pop,
        enabled: !_busy,
        obscureText: true,
        decoration: const InputDecoration(labelText: '기기 인증 코드 (PoP)'),
      ),
      FilledButton(
        onPressed: _busy || _device == null ? null : _scanWifi,
        child: const Text('기기의 Wi-Fi 검색'),
      ),
    ],
  ];

  List<Widget> _wifiStep() => [
    RadioGroup<SetupWifiNetwork>(
      groupValue: _network,
      onChanged: _busy ? (_) {} : (value) => setState(() => _network = value),
      child: Column(
        children: _networks
            .map(
              (network) => RadioListTile<SetupWifiNetwork>(
                value: network,
                title: Text(network.ssid.isEmpty ? '숨겨진 네트워크' : network.ssid),
                subtitle: Text('${network.rssi} dBm'),
                enabled: !_busy,
              ),
            )
            .toList(),
      ),
    ),
    TextField(
      controller: _wifiPassword,
      enabled: !_busy,
      obscureText: true,
      decoration: const InputDecoration(labelText: 'Wi-Fi 비밀번호'),
    ),
    Row(
      children: [
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = 0),
          child: const Text('이전'),
        ),
        const Spacer(),
        Expanded(
          child: FilledButton(
            onPressed: _busy || _network == null
                ? null
                : () => setState(() => _step = 2),
            child: const Text('다음'),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _confirmStep() => [
    ListTile(
      title: const Text('기기'),
      subtitle: Text(_device?.name ?? '선택 안 됨'),
    ),
    ListTile(
      title: const Text('Wi-Fi'),
      subtitle: Text(_network?.ssid ?? '선택 안 됨'),
    ),
    ListTile(
      title: const Text('서비스'),
      subtitle: Text('${widget.profile.server}:${widget.profile.port}'),
    ),
    Row(
      children: [
        TextButton(
          onPressed: () => setState(() => _step = 1),
          child: const Text('이전'),
        ),
        const Spacer(),
        Expanded(
          child: FilledButton.icon(
            onPressed: _complete,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('기기 추가'),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _progressStep() => const [
    SizedBox(height: 48),
    Center(child: CircularProgressIndicator()),
    SizedBox(height: 24),
    Text('앱을 닫거나 기기의 전원을 끄지 마세요.', textAlign: TextAlign.center),
  ];

  List<Widget> _completeStep() => [
    const SizedBox(height: 32),
    const Icon(Icons.check_circle, size: 88),
    const SizedBox(height: 16),
    Text(_status, textAlign: TextAlign.center),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('홈으로 이동'),
    ),
  ];

  static String _stepMessage(DeviceSetupStep step) => switch (step) {
    DeviceSetupStep.connecting => '기기에 연결하는 중입니다...',
    DeviceSetupStep.checkingProtocol => '기기 호환성을 확인하는 중입니다...',
    DeviceSetupStep.securing => '보안 연결을 설정하는 중입니다...',
    DeviceSetupStep.applyingWifi => 'Wi-Fi 정보를 전달하는 중입니다...',
    DeviceSetupStep.waitingForWifi => '기기의 Wi-Fi 연결을 기다리는 중입니다...',
    DeviceSetupStep.waitingForDevice => '기기의 첫 상태를 기다리는 중입니다...',
    DeviceSetupStep.completed => '기기 상태를 확인했습니다.',
  };
}
