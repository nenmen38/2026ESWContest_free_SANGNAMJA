import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/sdk_scope.dart';
import '../environment/environment_models.dart';
import '../environment/environment_scope.dart';
import 'developer_tools_page.dart';
import 'device_management_page.dart';
import 'installation_location_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({
    super.key,
    required this.controlModeLabel,
    required this.rainProtectionLabel,
    required this.safetyStopLabel,
    required this.indoorEnvironmentLabel,
    required this.outdoorEnvironmentLabel,
    required this.indoorFineDustLabel,
    required this.outdoorFineDustLabel,
  });

  final String controlModeLabel;
  final String rainProtectionLabel;
  final String safetyStopLabel;
  final String indoorEnvironmentLabel;
  final String outdoorEnvironmentLabel;
  final String indoorFineDustLabel;
  final String outdoorFineDustLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(installationLocationProvider).value;
    final sdk = ref.watch(sdkProvider);
    final sdkState = ref.watch(sdkStateProvider).value ?? sdk.currentState;
    final selected =
        ref.watch(selectedDeviceIdsProvider).value ?? const SelectedDeviceIds();
    final hasEnvironmentOverride =
        (ref.watch(indoorEnvironmentOverrideProvider).value?.isActive ??
            false) ||
        (ref.watch(outdoorEnvironmentOverrideProvider).value?.isActive ??
            false);
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
                  title: '장치',
                  children: [
                    _SettingsTile(
                      icon: Icons.devices_other_outlined,
                      title: '장치 관리',
                      value: '추가 및 연결',
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const DeviceManagementPage(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    _DeviceSelector(
                      title: '홈 모터',
                      icon: Icons.window_outlined,
                      devices: sdkState.devices
                          .whereType<MotorDeviceSnapshot>()
                          .toList(),
                      selectedId: selected.motorId,
                      onChanged: (id) async {
                        await ref
                            .read(appStorageProvider)
                            .writeSelectedDeviceIds(
                              SelectedDeviceIds(
                                motorId: id,
                                sensorId: selected.sensorId,
                              ),
                            );
                        ref.invalidate(selectedDeviceIdsProvider);
                      },
                    ),
                    const Divider(height: 1),
                    _DeviceSelector(
                      title: '홈 센서',
                      icon: Icons.sensors_outlined,
                      devices: sdkState.devices
                          .whereType<AirQualityDeviceSnapshot>()
                          .toList(),
                      selectedId: selected.sensorId,
                      onChanged: (id) async {
                        await ref
                            .read(appStorageProvider)
                            .writeSelectedDeviceIds(
                              SelectedDeviceIds(
                                motorId: selected.motorId,
                                sensorId: id,
                              ),
                            );
                        ref.invalidate(selectedDeviceIdsProvider);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SettingsSection(
                  title: '설치 위치',
                  children: [
                    _SettingsTile(
                      icon: Icons.location_on_outlined,
                      title: '날씨 조회 위치',
                      value: location?.label ?? '설정 필요',
                      onTap: () async {
                        await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => const InstallationLocationPage(),
                          ),
                        );
                        ref.invalidate(installationLocationProvider);
                        ref.invalidate(rawOutdoorWeatherProvider);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
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
                      title: '실내 미세먼지',
                      value: indoorFineDustLabel,
                    ),
                    _SettingsTile(
                      icon: Icons.air,
                      title: '실외 미세먼지',
                      value: outdoorFineDustLabel,
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
                      value: '실행 중 15분마다',
                    ),
                    _SettingsTile(
                      icon: Icons.info_outline,
                      title: '날씨·공기질 출처',
                      value: 'Open-Meteo · CAMS',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SettingsSection(
                  title: '개발자',
                  children: [
                    _SettingsTile(
                      icon: Icons.developer_mode_outlined,
                      title: '개발자 도구',
                      value: hasEnvironmentOverride
                          ? '테스트값 사용 중'
                          : '환경 데이터 테스트',
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const DeveloperToolsPage(),
                        ),
                      ),
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

class _DeviceSelector extends StatelessWidget {
  const _DeviceSelector({
    required this.title,
    required this.icon,
    required this.devices,
    required this.selectedId,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final List<EswDeviceSnapshot> devices;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final effective = devices.any((device) => device.id == selectedId)
        ? selectedId
        : devices.length == 1
        ? devices.single.id
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF3182F6)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButton<String>(
              value: effective,
              isExpanded: true,
              hint: Text(devices.isEmpty ? '장치 없음' : '선택 필요'),
              items: devices
                  .map(
                    (device) => DropdownMenuItem(
                      value: device.id,
                      child: Text(device.id, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: devices.isEmpty
                  ? null
                  : (value) {
                      if (value != null) onChanged(value);
                    },
            ),
          ),
        ],
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
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
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
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFF8B95A1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
