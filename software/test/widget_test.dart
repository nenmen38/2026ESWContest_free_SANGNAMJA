import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_smart_window_system/main.dart';

void main() {
  test('API 응답 형태의 환경 데이터를 화면 표시값으로 변환한다', () {
    final snapshot = EnvironmentSnapshot.fromJson({
      'indoor': {'temperatureC': 25.8, 'humidityPercent': 54},
      'outdoor': {'temperatureC': '28.2', 'humidityPercent': '69'},
      'fineDust': {'pm25': 22},
      'updatedAtLabel': '방금 업데이트',
    });

    expect(snapshot.indoor.temperatureLabel, '25.8°C');
    expect(snapshot.indoor.humidityLabel, '습도 54%');
    expect(snapshot.outdoor.temperatureLabel, '28.2°C');
    expect(snapshot.outdoor.humidityLabel, '습도 69%');
    expect(snapshot.fineDust.levelLabel, '보통');
    expect(snapshot.fineDust.detailLabel, 'PM2.5 22㎍/㎥');
  });

  testWidgets('스마트 창문 앱이 한 화면에 핵심 정보를 표시한다', (tester) async {
    await tester.pumpWidget(const SmartWindowApp());

    expect(find.text('스마트 창문'), findsOneWidget);
    expect(find.text('창문 개도율'), findsOneWidget);
    expect(find.text('실내'), findsOneWidget);
    expect(find.text('실외'), findsOneWidget);
    expect(find.text('습도 58%'), findsOneWidget);
    expect(find.text('습도 71% · 비'), findsOneWidget);
    expect(find.text('환기'), findsOneWidget);
    expect(find.text('미세먼지'), findsOneWidget);
    expect(find.text('최근 동작'), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
  });

  testWidgets('열기와 닫기 조작은 수동모드로 전환한다', (tester) async {
    await tester.pumpWidget(const SmartWindowApp());

    expect(find.text('자동'), findsOneWidget);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    expect(find.text('수동'), findsOneWidget);

    await tester.tap(find.text('수동'));
    await tester.pumpAndSettle();

    expect(find.text('자동'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('설정 버튼을 누르면 설정 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(const SmartWindowApp());

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('설정'), findsOneWidget);
    expect(find.text('환경 데이터'), findsOneWidget);
    expect(find.text('API 연결 준비됨'), findsOneWidget);
  });
}
