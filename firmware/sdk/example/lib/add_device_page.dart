import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'demo_controller.dart';
import 'provisioning_qr_scanner.dart';

class AddDevicePage extends ConsumerStatefulWidget {
  const AddDevicePage({required this.profile, super.key});

  final EswConnectionConfig profile;

  @override
  ConsumerState<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends ConsumerState<AddDevicePage> {
  final _pop = TextEditingController();
  final _wifiPassword = TextEditingController();
  int _step = 0;
  bool _showManualSetup = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(demoControllerProvider.notifier).resetProvisioning(),
    );
  }

  @override
  void dispose() {
    _pop.dispose();
    _wifiPassword.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final payload = await Navigator.of(context).push<ProvisioningQrPayload>(
      MaterialPageRoute(builder: (_) => const ProvisioningQrScannerPage()),
    );
    if (!mounted || payload == null) return;
    _pop.text = payload.pop;
    final controller = ref.read(demoControllerProvider.notifier);
    final found = await controller.startQrSetup(payload);
    if (!mounted || !found) return;
    setState(() => _step = 1);
  }

  Future<void> _scanNearby() async {
    setState(() => _showManualSetup = true);
    await ref.read(demoControllerProvider.notifier).scanDevices();
  }

  Future<void> _loadWifi() async {
    final success = await ref
        .read(demoControllerProvider.notifier)
        .scanWifi(_pop.text.trim());
    if (mounted && success) setState(() => _step = 1);
  }

  void _continueToCredentials() {
    if (ref.read(demoControllerProvider).selectedNetwork == null) {
      _notice('연결할 Wi-Fi를 선택하세요.');
      return;
    }
    setState(() => _step = 2);
  }

  Future<void> _provision() async {
    final state = ref.read(demoControllerProvider);
    final device = state.selectedDevice;
    final network = state.selectedNetwork;
    if (device == null || network == null) return;
    setState(() => _step = 3);
    final success = await ref
        .read(demoControllerProvider.notifier)
        .completeSetup(_wifiPassword.text);
    if (!mounted) return;
    setState(() => _step = success ? 4 : 2);
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoControllerProvider);
    final completed = _step == 4;
    return PopScope(
      canPop: !state.busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(completed ? '기기 추가 완료' : '기기 추가'),
          leading: IconButton(
            onPressed: state.busy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: '닫기',
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (!completed) _StepHeader(currentStep: _step.clamp(0, 3)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _content(state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(DemoState state) => switch (_step) {
    0 => _deviceStep(state),
    1 => _wifiStep(state),
    2 => _credentialStep(state),
    3 => _progressStep(state),
    _ => _completeStep(state),
  };

  Widget _deviceStep(DemoState state) => _StepBody(
    key: const ValueKey('device'),
    title: '추가할 기기를 준비하세요',
    description: '기기의 전원을 켜고 상태 표시등이 등록 대기 상태인지 확인하세요.',
    children: [
      const _DeviceIllustration(),
      const _Requirement(
        icon: Icons.power_settings_new,
        text: '기기의 전원이 켜져 있어요',
      ),
      const _Requirement(icon: Icons.bluetooth, text: '휴대폰의 Bluetooth가 켜져 있어요'),
      const _Requirement(
        icon: Icons.near_me_outlined,
        text: '기기와 휴대폰이 가까이 있어요',
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: state.busy ? null : _scanQr,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('QR 코드로 기기 찾기'),
      ),
      OutlinedButton(
        onPressed: state.busy ? null : _scanNearby,
        child: const Text('QR 코드 없이 찾기'),
      ),
      if (_showManualSetup) ...[
        const SizedBox(height: 12),
        _StatusBanner(state: state),
        ...state.nearby.map(
          (device) => _SelectionTile(
            selected: state.selectedDevice?.id == device.id,
            icon: device.name.startsWith('PROV-MOTOR-')
                ? Icons.blinds
                : Icons.air,
            title: _friendlyDeviceName(device.name),
            subtitle: '${device.name} · 신호 ${device.rssi} dBm',
            onTap: state.busy
                ? null
                : () => ref
                      .read(demoControllerProvider.notifier)
                      .selectDevice(device),
          ),
        ),
        TextField(
          controller: _pop,
          enabled: !state.busy,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '기기 인증 코드 (PoP)',
            hintText: '제품 라벨의 인증 코드',
            prefixIcon: Icon(Icons.key_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton(
          onPressed: state.busy || state.selectedDevice == null
              ? null
              : _loadWifi,
          child: const Text('다음'),
        ),
      ],
    ],
  );

  Widget _wifiStep(DemoState state) => _StepBody(
    key: const ValueKey('wifi'),
    title: 'Wi-Fi를 선택하세요',
    description: '기기가 사용할 Wi-Fi에 연결합니다. 기기에서 감지한 네트워크만 표시됩니다.',
    onBack: state.busy ? null : () => setState(() => _step = 0),
    children: [
      _StatusBanner(state: state),
      if (state.networks.isEmpty)
        OutlinedButton.icon(
          onPressed: state.busy ? null : _loadWifi,
          icon: const Icon(Icons.refresh),
          label: const Text('Wi-Fi 다시 검색'),
        )
      else
        ...state.networks.map(
          (network) => _SelectionTile(
            selected: state.selectedNetwork == network,
            icon: _wifiIcon(network.rssi),
            title: network.ssid.isEmpty ? '숨겨진 네트워크' : network.ssid,
            subtitle: '${network.rssi} dBm',
            onTap: state.busy
                ? null
                : () => ref
                      .read(demoControllerProvider.notifier)
                      .selectNetwork(network),
          ),
        ),
      const SizedBox(height: 8),
      TextField(
        controller: _wifiPassword,
        enabled: !state.busy,
        obscureText: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Wi-Fi 비밀번호',
          prefixIcon: Icon(Icons.lock_outline),
          border: OutlineInputBorder(),
        ),
      ),
      FilledButton(
        onPressed: state.busy ? null : _continueToCredentials,
        child: const Text('다음'),
      ),
    ],
  );

  Widget _credentialStep(DemoState state) => _StepBody(
    key: const ValueKey('credentials'),
    title: '추가할 정보를 확인하세요',
    description: '선택한 Wi-Fi와 연결할 서비스를 확인하세요.',
    onBack: state.busy ? null : () => setState(() => _step = 1),
    children: [
      _SummaryRow(
        icon: Icons.router_outlined,
        label: 'Wi-Fi',
        value: state.selectedNetwork?.ssid ?? '선택 안 됨',
      ),
      _SummaryRow(
        icon: Icons.cloud_outlined,
        label: '서비스',
        value: '${widget.profile.server}:${widget.profile.port}',
      ),
      _StatusBanner(state: state),
      FilledButton.icon(
        onPressed: state.busy ? null : _provision,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('기기 추가'),
      ),
    ],
  );

  Widget _progressStep(DemoState state) => _StepBody(
    key: const ValueKey('progress'),
    title: '기기를 연결하고 있어요',
    description: '앱을 닫거나 기기의 전원을 끄지 마세요.',
    children: [
      const SizedBox(height: 48),
      const Center(child: CircularProgressIndicator()),
      const SizedBox(height: 32),
      _StatusBanner(state: state),
      const _ProgressItem(text: 'Wi-Fi 정보 전달', done: true),
      const _ProgressItem(text: 'Wi-Fi 연결', done: true),
      const _ProgressItem(text: '기기 온라인 상태 확인', done: false),
    ],
  );

  Widget _completeStep(DemoState state) => _StepBody(
    key: const ValueKey('complete'),
    title: '기기가 추가되었습니다',
    description: '이제 홈에서 기기 상태를 확인하고 제어할 수 있습니다.',
    children: [
      const SizedBox(height: 28),
      Center(
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      const SizedBox(height: 20),
      _StatusBanner(state: state),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('홈으로 이동'),
      ),
    ],
  );

  static String _friendlyDeviceName(String name) =>
      name.startsWith('PROV-MOTOR-')
      ? '스마트 환기창'
      : name.startsWith('PROV-SENSOR-')
      ? '공기질 센서'
      : '새 기기';

  static IconData _wifiIcon(int rssi) => rssi >= -55
      ? Icons.signal_wifi_4_bar
      : rssi >= -70
      ? Icons.network_wifi_3_bar
      : Icons.network_wifi_1_bar;
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.currentStep});
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    const labels = ['기기', 'Wi-Fi', '확인', '연결'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0)
              Expanded(
                child: Divider(
                  color: index <= currentStep
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  thickness: 2,
                ),
              ),
            Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: index <= currentStep
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: index < currentStep
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: Theme.of(context).colorScheme.onPrimary,
                        )
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: index == currentStep
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[index],
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.title,
    required this.description,
    required this.children,
    this.onBack,
    super.key,
  });

  final String title;
  final String description;
  final List<Widget> children;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
    children: [
      if (onBack != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('이전'),
          ),
        ),
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(
        description,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 24),
      ...children.map(
        (child) =>
            Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
      ),
    ],
  );
}

class _DeviceIllustration extends StatelessWidget {
  const _DeviceIllustration();

  @override
  Widget build(BuildContext context) => Container(
    height: 148,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Theme.of(context).colorScheme.primaryContainer,
          Theme.of(context).colorScheme.secondaryContainer,
        ],
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.phone_android, size: 62),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 22),
          child: Icon(Icons.bluetooth_connected, size: 34),
        ),
        Icon(Icons.sensors, size: 62),
      ],
    ),
  );
}

class _Requirement extends StatelessWidget {
  const _Requirement({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(child: Text(text)),
    ],
  );
}

class _SelectionTile extends StatelessWidget {
  const _SelectionTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(selected ? Icons.check_circle : Icons.circle_outlined),
          ],
        ),
      ),
    ),
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.state});
  final DemoState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state.messageKind) {
      DemoMessageKind.info => Theme.of(context).colorScheme.secondaryContainer,
      DemoMessageKind.success => Colors.green.shade100,
      DemoMessageKind.error => Theme.of(context).colorScheme.errorContainer,
    };
    final icon = switch (state.messageKind) {
      DemoMessageKind.info => Icons.info_outline,
      DemoMessageKind.success => Icons.check_circle_outline,
      DemoMessageKind.error => Icons.error_outline,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (state.busy)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(state.status)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Text(label),
      const Spacer(),
      Flexible(child: Text(value, textAlign: TextAlign.end)),
    ],
  );
}

class _ProgressItem extends StatelessWidget {
  const _ProgressItem({required this.text, required this.done});
  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      done ? Icons.check_circle : Icons.more_horiz,
      color: done ? Colors.green : Theme.of(context).colorScheme.primary,
    ),
    title: Text(text),
  );
}
