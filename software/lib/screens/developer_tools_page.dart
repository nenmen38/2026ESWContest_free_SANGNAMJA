import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../environment/environment_models.dart';
import '../environment/environment_scope.dart';

class DeveloperToolsPage extends ConsumerStatefulWidget {
  const DeveloperToolsPage({super.key});

  @override
  ConsumerState<DeveloperToolsPage> createState() => _DeveloperToolsPageState();
}

class _DeveloperToolsPageState extends ConsumerState<DeveloperToolsPage> {
  final _indoorFormKey = GlobalKey<FormState>();
  final _outdoorFormKey = GlobalKey<FormState>();
  final _indoorTemperature = TextEditingController();
  final _indoorHumidity = TextEditingController();
  final _indoorPm25 = TextEditingController();
  final _outdoorTemperature = TextEditingController();
  final _outdoorHumidity = TextEditingController();
  final _outdoorPm25 = TextEditingController();
  final _outdoorPrecipitation = TextEditingController();
  bool _initialized = false;
  bool _savingIndoor = false;
  bool _savingOutdoor = false;
  bool _clearingAll = false;

  @override
  void dispose() {
    _indoorTemperature.dispose();
    _indoorHumidity.dispose();
    _indoorPm25.dispose();
    _outdoorTemperature.dispose();
    _outdoorHumidity.dispose();
    _outdoorPm25.dispose();
    _outdoorPrecipitation.dispose();
    super.dispose();
  }

  void _initialize(
    IndoorEnvironmentOverride? indoor,
    OutdoorEnvironmentOverride? outdoor,
  ) {
    _indoorTemperature.text = _text(indoor?.temperatureC);
    _indoorHumidity.text = _text(indoor?.humidityPercent);
    _indoorPm25.text = _text(indoor?.pm2_5);
    _outdoorTemperature.text = _text(outdoor?.temperatureC);
    _outdoorHumidity.text = _text(outdoor?.humidityPercent);
    _outdoorPm25.text = _text(outdoor?.pm2_5);
    _outdoorPrecipitation.text = _text(outdoor?.precipitationMm);
    _initialized = true;
  }

  String _text(double? value) => value == null ? '' : '$value';

  double? _value(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : double.parse(text);
  }

  Future<void> _saveIndoor() async {
    if (!_indoorFormKey.currentState!.validate()) return;
    setState(() => _savingIndoor = true);
    try {
      await ref
          .read(indoorEnvironmentOverrideProvider.notifier)
          .replace(
            temperatureC: _value(_indoorTemperature),
            humidityPercent: _value(_indoorHumidity),
            pm2_5: _value(_indoorPm25),
          );
      _showMessage('실내 환경 테스트값을 적용했습니다.');
    } on Object catch (error) {
      _showMessage('실내 환경 테스트값을 저장하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _savingIndoor = false);
    }
  }

  Future<void> _saveOutdoor() async {
    if (!_outdoorFormKey.currentState!.validate()) return;
    setState(() => _savingOutdoor = true);
    try {
      await ref
          .read(outdoorEnvironmentOverrideProvider.notifier)
          .replace(
            temperatureC: _value(_outdoorTemperature),
            humidityPercent: _value(_outdoorHumidity),
            pm2_5: _value(_outdoorPm25),
            precipitationMm: _value(_outdoorPrecipitation),
          );
      _showMessage('실외 환경 테스트값을 적용했습니다.');
    } on Object catch (error) {
      _showMessage('실외 환경 테스트값을 저장하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _savingOutdoor = false);
    }
  }

  Future<void> _clearIndoor() async {
    setState(() => _savingIndoor = true);
    try {
      await ref.read(indoorEnvironmentOverrideProvider.notifier).clearAll();
      _indoorTemperature.clear();
      _indoorHumidity.clear();
      _indoorPm25.clear();
      _showMessage('실내 환경을 실데이터로 복원했습니다.');
    } on Object catch (error) {
      _showMessage('실내 환경 테스트값을 해제하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _savingIndoor = false);
    }
  }

  Future<void> _clearOutdoor() async {
    setState(() => _savingOutdoor = true);
    try {
      await ref.read(outdoorEnvironmentOverrideProvider.notifier).clearAll();
      _outdoorTemperature.clear();
      _outdoorHumidity.clear();
      _outdoorPm25.clear();
      _outdoorPrecipitation.clear();
      _showMessage('실외 환경을 실데이터로 복원했습니다.');
    } on Object catch (error) {
      _showMessage('실외 환경 테스트값을 해제하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _savingOutdoor = false);
    }
  }

  Future<void> _clearAll() async {
    setState(() => _clearingAll = true);
    try {
      await Future.wait([
        ref.read(indoorEnvironmentOverrideProvider.notifier).clearAll(),
        ref.read(outdoorEnvironmentOverrideProvider.notifier).clearAll(),
      ]);
      _indoorTemperature.clear();
      _indoorHumidity.clear();
      _indoorPm25.clear();
      _outdoorTemperature.clear();
      _outdoorHumidity.clear();
      _outdoorPm25.clear();
      _outdoorPrecipitation.clear();
      _showMessage('모든 환경 데이터를 실데이터로 복원했습니다.');
    } on Object catch (error) {
      _showMessage('환경 테스트값을 해제하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _clearingAll = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final indoor = ref.watch(indoorEnvironmentOverrideProvider);
    final outdoor = ref.watch(outdoorEnvironmentOverrideProvider);
    if (indoor.isLoading || outdoor.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (indoor.hasError || outdoor.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('개발자 도구')),
        body: Center(
          child: FilledButton.icon(
            onPressed: () {
              ref.invalidate(indoorEnvironmentOverrideProvider);
              ref.invalidate(outdoorEnvironmentOverrideProvider);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('다시 불러오기'),
          ),
        ),
      );
    }
    if (!_initialized) _initialize(indoor.value, outdoor.value);
    final busy = _savingIndoor || _savingOutdoor || _clearingAll;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: const Text(
          '개발자 도구',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              key: const ValueKey('developer_tools.list'),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.science_outlined, color: Color(0xFFFF8A00)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '테스트용 환경 데이터입니다. 비워 둔 항목은 실제 데이터를 사용하며, 입력한 테스트값은 앱을 다시 시작해도 유지됩니다.',
                          style: TextStyle(
                            color: Color(0xFF6B4F1D),
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _OverrideSection(
                  title: '실내 환경',
                  isActive: indoor.value?.isActive ?? false,
                  formKey: _indoorFormKey,
                  fields: [
                    _NumberField(
                      fieldKey: const ValueKey('indoor.temperatureC'),
                      controller: _indoorTemperature,
                      label: '기온',
                      unit: '°C',
                      minimum: -100,
                      maximum: 100,
                    ),
                    _NumberField(
                      fieldKey: const ValueKey('indoor.humidityPercent'),
                      controller: _indoorHumidity,
                      label: '습도',
                      unit: '%',
                      minimum: 0,
                      maximum: 100,
                    ),
                    _NumberField(
                      fieldKey: const ValueKey('indoor.pm2_5'),
                      controller: _indoorPm25,
                      label: 'PM2.5',
                      unit: '㎍/㎥',
                      minimum: 0,
                      maximum: 10000,
                    ),
                  ],
                  busy: _savingIndoor || _clearingAll,
                  applyKey: const ValueKey('indoor.apply'),
                  clearKey: const ValueKey('indoor.clear'),
                  onApply: _saveIndoor,
                  onClear: _clearIndoor,
                ),
                const SizedBox(height: 16),
                _OverrideSection(
                  title: '실외 환경',
                  isActive: outdoor.value?.isActive ?? false,
                  formKey: _outdoorFormKey,
                  fields: [
                    _NumberField(
                      fieldKey: const ValueKey('outdoor.temperatureC'),
                      controller: _outdoorTemperature,
                      label: '기온',
                      unit: '°C',
                      minimum: -100,
                      maximum: 100,
                    ),
                    _NumberField(
                      fieldKey: const ValueKey('outdoor.humidityPercent'),
                      controller: _outdoorHumidity,
                      label: '습도',
                      unit: '%',
                      minimum: 0,
                      maximum: 100,
                    ),
                    _NumberField(
                      fieldKey: const ValueKey('outdoor.pm2_5'),
                      controller: _outdoorPm25,
                      label: 'PM2.5',
                      unit: '㎍/㎥',
                      minimum: 0,
                      maximum: 10000,
                    ),
                    _NumberField(
                      fieldKey: const ValueKey('outdoor.precipitationMm'),
                      controller: _outdoorPrecipitation,
                      label: '강수량',
                      unit: 'mm',
                      minimum: 0,
                      maximum: 1000,
                    ),
                  ],
                  busy: _savingOutdoor || _clearingAll,
                  applyKey: const ValueKey('outdoor.apply'),
                  clearKey: const ValueKey('outdoor.clear'),
                  onApply: _saveOutdoor,
                  onClear: _clearOutdoor,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const ValueKey('environment.clearAll'),
                  onPressed: busy ? null : _clearAll,
                  icon: const Icon(Icons.restore),
                  label: const Text('모든 테스트값 해제'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
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

class _OverrideSection extends StatelessWidget {
  const _OverrideSection({
    required this.title,
    required this.isActive,
    required this.formKey,
    required this.fields,
    required this.busy,
    required this.applyKey,
    required this.clearKey,
    required this.onApply,
    required this.onClear,
  });

  final String title;
  final bool isActive;
  final GlobalKey<FormState> formKey;
  final List<Widget> fields;
  final bool busy;
  final Key applyKey;
  final Key clearKey;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color:
                      (isActive
                              ? const Color(0xFFFF8A00)
                              : const Color(0xFF8B95A1))
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isActive ? '테스트값 사용' : '실데이터',
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFFD96F00)
                        : const Color(0xFF6B7684),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...fields.expand((field) => [field, const SizedBox(height: 12)]),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: clearKey,
                  onPressed: busy ? null : onClear,
                  child: const Text('실데이터로 복원'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: applyKey,
                  onPressed: busy ? null : onApply,
                  child: const Text('적용'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.unit,
    required this.minimum,
    required this.maximum,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String unit;
  final double minimum;
  final double maximum;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: fieldKey,
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    decoration: InputDecoration(
      labelText: label,
      suffixText: unit,
      helperText: '비워두면 실데이터 사용',
      border: const OutlineInputBorder(),
    ),
    validator: (raw) {
      final text = raw?.trim() ?? '';
      if (text.isEmpty) return null;
      final value = double.tryParse(text);
      if (value == null || !value.isFinite) return '숫자를 입력해 주세요.';
      if (value < minimum || value > maximum) {
        return '$minimum부터 $maximum 사이여야 합니다.';
      }
      return null;
    },
  );
}
