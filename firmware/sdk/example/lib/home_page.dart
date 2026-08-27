import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_device_page.dart';
import 'connection.dart';
import 'sdk_scope.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  EswConnectionConfig? _profile;
  bool _restoring = true;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    Future.microtask(_restoreConnection);
  }

  Future<void> _restoreConnection() async {
    final saved = await ref.read(credentialStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _profile = saved;
      _restoring = false;
    });
    if (saved == null) return;
    try {
      await ref.read(sdkProvider).connect(saved);
    } on Object catch (error) {
      if (mounted) setState(() => _connectionError = friendlySdkError(error));
    }
  }

  Future<bool> _openConnection() async {
    final profile = await Navigator.of(context).push<EswConnectionConfig>(
      MaterialPageRoute(
        builder: (_) => ConnectionPage(initialProfile: _profile),
      ),
    );
    if (!mounted || profile == null) return false;
    setState(() {
      _profile = profile;
      _connectionError = null;
    });
    return true;
  }

  Future<void> _addDevice() async {
    var state = ref.read(sdkProvider).currentState;
    if (_profile == null || state.connection != EswConnectionState.connected) {
      if (!await _openConnection() || !mounted) return;
      state = ref.read(sdkProvider).currentState;
    }
    if (_profile == null || state.connection != EswConnectionState.connected) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => AddDevicePage(profile: _profile!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sdk = ref.watch(sdkProvider);
    final state = ref.watch(sdkStateProvider).value ?? sdk.currentState;
    final connected = state.connection == EswConnectionState.connected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('우리 집'),
        actions: [
          IconButton(
            onPressed: _restoring ? null : _openConnection,
            icon: const Icon(Icons.settings_outlined),
            tooltip: '서비스 연결 설정',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final profile = _profile;
          if (profile != null && !connected) await sdk.connect(profile);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: _restoring
                    ? const CircularProgressIndicator()
                    : Icon(connected ? Icons.cloud_done : Icons.cloud_off),
                title: Text(connected ? '서비스 연결됨' : '서비스 연결 필요'),
                subtitle: Text(
                  _restoring
                      ? '저장된 연결 정보를 확인하는 중...'
                      : _connectionError ?? state.connection.name,
                ),
                trailing: !connected && !_restoring
                    ? TextButton(
                        onPressed: _openConnection,
                        child: const Text('연결'),
                      )
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '내 기기 ${state.devices.length}대',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (state.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    const Icon(Icons.devices_other, size: 64),
                    const SizedBox(height: 12),
                    const Text('아직 추가된 기기가 없어요'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _addDevice,
                      icon: const Icon(Icons.add),
                      label: const Text('첫 기기 추가하기'),
                    ),
                  ],
                ),
              )
            else
              ...state.devices.map((device) => _DeviceCard(device: device)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDevice,
        icon: const Icon(Icons.add),
        label: const Text('기기 추가'),
      ),
    );
  }
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard({required this.device});

  final EswDeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: switch (device) {
        final MotorDeviceSnapshot value => _MotorPanel(
          device: value,
          controller: ref.read(sdkProvider).motor(value.id),
        ),
        final AirQualityDeviceSnapshot value => _SensorPanel(device: value),
      },
    ),
  );
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({required this.device, required this.title});

  final EswDeviceSnapshot device;
  final String title;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(device.id),
    trailing: Chip(label: Text(device.isOnline ? '온라인' : '오프라인')),
  );
}

class _MotorPanel extends StatefulWidget {
  const _MotorPanel({required this.device, required this.controller});

  final MotorDeviceSnapshot device;
  final MotorController controller;

  @override
  State<_MotorPanel> createState() => _MotorPanelState();
}

class _MotorPanelState extends State<_MotorPanel> {
  double? _dragPosition;

  Future<void> _run(Future<CommandResult> Function() command) async {
    final result = await command();
    if (!mounted) return;
    final message = switch (result.status) {
      CommandStatus.accepted => '명령을 전송했습니다.',
      CommandStatus.deviceOffline => '장치가 오프라인입니다.',
      CommandStatus.safetyUnavailable => '리미트 또는 보호 입력을 확인하세요.',
      CommandStatus.positionUnknown => '홈잉이 완료되지 않았습니다.',
      CommandStatus.hardwareRejected => '모터가 명령을 거부했습니다.',
      CommandStatus.invalidCommand => '유효하지 않은 명령입니다.',
      CommandStatus.duplicateCommand => '이미 처리된 명령입니다.',
      CommandStatus.timeout => '장치 응답 시간이 초과되었습니다.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.device.latestState;
    final position = state?.currentPositionPercent ?? 0;
    final enabled = widget.device.isOnline && (state?.positionValid ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeviceHeader(device: widget.device, title: '스마트 환기창'),
        Text(
          '열림 ${position.toStringAsFixed(0)}% · ${state?.mainState.name ?? '상태 확인 중'}',
        ),
        Slider(
          value: (_dragPosition ?? position).clamp(0, 100).toDouble(),
          max: 100,
          divisions: 20,
          onChanged: enabled
              ? (value) => setState(() => _dragPosition = value)
              : null,
          onChangeEnd: enabled
              ? (value) async {
                  await _run(
                    () => widget.controller.setPosition(percent: value),
                  );
                  if (mounted) setState(() => _dragPosition = null);
                }
              : null,
        ),
        Wrap(
          spacing: 8,
          children:
              {
                    '열기': widget.controller.open,
                    '정지': widget.controller.stop,
                    '닫기': widget.controller.close,
                    '환기': widget.controller.ventilate,
                  }.entries
                  .map(
                    (entry) => ActionChip(
                      label: Text(entry.key),
                      onPressed: widget.device.isOnline
                          ? () => _run(entry.value)
                          : null,
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }
}

class _SensorPanel extends StatelessWidget {
  const _SensorPanel({required this.device});

  final AirQualityDeviceSnapshot device;

  @override
  Widget build(BuildContext context) {
    final reading = device.latestReading;
    return Column(
      children: [
        _DeviceHeader(device: device, title: '공기질 센서'),
        Text(
          'PM2.5 ${reading?.pm2_5 ?? '—'} µg/m³ · '
          '온도 ${reading?.temperatureC ?? '—'}° · '
          '습도 ${reading?.humidityPercent ?? '—'}%',
        ),
      ],
    );
  }
}
