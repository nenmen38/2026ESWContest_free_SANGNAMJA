import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_smart_window_system/app/sdk_scope.dart';
import 'package:safe_smart_window_system/environment/environment_models.dart';
import 'package:safe_smart_window_system/screens/developer_tools_page.dart';

import 'support/fakes.dart';

void main() {
  Widget testApp(MemoryAppStorage storage) => ProviderScope(
    overrides: [appStorageProvider.overrideWithValue(storage)],
    child: const MaterialApp(home: DeveloperToolsPage()),
  );

  testWidgets('저장된 실내·실외 테스트값을 입력란에 복원한다', (tester) async {
    final storage = MemoryAppStorage(
      indoorEnvironmentOverride: IndoorEnvironmentOverride(
        temperatureC: 29.5,
        updatedAt: DateTime(2026, 8, 31),
      ),
      outdoorEnvironmentOverride: OutdoorEnvironmentOverride(
        precipitationMm: 1.2,
        updatedAt: DateTime(2026, 8, 31),
      ),
    );
    await tester.pumpWidget(testApp(storage));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('indoor.temperatureC')),
          )
          .controller
          ?.text,
      '29.5',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('outdoor.precipitationMm')),
          )
          .controller
          ?.text,
      '1.2',
    );
    expect(find.text('테스트값 사용'), findsNWidgets(2));
  });

  testWidgets('실내 입력값을 한 번에 적용하고 잘못된 범위는 거부한다', (tester) async {
    final storage = MemoryAppStorage();
    await tester.pumpWidget(testApp(storage));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('indoor.temperatureC')),
      '30.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('indoor.humidityPercent')),
      '101',
    );
    await tester.enterText(find.byKey(const ValueKey('indoor.pm2_5')), '80');
    final apply = find.byKey(const ValueKey('indoor.apply'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text('0.0부터 100.0 사이여야 합니다.'), findsOneWidget);
    expect(storage.indoorEnvironmentOverride, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('indoor.humidityPercent')),
      '70',
    );
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(storage.indoorEnvironmentOverride?.temperatureC, 30.5);
    expect(storage.indoorEnvironmentOverride?.humidityPercent, 70);
    expect(storage.indoorEnvironmentOverride?.pm2_5, 80);
    expect(find.text('실내 환경 테스트값을 적용했습니다.'), findsOneWidget);
  });

  testWidgets('실외 입력값을 적용하고 모든 테스트값을 함께 해제한다', (tester) async {
    final storage = MemoryAppStorage(
      indoorEnvironmentOverride: IndoorEnvironmentOverride(
        temperatureC: 25,
        updatedAt: DateTime(2026, 8, 31),
      ),
    );
    await tester.pumpWidget(testApp(storage));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('outdoor.temperatureC')),
      '12.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('outdoor.humidityPercent')),
      '90',
    );
    await tester.enterText(find.byKey(const ValueKey('outdoor.pm2_5')), '120');
    await tester.enterText(
      find.byKey(const ValueKey('outdoor.precipitationMm')),
      '3.5',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final pageScroll = find
        .descendant(
          of: find.byKey(const ValueKey('developer_tools.list')),
          matching: find.byType(Scrollable),
        )
        .first;
    final apply = find.byKey(const ValueKey('outdoor.apply'));
    await tester.scrollUntilVisible(apply, 300, scrollable: pageScroll);
    await tester.drag(
      find.byKey(const ValueKey('developer_tools.list')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(storage.outdoorEnvironmentOverride?.temperatureC, 12.5);
    expect(storage.outdoorEnvironmentOverride?.humidityPercent, 90);
    expect(storage.outdoorEnvironmentOverride?.pm2_5, 120);
    expect(storage.outdoorEnvironmentOverride?.precipitationMm, 3.5);

    final clearAll = find.byKey(const ValueKey('environment.clearAll'));
    await tester.scrollUntilVisible(clearAll, 300, scrollable: pageScroll);
    await tester.tap(clearAll);
    await tester.pumpAndSettle();
    expect(storage.indoorEnvironmentOverride, isNull);
    expect(storage.outdoorEnvironmentOverride, isNull);
    expect(find.text('모든 환경 데이터를 실데이터로 복원했습니다.'), findsOneWidget);
  });
}
