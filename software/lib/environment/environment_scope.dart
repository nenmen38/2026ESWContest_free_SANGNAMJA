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

final outdoorWeatherProvider = StreamProvider<OutdoorWeatherStatus>((ref) {
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
