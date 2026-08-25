import 'package:esw_device_sdk_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty home routes device addition through service setup', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: EswDemoApp()));
    await tester.pumpAndSettle();

    expect(find.text('우리 집'), findsOneWidget);
    expect(find.text('아직 추가된 기기가 없어요'), findsOneWidget);

    await tester.tap(find.text('첫 기기 추가하기'));
    await tester.pumpAndSettle();

    expect(find.text('서비스 연결'), findsOneWidget);
    expect(find.text('연결하고 저장'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(4));
  });
}
