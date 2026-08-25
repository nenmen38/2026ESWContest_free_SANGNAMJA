import 'models.dart';

/// A nearby ESW device advertising that it is ready for setup.
final class SetupDevice {
  /// Creates a setup candidate discovered by the SDK.
  const SetupDevice({required this.id, required this.name, required this.rssi});

  /// Platform-specific BLE identifier used only to retain this selection.
  final String id;

  /// Firmware provisioning service name printed in the device QR code.
  final String name;

  /// Last observed signal strength in dBm.
  final int rssi;
}

/// One Wi-Fi network observed by the device being configured.
final class SetupWifiNetwork {
  /// Creates a device-observed Wi-Fi network.
  const SetupWifiNetwork({
    required this.ssid,
    required this.rssi,
    this.bssid,
    required this.isPrivate,
  });

  /// Network name. An empty value represents a hidden network.
  final String ssid;

  /// Signal strength reported by the device in dBm.
  final int rssi;

  /// Access-point identifier, when reported by the device.
  final String? bssid;

  /// Whether the network reports that credentials are required.
  final bool isPrivate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetupWifiNetwork &&
          ssid == other.ssid &&
          rssi == other.rssi &&
          bssid == other.bssid &&
          isPrivate == other.isPrivate;

  @override
  int get hashCode => Object.hash(ssid, rssi, bssid, isPrivate);
}

/// Progress reported while a device receives Wi-Fi and becomes usable.
enum DeviceSetupStep {
  /// Connecting to the device over BLE.
  connecting,

  /// Checking the firmware provisioning contract.
  checkingProtocol,

  /// Establishing the Security 1 session.
  securing,

  /// Sending and applying the selected Wi-Fi settings.
  applyingWifi,

  /// Waiting for the device to join Wi-Fi.
  waitingForWifi,

  /// Waiting for the first post-setup motor state or sensor reading.
  waitingForDevice,

  /// The device is online and has supplied domain data.
  completed,
}

/// Result of a complete BLE, Wi-Fi, and control-service setup.
final class DeviceSetupResult {
  /// Creates a completed setup result.
  const DeviceSetupResult({required this.device, this.deviceIp});

  /// First ready device snapshot observed after Wi-Fi setup.
  final EswDeviceSnapshot device;

  /// IP address reported by provisioning, when available.
  final String? deviceIp;
}

/// Guided setup session for one selected device and proof of possession.
///
/// No BLE connection is held between calls. [scanWifi] may be repeated, and a
/// failed [complete] may be retried. After [complete] succeeds the session is
/// consumed. The owning SDK must stay alive for the whole operation.
abstract interface class DeviceSetup {
  /// Device selected for this setup session.
  SetupDevice get device;

  /// Scans Wi-Fi from the device using a short-lived secure BLE session.
  Future<List<SetupWifiNetwork>> scanWifi();

  /// Applies [network] and waits for post-setup domain data.
  ///
  /// Throws a provisioning exception for BLE or Wi-Fi failures, and a
  /// `DeviceAvailabilityTimeoutException` when no fresh motor state or sensor
  /// reading arrives before [availabilityTimeout]. Only one SDK setup
  /// operation may be active at a time.
  Future<DeviceSetupResult> complete({
    required SetupWifiNetwork network,
    required String password,
    void Function(DeviceSetupStep step)? onProgress,
    Duration availabilityTimeout = const Duration(seconds: 20),
  });
}
