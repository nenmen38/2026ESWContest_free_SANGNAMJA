import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:esw_device_sdk_example/add_device_page.dart';
import 'package:esw_device_sdk_example/sdk_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_sdk.dart';

void main() {
  testWidgets('QR setup discovers the printed device and its Wi-Fi', (
    tester,
  ) async {
    final fake = FakeEswDeviceSdk();
    final qr = ProvisioningQrPayload.parse(
      '{"ver":"v1","name":"PROV-MOTOR-12EF",'
      '"pop":"device-pop","transport":"ble"}',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sdkProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: AddDevicePage(profile: _profile, scanQr: (_) async => qr),
        ),
      ),
    );

    await tester.tap(find.text('QR 코드로 기기 찾기'));
    await tester.pumpAndSettle();

    expect(find.text('contest-wifi'), findsOneWidget);
    expect(find.textContaining('1개 Wi-Fi'), findsOneWidget);
  });
}

const _profile = EswConnectionConfig(
  server: 'control.example.com',
  account: 'app',
  secret: 'secret',
);
