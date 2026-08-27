import 'package:geolocator/geolocator.dart';

import 'environment_models.dart';

abstract interface class InstallationLocationService {
  Future<InstallationLocation> current();
}

final class DeviceLocationService implements InstallationLocationService {
  @override
  Future<InstallationLocation> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('휴대폰 위치 서비스를 켜 주세요.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('위치 권한이 거부되었습니다.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException('설정에서 위치 권한을 허용해 주세요.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return InstallationLocation(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}

final class LocationException implements Exception {
  const LocationException(this.message);
  final String message;
  @override
  String toString() => message;
}
