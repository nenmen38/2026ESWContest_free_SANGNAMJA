import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/sdk_scope.dart';
import 'add_device_page.dart';
import 'connection_page.dart';

Future<bool> openDevicePairing(
  BuildContext context,
  WidgetRef ref, {
  Future<ProvisioningQrPayload?> Function(BuildContext context)? scanQr,
  bool requireMotorAndSensor = false,
}) async {
  final sdk = ref.read(sdkProvider);
  var credentials = await ref.read(appStorageProvider).readCredentials();
  var connected = sdk.currentState.connection == EswConnectionState.connected;

  if (!connected && credentials != null) {
    try {
      await sdk.connect(credentials);
      connected = true;
    } on Object {
      connected = false;
    }
  }

  if (!context.mounted) return false;
  if (!connected) {
    credentials = await Navigator.of(context).push<EswConnectionConfig>(
      MaterialPageRoute(
        builder: (_) => ConnectionPage(initialCredentials: credentials),
      ),
    );
    if (!context.mounted || credentials == null) return false;
  }

  if (requireMotorAndSensor) {
    return await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => RequiredDevicePairingPage(scanQr: scanQr),
          ),
        ) ??
        false;
  }

  final device = await Navigator.of(context).push<SetupDevice>(
    MaterialPageRoute(builder: (_) => AddDevicePage(scanQr: scanQr)),
  );
  return device != null;
}

enum ProvisioningDeviceRole { motor, sensor }

ProvisioningDeviceRole? roleFromProvisioningServiceName(String serviceName) {
  if (RegExp(r'^PROV-MOTOR-[0-9A-F]{4}$').hasMatch(serviceName)) {
    return ProvisioningDeviceRole.motor;
  }
  if (RegExp(r'^PROV-SENSOR-[0-9A-F]{4}$').hasMatch(serviceName)) {
    return ProvisioningDeviceRole.sensor;
  }
  return null;
}

class RequiredDevicePairingPage extends ConsumerStatefulWidget {
  const RequiredDevicePairingPage({this.scanQr, super.key});

  final Future<ProvisioningQrPayload?> Function(BuildContext context)? scanQr;

  @override
  ConsumerState<RequiredDevicePairingPage> createState() =>
      _RequiredDevicePairingPageState();
}

class _RequiredDevicePairingPageState
    extends ConsumerState<RequiredDevicePairingPage> {
  final Set<ProvisioningDeviceRole> _connectedRoles = {};
  bool _busy = false;

  bool get _complete =>
      _connectedRoles.contains(ProvisioningDeviceRole.motor) &&
      _connectedRoles.contains(ProvisioningDeviceRole.sensor);

  Future<void> _addDevice() async {
    setState(() => _busy = true);
    final device = await Navigator.of(context).push<SetupDevice>(
      MaterialPageRoute(builder: (_) => AddDevicePage(scanQr: widget.scanQr)),
    );
    if (!mounted) return;
    final role = device == null
        ? null
        : roleFromProvisioningServiceName(device.name);
    setState(() {
      _busy = false;
      if (role != null) _connectedRoles.add(role);
    });
    if (device != null && role == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('모터 또는 센서 장치만 연결할 수 있어요.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6F8),
    appBar: AppBar(title: const Text('필수 장치 연결')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '모터와 센서를\n모두 연결해 주세요',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900, height: 1.3),
                ),
                const SizedBox(height: 10),
                const Text(
                  '장치의 프로비저닝 서비스 이름으로 모터와 센서를 구분해요.',
                  style: TextStyle(
                    color: Color(0xFF6B7684),
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                _roleCard(
                  role: ProvisioningDeviceRole.motor,
                  icon: Icons.settings_remote_outlined,
                  title: '모터',
                  description: '창문을 열고 닫는 장치',
                ),
                const SizedBox(height: 12),
                _roleCard(
                  role: ProvisioningDeviceRole.sensor,
                  icon: Icons.sensors_outlined,
                  title: '센서',
                  description: '공기와 주변 환경을 측정하는 장치',
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _busy || _complete ? null : _addDevice,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  icon: const Icon(Icons.add_link),
                  label: Text(_nextDeviceLabel),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _complete
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  child: const Text('스마트 창문 시작하기'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  String get _nextDeviceLabel {
    if (!_connectedRoles.contains(ProvisioningDeviceRole.motor)) {
      return '모터 연결하기';
    }
    return '센서 연결하기';
  }

  Widget _roleCard({
    required ProvisioningDeviceRole role,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final connected = _connectedRoles.contains(role);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Icon(
          connected ? Icons.check_circle : icon,
          color: connected ? const Color(0xFF3182F6) : null,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(description),
        trailing: Text(
          connected ? '연결됨' : '연결 필요',
          style: TextStyle(
            color: connected
                ? const Color(0xFF3182F6)
                : const Color(0xFF6B7684),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
