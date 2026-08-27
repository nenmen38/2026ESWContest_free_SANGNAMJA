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
    expect(find.text('환기'), findsOneWidget);
    expect(find.text('최근 동작'), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
  });
}
