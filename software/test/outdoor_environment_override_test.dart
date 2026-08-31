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

  final changedAt = DateTime(2026, 8, 29, 15, 30);

  OutdoorEnvironmentOverride completeOverride() => OutdoorEnvironmentOverride(
    temperatureC: 31.5,
    humidityPercent: 82,
    pm2_5: 55,
    precipitationMm: 2.4,
    updatedAt: changedAt,
  );

  test('override JSON 왕복과 활성·완전 상태를 판정한다', () {
    final partial = OutdoorEnvironmentOverride(
      humidityPercent: 75,
      updatedAt: changedAt,
    );
    expect(partial.isActive, isTrue);
    expect(partial.isComplete, isFalse);

    final restored = OutdoorEnvironmentOverride.fromJson(
      completeOverride().toJson(),
    );
    expect(restored.isActive, isTrue);
    expect(restored.isComplete, isTrue);
    expect(restored.temperatureC, 31.5);
    expect(restored.humidityPercent, 82);
    expect(restored.pm2_5, 55);
    expect(restored.precipitationMm, 2.4);
    expect(restored.updatedAt, changedAt);
  });

  test('override 입력값의 도메인 범위를 검증한다', () {
    OutdoorEnvironmentOverride(
      temperatureC: -100,
      humidityPercent: 100,
      pm2_5: 10000,
      precipitationMm: 1000,
      updatedAt: changedAt,
    ).validate();

    for (final value in [
      OutdoorEnvironmentOverride(temperatureC: 100.1, updatedAt: changedAt),
      OutdoorEnvironmentOverride(humidityPercent: -0.1, updatedAt: changedAt),
      OutdoorEnvironmentOverride(pm2_5: -1, updatedAt: changedAt),
      OutdoorEnvironmentOverride(precipitationMm: 1000.1, updatedAt: changedAt),
      OutdoorEnvironmentOverride(
        temperatureC: double.nan,
        updatedAt: changedAt,
      ),
    ]) {
      expect(value.validate, throwsArgumentError);
    }
  });

  test('실외 실데이터 위에 지정된 필드만 덮어쓴다', () {
    final sourceReading = _reading(
      temperatureC: 20,
      precipitationMm: 0,
      fetchedAt: changedAt.subtract(const Duration(minutes: 5)),
    );
    final result = applyOutdoorEnvironmentOverride(
      OutdoorWeatherStatus(reading: sourceReading),
      OutdoorEnvironmentOverride(
        temperatureC: 35,
        precipitationMm: 1.5,
        updatedAt: changedAt,
      ),
    );

    expect(result.reading?.temperatureC, 35);
    expect(result.reading?.humidityPercent, sourceReading.humidityPercent);
    expect(result.reading?.pm2_5, sourceReading.pm2_5);
    expect(result.reading?.precipitationMm, 1.5);
    expect(result.reading?.fetchedAt, changedAt);
  });

  test('실데이터가 없으면 부분값은 대기하고 완전값은 독립 동작한다', () {
    const error = WeatherTestException();
    const source = OutdoorWeatherStatus(isLoading: true, error: error);
    final partial = OutdoorEnvironmentOverride(
      temperatureC: 30,
      updatedAt: changedAt,
    );
    expect(applyOutdoorEnvironmentOverride(source, partial), same(source));

    final result = applyOutdoorEnvironmentOverride(source, completeOverride());
    expect(result.reading?.temperatureC, 31.5);
    expect(result.reading?.isRaining, isTrue);
    expect(result.reading?.observedAt, changedAt);
    expect(result.isLoading, isFalse);
    expect(result.error, same(error));
  });

  test('새 API 값이 와도 활성 override를 유지하고 해제 시 실데이터로 복귀한다', () {
    final override = OutdoorEnvironmentOverride(
      humidityPercent: 88,
      updatedAt: changedAt,
    );
    final first = applyOutdoorEnvironmentOverride(
      OutdoorWeatherStatus(reading: _reading(humidityPercent: 40)),
      override,
    );
    final refreshed = applyOutdoorEnvironmentOverride(
      OutdoorWeatherStatus(reading: _reading(humidityPercent: 50)),
      override,
    );
    final cleared = applyOutdoorEnvironmentOverride(
      OutdoorWeatherStatus(reading: _reading(humidityPercent: 50)),
      null,
    );

    expect(first.reading?.humidityPercent, 88);
    expect(refreshed.reading?.humidityPercent, 88);
    expect(cleared.reading?.humidityPercent, 50);
  });

  test('컨트롤러가 필드별 변경을 저장·복원하고 마지막 해제 시 삭제한다', () async {
    final storage = MemoryAppStorage(onboardingSeen: true);
    var container = ProviderContainer(
      overrides: [appStorageProvider.overrideWithValue(storage)],
    );
    expect(
      await container.read(outdoorEnvironmentOverrideProvider.future),
      isNull,
    );

    final controller = container.read(
      outdoorEnvironmentOverrideProvider.notifier,
    );
    await controller.setField(OutdoorEnvironmentField.temperatureC, 29.5);
    await controller.setField(OutdoorEnvironmentField.pm2_5, 42);
    expect(storage.outdoorEnvironmentOverride?.temperatureC, 29.5);
    expect(storage.outdoorEnvironmentOverride?.pm2_5, 42);
    container.dispose();

    container = ProviderContainer(
      overrides: [appStorageProvider.overrideWithValue(storage)],
    );
    expect(
      (await container.read(outdoorEnvironmentOverrideProvider.future))?.pm2_5,
      42,
    );
    final restoredController = container.read(
      outdoorEnvironmentOverrideProvider.notifier,
    );
    await restoredController.setField(
      OutdoorEnvironmentField.temperatureC,
      null,
    );
    expect(storage.outdoorEnvironmentOverride?.temperatureC, isNull);
    expect(storage.outdoorEnvironmentOverride?.pm2_5, 42);
    await restoredController.setField(OutdoorEnvironmentField.pm2_5, null);
    expect(storage.outdoorEnvironmentOverride, isNull);
    expect(container.read(outdoorEnvironmentOverrideProvider).value, isNull);
    container.dispose();
  });

  test('컨트롤러는 잘못된 값을 저장하지 않는다', () async {
    final storage = MemoryAppStorage(onboardingSeen: true);
    final container = ProviderContainer(
      overrides: [appStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    await container.read(outdoorEnvironmentOverrideProvider.future);

    expect(
      () => container
          .read(outdoorEnvironmentOverrideProvider.notifier)
          .setField(OutdoorEnvironmentField.humidityPercent, 101),
      throwsArgumentError,
    );
    expect(storage.outdoorEnvironmentOverride, isNull);
  });

  test('손상된 저장값은 비활성 상태로 복원한다', () async {
    FlutterSecureStorage.setMockInitialValues({
      'esw.outdoor_environment.override': '{not-json',
    });
    expect(await SecureAppStorage().readOutdoorEnvironmentOverride(), isNull);
  });
}

OutdoorReading _reading({
  double temperatureC = 25,
  double humidityPercent = 60,
  double pm2_5 = 15,
  double precipitationMm = 0,
  DateTime? fetchedAt,
}) => OutdoorReading(
  temperatureC: temperatureC,
  humidityPercent: humidityPercent,
  pm2_5: pm2_5,
  precipitationMm: precipitationMm,
  observedAt: DateTime(2026, 8, 29, 12),
  fetchedAt: fetchedAt ?? DateTime(2026, 8, 29, 12),
);

final class WeatherTestException implements Exception {
  const WeatherTestException();
}
