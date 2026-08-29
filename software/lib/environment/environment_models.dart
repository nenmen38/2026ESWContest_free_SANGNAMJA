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

enum WindowOrientation {
  north,
  northEast,
  east,
  southEast,
  south,
  southWest,
  west,
  northWest;

  static WindowOrientation fromJson(dynamic value) => switch (value) {
    'north' => WindowOrientation.north,
    'northEast' || 'northeast' => WindowOrientation.northEast,
    'east' => WindowOrientation.east,
    'southEast' || 'southeast' => WindowOrientation.southEast,
    'south' => WindowOrientation.south,
    'southWest' || 'southwest' => WindowOrientation.southWest,
    'west' => WindowOrientation.west,
    'northWest' || 'northwest' => WindowOrientation.northWest,
    _ => WindowOrientation.south,
  };

  String get label => switch (this) {
    WindowOrientation.north => '북향',
    WindowOrientation.northEast => '북동향',
    WindowOrientation.east => '동향',
    WindowOrientation.southEast => '남동향',
    WindowOrientation.south => '남향',
    WindowOrientation.southWest => '남서향',
    WindowOrientation.west => '서향',
    WindowOrientation.northWest => '북서향',
  };

  double get exposureFactor => switch (this) {
    WindowOrientation.north => 0.85,
    WindowOrientation.northEast => 0.9,
    WindowOrientation.east => 1.0,
    WindowOrientation.southEast => 1.1,
    WindowOrientation.south => 1.2,
    WindowOrientation.southWest => 1.1,
    WindowOrientation.west => 1.0,
    WindowOrientation.northWest => 0.9,
  };
}

final class HouseProfile {
  const HouseProfile({
    this.floorAreaPyeong = 25,
    this.windowOrientation = WindowOrientation.south,
    this.recommendedSeconds = 180,
    this.maxWindowAreaM2 = 1.0,
  });

  final double floorAreaPyeong;
  final WindowOrientation windowOrientation;
  final int recommendedSeconds;
  final double maxWindowAreaM2;

  double get floorAreaVolumeM3 => 3.3 * floorAreaPyeong * 2.3;

  Map<String, dynamic> toJson() => {
    'floorAreaPyeong': floorAreaPyeong,
    'windowOrientation': windowOrientation.name,
    'recommendedSeconds': recommendedSeconds,
    'maxWindowAreaM2': maxWindowAreaM2,
  };

  factory HouseProfile.fromJson(Map<String, dynamic> json) => HouseProfile(
    floorAreaPyeong: ((json['floorAreaPyeong'] as num?) ?? 25).toDouble(),
    windowOrientation: WindowOrientation.fromJson(json['windowOrientation']),
    recommendedSeconds: (json['recommendedSeconds'] as int?) ?? 180,
    maxWindowAreaM2: ((json['maxWindowAreaM2'] as num?) ?? 1.0).toDouble(),
  );

  HouseProfile copyWith({
    double? floorAreaPyeong,
    WindowOrientation? windowOrientation,
    int? recommendedSeconds,
    double? maxWindowAreaM2,
  }) => HouseProfile(
    floorAreaPyeong: floorAreaPyeong ?? this.floorAreaPyeong,
    windowOrientation: windowOrientation ?? this.windowOrientation,
    recommendedSeconds: recommendedSeconds ?? this.recommendedSeconds,
    maxWindowAreaM2: maxWindowAreaM2 ?? this.maxWindowAreaM2,
  );
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
    this.windSpeed10m,
    this.windDirection10m,
    required this.observedAt,
    required this.fetchedAt,
  });

  final double temperatureC;
  final double humidityPercent;
  final double pm2_5;
  final double precipitationMm;
  final double? windSpeed10m;
  final double? windDirection10m;
  final DateTime observedAt;
  final DateTime fetchedAt;

  bool get isRaining => precipitationMm > 0.1;
}

enum IndoorEnvironmentField { temperatureC, humidityPercent, pm2_5 }

final class IndoorEnvironmentOverride {
  const IndoorEnvironmentOverride({
    required this.updatedAt,
    this.temperatureC,
    this.humidityPercent,
    this.pm2_5,
  });

  final double? temperatureC;
  final double? humidityPercent;
  final double? pm2_5;
  final DateTime updatedAt;

  bool get isActive =>
      temperatureC != null || humidityPercent != null || pm2_5 != null;

  bool get isComplete =>
      temperatureC != null && humidityPercent != null && pm2_5 != null;

  void validate() {
    _validateRange(temperatureC, 'temperatureC', -100, 100);
    _validateRange(humidityPercent, 'humidityPercent', 0, 100);
    _validateRange(pm2_5, 'pm2_5', 0, 10000);
  }

  Map<String, dynamic> toJson() => {
    'temperatureC': temperatureC,
    'humidityPercent': humidityPercent,
    'pm2_5': pm2_5,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory IndoorEnvironmentOverride.fromJson(Map<String, dynamic> json) {
    double? optionalNumber(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! num) {
        throw FormatException('$key must be a number.');
      }
      return value.toDouble();
    }

    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (updatedAt == null) {
      throw const FormatException('updatedAt must be an ISO-8601 timestamp.');
    }
    final value = IndoorEnvironmentOverride(
      temperatureC: optionalNumber('temperatureC'),
      humidityPercent: optionalNumber('humidityPercent'),
      pm2_5: optionalNumber('pm2_5'),
      updatedAt: updatedAt,
    );
    value.validate();
    return value;
  }

  static void _validateRange(
    double? value,
    String name,
    double minimum,
    double maximum,
  ) {
    if (value == null) return;
    if (!value.isFinite || value < minimum || value > maximum) {
      throw ArgumentError.value(
        value,
        name,
        'Must be a finite number from $minimum to $maximum.',
      );
    }
  }
}

enum OutdoorEnvironmentField {
  temperatureC,
  humidityPercent,
  pm2_5,
  precipitationMm,
}

final class OutdoorEnvironmentOverride {
  const OutdoorEnvironmentOverride({
    required this.updatedAt,
    this.temperatureC,
    this.humidityPercent,
    this.pm2_5,
    this.precipitationMm,
  });

  final double? temperatureC;
  final double? humidityPercent;
  final double? pm2_5;
  final double? precipitationMm;
  final DateTime updatedAt;

  bool get isActive =>
      temperatureC != null ||
      humidityPercent != null ||
      pm2_5 != null ||
      precipitationMm != null;

  bool get isComplete =>
      temperatureC != null &&
      humidityPercent != null &&
      pm2_5 != null &&
      precipitationMm != null;

  void validate() {
    _validateRange(temperatureC, 'temperatureC', -100, 100);
    _validateRange(humidityPercent, 'humidityPercent', 0, 100);
    _validateRange(pm2_5, 'pm2_5', 0, 10000);
    _validateRange(precipitationMm, 'precipitationMm', 0, 1000);
  }

  Map<String, dynamic> toJson() => {
    'temperatureC': temperatureC,
    'humidityPercent': humidityPercent,
    'pm2_5': pm2_5,
    'precipitationMm': precipitationMm,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory OutdoorEnvironmentOverride.fromJson(Map<String, dynamic> json) {
    double? optionalNumber(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! num) {
        throw FormatException('$key must be a number.');
      }
      return value.toDouble();
    }

    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (updatedAt == null) {
      throw const FormatException('updatedAt must be an ISO-8601 timestamp.');
    }
    final value = OutdoorEnvironmentOverride(
      temperatureC: optionalNumber('temperatureC'),
      humidityPercent: optionalNumber('humidityPercent'),
      pm2_5: optionalNumber('pm2_5'),
      precipitationMm: optionalNumber('precipitationMm'),
      updatedAt: updatedAt,
    );
    value.validate();
    return value;
  }

  static void _validateRange(
    double? value,
    String name,
    double minimum,
    double maximum,
  ) {
    if (value == null) return;
    if (!value.isFinite || value < minimum || value > maximum) {
      throw ArgumentError.value(
        value,
        name,
        'Must be a finite number from $minimum to $maximum.',
      );
    }
  }
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

OutdoorWeatherStatus applyOutdoorEnvironmentOverride(
  OutdoorWeatherStatus source,
  OutdoorEnvironmentOverride? override,
) {
  if (override == null || !override.isActive) return source;
  override.validate();

  final sourceReading = source.reading;
  if (sourceReading == null && !override.isComplete) return source;

  final reading = sourceReading == null
      ? OutdoorReading(
          temperatureC: override.temperatureC!,
          humidityPercent: override.humidityPercent!,
          pm2_5: override.pm2_5!,
          precipitationMm: override.precipitationMm!,
          observedAt: override.updatedAt,
          fetchedAt: override.updatedAt,
        )
      : OutdoorReading(
          temperatureC: override.temperatureC ?? sourceReading.temperatureC,
          humidityPercent:
              override.humidityPercent ?? sourceReading.humidityPercent,
          pm2_5: override.pm2_5 ?? sourceReading.pm2_5,
          precipitationMm:
              override.precipitationMm ?? sourceReading.precipitationMm,
          observedAt: sourceReading.observedAt,
          fetchedAt: override.updatedAt.isAfter(sourceReading.fetchedAt)
              ? override.updatedAt
              : sourceReading.fetchedAt,
        );
  return OutdoorWeatherStatus(
    reading: reading,
    isLoading: false,
    isDelayed: source.isDelayed,
    error: source.error,
  );
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
    IndoorEnvironmentOverride? indoorOverride,
    OutdoorWeatherStatus weather = const OutdoorWeatherStatus.loading(),
  }) {
    final appliesIndoorOverride =
        indoorOverride != null &&
        indoorOverride.isActive &&
        (indoor != null || indoorOverride.isComplete);
    if (appliesIndoorOverride) indoorOverride.validate();
    final outdoor = weather.reading;
    final timestamps = <DateTime>[
      if (indoor != null) indoor.receivedAt,
      if (appliesIndoorOverride) indoorOverride.updatedAt,
      if (outdoor != null) outdoor.fetchedAt,
    ];
    timestamps.sort();
    final latest = timestamps.lastOrNull;
    return EnvironmentSnapshot(
      indoor: TemperatureHumidity(
        temperatureC: appliesIndoorOverride
            ? indoorOverride.temperatureC ?? indoor?.temperatureC
            : indoor?.temperatureC,
        humidityPercent: appliesIndoorOverride
            ? indoorOverride.humidityPercent ?? indoor?.humidityPercent
            : indoor?.humidityPercent,
      ),
      outdoor: TemperatureHumidity(
        temperatureC: outdoor?.temperatureC,
        humidityPercent: outdoor?.humidityPercent,
      ),
      indoorFineDust: FineDust(
        pm25: appliesIndoorOverride
            ? indoorOverride.pm2_5 ?? indoor?.pm2_5?.toDouble()
            : indoor?.pm2_5?.toDouble(),
      ),
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
