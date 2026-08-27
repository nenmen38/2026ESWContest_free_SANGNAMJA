import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/sdk_scope.dart';
import '../pairing/connection_page.dart';
import '../pairing/pairing_flow.dart';

class DeviceManagementPage extends ConsumerStatefulWidget {
  const DeviceManagementPage({super.key});

  @override
  ConsumerState<DeviceManagementPage> createState() =>
      _DeviceManagementPageState();
}

class _DeviceManagementPageState extends ConsumerState<DeviceManagementPage> {
  bool _busy = false;

  Future<void> _addDevice() async {
    setState(() => _busy = true);
    await openDevicePairing(context, ref);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _changeCredentials() async {
    final saved = await ref.read(appStorageProvider).readCredentials();
    if (!mounted) return;
    await Navigator.of(context).push<EswConnectionConfig>(
      MaterialPageRoute(
        builder: (_) => ConnectionPage(initialCredentials: saved),
      ),
    );
  }

  Future<void> _deleteCredentials() async {
    setState(() => _busy = true);
    await ref.read(sdkProvider).disconnect();
    await ref.read(appStorageProvider).clearCredentials();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('저장된 서비스 계정을 삭제했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sdk = ref.watch(sdkProvider);
    final state = ref.watch(sdkStateProvider).value ?? sdk.currentState;
    final connected = state.connection == EswConnectionState.connected;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: const Text(
          '장치 관리',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Card(
                  child: ListTile(
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3182F6).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        connected
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_off_outlined,
                        color: const Color(0xFF3182F6),
                      ),
                    ),
                    title: Text(
                      connected ? '서비스 연결됨' : '서비스 연결 필요',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('${state.devices.length}개 장치 확인됨'),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _addDevice,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('새 장치 추가'),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.manage_accounts_outlined),
                        title: const Text('서비스 계정 변경'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : _changeCredentials,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('저장된 계정 삭제'),
                        textColor: Theme.of(context).colorScheme.error,
                        iconColor: Theme.of(context).colorScheme.error,
                        onTap: _busy ? null : _deleteCredentials,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
