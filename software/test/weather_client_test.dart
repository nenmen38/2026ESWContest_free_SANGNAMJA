import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_smart_window_system/environment/environment_models.dart';
import 'package:safe_smart_window_system/environment/weather_client.dart';

void main() {
  test('Open-Meteo 현재 날씨와 공기질 응답을 결합한다', () {
    final reading = OpenMeteoWeatherClient.parse(
      {
        'current': {
          'time': '2026-08-28T14:00',
          'temperature_2m': 27.4,
          'relative_humidity_2m': 63,
          'precipitation': 0.5,
          'wind_speed_10m': 12.5,
          'wind_direction_10m': 275,
        },
      },
      {
        'current': {'time': '2026-08-28T14:00', 'pm2_5': 12.6},
      },
      fetchedAt: DateTime(2026, 8, 28, 14, 5),
    );
    expect(reading.temperatureC, 27.4);
    expect(reading.humidityPercent, 63);
    expect(reading.pm2_5, 12.6);
    expect(reading.windSpeed10m, 12.5);
    expect(reading.windDirection10m, 275);
    expect(reading.isRaining, isTrue);
  });

  test('필수 current 필드가 없으면 응답을 거부한다', () {
    expect(
      () => OpenMeteoWeatherClient.parse(
        const {},
        const {},
        fetchedAt: DateTime(2026),
      ),
      throwsA(isA<WeatherException>()),
    );
  });

  test('저장된 좌표로 날씨와 공기질 current API를 모두 요청한다', () async {
    final requests = <Uri>[];
    final client = OpenMeteoWeatherClient(
      MockClient((request) async {
        requests.add(request.url);
        final body = request.url.host.startsWith('air-quality')
            ? {
                'current': {'time': '2026-08-28T14:00', 'pm2_5': 12.6},
              }
            : {
                'current': {
                  'time': '2026-08-28T14:00',
                  'temperature_2m': 27.4,
                  'relative_humidity_2m': 63,
                  'precipitation': 0,
                },
              };
        return http.Response(jsonEncode(body), 200);
      }),
    );

    await client.fetch(
      const InstallationLocation(latitude: 37.5665, longitude: 126.978),
    );

    expect(requests, hasLength(2));
    expect(
      requests.every((uri) => uri.queryParameters['latitude'] == '37.5665'),
      isTrue,
    );
    expect(requests.any((uri) => uri.path == '/v1/forecast'), isTrue);
    expect(requests.any((uri) => uri.path == '/v1/air-quality'), isTrue);
    expect(
      requests
          .where((uri) => uri.path == '/v1/forecast')
          .single
          .queryParameters['wind_speed_unit'],
      'kmh',
    );
  });
}
