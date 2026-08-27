import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controlModeLabel,
    required this.rainProtectionLabel,
    required this.safetyStopLabel,
    required this.indoorEnvironmentLabel,
    required this.outdoorEnvironmentLabel,
    required this.fineDustLabel,
  });

  final String controlModeLabel;
  final String rainProtectionLabel;
  final String safetyStopLabel;
  final String indoorEnvironmentLabel;
  final String outdoorEnvironmentLabel;
  final String fineDustLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: const Text('설정', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              children: [
                _SettingsSection(
                  title: '제어',
                  children: [
                    _SettingsTile(
                      icon: controlModeLabel == '자동'
                          ? Icons.auto_mode
                          : Icons.touch_app_outlined,
                      title: '제어 모드',
                      value: controlModeLabel,
                    ),
                    _SettingsTile(
                      icon: Icons.water_drop_outlined,
                      title: '비 감지 보호',
                      value: rainProtectionLabel,
                    ),
                    _SettingsTile(
                      icon: Icons.stop_circle_outlined,
                      title: '안전 정지',
                      value: safetyStopLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SettingsSection(
                  title: '환경 데이터',
                  children: [
                    _SettingsTile(
                      icon: Icons.home_outlined,
                      title: '실내 온습도',
                      value: indoorEnvironmentLabel,
                    ),
                    _SettingsTile(
                      icon: Icons.cloud_outlined,
                      title: '실외 온습도',
                      value: outdoorEnvironmentLabel,
                    ),
                    _SettingsTile(
                      icon: Icons.grain,
                      title: '미세먼지',
                      value: fineDustLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _SettingsSection(
                  title: 'API',
                  children: [
                    _SettingsTile(
                      icon: Icons.sync_outlined,
                      title: '데이터 갱신',
                      value: 'API 연결 준비됨',
                    ),
                    _SettingsTile(
                      icon: Icons.schedule_outlined,
                      title: '마지막 갱신',
                      value: '앱 상단 시간과 동일',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF333D4B),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF3182F6).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: const Color(0xFF3182F6), size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF191F28),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B7684),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
