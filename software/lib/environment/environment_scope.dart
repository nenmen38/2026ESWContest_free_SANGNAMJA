import 'dart:async';

import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../app/sdk_scope.dart';
import 'environment_models.dart';
import 'location_service.dart';
import 'weather_client.dart';

final locationServiceProvider = Provider<InstallationLocationService>(
  (_) => DeviceLocationService(),
);

final weatherClientProvider = Provider<WeatherClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return OpenMeteoWeatherClient(client);
});

final installationLocationProvider = FutureProvider<InstallationLocation?>(
  (ref) => ref.watch(appStorageProvider).readInstallationLocation(),
);

final selectedDeviceIdsProvider = FutureProvider<SelectedDeviceIds>(
  (ref) => ref.watch(appStorageProvider).readSelectedDeviceIds(),
);

final indoorEnvironmentOverrideProvider =
    AsyncNotifierProvider<
      IndoorEnvironmentOverrideController,
      IndoorEnvironmentOverride?
    >(IndoorEnvironmentOverrideController.new);

final class IndoorEnvironmentOverrideController
    extends AsyncNotifier<IndoorEnvironmentOverride?> {
  Future<IndoorEnvironmentOverride?>? _restore;

  @override
  Future<IndoorEnvironmentOverride?> build() =>
      _restore = ref.watch(appStorageProvider).readIndoorEnvironmentOverride();

  Future<void> setField(IndoorEnvironmentField field, double? value) async {
    final current =
        state.value ??
        await (_restore ??= ref
            .read(appStorageProvider)
            .readIndoorEnvironmentOverride());
    await replace(
      temperatureC: field == IndoorEnvironmentField.temperatureC
          ? value
          : current?.temperatureC,
      humidityPercent: field == IndoorEnvironmentField.humidityPercent
          ? value
          : current?.humidityPercent,
      pm2_5: field == IndoorEnvironmentField.pm2_5 ? value : current?.pm2_5,
    );
  }

  Future<void> replace({
    double? temperatureC,
    double? humidityPercent,
    double? pm2_5,
  }) async {
    final next = IndoorEnvironmentOverride(
      temperatureC: temperatureC,
      humidityPercent: humidityPercent,
      pm2_5: pm2_5,
      updatedAt: DateTime.now(),
    );
    next.validate();
    if (!next.isActive) {
      await clearAll();
      return;
    }
    await ref.read(appStorageProvider).writeIndoorEnvironmentOverride(next);
    state = AsyncData(next);
  }

  Future<void> clearAll() async {
    await ref.read(appStorageProvider).clearIndoorEnvironmentOverride();
    state = const AsyncData(null);
  }
}

final outdoorEnvironmentOverrideProvider =
    AsyncNotifierProvider<
      OutdoorEnvironmentOverrideController,
      OutdoorEnvironmentOverride?
    >(OutdoorEnvironmentOverrideController.new);

final class OutdoorEnvironmentOverrideController
    extends AsyncNotifier<OutdoorEnvironmentOverride?> {
  Future<OutdoorEnvironmentOverride?>? _restore;

  @override
  Future<OutdoorEnvironmentOverride?> build() =>
      _restore = ref.watch(appStorageProvider).readOutdoorEnvironmentOverride();

  Future<void> setField(OutdoorEnvironmentField field, double? value) async {
    final current =
        state.value ??
        await (_restore ??= ref
            .read(appStorageProvider)
            .readOutdoorEnvironmentOverride());
    await replace(
      temperatureC: field == OutdoorEnvironmentField.temperatureC
          ? value
          : current?.temperatureC,
      humidityPercent: field == OutdoorEnvironmentField.humidityPercent
          ? value
          : current?.humidityPercent,
      pm2_5: field == OutdoorEnvironmentField.pm2_5 ? value : current?.pm2_5,
      precipitationMm: field == OutdoorEnvironmentField.precipitationMm
          ? value
          : current?.precipitationMm,
    );
  }

  Future<void> replace({
    double? temperatureC,
    double? humidityPercent,
    double? pm2_5,
    double? precipitationMm,
  }) async {
    final next = OutdoorEnvironmentOverride(
      temperatureC: temperatureC,
      humidityPercent: humidityPercent,
      pm2_5: pm2_5,
      precipitationMm: precipitationMm,
      updatedAt: DateTime.now(),
    );
    next.validate();
    if (!next.isActive) {
      await clearAll();
      return;
    }
    await ref.read(appStorageProvider).writeOutdoorEnvironmentOverride(next);
    state = AsyncData(next);
  }

  Future<void> clearAll() async {
    await ref.read(appStorageProvider).clearOutdoorEnvironmentOverride();
    state = const AsyncData(null);
  }
}

final rawOutdoorWeatherProvider = StreamProvider<OutdoorWeatherStatus>((ref) {
  final controller = StreamController<OutdoorWeatherStatus>();
  var disposed = false;
  Timer? timer;
  OutdoorReading? latest;

  Future<void> refresh() async {
    final location = await ref.read(installationLocationProvider.future);
    if (disposed) return;
    if (location == null) {
      controller.add(const OutdoorWeatherStatus());
      return;
    }
    if (latest == null) {
      controller.add(const OutdoorWeatherStatus.loading());
    }
    try {
      latest = await ref.read(weatherClientProvider).fetch(location);
      if (!disposed) controller.add(OutdoorWeatherStatus(reading: latest));
    } on Object catch (error) {
      if (!disposed) {
        controller.add(
          OutdoorWeatherStatus(
            reading: latest,
            isDelayed: latest != null,
            error: error,
          ),
        );
      }
    }
  }

  unawaited(refresh());
  timer = Timer.periodic(
    const Duration(minutes: 15),
    (_) => unawaited(refresh()),
  );
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
    unawaited(controller.close());
  });
  return controller.stream;
});

final outdoorWeatherProvider = Provider<AsyncValue<OutdoorWeatherStatus>>((
  ref,
) {
  final source = ref.watch(rawOutdoorWeatherProvider);
  final override = ref.watch(outdoorEnvironmentOverrideProvider);
  if (override.isLoading) return const AsyncValue.loading();
  return source.whenData(
    (status) => applyOutdoorEnvironmentOverride(status, override.value),
  );
});

MotorDeviceSnapshot? resolveMotor(
  EswSdkState state,
  SelectedDeviceIds selected,
) {
  final motors = state.devices.whereType<MotorDeviceSnapshot>().toList();
  if (selected.motorId case final id?) {
    return motors.where((device) => device.id == id).firstOrNull;
  }
  return motors.length == 1 ? motors.single : null;
}

AirQualityDeviceSnapshot? resolveSensor(
  EswSdkState state,
  SelectedDeviceIds selected,
) {
  final sensors = state.devices.whereType<AirQualityDeviceSnapshot>().toList();
  if (selected.sensorId case final id?) {
    return sensors.where((device) => device.id == id).firstOrNull;
  }
  return sensors.length == 1 ? sensors.single : null;
}
