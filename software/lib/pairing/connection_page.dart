import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/sdk_scope.dart';
import 'pairing_errors.dart';

const mqttHost = String.fromEnvironment('MQTT_HOST');
const mqttPort = int.fromEnvironment('MQTT_PORT', defaultValue: 8883);

class ConnectionPage extends ConsumerStatefulWidget {
  const ConnectionPage({this.initialCredentials, super.key});

  final EswConnectionConfig? initialCredentials;

  @override
  ConsumerState<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends ConsumerState<ConnectionPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _account;
  late final TextEditingController _secret;
  bool _busy = false;
  bool _showSecret = false;
  String? _error;

  bool get _configured =>
      mqttHost.trim().isNotEmpty && mqttPort >= 1 && mqttPort <= 65535;

  @override
  void initState() {
    super.initState();
    _account = TextEditingController(
      text: widget.initialCredentials?.account ?? '',
    );
    _secret = TextEditingController(
      text: widget.initialCredentials?.secret ?? '',
    );
  }

  @override
  void dispose() {
    _account.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_configured || !_formKey.currentState!.validate()) return;
    final config = EswConnectionConfig(
      server: mqttHost,
      port: mqttPort,
      account: _account.text.trim(),
      secret: _secret.text,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sdkProvider).connect(config);
      await ref.read(appStorageProvider).writeCredentials(config);
      if (mounted) Navigator.of(context).pop(config);
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlySdkError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6F8),
    appBar: AppBar(title: const Text('서비스 연결')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '장치 등록을 위해 제어 서비스에 연결합니다.',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '서버',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _configured ? '$mqttHost:$mqttPort' : '빌드 설정 필요',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (!_configured)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'MQTT_HOST를 --dart-define으로 지정해 주세요.',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _account,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    filled: true,
                    labelText: '계정',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '계정을 입력해 주세요.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _secret,
                  enabled: !_busy,
                  obscureText: !_showSecret,
                  decoration: InputDecoration(
                    filled: true,
                    labelText: '비밀번호',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _showSecret = !_showSecret),
                      icon: Icon(
                        _showSecret ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                  validator: (value) =>
                      value == null || value.isEmpty ? '비밀번호를 입력해 주세요.' : null,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy || !_configured ? null : _connect,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(_busy ? '연결 중...' : '연결하고 저장'),
                ),
                const SizedBox(height: 10),
                const Text(
                  '계정 정보는 이 기기의 보안 저장소에만 보관됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7684)),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
