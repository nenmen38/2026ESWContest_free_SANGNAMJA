import 'package:esw_device_sdk_example/main.dart';
import 'package:esw_device_sdk_example/connection.dart';
import 'package:esw_device_sdk_example/sdk_scope.dart';
import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_sdk.dart';

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

  testWidgets('restores credentials and renders SDK device state', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await CredentialStore().save(
      const EswConnectionConfig(
        server: 'control.example.com',
        account: 'app',
        secret: 'secret',
      ),
    );
    final fake = FakeEswDeviceSdk(
      initial: EswSdkState(
        connection: EswConnectionState.disconnected,
        devices: [
          MotorDeviceSnapshot(
            id: 'motor-aabb',
            isOnline: true,
            lastSeen: DateTime(2026),
            latestState: null,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sdkProvider.overrideWithValue(fake)],
        child: const EswDemoApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(fake.connectCalls, 1);
    expect(find.text('스마트 환기창'), findsOneWidget);
    expect(find.text('motor-aabb'), findsOneWidget);
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(fake.commands, contains('open'));
    expect(find.text('명령을 전송했습니다.'), findsOneWidget);
  });

  testWidgets('manual setup uses only the public SDK flow', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await CredentialStore().save(
      const EswConnectionConfig(
        server: 'control.example.com',
        account: 'app',
        secret: 'secret',
      ),
    );
    final fake = FakeEswDeviceSdk(completeFailures: 1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sdkProvider.overrideWithValue(fake)],
        child: const EswDemoApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('첫 기기 추가하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QR 코드 없이 찾기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'device-pop');
    await tester.tap(find.text('기기의 Wi-Fi 검색'));
    await tester.pumpAndSettle();

    expect(fake.discoverCalls, 1);
    expect(find.text('contest-wifi'), findsOneWidget);
    await tester.tap(find.text('다음'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '기기 추가'));
    await tester.pumpAndSettle();

    expect(find.text('Temporary setup failure.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '기기 추가'));
    await tester.pumpAndSettle();

    expect(find.text('기기가 추가되었습니다'), findsOneWidget);
    expect(find.textContaining('192.0.2.10'), findsOneWidget);
  });
}
