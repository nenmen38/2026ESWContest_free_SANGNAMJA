import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_smart_window_system/main.dart';

void main() {
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
}
