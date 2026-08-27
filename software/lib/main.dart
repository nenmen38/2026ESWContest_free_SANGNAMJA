import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  bool get _isLocked => _rainLock || _safetyStop;

  void _openWindow() {
    if (_isLocked) {
      return;
    }

    setState(() {
      _openPercent = 100;
    });
  }

  void _closeWindow() {
    setState(() {
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

  void _clearSafetyStop() {
    setState(() {
      _safetyStop = false;
    });
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
                          onAutoTap: _toggleAutoMode,
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
                            rainLock: _rainLock,
                            safetyStop: _safetyStop,
                            onRainTap: _toggleRainLock,
                            onSafetyTap: _clearSafetyStop,
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
    required this.onAutoTap,
  });

  final bool isLocked;
  final bool autoMode;
  final VoidCallback onAutoTap;

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
                '오늘 15:20 업데이트',
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
      ],
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
    required this.rainLock,
    required this.safetyStop,
    required this.onRainTap,
    required this.onSafetyTap,
  });

  final bool rainLock;
  final bool safetyStop;
  final VoidCallback onRainTap;
  final VoidCallback onSafetyTap;

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
                  value: '26.4°C',
                  detail: '습도 58%',
                  color: const Color(0xFF3182F6),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _InfoCard(
                  icon: Icons.cloud_outlined,
                  title: '실외',
                  value: '29.0°C',
                  detail: rainLock ? '비 감지' : '비 없음',
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
                  icon: Icons.security_outlined,
                  title: '안전',
                  value: safetyStop ? '정지' : '정상',
                  detail: safetyStop ? '탭해서 해제' : '모터 대기',
                  color: safetyStop
                      ? const Color(0xFFFF5A5F)
                      : const Color(0xFF6B7684),
                  onTap: safetyStop ? onSafetyTap : null,
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
                      color: const Color(0xFF6B7684),
                      fontWeight: FontWeight.w800,
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
                letterSpacing: 0,
              ),
            ),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8B95A1),
                fontWeight: FontWeight.w700,
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
