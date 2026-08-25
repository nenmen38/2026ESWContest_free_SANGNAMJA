import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_device_page.dart';
import 'demo_controller.dart';

const defaultBrokerHost = String.fromEnvironment(
  'MQTT_HOST',
  defaultValue: 'broker.example.com',
);
const defaultBrokerPort = int.fromEnvironment('MQTT_PORT', defaultValue: 8883);

void main() => runApp(const ProviderScope(child: EswDemoApp()));

class EswDemoApp extends StatelessWidget {
  const EswDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ESW Home',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B5B)),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7F9F8),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
    home: const HomePage(),
  );
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  EswConnectionConfig? _profile;
  bool _restoring = true;

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
    if (saved != null) {
      await ref.read(demoControllerProvider.notifier).connect(saved);
    }
  }

  Future<bool> _openConnectionSettings() async {
    final result = await Navigator.of(context).push<EswConnectionConfig>(
      MaterialPageRoute(
        builder: (_) => ConnectionSettingsPage(initialProfile: _profile),
      ),
    );
    if (!mounted || result == null) return false;
    setState(() => _profile = result);
    return true;
  }

  Future<void> _addDevice() async {
    var state = ref.read(demoControllerProvider);
    if (_profile == null || state.connection != EswConnectionState.connected) {
      if (!await _openConnectionSettings() || !mounted) return;
      state = ref.read(demoControllerProvider);
    }
    if (state.connection != EswConnectionState.connected || _profile == null) {
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddDevicePage(profile: _profile!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoControllerProvider);
    final connected = state.connection == EswConnectionState.connected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('우리 집'),
        actions: [
          IconButton(
            onPressed: _restoring || state.busy
                ? null
                : _openConnectionSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: '서비스 연결 설정',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (_profile != null && !connected) {
            await ref.read(demoControllerProvider.notifier).connect(_profile!);
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              sliver: SliverToBoxAdapter(
                child: _ConnectionCard(
                  connected: connected,
                  restoring: _restoring,
                  message: state.status,
                  onConnect: _openConnectionSettings,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Text('내 기기', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    Text('${state.devices.length}대'),
                  ],
                ),
              ),
            ),
            if (state.devices.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyDevices(onAdd: _addDevice),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                sliver: SliverList.builder(
                  itemCount: state.devices.length,
                  itemBuilder: (context, index) => _DeviceCard(
                    device: state.devices[index],
                    sdk: ref.read(demoControllerProvider.notifier).sdk,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.busy ? null : _addDevice,
        icon: const Icon(Icons.add),
        label: const Text('기기 추가'),
      ),
    );
  }
}

class ConnectionSettingsPage extends ConsumerStatefulWidget {
  const ConnectionSettingsPage({this.initialProfile, super.key});
  final EswConnectionConfig? initialProfile;

  @override
  ConsumerState<ConnectionSettingsPage> createState() =>
      _ConnectionSettingsPageState();
}

class _ConnectionSettingsPageState
    extends ConsumerState<ConnectionSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _server;
  late final TextEditingController _port;
  late final TextEditingController _account;
  late final TextEditingController _secret;
  bool _showSecret = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    _server = TextEditingController(text: profile?.server ?? defaultBrokerHost);
    _port = TextEditingController(
      text: '${profile?.port ?? defaultBrokerPort}',
    );
    _account = TextEditingController(text: profile?.account ?? '');
    _secret = TextEditingController(text: profile?.secret ?? '');
  }

  @override
  void dispose() {
    _server.dispose();
    _port.dispose();
    _account.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = EswConnectionConfig(
      server: _server.text.trim(),
      port: int.parse(_port.text),
      account: _account.text.trim(),
      secret: _secret.text,
    );
    final success = await ref
        .read(demoControllerProvider.notifier)
        .connect(profile);
    if (mounted && success) Navigator.of(context).pop(profile);
  }

  Future<void> _clear() async {
    await ref.read(demoControllerProvider.notifier).clearCredentials();
    _account.clear();
    _secret.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('서비스 연결')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.cloud_outlined,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '기기와 앱을 연결할 서비스를 설정하세요',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '연결 정보는 이 휴대폰의 보안 저장소에만 보관됩니다.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              _field(_server, '서비스 주소', Icons.dns_outlined),
              const SizedBox(height: 12),
              TextFormField(
                controller: _port,
                enabled: !state.busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '포트',
                  prefixIcon: Icon(Icons.numbers),
                ),
                validator: (value) {
                  final port = int.tryParse(value ?? '');
                  return port == null || port < 1 || port > 65535
                      ? '1~65535 사이의 포트를 입력하세요.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              _field(_account, '앱 계정', Icons.person_outline),
              const SizedBox(height: 12),
              TextFormField(
                controller: _secret,
                enabled: !state.busy,
                obscureText: !_showSecret,
                decoration: InputDecoration(
                  labelText: '앱 비밀번호',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showSecret = !_showSecret),
                    icon: Icon(
                      _showSecret ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? '앱 비밀번호를 입력하세요.' : null,
              ),
              const SizedBox(height: 16),
              if (state.messageKind == DemoMessageKind.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    state.status,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: state.busy ? null : _connect,
                child: state.busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('연결하고 저장'),
              ),
              TextButton(
                onPressed: state.busy ? null : _clear,
                child: const Text('저장된 연결 정보 삭제'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextFormField _field(
    TextEditingController controller,
    String label,
    IconData icon,
  ) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    validator: (value) =>
        value == null || value.trim().isEmpty ? '$label을 입력하세요.' : null,
  );
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connected,
    required this.restoring,
    required this.message,
    required this.onConnect,
  });
  final bool connected;
  final bool restoring;
  final String message;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: connected
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            child: restoring
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(connected ? Icons.cloud_done : Icons.cloud_off_outlined),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? '서비스 연결됨' : '서비스 연결 필요',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  restoring ? '저장된 연결 정보를 확인하는 중...' : message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!connected && !restoring)
            TextButton(onPressed: onConnect, child: const Text('연결')),
        ],
      ),
    ),
  );
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 32, 32, 120),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.devices_other, size: 54),
        ),
        const SizedBox(height: 24),
        Text('아직 추가된 기기가 없어요', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          '스마트 환기창이나 공기질 센서를 추가해\n한곳에서 확인하고 제어하세요.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('첫 기기 추가하기'),
        ),
      ],
    ),
  );
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.sdk});
  final EswDeviceSnapshot device;
  final EswDeviceSdk sdk;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: switch (device) {
        final MotorDeviceSnapshot motor => _MotorPanel(
          device: motor,
          motor: sdk.motor(motor.id),
        ),
        final AirQualityDeviceSnapshot sensor => _SensorPanel(device: sensor),
      },
    ),
  );
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({required this.device, required this.icon});
  final EswDeviceSnapshot device;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(child: Icon(icon)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.kind == EswDeviceKind.motor ? '스마트 환기창' : '공기질 센서',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(device.id, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      Chip(label: Text(device.isOnline ? '온라인' : '오프라인')),
    ],
  );
}

class _MotorPanel extends StatefulWidget {
  const _MotorPanel({required this.device, required this.motor});
  final MotorDeviceSnapshot device;
  final MotorController motor;

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.device.latestState;
    final position = state?.currentPositionPercent ?? 0;
    final displayedPosition = _dragPosition ?? position;
    final canSetPosition =
        widget.device.isOnline && (state?.positionValid ?? false);
    ActionChip action(
      String label,
      Future<CommandResult> Function() callback,
    ) => ActionChip(
      label: Text(label),
      onPressed: widget.device.isOnline ? () => _run(callback) : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeviceHeader(device: widget.device, icon: Icons.blinds),
        const SizedBox(height: 14),
        Text(
          '열림 ${position.toStringAsFixed(0)}% · ${state?.mainState.name ?? '상태 확인 중'}',
        ),
        Slider(
          value: displayedPosition.clamp(0.0, 100.0).toDouble(),
          max: 100,
          divisions: 20,
          onChanged: canSetPosition
              ? (value) => setState(() => _dragPosition = value)
              : null,
          onChangeEnd: canSetPosition
              ? (value) async {
                  await _run(() => widget.motor.setPosition(percent: value));
                  if (mounted) setState(() => _dragPosition = null);
                }
              : null,
        ),
        Wrap(
          spacing: 8,
          children: [
            action('열기', widget.motor.open),
            action('정지', widget.motor.stop),
            action('닫기', widget.motor.close),
            action('환기', widget.motor.ventilate),
          ],
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
    final value = device.latestReading;
    String show(Object? item, String unit) => item == null ? '—' : '$item$unit';
    return Column(
      children: [
        _DeviceHeader(device: device, icon: Icons.air),
        const SizedBox(height: 18),
        Row(
          children: [
            _Reading(label: 'PM2.5', value: show(value?.pm2_5, ' µg/m³')),
            _Reading(label: '온도', value: show(value?.temperatureC, '°')),
            _Reading(label: '습도', value: show(value?.humidityPercent, '%')),
          ],
        ),
      ],
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}
