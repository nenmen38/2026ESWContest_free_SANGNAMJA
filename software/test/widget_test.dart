import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_smart_window_system/app/sdk_scope.dart';
import 'package:safe_smart_window_system/environment/environment_models.dart';
import 'package:safe_smart_window_system/environment/environment_scope.dart';
import 'package:safe_smart_window_system/main.dart';

import 'support/fakes.dart';

void main() {
  Widget testApp({
    MemoryAppStorage? storage,
    FakeEswDeviceSdk? sdk,
    OutdoorWeatherStatus weather = const OutdoorWeatherStatus(),
  }) => ProviderScope(
    overrides: [
      appStorageProvider.overrideWithValue(
        storage ?? MemoryAppStorage(onboardingSeen: true),
      ),
      sdkProvider.overrideWithValue(sdk ?? FakeEswDeviceSdk()),
      outdoorWeatherProvider.overrideWithValue(AsyncData(weather)),
    ],
    child: const SmartWindowApp(),
  );

  test('SDK 실내값과 Open-Meteo 실외값을 표시 모델로 결합한다', () {
    final snapshot = EnvironmentSnapshot.fromSources(
      indoor: sensorReading(),
      weather: OutdoorWeatherStatus(reading: outdoorReading()),
    );
    expect(snapshot.indoor.temperatureLabel, '25.8°C');
    expect(snapshot.indoor.humidityLabel, '습도 54%');
    expect(snapshot.outdoor.temperatureLabel, '28.2°C');
    expect(snapshot.outdoor.humidityLabel, '습도 69%');
    expect(snapshot.indoorFineDust.detailLabel, 'PM2.5 13㎍/㎥');
    expect(snapshot.outdoorFineDust.detailLabel, 'PM2.5 18㎍/㎥');
  });

  testWidgets('홈이 SDK 장치와 외부 환경 실데이터를 표시한다', (tester) async {
    await tester.pumpWidget(
      testApp(
        sdk: readySdk(),
        weather: OutdoorWeatherStatus(reading: outdoorReading()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('스마트 창문'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('습도 54%'), findsOneWidget);
    expect(find.text('습도 69%'), findsOneWidget);
    expect(find.text('13 / 18'), findsOneWidget);
    expect(find.text('좋음 / 보통'), findsOneWidget);
  });

  testWidgets('수동 버튼은 선택된 모터의 공개 명령 API를 호출한다', (tester) async {
    final sdk = readySdk();
    await tester.pumpWidget(
      testApp(
        sdk: sdk,
        weather: OutdoorWeatherStatus(reading: outdoorReading()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(sdk.commands, ['close']);
    expect(find.text('수동'), findsOneWidget);
    await tester.tap(find.text('정지'));
    await tester.pumpAndSettle();
    expect(sdk.commands, ['close', 'stop']);
  });

  testWidgets('개도율 숫자를 직접 입력하면 위치 명령을 보내고 수동으로 전환한다', (tester) async {
    final sdk = readySdk();
    await tester.pumpWidget(
      testApp(
        sdk: sdk,
        weather: OutdoorWeatherStatus(reading: outdoorReading()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('25%'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '40');
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(sdk.commands, ['set:40.0']);
    expect(find.text('수동'), findsOneWidget);
  });

  testWidgets('비가 오면 열기만 제한하고 자동 닫기 명령은 보내지 않는다', (tester) async {
    final sdk = readySdk();
    await tester.pumpWidget(
      testApp(
        sdk: sdk,
        weather: OutdoorWeatherStatus(
          reading: outdoorReading(precipitationMm: 1.2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('습도 69% · 비'), findsOneWidget);
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(sdk.commands, isEmpty);
  });

  testWidgets('저장된 강수량 override가 최종 provider를 거쳐 비 보호에 반영된다', (tester) async {
    final sdk = readySdk();
    final storage = MemoryAppStorage(
      onboardingSeen: true,
      outdoorEnvironmentOverride: OutdoorEnvironmentOverride(
        precipitationMm: 1.2,
        updatedAt: DateTime.now(),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStorageProvider.overrideWithValue(storage),
          sdkProvider.overrideWithValue(sdk),
          rawOutdoorWeatherProvider.overrideWith(
            (_) =>
                Stream.value(OutdoorWeatherStatus(reading: outdoorReading())),
          ),
        ],
        child: const SmartWindowApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('습도 69% · 비'), findsOneWidget);
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(sdk.commands, isEmpty);
  });

  testWidgets('오래된 센서값은 실내 실데이터로 표시하지 않는다', (tester) async {
    final sdk = FakeEswDeviceSdk();
    sdk.emitDevices([
      AirQualityDeviceSnapshot(
        id: 'sensor-old',
        isOnline: true,
        lastSeen: DateTime.now().subtract(const Duration(minutes: 1)),
        latestReading: sensorReading(
          receivedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ),
    ]);
    await tester.pumpWidget(
      testApp(
        sdk: sdk,
        weather: OutdoorWeatherStatus(reading: outdoorReading()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('— / 18'), findsOneWidget);
  });

  testWidgets('저장된 실내 override를 표시하고 해제하면 최신 센서값으로 복귀한다', (tester) async {
    final storage = MemoryAppStorage(
      onboardingSeen: true,
      indoorEnvironmentOverride: IndoorEnvironmentOverride(
        temperatureC: 33.3,
        humidityPercent: 77,
        pm2_5: 88,
        updatedAt: DateTime.now(),
      ),
    );
    await tester.pumpWidget(
      testApp(
        storage: storage,
        sdk: readySdk(),
        weather: OutdoorWeatherStatus(reading: outdoorReading()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('33.3°C'), findsOneWidget);
    expect(find.text('습도 77%'), findsOneWidget);
    expect(find.text('88 / 18'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SmartWindowHome)),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('33.3°C · 습도 77%'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('33.3°C · 습도 77%'), findsOneWidget);
    expect(find.text('매우 나쁨 · PM2.5 88㎍/㎥'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await container.read(indoorEnvironmentOverrideProvider.notifier).clearAll();
    await tester.pumpAndSettle();
    expect(find.text('25.8°C'), findsOneWidget);
    expect(find.text('습도 54%'), findsOneWidget);
    expect(find.text('13 / 18'), findsOneWidget);
  });

  for (final scenario in ['센서 없음', '센서 오프라인', '센서 오류', '센서 지연']) {
    testWidgets('완전한 실내 override는 $scenario 상태에서도 표시된다', (tester) async {
      final sdk = FakeEswDeviceSdk();
      final now = DateTime.now();
      if (scenario != '센서 없음') {
        sdk.emitDevices([
          AirQualityDeviceSnapshot(
            id: 'sensor-test',
            isOnline: scenario != '센서 오프라인',
            lastSeen: now,
            latestReading: sensorReading(
              receivedAt: scenario == '센서 지연'
                  ? now.subtract(const Duration(minutes: 1))
                  : now,
              errorFlags: scenario == '센서 오류' ? 1 : 0,
            ),
          ),
        ]);
      }
      await tester.pumpWidget(
        testApp(
          storage: MemoryAppStorage(
            onboardingSeen: true,
            indoorEnvironmentOverride: IndoorEnvironmentOverride(
              temperatureC: 33.3,
              humidityPercent: 77,
              pm2_5: 88,
              updatedAt: now,
            ),
          ),
          sdk: sdk,
          weather: OutdoorWeatherStatus(reading: outdoorReading()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('33.3°C'), findsOneWidget);
      expect(find.text('습도 77%'), findsOneWidget);
      expect(find.text('88 / 18'), findsOneWidget);
    });
  }

  testWidgets('설정에서 장치와 설치 위치 관리 경로를 표시한다', (tester) async {
    final storage = MemoryAppStorage(
      onboardingSeen: true,
      location: const InstallationLocation(
        latitude: 37.5665,
        longitude: 126.978,
      ),
    );
    await tester.pumpWidget(
      testApp(
        storage: storage,
        sdk: readySdk(),
        weather: OutdoorWeatherStatus(reading: outdoorReading()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('홈 모터'), findsOneWidget);
    expect(find.text('홈 센서'), findsOneWidget);
    expect(find.text('날씨 조회 위치'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Open-Meteo · CAMS'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Open-Meteo · CAMS'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('개발자 도구'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('개발자 도구'));
    await tester.pumpAndSettle();
    expect(find.text('테스트용 환경 데이터입니다.'), findsNothing);
    expect(find.textContaining('테스트용 환경 데이터입니다.'), findsOneWidget);
    expect(find.text('실내 환경'), findsOneWidget);
    expect(find.text('실외 환경'), findsOneWidget);
  });

  testWidgets('최초 실행 랜딩을 건너뛰면 이후 홈으로 진입한다', (tester) async {
    final storage = MemoryAppStorage();
    await tester.pumpWidget(testApp(storage: storage));
    await tester.pumpAndSettle();
    expect(find.text('장치 연결하기'), findsOneWidget);
    await tester.tap(find.text('나중에 하기'));
    await tester.pumpAndSettle();
    expect(storage.onboardingSeen, isTrue);
    expect(find.text('스마트 창문'), findsOneWidget);
  });

  testWidgets('저장된 서비스 계정으로 백그라운드 재연결한다', (tester) async {
    final sdk = FakeEswDeviceSdk();
    final storage = MemoryAppStorage(
      onboardingSeen: true,
      credentials: const EswConnectionConfig(
        server: 'control.example.com',
        account: 'app',
        secret: 'secret',
      ),
    );
    await tester.pumpWidget(testApp(storage: storage, sdk: sdk));
    await tester.pumpAndSettle();
    expect(sdk.connectCalls, 1);
  });
}

FakeEswDeviceSdk readySdk() {
  final sdk = FakeEswDeviceSdk();
  sdk.emitDevices([
    MotorDeviceSnapshot(
      id: 'motor-aabb',
      isOnline: true,
      lastSeen: DateTime.now(),
      latestState: const MotorState(
        mainState: MotorMainState.idle,
        currentPositionPercent: 25,
        targetPositionPercent: 25,
        positionValid: true,
        errorFlags: 0,
        revision: 1,
      ),
    ),
    AirQualityDeviceSnapshot(
      id: 'sensor-aabb',
      isOnline: true,
      lastSeen: DateTime.now(),
      latestReading: sensorReading(),
    ),
  ]);
  return sdk;
}

OutdoorReading outdoorReading({double precipitationMm = 0}) => OutdoorReading(
  temperatureC: 28.2,
  humidityPercent: 69,
  pm2_5: 18,
  precipitationMm: precipitationMm,
  observedAt: DateTime(2026, 1, 1, 12),
  fetchedAt: DateTime(2026, 1, 1, 12),
);
