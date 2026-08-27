import 'package:esw_device_sdk/esw_device_sdk.dart';

final class InstallationLocation {
  const InstallationLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  void validate() {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(latitude, 'latitude', 'Must be -90 to 90.');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(longitude, 'longitude', 'Must be -180 to 180.');
    }
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };

  factory InstallationLocation.fromJson(Map<String, dynamic> json) {
    final location = InstallationLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
    location.validate();
    return location;
  }

  String get label =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

final class SelectedDeviceIds {
  const SelectedDeviceIds({this.motorId, this.sensorId});

  final String? motorId;
  final String? sensorId;

  SelectedDeviceIds copyWith({String? motorId, String? sensorId}) =>
      SelectedDeviceIds(
        motorId: motorId ?? this.motorId,
        sensorId: sensorId ?? this.sensorId,
      );

  Map<String, dynamic> toJson() => {'motorId': motorId, 'sensorId': sensorId};

  factory SelectedDeviceIds.fromJson(Map<String, dynamic> json) =>
      SelectedDeviceIds(
        motorId: json['motorId'] as String?,
        sensorId: json['sensorId'] as String?,
      );
}

final class OutdoorReading {
  const OutdoorReading({
    required this.temperatureC,
    required this.humidityPercent,
    required this.pm2_5,
    required this.precipitationMm,
    required this.observedAt,
    required this.fetchedAt,
  });

  final double temperatureC;
  final double humidityPercent;
  final double pm2_5;
  final double precipitationMm;
  final DateTime observedAt;
  final DateTime fetchedAt;

  bool get isRaining => precipitationMm > 0;
}

final class OutdoorWeatherStatus {
  const OutdoorWeatherStatus({
    this.reading,
    this.isLoading = false,
    this.isDelayed = false,
    this.error,
  });

  const OutdoorWeatherStatus.loading()
    : reading = null,
      isLoading = true,
      isDelayed = false,
      error = null;

  final OutdoorReading? reading;
  final bool isLoading;
  final bool isDelayed;
  final Object? error;
}

final class TemperatureHumidity {
  const TemperatureHumidity({this.temperatureC, this.humidityPercent});

  final double? temperatureC;
  final double? humidityPercent;

  String get temperatureLabel =>
      temperatureC == null ? '—' : '${temperatureC!.toStringAsFixed(1)}°C';
  String get humidityLabel =>
      humidityPercent == null ? '습도 —' : '습도 ${humidityPercent!.round()}%';
}

final class FineDust {
  const FineDust({this.pm25});

  final double? pm25;

  String get levelLabel {
    final value = pm25;
    if (value == null) return '—';
    if (value <= 15) return '좋음';
    if (value <= 35) return '보통';
    if (value <= 75) return '나쁨';
    return '매우 나쁨';
  }

  String get detailLabel =>
      pm25 == null ? 'PM2.5 —' : 'PM2.5 ${pm25!.round()}㎍/㎥';
}

final class EnvironmentSnapshot {
  const EnvironmentSnapshot({
    required this.indoor,
    required this.outdoor,
    required this.indoorFineDust,
    required this.outdoorFineDust,
    required this.isRaining,
    required this.updatedAtLabel,
    required this.isWeatherDelayed,
  });

  factory EnvironmentSnapshot.fromSources({
    AirQualityReading? indoor,
    OutdoorWeatherStatus weather = const OutdoorWeatherStatus.loading(),
  }) {
    final outdoor = weather.reading;
    final timestamps = <DateTime>[
      if (indoor != null) indoor.receivedAt,
      if (outdoor != null) outdoor.fetchedAt,
    ];
    timestamps.sort();
    final latest = timestamps.lastOrNull;
    return EnvironmentSnapshot(
      indoor: TemperatureHumidity(
        temperatureC: indoor?.temperatureC,
        humidityPercent: indoor?.humidityPercent,
      ),
      outdoor: TemperatureHumidity(
        temperatureC: outdoor?.temperatureC,
        humidityPercent: outdoor?.humidityPercent,
      ),
      indoorFineDust: FineDust(pm25: indoor?.pm2_5?.toDouble()),
      outdoorFineDust: FineDust(pm25: outdoor?.pm2_5),
      isRaining: outdoor?.isRaining ?? false,
      updatedAtLabel: latest == null
          ? '실데이터를 기다리는 중'
          : '${latest.hour.toString().padLeft(2, '0')}:${latest.minute.toString().padLeft(2, '0')} 업데이트${weather.isDelayed ? ' · 갱신 지연' : ''}',
      isWeatherDelayed: weather.isDelayed,
    );
  }

  final TemperatureHumidity indoor;
  final TemperatureHumidity outdoor;
  final FineDust indoorFineDust;
  final FineDust outdoorFineDust;
  final bool isRaining;
  final String updatedAtLabel;
  final bool isWeatherDelayed;
}
