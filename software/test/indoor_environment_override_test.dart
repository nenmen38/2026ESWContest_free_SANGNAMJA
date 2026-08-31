import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_smart_window_system/app/app_storage.dart';
import 'package:safe_smart_window_system/app/sdk_scope.dart';
import 'package:safe_smart_window_system/environment/environment_models.dart';
import 'package:safe_smart_window_system/environment/environment_scope.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final changedAt = DateTime(2026, 8, 31, 15, 30);

  IndoorEnvironmentOverride completeOverride() => IndoorEnvironmentOverride(
    temperatureC: 31.5,
    humidityPercent: 82,
    pm2_5: 55,
    updatedAt: changedAt,
  );

  test('실내 override JSON 왕복과 활성·완전 상태를 판정한다', () {
    final partial = IndoorEnvironmentOverride(
      humidityPercent: 75,
      updatedAt: changedAt,
    );
    expect(partial.isActive, isTrue);
    expect(partial.isComplete, isFalse);

    final restored = IndoorEnvironmentOverride.fromJson(
      completeOverride().toJson(),
    );
    expect(restored.isActive, isTrue);
    expect(restored.isComplete, isTrue);
    expect(restored.temperatureC, 31.5);
    expect(restored.humidityPercent, 82);
    expect(restored.pm2_5, 55);
    expect(restored.updatedAt, changedAt);
  });

  test('실내 override 입력값의 도메인 범위를 검증한다', () {
    IndoorEnvironmentOverride(
      temperatureC: -100,
      humidityPercent: 100,
      pm2_5: 10000,
      updatedAt: changedAt,
    ).validate();

    for (final value in [
      IndoorEnvironmentOverride(temperatureC: 100.1, updatedAt: changedAt),
      IndoorEnvironmentOverride(humidityPercent: -0.1, updatedAt: changedAt),
      IndoorEnvironmentOverride(pm2_5: 10000.1, updatedAt: changedAt),
      IndoorEnvironmentOverride(
        humidityPercent: double.infinity,
        updatedAt: changedAt,
      ),
    ]) {
      expect(value.validate, throwsArgumentError);
    }
  });

  test('정상 센서값 위에 지정한 실내 필드만 덮어쓴다', () {
    final snapshot = EnvironmentSnapshot.fromSources(
      indoor: sensorReading(
        receivedAt: changedAt.subtract(const Duration(minutes: 1)),
      ),
      indoorOverride: IndoorEnvironmentOverride(
        temperatureC: 30.5,
        pm2_5: 90,
        updatedAt: changedAt,
      ),
    );

    expect(snapshot.indoor.temperatureC, 30.5);
    expect(snapshot.indoor.humidityPercent, 54);
    expect(snapshot.indoorFineDust.pm25, 90);
    expect(snapshot.updatedAtLabel, '15:30 업데이트');
  });

  test('센서값이 없으면 부분값은 대기하고 완전값은 독립 동작한다', () {
    final partial = EnvironmentSnapshot.fromSources(
      indoorOverride: IndoorEnvironmentOverride(
        temperatureC: 30,
        updatedAt: changedAt,
      ),
    );
    expect(partial.indoor.temperatureC, isNull);
    expect(partial.indoorFineDust.pm25, isNull);
    expect(partial.updatedAtLabel, '실데이터를 기다리는 중');

    final complete = EnvironmentSnapshot.fromSources(
      indoorOverride: completeOverride(),
    );
    expect(complete.indoor.temperatureC, 31.5);
    expect(complete.indoor.humidityPercent, 82);
    expect(complete.indoorFineDust.pm25, 55);
    expect(complete.updatedAtLabel, '15:30 업데이트');
  });

  test('컨트롤러가 실내 필드를 저장·복원하고 마지막 해제 시 삭제한다', () async {
    final storage = MemoryAppStorage(onboardingSeen: true);
    var container = ProviderContainer(
      overrides: [appStorageProvider.overrideWithValue(storage)],
    );
    expect(
      await container.read(indoorEnvironmentOverrideProvider.future),
      isNull,
    );

    final controller = container.read(
      indoorEnvironmentOverrideProvider.notifier,
    );
    await controller.setField(IndoorEnvironmentField.temperatureC, 29.5);
    await controller.setField(IndoorEnvironmentField.pm2_5, 42);
    expect(storage.indoorEnvironmentOverride?.temperatureC, 29.5);
    expect(storage.indoorEnvironmentOverride?.pm2_5, 42);
    container.dispose();

    container = ProviderContainer(
      overrides: [appStorageProvider.overrideWithValue(storage)],
    );
    expect(
      (await container.read(indoorEnvironmentOverrideProvider.future))?.pm2_5,
      42,
    );
    final restoredController = container.read(
      indoorEnvironmentOverrideProvider.notifier,
    );
    await restoredController.setField(
      IndoorEnvironmentField.temperatureC,
      null,
    );
    expect(storage.indoorEnvironmentOverride?.temperatureC, isNull);
    expect(storage.indoorEnvironmentOverride?.pm2_5, 42);
    await restoredController.setField(IndoorEnvironmentField.pm2_5, null);
    expect(storage.indoorEnvironmentOverride, isNull);
    container.dispose();
  });

  test('실내와 실외 override 저장 상태는 서로 독립적이다', () async {
    final outdoor = OutdoorEnvironmentOverride(
      precipitationMm: 1,
      updatedAt: changedAt,
    );
    final storage = MemoryAppStorage(
      onboardingSeen: true,
      outdoorEnvironmentOverride: outdoor,
    );
    final container = ProviderContainer(
      overrides: [appStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    await container.read(indoorEnvironmentOverrideProvider.future);

    await container
        .read(indoorEnvironmentOverrideProvider.notifier)
        .setField(IndoorEnvironmentField.humidityPercent, 70);
    expect(storage.outdoorEnvironmentOverride, same(outdoor));
    await container.read(indoorEnvironmentOverrideProvider.notifier).clearAll();
    expect(storage.outdoorEnvironmentOverride, same(outdoor));
  });

  test('컨트롤러는 잘못된 실내값을 저장하지 않는다', () async {
    final storage = MemoryAppStorage(onboardingSeen: true);
    final container = ProviderContainer(
      overrides: [appStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    await container.read(indoorEnvironmentOverrideProvider.future);

    expect(
      () => container
          .read(indoorEnvironmentOverrideProvider.notifier)
          .setField(IndoorEnvironmentField.humidityPercent, 101),
      throwsArgumentError,
    );
    expect(storage.indoorEnvironmentOverride, isNull);
  });

  test('손상된 실내 override 저장값은 비활성 상태로 복원한다', () async {
    FlutterSecureStorage.setMockInitialValues({
      'esw.indoor_environment.override': '{not-json',
    });
    expect(await SecureAppStorage().readIndoorEnvironmentOverride(), isNull);
  });
}
