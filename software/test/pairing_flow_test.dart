import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_smart_window_system/app/sdk_scope.dart';
import 'package:safe_smart_window_system/pairing/add_device_page.dart';
import 'package:safe_smart_window_system/pairing/pairing_flow.dart';

import 'support/fakes.dart';

void main() {
  test('프로비저닝 서비스 이름으로 모터와 센서를 구분한다', () {
    expect(
      roleFromProvisioningServiceName('PROV-MOTOR-12EF'),
      ProvisioningDeviceRole.motor,
    );
    expect(
      roleFromProvisioningServiceName('PROV-SENSOR-C4A0'),
      ProvisioningDeviceRole.sensor,
    );
    expect(roleFromProvisioningServiceName('PROV-OTHER-12EF'), isNull);
    expect(roleFromProvisioningServiceName('PROV-MOTOR-12EF-extra'), isNull);
  });

  testWidgets('모터와 센서를 모두 연결해야 최초 설정을 완료한다', (tester) async {
    final fake = FakeEswDeviceSdk();
    final qrPayloads = [
      ProvisioningQrPayload.parse(
        '{"ver":"v1","name":"PROV-MOTOR-12EF","pop":"device-pop","transport":"ble"}',
      ),
      ProvisioningQrPayload.parse(
        '{"ver":"v1","name":"PROV-SENSOR-C4A0","pop":"device-pop","transport":"ble"}',
      ),
    ];
    var scanCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sdkProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: RequiredDevicePairingPage(
            scanQr: (_) async => qrPayloads[scanCount++],
          ),
        ),
      ),
    );

    FilledButton startButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '스마트 창문 시작하기'),
    );

    expect(find.text('연결 필요'), findsNWidgets(2));
    expect(startButton().onPressed, isNull);

    await _completeQrSetup(tester, '모터 연결하기');

    expect(find.text('연결됨'), findsOneWidget);
    expect(find.text('연결 필요'), findsOneWidget);
    expect(find.text('센서 연결하기'), findsOneWidget);
    expect(startButton().onPressed, isNull);

    await _completeQrSetup(tester, '센서 연결하기');

    expect(find.text('연결됨'), findsNWidgets(2));
    expect(find.text('연결 필요'), findsNothing);
    expect(startButton().onPressed, isNotNull);
  });

  testWidgets('QR 장치 검색부터 Wi-Fi 설정 완료까지 진행한다', (tester) async {
    final fake = FakeEswDeviceSdk();
    final qr = ProvisioningQrPayload.parse(
      '{"ver":"v1","name":"PROV-MOTOR-12EF","pop":"device-pop","transport":"ble"}',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sdkProvider.overrideWithValue(fake)],
        child: MaterialApp(home: AddDevicePage(scanQr: (_) async => qr)),
      ),
    );

    await tester.tap(find.text('QR 코드로 장치 찾기'));
    await tester.pumpAndSettle();
    expect(find.text('contest-wifi'), findsOneWidget);

    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '장치 추가'));
    await tester.pumpAndSettle();

    expect(find.text('장치가 추가되었습니다'), findsOneWidget);
    expect(find.textContaining('192.0.2.10'), findsOneWidget);
  });

  testWidgets('수동 검색 실패 후 같은 확인 단계에서 재시도한다', (tester) async {
    final fake = FakeEswDeviceSdk(completeFailures: 1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sdkProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: AddDevicePage()),
      ),
    );

    await tester.tap(find.text('QR 코드 없이 찾기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'device-pop');
    await tester.tap(find.text('장치의 Wi-Fi 검색'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '장치 추가'));
    await tester.pumpAndSettle();

    expect(find.textContaining('응답 시간이 초과'), findsOneWidget);
    expect(find.text('연결 정보를 확인해 주세요'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '장치 추가'));
    await tester.pumpAndSettle();
    expect(find.text('장치가 추가되었습니다'), findsOneWidget);
  });
}

Future<void> _completeQrSetup(WidgetTester tester, String buttonLabel) async {
  await tester.tap(find.text(buttonLabel));
  await tester.pumpAndSettle();
  await tester.tap(find.text('QR 코드로 장치 찾기'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('다음'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '장치 추가'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '완료'));
  await tester.pumpAndSettle();
}
