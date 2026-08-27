import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'screens/settings_page.dart';

void main() {
  runApp(const SmartWindowApp());
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
      home: const SmartWindowHome(),
    );
  }
}

class EnvironmentSnapshot {
  const EnvironmentSnapshot({
    required this.indoor,
    required this.outdoor,
    required this.fineDust,
    required this.updatedAtLabel,
  });

  const EnvironmentSnapshot.demo()
    : indoor = const TemperatureHumidity(
        temperatureC: 26.4,
        humidityPercent: 58,
      ),
      outdoor = const TemperatureHumidity(
        temperatureC: 29.0,
        humidityPercent: 71,
      ),
      fineDust = const FineDust(pm25: 18),
      updatedAtLabel = '오늘 15:20 업데이트';

  final TemperatureHumidity indoor;
  final TemperatureHumidity outdoor;
  final FineDust fineDust;
  final String updatedAtLabel;

  factory EnvironmentSnapshot.fromJson(Map<String, dynamic> json) {
    final indoorJson = _readMap(json['indoor']);
    final outdoorJson = _readMap(json['outdoor']);
    final fineDustJson = _readMap(json['fineDust']);

    return EnvironmentSnapshot(
      indoor: TemperatureHumidity(
        temperatureC: _readDouble(indoorJson['temperatureC']),
        humidityPercent: _readInt(indoorJson['humidityPercent']),
      ),
      outdoor: TemperatureHumidity(
        temperatureC: _readDouble(outdoorJson['temperatureC']),
        humidityPercent: _readInt(outdoorJson['humidityPercent']),
      ),
      fineDust: FineDust(pm25: _readInt(fineDustJson['pm25'])),
      updatedAtLabel: json['updatedAtLabel'] as String? ?? '방금 업데이트',
    );
  }

  static Map<String, dynamic> _readMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return const {};
  }

  static double _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }

  static int _readInt(Object? value) {
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

class TemperatureHumidity {
  const TemperatureHumidity({
    required this.temperatureC,
    required this.humidityPercent,
  });

  final double temperatureC;
  final int humidityPercent;

  String get temperatureLabel => '${temperatureC.toStringAsFixed(1)}°C';
  String get humidityLabel => '습도 $humidityPercent%';
}

class FineDust {
  const FineDust({required this.pm25});

  final int pm25;

  String get levelLabel {
    if (pm25 <= 15) {
      return '좋음';
    }
    if (pm25 <= 35) {
      return '보통';
    }
    if (pm25 <= 75) {
      return '나쁨';
    }
    return '매우 나쁨';
  }

  String get detailLabel => 'PM2.5 $pm25㎍/㎥';
}

class SmartWindowHome extends StatefulWidget {
  const SmartWindowHome({super.key});

  @override
  State<SmartWindowHome> createState() => _SmartWindowHomeState();
}

class _SmartWindowHomeState extends State<SmartWindowHome> {
  double _openPercent = 11;
  bool _autoMode = true;
  bool _rainLock = true;
  bool _safetyStop = false;
  EnvironmentSnapshot _environment = const EnvironmentSnapshot.demo();

  @override
  void initState() {
    super.initState();
    _loadEnvironment();
  }

  bool get _isLocked => _rainLock || _safetyStop;

  double get _automaticOpenPercent {
    if (_rainLock || _safetyStop) {
      return 0;
    }

    return 45;
  }

  Future<void> _loadEnvironment() async {
    final snapshot = await _fetchEnvironmentSnapshot();
    if (!mounted) {
      return;
    }

    setState(() {
      _environment = snapshot;
    });
  }

  // API 연결 시 이 함수에서 응답을 EnvironmentSnapshot으로 변환하면 됩니다.
  Future<EnvironmentSnapshot> _fetchEnvironmentSnapshot() {
    return Future.value(const EnvironmentSnapshot.demo());
  }

  void _openWindow() {
    setState(() {
      _autoMode = false;
      if (!_isLocked) {
        _openPercent = 100;
      }
    });
  }

  void _closeWindow() {
    setState(() {
      _autoMode = false;
      _openPercent = 0;
    });
  }

  void _stopWindow() {
    setState(() {
      _autoMode = false;
      _safetyStop = true;
    });
  }

  void _toggleAutoMode() {
    setState(() {
      _autoMode = !_autoMode;
      if (_autoMode) {
        _openPercent = _automaticOpenPercent;
      }
    });
  }

  void _toggleRainLock() {
    setState(() {
      _rainLock = !_rainLock;
      if (_rainLock) {
        _openPercent = 0;
      }
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsPage(
          controlModeLabel: _autoMode ? '자동' : '수동',
          rainProtectionLabel: _rainLock ? '사용 중' : '해제',
          safetyStopLabel: _safetyStop ? '활성' : '대기',
          indoorEnvironmentLabel:
              '${_environment.indoor.temperatureLabel} · ${_environment.indoor.humidityLabel}',
          outdoorEnvironmentLabel:
              '${_environment.outdoor.temperatureLabel} · ${_environment.outdoor.humidityLabel}',
          fineDustLabel:
              '${_environment.fineDust.levelLabel} · ${_environment.fineDust.detailLabel}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                          isLocked: _isLocked,
                          autoMode: _autoMode,
                          updatedAtLabel: _environment.updatedAtLabel,
                          onAutoTap: _toggleAutoMode,
                          onSettingsTap: _openSettings,
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          flex: 38,
                          child: _HeroWindowCard(
                            openPercent: _openPercent,
                            isLocked: _isLocked,
                            rainLock: _rainLock,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _QuickControls(
                          isLocked: _isLocked,
                          onOpen: _openWindow,
                          onClose: _closeWindow,
                          onStop: _stopWindow,
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          flex: 28,
                          child: _EnvironmentPanel(
                            environment: _environment,
                            rainLock: _rainLock,
                            onRainTap: _toggleRainLock,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _LatestActivity(),
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
  });

  final double openPercent;
  final bool isLocked;
  final bool rainLock;

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
                      Text(
                        '${openPercent.round()}%',
                        style: Theme.of(context).textTheme.displayMedium
                            ?.copyWith(
                              color: const Color(0xFF191F28),
                              fontWeight: FontWeight.w900,
                              height: 0.95,
                              letterSpacing: 0,
                            ),
                      ),
                    ],
                  ),
                ),
                _DecisionBadge(
                  label: isLocked ? '닫힘 유지' : '환기 가능',
                  color: isLocked
                      ? const Color(0xFFFF8A00)
                      : const Color(0xFF3182F6),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(child: _WindowIllustration(openPercent: openPercent)),
            const SizedBox(height: 12),
            Text(
              rainLock
                  ? '비가 감지되어 창문 열기를 제한하고 있습니다.'
                  : '실내 공기 상태에 따라 바로 환기할 수 있습니다.',
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

class _QuickControls extends StatelessWidget {
  const _QuickControls({
    required this.isLocked,
    required this.onOpen,
    required this.onClose,
    required this.onStop,
  });

  final bool isLocked;
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
              onTap: onClose,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              icon: Icons.stop_circle_outlined,
              label: '정지',
              color: const Color(0xFFFF5A5F),
              onTap: onStop,
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
              onTap: isLocked ? null : onOpen,
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
    required this.onRainTap,
  });

  final EnvironmentSnapshot environment;
  final bool rainLock;
  final VoidCallback onRainTap;

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
                  detail: rainLock
                      ? '${environment.outdoor.humidityLabel} · 비'
                      : environment.outdoor.humidityLabel,
                  color: const Color(0xFFFF8A00),
                  onTap: onRainTap,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _InfoCard(
                  icon: Icons.air_outlined,
                  title: '환기',
                  value: rainLock ? '대기' : '가능',
                  detail: rainLock ? '닫힘 권장' : '열기 가능',
                  color: const Color(0xFF00A661),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _InfoCard(
                  icon: Icons.grain,
                  title: '미세먼지',
                  value: environment.fineDust.levelLabel,
                  detail: environment.fineDust.detailLabel,
                  color: const Color(0xFF6B7684),
                ),
              ),
            ],
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
  const _LatestActivity();

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
                  '15:20 · 강우 감지로 창문을 닫았습니다',
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
