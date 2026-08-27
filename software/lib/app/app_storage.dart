import 'dart:convert';

import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../environment/environment_models.dart';

abstract interface class AppStorage {
  Future<bool> readOnboardingSeen();
  Future<void> writeOnboardingSeen(bool value);
  Future<EswConnectionConfig?> readCredentials();
  Future<void> writeCredentials(EswConnectionConfig config);
  Future<void> clearCredentials();
  Future<InstallationLocation?> readInstallationLocation();
  Future<void> writeInstallationLocation(InstallationLocation location);
  Future<SelectedDeviceIds> readSelectedDeviceIds();
  Future<void> writeSelectedDeviceIds(SelectedDeviceIds selection);
}

final class SecureAppStorage implements AppStorage {
  SecureAppStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _onboardingKey = 'esw.onboarding.seen';
  static const _credentialsKey = 'esw.connection.credentials';
  static const _locationKey = 'esw.installation.location';
  static const _selectedDevicesKey = 'esw.home.selected_devices';
  final FlutterSecureStorage _storage;

  @override
  Future<bool> readOnboardingSeen() async =>
      await _storage.read(key: _onboardingKey) == 'true';

  @override
  Future<void> writeOnboardingSeen(bool value) =>
      _storage.write(key: _onboardingKey, value: '$value');

  @override
  Future<EswConnectionConfig?> readCredentials() async {
    final raw = await _storage.read(key: _credentialsKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final config = EswConnectionConfig(
        server: json['server'] as String,
        port: json['port'] as int,
        account: json['account'] as String,
        secret: json['secret'] as String,
      );
      config.validate();
      return config;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeCredentials(EswConnectionConfig config) => _storage.write(
    key: _credentialsKey,
    value: jsonEncode({
      'server': config.server,
      'port': config.port,
      'account': config.account,
      'secret': config.secret,
    }),
  );

  @override
  Future<void> clearCredentials() => _storage.delete(key: _credentialsKey);

  @override
  Future<InstallationLocation?> readInstallationLocation() async {
    final raw = await _storage.read(key: _locationKey);
    if (raw == null) return null;
    try {
      return InstallationLocation.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeInstallationLocation(InstallationLocation location) {
    location.validate();
    return _storage.write(
      key: _locationKey,
      value: jsonEncode(location.toJson()),
    );
  }

  @override
  Future<SelectedDeviceIds> readSelectedDeviceIds() async {
    final raw = await _storage.read(key: _selectedDevicesKey);
    if (raw == null) return const SelectedDeviceIds();
    try {
      return SelectedDeviceIds.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return const SelectedDeviceIds();
    }
  }

  @override
  Future<void> writeSelectedDeviceIds(SelectedDeviceIds selection) => _storage
      .write(key: _selectedDevicesKey, value: jsonEncode(selection.toJson()));
}
