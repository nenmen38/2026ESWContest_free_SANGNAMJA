import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'environment_models.dart';

abstract interface class WeatherClient {
  Future<OutdoorReading> fetch(InstallationLocation location);
}

final class OpenMeteoWeatherClient implements WeatherClient {
  OpenMeteoWeatherClient(
    this._client, {
    this.timeout = const Duration(seconds: 10),
  });

  final http.Client _client;
  final Duration timeout;

  @override
  Future<OutdoorReading> fetch(InstallationLocation location) async {
    location.validate();
    final forecastUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${location.latitude}',
      'longitude': '${location.longitude}',
      'current':
          'temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m,wind_direction_10m',
      'timezone': 'auto',
    });
    final airUri = Uri.https(
      'air-quality-api.open-meteo.com',
      '/v1/air-quality',
      {
        'latitude': '${location.latitude}',
        'longitude': '${location.longitude}',
        'current': 'pm2_5',
        'timezone': 'auto',
      },
    );
    final responses = await Future.wait([
      _client.get(forecastUri).timeout(timeout),
      _client.get(airUri).timeout(timeout),
    ]);
    for (final response in responses) {
      if (response.statusCode != 200) {
        throw WeatherException('Open-Meteo 응답 오류 (${response.statusCode})');
      }
    }
    return parse(
      jsonDecode(responses[0].body) as Map<String, dynamic>,
      jsonDecode(responses[1].body) as Map<String, dynamic>,
      fetchedAt: DateTime.now(),
    );
  }

  static OutdoorReading parse(
    Map<String, dynamic> forecast,
    Map<String, dynamic> airQuality, {
    required DateTime fetchedAt,
  }) {
    final weather = forecast['current'];
    final air = airQuality['current'];
    if (weather is! Map<String, dynamic> || air is! Map<String, dynamic>) {
      throw const WeatherException('Open-Meteo 현재 관측값이 없습니다.');
    }
    double number(Map<String, dynamic> map, String key) {
      final value = map[key];
      if (value is! num || !value.toDouble().isFinite) {
        throw WeatherException('Open-Meteo 필드가 올바르지 않습니다: $key');
      }
      return value.toDouble();
    }

    final observedAt = DateTime.tryParse(weather['time'] as String? ?? '');
    if (observedAt == null) {
      throw const WeatherException('Open-Meteo 관측 시간이 올바르지 않습니다.');
    }
    final windSpeed = weather['wind_speed_10m'];
    final windDirection = weather['wind_direction_10m'];
    return OutdoorReading(
      temperatureC: number(weather, 'temperature_2m'),
      humidityPercent: number(weather, 'relative_humidity_2m'),
      precipitationMm: number(weather, 'precipitation'),
      windSpeed10m: windSpeed is num ? windSpeed.toDouble() : null,
      windDirection10m:
          windDirection is num ? windDirection.toDouble() : null,
      pm2_5: number(air, 'pm2_5'),
      observedAt: observedAt,
      fetchedAt: fetchedAt,
    );
  }
}

final class WeatherException implements Exception {
  const WeatherException(this.message);
  final String message;
  @override
  String toString() => message;
}
