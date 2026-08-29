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
  Future<HouseProfile> readHouseProfile();
  Future<void> writeHouseProfile(HouseProfile profile);
  Future<SelectedDeviceIds> readSelectedDeviceIds();
  Future<void> writeSelectedDeviceIds(SelectedDeviceIds selection);
  Future<IndoorEnvironmentOverride?> readIndoorEnvironmentOverride();
  Future<void> writeIndoorEnvironmentOverride(IndoorEnvironmentOverride value);
  Future<void> clearIndoorEnvironmentOverride();
  Future<OutdoorEnvironmentOverride?> readOutdoorEnvironmentOverride();
  Future<void> writeOutdoorEnvironmentOverride(
    OutdoorEnvironmentOverride value,
  );
  Future<void> clearOutdoorEnvironmentOverride();
}

final class SecureAppStorage implements AppStorage {
  SecureAppStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _onboardingKey = 'esw.onboarding.seen';
  static const _credentialsKey = 'esw.connection.credentials';
  static const _locationKey = 'esw.installation.location';
  static const _houseProfileKey = 'esw.home.house_profile';
  static const _selectedDevicesKey = 'esw.home.selected_devices';
  static const _indoorEnvironmentOverrideKey =
      'esw.indoor_environment.override';
  static const _outdoorEnvironmentOverrideKey =
      'esw.outdoor_environment.override';
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
  Future<HouseProfile> readHouseProfile() async {
    final raw = await _storage.read(key: _houseProfileKey);
    if (raw == null) return const HouseProfile();
    try {
      return HouseProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const HouseProfile();
    }
  }

  @override
  Future<void> writeHouseProfile(HouseProfile profile) => _storage.write(
    key: _houseProfileKey,
    value: jsonEncode(profile.toJson()),
  );

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

  @override
  Future<IndoorEnvironmentOverride?> readIndoorEnvironmentOverride() async {
    final raw = await _storage.read(key: _indoorEnvironmentOverrideKey);
    if (raw == null) return null;
    try {
      final value = IndoorEnvironmentOverride.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      return value.isActive ? value : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeIndoorEnvironmentOverride(IndoorEnvironmentOverride value) {
    value.validate();
    if (!value.isActive) return clearIndoorEnvironmentOverride();
    return _storage.write(
      key: _indoorEnvironmentOverrideKey,
      value: jsonEncode(value.toJson()),
    );
  }

  @override
  Future<void> clearIndoorEnvironmentOverride() =>
      _storage.delete(key: _indoorEnvironmentOverrideKey);

  @override
  Future<OutdoorEnvironmentOverride?> readOutdoorEnvironmentOverride() async {
    final raw = await _storage.read(key: _outdoorEnvironmentOverrideKey);
    if (raw == null) return null;
    try {
      final value = OutdoorEnvironmentOverride.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      return value.isActive ? value : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeOutdoorEnvironmentOverride(
    OutdoorEnvironmentOverride value,
  ) {
    value.validate();
    if (!value.isActive) return clearOutdoorEnvironmentOverride();
    return _storage.write(
      key: _outdoorEnvironmentOverrideKey,
      value: jsonEncode(value.toJson()),
    );
  }

  @override
  Future<void> clearOutdoorEnvironmentOverride() =>
      _storage.delete(key: _outdoorEnvironmentOverrideKey);
}
