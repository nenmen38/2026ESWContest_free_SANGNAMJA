import 'dart:math' as math;

import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/sdk_scope.dart';
import 'app/startup_gate.dart';
import 'environment/environment_models.dart';
import 'environment/environment_scope.dart';
import 'screens/settings_page.dart';

void main() {
  runApp(const ProviderScope(child: SmartWindowApp()));
}

class SmartWindowApp extends StatelessWidget {
  const SmartWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const tossBlue = Color(0xFF3182F6);

    return MaterialApp(
      title: 'Safe Smart Window',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: tossBlue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        fontFamily: 'Roboto',
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: const Color(0xFF191F28),
          displayColor: const Color(0xFF191F28),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      home: const StartupGate(home: SmartWindowHome()),
    );
  }
}

class SmartWindowHome extends ConsumerStatefulWidget {
  const SmartWindowHome({super.key});

  @override
  ConsumerState<SmartWindowHome> createState() => _SmartWindowHomeState();
}

class _SmartWindowHomeState extends ConsumerState<SmartWindowHome>
    with WidgetsBindingObserver {
  bool _autoMode = false;
  bool _commandBusy = false;
  String? _latestActivity;
  double? _manualPositionPercent;
  double? _autoRecommendedPercent;

  double _normalizedPercent(double? value) =>
      (value ?? 0.0).clamp(0.0, 100.0).roundToDouble();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(rawOutdoorWeatherProvider);
    }
  }

  Future<void> _runCommand(
    MotorDeviceSnapshot? motor,
    Future<CommandResult> Function(MotorController controller) command, {
    bool keepAutoMode = false,
  }) async {
    if (_commandBusy) return;
    if (motor == null || !motor.isOnline) {
      _showMessage('선택된 모터가 오프라인이거나 없습니다.');
      return;
    }
    setState(() {
      if (!keepAutoMode) _autoMode = false;
      _commandBusy = true;
    });
    try {
      final result = await command(ref.read(sdkProvider).motor(motor.id));
      if (!mounted) return;
      final message = switch (result.status) {
        CommandStatus.accepted => '명령을 전송했습니다.',
        CommandStatus.deviceOffline => '장치가 오프라인입니다.',
        CommandStatus.feedbackUnavailable => '모터 위치 피드백을 기다리는 중입니다.',
        CommandStatus.positionUnknown => '모터 위치를 확인할 수 없습니다.',
        CommandStatus.hardwareRejected => '모터가 명령을 거부했습니다.',
        CommandStatus.invalidCommand => '지원하지 않는 명령입니다.',
        CommandStatus.duplicateCommand => '이미 처리된 명령입니다.',
        CommandStatus.timeout => '장치 응답 시간이 초과되었습니다.',
      };
      setState(() => _latestActivity = message);
      _showMessage(message);
    } on Object catch (error) {
      if (mounted) _showMessage('명령을 보내지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _commandBusy = false);
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  String _motorActivity(MotorDeviceSnapshot? motor) {
    if (motor == null) return '설정에서 홈 모터를 선택해 주세요';
    final state = motor.latestState;
    if (state == null) return '모터의 첫 상태를 기다리는 중입니다';
    final action = switch (state.mainState) {
      MotorMainState.unknown => '상태 확인 중',
      MotorMainState.idle => '대기',
      MotorMainState.opening => '창문 여는 중',
      MotorMainState.closing => '창문 닫는 중',
      MotorMainState.stopping => '정지 중',
      MotorMainState.fault => '모터 오류',
    };
    final time =
        '${motor.lastSeen.hour.toString().padLeft(2, '0')}:${motor.lastSeen.minute.toString().padLeft(2, '0')}';
    return '$time · $action${motor.isOnline ? '' : ' · 오프라인'}';
  }

  double? _recommendedOpenPercent(
    EnvironmentSnapshot environment,
    HouseProfile profile,
    OutdoorWeatherStatus weather,
  ) {
    final outdoor = weather.reading;
    if (outdoor == null) return null;
    if (environment.indoor.temperatureC == null ||
        environment.outdoor.temperatureC == null ||
        environment.indoor.humidityPercent == null ||
        environment.outdoor.humidityPercent == null) {
      return null;
    }

    final indoorTemp = environment.indoor.temperatureC!;
    final outdoorTemp = environment.outdoor.temperatureC!;
    final indoorHumidity = environment.indoor.humidityPercent!;
    final outdoorHumidity = environment.outdoor.humidityPercent!;
    final windSpeed = outdoor.windSpeed10m ?? 0.0;
    final windDirection = outdoor.windDirection10m;

    if (outdoor.precipitationMm > 0.1 ||
        windSpeed >= 10.0 ||
        (environment.outdoorFineDust.pm25 != null &&
            environment.outdoorFineDust.pm25! >= 36)) {
      return 0;
    }

    final floorAreaFactor = (profile.floorAreaPyeong / 25.0).clamp(0.8, 1.8);
    final orientationFactor = (profile.windowOrientation.exposureFactor * 0.82)
        .clamp(0.75, 1.1);
    final tempDelta = (indoorTemp - outdoorTemp).clamp(0.0, 10.0).toDouble();
    final humidityDelta = (indoorHumidity - outdoorHumidity).abs().clamp(0.0, 25.0);
    final pmDelta = (environment.indoorFineDust.pm25 != null &&
            environment.outdoorFineDust.pm25 != null)
        ? (environment.indoorFineDust.pm25! - environment.outdoorFineDust.pm25!)
            .clamp(0.0, 20.0)
            .toDouble()
        : 0.0;

    final tempScore = tempDelta * 1.8;
    final humidityScore = humidityDelta * 0.8;
    final pmScore = pmDelta * 0.4;
    final windPenalty = (windDirection != null && windSpeed >= 3.0)
        ? (windSpeed * 1.4) * (1.2 / profile.windowOrientation.exposureFactor)
        : 0.0;

    var recommended = (10.0 + tempScore + humidityScore + pmScore - windPenalty) *
        floorAreaFactor *
        orientationFactor;
    if (recommended < 8.0) recommended = 8.0;
    if (recommended > 80.0) recommended = 80.0;

    return recommended.roundToDouble().clamp(0.0, 100.0);
  }

  Future<void> _toggleAutoMode(
    MotorDeviceSnapshot? motor,
    EnvironmentSnapshot environment,
    HouseProfile profile,
    OutdoorWeatherStatus weather, {
    double? currentPercent,
  }) async {
    if (_autoMode) {
      final restore = _normalizedPercent(_manualPositionPercent ?? currentPercent);
      setState(() {
        _autoMode = false;
        _manualPositionPercent = restore;
        _autoRecommendedPercent = null;
      });
      await _runCommand(
        motor,
        (controller) => controller.setPosition(percent: restore),
      );
      setState(() => _latestActivity = '수동 복귀: ${restore.round()}%');
      return;
    }

    final recommended = _recommendedOpenPercent(environment, profile, weather);
    if (recommended == null) {
      _showMessage('추천 계산에 필요한 실내·실외 데이터가 아직 부족합니다.');
      return;
    }

    final normalizedRecommended = _normalizedPercent(recommended);
    setState(() {
      _manualPositionPercent = _normalizedPercent(
        currentPercent ?? _manualPositionPercent ?? 25.0,
      );
      _autoRecommendedPercent = normalizedRecommended;
      _autoMode = true;
    });
    setState(() => _latestActivity = '자동 추천 미리보기: ${normalizedRecommended.round()}%');
  }

  Future<void> _executeAutoRecommendation(
    MotorDeviceSnapshot? motor,
  ) async {
    final recommended = _autoRecommendedPercent;
    if (recommended == null) return;

    final normalizedPercent = _normalizedPercent(recommended);
    setState(() {
      _manualPositionPercent = normalizedPercent;
      _autoRecommendedPercent = normalizedPercent;
    });
    await _runCommand(
      motor,
      (controller) => controller.setPosition(percent: normalizedPercent),
      keepAutoMode: true,
    );
    setState(() => _latestActivity = '자동 실행: ${normalizedPercent.round()}%');
  }

  Future<void> _changePositionManually(
    MotorDeviceSnapshot? motor,
    double? currentPercent,
  ) async {
    final percent = await _askPositionPercent(currentPercent);
    if (percent == null) return;

    final normalizedPercent = _normalizedPercent(percent);
    setState(() {
      _autoMode = false;
      _manualPositionPercent = normalizedPercent;
      _autoRecommendedPercent = null;
    });
    await _runCommand(
      motor,
      (controller) => controller.setPosition(percent: normalizedPercent),
    );
    setState(() => _latestActivity = '수동 설정: ${normalizedPercent.round()}%');
  }

  Future<double?> _askPositionPercent(double? currentPercent) =>
      showDialog<double>(
        context: context,
        builder: (context) =>
            _PositionInputDialog(initialPercent: currentPercent),
      );

  void _openSettings(
    EnvironmentSnapshot environment,
    bool rainLock,
    bool safetyStop,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsPage(
          controlModeLabel: _autoMode ? '자동' : '수동',
          rainProtectionLabel: rainLock ? '비 감지' : '비 없음',
          safetyStopLabel: safetyStop ? '활성' : '대기',
          indoorEnvironmentLabel:
              '${environment.indoor.temperatureLabel} · ${environment.indoor.humidityLabel}',
          outdoorEnvironmentLabel:
              '${environment.outdoor.temperatureLabel} · ${environment.outdoor.humidityLabel}',
          indoorFineDustLabel:
              '${environment.indoorFineDust.levelLabel} · ${environment.indoorFineDust.detailLabel}',
          outdoorFineDustLabel:
              '${environment.outdoorFineDust.levelLabel} · ${environment.outdoorFineDust.detailLabel}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sdk = ref.watch(sdkProvider);
    final sdkState = ref.watch(sdkStateProvider).value ?? sdk.currentState;
    final selected =
        ref.watch(selectedDeviceIdsProvider).value ?? const SelectedDeviceIds();
    final motor = resolveMotor(sdkState, selected);
    final sensor = resolveSensor(sdkState, selected);
    final latestSensorReading = sensor?.latestReading;
    final sensorFresh =
        latestSensorReading != null &&
        sensor?.isOnline == true &&
        !latestSensorReading.hasSensorError &&
        DateTime.now().difference(latestSensorReading.receivedAt) <=
            const Duration(seconds: 15);
    final indoorOverride = ref.watch(indoorEnvironmentOverrideProvider);
    final weather =
        ref.watch(outdoorWeatherProvider).value ??
        const OutdoorWeatherStatus.loading();
    final profile = ref.watch(houseProfileProvider).value ?? const HouseProfile();
    final environment = EnvironmentSnapshot.fromSources(
      indoor: !indoorOverride.isLoading && sensorFresh
          ? latestSensorReading
          : null,
      indoorOverride: indoorOverride.value,
      weather: weather,
    );
    final motorState = motor?.latestState;
    final livePercent = motorState?.positionValid == true
        ? motorState?.currentPositionPercent
        : null;
    final openPercent = _autoMode && _autoRecommendedPercent != null
        ? _autoRecommendedPercent
        : livePercent;
    final safetyStop = motorState?.hasError ?? false;
    final rainLock = environment.isRaining;
    final isLocked = rainLock || safetyStop;
    final controlsEnabled = !_commandBusy && motor?.isOnline == true;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = math.min(constraints.maxWidth, 430.0);

            return Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: screenWidth,
                  height: 760,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AppHeader(
                          isLocked: isLocked,
                          autoMode: _autoMode,
                          updatedAtLabel: environment.updatedAtLabel,
                          onAutoTap: () => _toggleAutoMode(
                            motor,
                            environment,
                            profile,
                            weather,
                            currentPercent: openPercent,
                          ),
                          onSettingsTap: () =>
                              _openSettings(environment, rainLock, safetyStop),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          flex: 38,
                          child: _HeroWindowCard(
                            openPercent: openPercent,
                            isLocked: isLocked,
                            rainLock: rainLock,
                            motorOnline: motor?.isOnline == true,
                            onPositionTap: controlsEnabled
                                ? () => _changePositionManually(
                                    motor,
                                    openPercent,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _QuickControls(
                          isLocked: isLocked || !controlsEnabled,
                          enabled: controlsEnabled,
                          onOpen: () =>
                              _runCommand(motor, (value) => value.open()),
                          onClose: () =>
                              _runCommand(motor, (value) => value.close()),
                          onStop: () =>
                              _runCommand(motor, (value) => value.stop()),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          flex: 28,
                          child: _EnvironmentPanel(
                            environment: environment,
                            rainLock: rainLock,
                            weatherError: weather.error != null,
                            onWeatherRefresh: () =>
                                ref.invalidate(rawOutdoorWeatherProvider),
                          ),
                        ),
                        if (_autoMode && _autoRecommendedPercent != null) ...[
                          const SizedBox(height: 8),
                          _AutoRecommendAction(
                            recommendedPercent: _autoRecommendedPercent!,
                            enabled: controlsEnabled,
                            onExecute: () => _executeAutoRecommendation(motor),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _LatestActivity(
                          text: _latestActivity ?? _motorActivity(motor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PositionInputDialog extends StatefulWidget {
  const _PositionInputDialog({required this.initialPercent});

  final double? initialPercent;

  @override
  State<_PositionInputDialog> createState() => _PositionInputDialogState();
}

class _PositionInputDialogState extends State<_PositionInputDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final initialPercent = widget.initialPercent;
    _controller = TextEditingController(
      text: initialPercent == null ? '' : initialPercent.round().toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final rawValue = _controller.text.trim().replaceAll('%', '');
    final value = double.tryParse(rawValue);
    if (value == null || value < 0 || value > 100) {
      setState(() => _errorText = '0부터 100 사이 숫자를 입력해 주세요.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('개도율 직접 입력'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: '개도율',
          suffixText: '%',
          errorText: _errorText,
        ),
        onChanged: (_) {
          if (_errorText != null) {
            setState(() => _errorText = null);
          }
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('적용')),
      ],
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.isLocked,
    required this.autoMode,
    required this.updatedAtLabel,
    required this.onAutoTap,
    required this.onSettingsTap,
  });

  final bool isLocked;
  final bool autoMode;
  final String updatedAtLabel;
  final VoidCallback onAutoTap;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = isLocked
        ? const Color(0xFFFF8A00)
        : const Color(0xFF3182F6);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '스마트 창문',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 0),
              ),
              const SizedBox(height: 2),
              Text(
                updatedAtLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8B95A1),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        _HeaderButton(
          icon: autoMode ? Icons.auto_mode : Icons.touch_app_outlined,
          label: autoMode ? '자동' : '수동',
          color: const Color(0xFF3182F6),
          onTap: onAutoTap,
        ),
        const SizedBox(width: 8),
        _HeaderButton(
          icon: isLocked ? Icons.shield_outlined : Icons.check_circle_outline,
          label: isLocked ? '보호' : '정상',
          color: statusColor,
        ),
        const SizedBox(width: 8),
        _IconCircleButton(
          icon: Icons.settings_outlined,
          onTap: onSettingsTap,
          tooltip: '설정',
        ),
      ],
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  const _IconCircleButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(icon, size: 21, color: const Color(0xFF4E5968)),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroWindowCard extends StatelessWidget {
  const _HeroWindowCard({
    required this.openPercent,
    required this.isLocked,
    required this.rainLock,
    required this.motorOnline,
    required this.onPositionTap,
  });

  final double? openPercent;
  final bool isLocked;
  final bool rainLock;
  final bool motorOnline;
  final VoidCallback? onPositionTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '창문 개도율',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF6B7684),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: onPositionTap,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(11, 6, 11, 7),
                          decoration: BoxDecoration(
                            color: onPositionTap == null
                                ? const Color(0xFFF2F4F6)
                                : const Color(0xFFE8F2FF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: onPositionTap == null
                                  ? const Color(0xFFE5E8EB)
                                  : const Color(0xFFB9D8FF),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                openPercent == null
                                    ? '—'
                                    : '${openPercent!.round()}%',
                                style: Theme.of(context).textTheme.headlineLarge
                                    ?.copyWith(
                                      color: const Color(0xFF191F28),
                                      fontSize: 34,
                                      fontWeight: FontWeight.w900,
                                      height: 0.95,
                                      letterSpacing: 0,
                                    ),
                              ),
                              const SizedBox(width: 10),
                              if (onPositionTap != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.edit_outlined,
                                        size: 14,
                                        color: const Color(0xFF3182F6),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '직접 입력',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: const Color(0xFF3182F6),
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Text(
                                  '연결 필요',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: const Color(0xFF8B95A1),
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _DecisionBadge(
                  label: isLocked ? '닫힘 유지' : '열기 가능',
                  color: isLocked
                      ? const Color(0xFFFF8A00)
                      : const Color(0xFF3182F6),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(child: _WindowIllustration(openPercent: openPercent ?? 0)),
            const SizedBox(height: 12),
            Text(
              rainLock
                  ? '비가 감지되어 창문 열기를 제한하고 있습니다.'
                  : motorOnline
                  ? '연결된 모터의 실제 상태를 표시하고 있습니다.'
                  : '모터 연결 또는 홈 장치 선택이 필요합니다.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF4E5968),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionBadge extends StatelessWidget {
  const _DecisionBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _WindowIllustration extends StatelessWidget {
  const _WindowIllustration({required this.openPercent});

  final double openPercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = constraints.maxWidth * 0.5;
          final movableLeft = panelWidth * (1 - openPercent / 100);

          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFD5E9FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Positioned(
                  left: panelWidth,
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.50),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: panelWidth,
                  child: const _FixedGlassPanel(),
                ),
                Positioned(
                  left: movableLeft,
                  top: 0,
                  bottom: 0,
                  width: panelWidth,
                  child: const _SlidingGlassPanel(),
                ),
                Positioned(
                  left: panelWidth - 4,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FixedGlassPanel extends StatelessWidget {
  const _FixedGlassPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.72),
          width: 3,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class _SlidingGlassPanel extends StatelessWidget {
  const _SlidingGlassPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.34),
        border: Border.all(color: Colors.white, width: 3),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3182F6).withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: 7,
          height: 46,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF3182F6),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _AutoRecommendAction extends StatelessWidget {
  const _AutoRecommendAction({
    required this.recommendedPercent,
    required this.enabled,
    required this.onExecute,
  });

  final double recommendedPercent;
  final bool enabled;
  final VoidCallback onExecute;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '추천',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF6B7684),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${recommendedPercent.round()}%',
                    key: const ValueKey('auto_recommended_percent'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF3182F6),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('execute_auto_recommendation'),
              onPressed: enabled ? onExecute : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('실행'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickControls extends StatelessWidget {
  const _QuickControls({
    required this.isLocked,
    required this.enabled,
    required this.onOpen,
    required this.onClose,
    required this.onStop,
  });

  final bool isLocked;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: Icons.keyboard_arrow_down,
              label: '닫기',
              color: const Color(0xFF3182F6),
              onTap: enabled ? onClose : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              icon: Icons.stop_circle_outlined,
              label: '정지',
              color: const Color(0xFFFF5A5F),
              onTap: enabled ? onStop : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              icon: Icons.keyboard_arrow_up,
              label: '열기',
              color: isLocked
                  ? const Color(0xFFB0B8C1)
                  : const Color(0xFF3182F6),
              onTap: isLocked || !enabled ? null : onOpen,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xFF333D4B),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvironmentPanel extends StatelessWidget {
  const _EnvironmentPanel({
    required this.environment,
    required this.rainLock,
    required this.weatherError,
    required this.onWeatherRefresh,
  });

  final EnvironmentSnapshot environment;
  final bool rainLock;
  final bool weatherError;
  final VoidCallback onWeatherRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _InfoCard(
                  icon: Icons.home_outlined,
                  title: '실내',
                  value: environment.indoor.temperatureLabel,
                  detail: environment.indoor.humidityLabel,
                  color: const Color(0xFF3182F6),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _InfoCard(
                  icon: Icons.cloud_outlined,
                  title: '실외',
                  value: environment.outdoor.temperatureLabel,
                  detail:
                      weatherError && environment.outdoor.temperatureC == null
                      ? '눌러서 다시 시도'
                      : rainLock
                      ? '${environment.outdoor.humidityLabel} · 비'
                      : environment.outdoor.humidityLabel,
                  color: const Color(0xFFFF8A00),
                  onTap: onWeatherRefresh,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoCard(
            icon: Icons.grain,
            title: 'PM2.5 실내/외',
            value:
                '${environment.indoorFineDust.pm25?.round() ?? '—'} / ${environment.outdoorFineDust.pm25?.round() ?? '—'}',
            detail:
                '${environment.indoorFineDust.levelLabel} / ${environment.outdoorFineDust.levelLabel}',
            color: const Color(0xFF6B7684),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF4E5968),
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF191F28),
                fontWeight: FontWeight.w900,
                height: 1.05,
                letterSpacing: 0,
              ),
            ),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF4E5968),
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestActivity extends StatelessWidget {
  const _LatestActivity({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF3182F6).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.history,
              color: Color(0xFF3182F6),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '최근 동작',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF6B7684),
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF191F28),
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
