import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/sdk_scope.dart';
import '../environment/environment_models.dart';
import '../environment/environment_scope.dart';

class InstallationLocationPage extends ConsumerStatefulWidget {
  const InstallationLocationPage({this.initialSetup = false, super.key});

  final bool initialSetup;

  @override
  ConsumerState<InstallationLocationPage> createState() =>
      _InstallationLocationPageState();
}

class _InstallationLocationPageState
    extends ConsumerState<InstallationLocationPage> {
  final _formKey = GlobalKey<FormState>();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final location = await ref
        .read(appStorageProvider)
        .readInstallationLocation();
    if (!mounted || location == null) return;
    _latitude.text = '${location.latitude}';
    _longitude.text = '${location.longitude}';
  }

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final location = await ref.read(locationServiceProvider).current();
      if (!mounted) return;
      _latitude.text = '${location.latitude}';
      _longitude.text = '${location.longitude}';
      await _save(location);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveManual() async {
    if (!_formKey.currentState!.validate()) return;
    final location = InstallationLocation(
      latitude: double.parse(_latitude.text.trim()),
      longitude: double.parse(_longitude.text.trim()),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _save(location);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(InstallationLocation location) async {
    location.validate();
    await ref.read(appStorageProvider).writeInstallationLocation(location);
    ref.invalidate(installationLocationProvider);
    ref.invalidate(rawOutdoorWeatherProvider);
    if (mounted) Navigator.of(context).pop(true);
  }

  String? _coordinateValidator(String? value, double min, double max) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || !parsed.isFinite) return '숫자를 입력해 주세요.';
    if (parsed < min || parsed > max) return '$min부터 $max 사이여야 합니다.';
    return null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(title: Text(widget.initialSetup ? '설치 위치 설정' : '설치 위치')),
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
                    widget.initialSetup
                        ? '외부 공기를 확인할\n창문 위치를 설정해 주세요'
                        : '외부 날씨를 조회할 위치',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '현재 위치는 설치 좌표로 저장되며 언제든 설정에서 바꿀 수 있습니다.',
                    style: TextStyle(color: Color(0xFF6B7684), height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _useCurrentLocation,
                    icon: const Icon(Icons.my_location),
                    label: Text(_busy ? '위치 확인 중...' : '휴대폰 현재 위치 사용'),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('또는 좌표 직접 입력'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _latitude,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      filled: true,
                      labelText: '위도',
                      hintText: '예: 37.5665',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => _coordinateValidator(value, -90, 90),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _longitude,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      filled: true,
                      labelText: '경도',
                      hintText: '예: 126.9780',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        _coordinateValidator(value, -180, 180),
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
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _saveManual,
                    child: const Text('이 좌표 저장'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
