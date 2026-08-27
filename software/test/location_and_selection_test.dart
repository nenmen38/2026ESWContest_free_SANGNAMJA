import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_smart_window_system/app/sdk_scope.dart';
import 'package:safe_smart_window_system/environment/environment_models.dart';
import 'package:safe_smart_window_system/environment/environment_scope.dart';
import 'package:safe_smart_window_system/screens/installation_location_page.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('위치 실패 시 위도와 경도를 직접 저장할 수 있다', (tester) async {
    final storage = MemoryAppStorage(onboardingSeen: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStorageProvider.overrideWithValue(storage)],
        child: const MaterialApp(home: InstallationLocationPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '위도'), '37.5665');
    await tester.enterText(find.widgetWithText(TextFormField, '경도'), '126.978');
    await tester.tap(find.text('이 좌표 저장'));
    await tester.pumpAndSettle();

    expect(storage.location?.latitude, 37.5665);
    expect(storage.location?.longitude, 126.978);
  });

  test('장치가 하나면 자동 선택하고 여러 개면 저장된 ID만 사용한다', () {
    final motorA = MotorDeviceSnapshot(
      id: 'motor-a',
      isOnline: true,
      lastSeen: DateTime(2026),
      latestState: null,
    );
    final motorB = MotorDeviceSnapshot(
      id: 'motor-b',
      isOnline: true,
      lastSeen: DateTime(2026),
      latestState: null,
    );
    final one = EswSdkState(
      connection: EswConnectionState.connected,
      devices: [motorA],
    );
    final many = EswSdkState(
      connection: EswConnectionState.connected,
      devices: [motorA, motorB],
    );

    expect(resolveMotor(one, const SelectedDeviceIds())?.id, 'motor-a');
    expect(resolveMotor(many, const SelectedDeviceIds()), isNull);
    expect(
      resolveMotor(many, const SelectedDeviceIds(motorId: 'motor-b'))?.id,
      'motor-b',
    );
    expect(
      resolveMotor(many, const SelectedDeviceIds(motorId: 'missing')),
      isNull,
    );
  });
}
