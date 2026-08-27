import 'dart:convert';

import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sdk_scope.dart';

const defaultBrokerHost = String.fromEnvironment(
  'MQTT_HOST',
  defaultValue: 'broker.example.com',
);
const defaultBrokerPort = int.fromEnvironment('MQTT_PORT', defaultValue: 8883);

final credentialStoreProvider = Provider<CredentialStore>(
  (_) => CredentialStore(),
);

final class CredentialStore {
  CredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'esw.connection';
  final FlutterSecureStorage _storage;

  Future<void> save(EswConnectionConfig config) => _storage.write(
    key: _key,
    value: jsonEncode({
      'server': config.server,
      'port': config.port,
      'account': config.account,
      'secret': config.secret,
    }),
  );

  Future<EswConnectionConfig?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      final config = EswConnectionConfig(
        server: value['server'] as String,
        port: value['port'] as int,
        account: value['account'] as String,
        secret: value['secret'] as String,
      );
      config.validate();
      return config;
    } on Object {
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: _key);
}

class ConnectionPage extends ConsumerStatefulWidget {
  const ConnectionPage({this.initialProfile, super.key});

  final EswConnectionConfig? initialProfile;

  @override
  ConsumerState<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends ConsumerState<ConnectionPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _server;
  late final TextEditingController _port;
  late final TextEditingController _account;
  late final TextEditingController _secret;
  bool _busy = false;
  bool _showSecret = false;
  String? _error;

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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sdkProvider).connect(profile);
      await ref.read(credentialStoreProvider).save(profile);
      if (mounted) Navigator.of(context).pop(profile);
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlySdkError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    await ref.read(credentialStoreProvider).clear();
    _account.clear();
    _secret.clear();
    if (mounted) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('서비스 연결')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('연결 정보는 이 휴대폰의 보안 저장소에만 보관됩니다.'),
            const SizedBox(height: 20),
            _field(_server, '서비스 주소', Icons.dns_outlined),
            _field(
              _port,
              '포트',
              Icons.numbers,
              keyboardType: TextInputType.number,
              validator: (value) {
                final port = int.tryParse(value ?? '');
                return port == null || port < 1 || port > 65535
                    ? '1~65535 사이의 포트를 입력하세요.'
                    : null;
              },
            ),
            _field(_account, '앱 계정', Icons.person_outline),
            TextFormField(
              controller: _secret,
              enabled: !_busy,
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
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: Text(_busy ? '연결 중...' : '연결하고 저장'),
            ),
            TextButton(
              onPressed: _busy ? null : _clear,
              child: const Text('저장된 연결 정보 삭제'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator:
          validator ??
          (value) =>
              value == null || value.trim().isEmpty ? '$label을 입력하세요.' : null,
    ),
  );
}

String friendlySdkError(Object error) => switch (error) {
  final EswSdkException value => value.message,
  final StateError value => value.message,
  _ => '$error',
};
