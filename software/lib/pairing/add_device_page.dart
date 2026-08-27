import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/sdk_scope.dart';
import 'pairing_errors.dart';
import 'provisioning_qr_scanner.dart';

class AddDevicePage extends ConsumerStatefulWidget {
  const AddDevicePage({this.scanQr, super.key});

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
  String _status = 'QR 코드를 스캔하거나 주변 장치를 검색하세요.';

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
    await _run('QR과 일치하는 장치를 찾는 중입니다...', () async {
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
    await _run('주변 등록 대기 장치를 찾는 중입니다...', () async {
      _devices = await _sdk.discoverSetupDevices();
      _device = _devices.firstOrNull;
      _setup = null;
      _networks = const [];
      _network = null;
      _status = _devices.isEmpty
          ? '등록 대기 중인 장치를 찾지 못했습니다.'
          : '${_devices.length}개 장치를 찾았습니다.';
    });
  }

  Future<void> _scanWifi() async {
    final device = _device;
    if (device == null) return _notice('먼저 장치를 선택해 주세요.');
    if (_pop.text.trim().isEmpty) return _notice('장치 인증 코드를 입력해 주세요.');
    await _run('장치 주변의 Wi-Fi를 찾는 중입니다...', () async {
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
        _status =
            '장치 등록 완료${result.deviceIp == null ? '' : ' · ${result.deviceIp}'}';
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
      if (mounted) {
        setState(() {
          _error = true;
          _status = friendlySdkError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setNetworks(List<SetupWifiNetwork> networks) {
    _networks = networks;
    _network = networks.firstOrNull;
    _status = networks.isEmpty
        ? '사용 가능한 Wi-Fi를 찾지 못했습니다.'
        : '${networks.length}개 Wi-Fi 네트워크를 찾았습니다.';
  }

  void _notice(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(title: Text(_step == 4 ? '장치 추가 완료' : '장치 추가')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                if (_step < 4) LinearProgressIndicator(value: (_step + 1) / 4),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        _stepTitle,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 16),
                      if (_step != 4) _statusTile(),
                      const SizedBox(height: 14),
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
      ),
    ),
  );

  String get _stepTitle => switch (_step) {
    0 => '추가할 장치를 찾아주세요',
    1 => 'Wi-Fi를 선택해 주세요',
    2 => '연결 정보를 확인해 주세요',
    3 => '장치를 연결하고 있어요',
    _ => '장치가 추가되었습니다',
  };

  Widget _statusTile() => Card(
    color: _error ? Theme.of(context).colorScheme.errorContainer : Colors.white,
    child: ListTile(
      leading: _busy
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Icon(_error ? Icons.error_outline : Icons.info_outline),
      title: Text(_status),
    ),
  );

  List<Widget> _deviceStep() => [
    FilledButton.icon(
      onPressed: _busy ? null : _scanQr,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      icon: const Icon(Icons.qr_code_scanner),
      label: const Text('QR 코드로 장치 찾기'),
    ),
    const SizedBox(height: 10),
    OutlinedButton.icon(
      onPressed: _busy ? null : _scanNearby,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      icon: const Icon(Icons.bluetooth_searching),
      label: const Text('QR 코드 없이 찾기'),
    ),
    if (_manual) ...[
      const SizedBox(height: 12),
      RadioGroup<SetupDevice>(
        groupValue: _device,
        onChanged: _busy
            ? (_) {}
            : (value) => setState(() {
                _device = value;
                _setup = null;
              }),
        child: Card(
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
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pop,
        enabled: !_busy,
        obscureText: true,
        decoration: const InputDecoration(
          filled: true,
          labelText: '장치 인증 코드 (PoP)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _busy || _device == null ? null : _scanWifi,
        child: const Text('장치의 Wi-Fi 검색'),
      ),
    ],
  ];

  List<Widget> _wifiStep() => [
    Card(
      child: RadioGroup<SetupWifiNetwork>(
        groupValue: _network,
        onChanged: _busy ? (_) {} : (value) => setState(() => _network = value),
        child: Column(
          children: _networks
              .map(
                (network) => RadioListTile<SetupWifiNetwork>(
                  value: network,
                  title: Text(network.ssid.isEmpty ? '숨겨진 네트워크' : network.ssid),
                  subtitle: Text(
                    '${network.rssi} dBm${network.isPrivate ? ' · 보안' : ' · 공개'}',
                  ),
                  enabled: !_busy,
                ),
              )
              .toList(),
        ),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _wifiPassword,
      enabled: !_busy,
      obscureText: true,
      decoration: const InputDecoration(
        filled: true,
        labelText: 'Wi-Fi 비밀번호',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = 0),
          child: const Text('이전'),
        ),
        const Spacer(),
        FilledButton(
          onPressed: _busy || _network == null
              ? null
              : () => setState(() => _step = 2),
          child: const Text('다음'),
        ),
      ],
    ),
  ];

  List<Widget> _confirmStep() => [
    Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.window_outlined),
            title: const Text('장치'),
            subtitle: Text(_device?.name ?? '선택 안 됨'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.wifi),
            title: const Text('Wi-Fi'),
            subtitle: Text(_network?.ssid ?? '선택 안 됨'),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        TextButton(
          onPressed: () => setState(() => _step = 1),
          child: const Text('이전'),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: _complete,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('장치 추가'),
        ),
      ],
    ),
  ];

  List<Widget> _progressStep() => const [
    SizedBox(height: 42),
    Center(child: CircularProgressIndicator()),
    SizedBox(height: 24),
    Text('앱을 닫거나 장치의 전원을 끄지 마세요.', textAlign: TextAlign.center),
  ];

  List<Widget> _completeStep() => [
    const SizedBox(height: 24),
    const Icon(Icons.check_circle, size: 88, color: Color(0xFF3182F6)),
    const SizedBox(height: 16),
    Text(
      _status,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 28),
    FilledButton(
      onPressed: () => Navigator.of(context).pop(_device),
      child: const Text('완료'),
    ),
  ];

  static String _stepMessage(DeviceSetupStep step) => switch (step) {
    DeviceSetupStep.connecting => '장치에 연결하는 중입니다...',
    DeviceSetupStep.checkingProtocol => '장치 호환성을 확인하는 중입니다...',
    DeviceSetupStep.securing => '보안 연결을 설정하는 중입니다...',
    DeviceSetupStep.applyingWifi => 'Wi-Fi 정보를 전달하는 중입니다...',
    DeviceSetupStep.waitingForWifi => '장치의 Wi-Fi 연결을 기다리는 중입니다...',
    DeviceSetupStep.waitingForDevice => '장치의 첫 상태를 기다리는 중입니다...',
    DeviceSetupStep.completed => '장치 상태를 확인했습니다.',
  };
}
