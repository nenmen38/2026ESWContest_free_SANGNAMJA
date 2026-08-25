// ignore_for_file: public_member_api_docs

/// Base class for failures reported by the ESW SDK.
sealed class EswSdkException implements Exception {
  /// Creates an SDK failure with a stable human-readable [message].
  const EswSdkException(this.message, [this.cause]);

  /// A description suitable for logs and simple user interfaces.
  final String message;

  /// The lower-level cause, retained for diagnostics only.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The control server could not be reached or the connection was lost.
final class ConnectionException extends EswSdkException {
  /// Creates a connection failure.
  const ConnectionException(super.message, [super.cause]);
}

/// The supplied server or provisioning credentials were rejected.
final class AuthenticationException extends EswSdkException {
  /// Creates an authentication failure.
  const AuthenticationException(super.message, [super.cause]);
}

/// The requested device is not currently online.
final class DeviceOfflineException extends EswSdkException {
  /// Creates an offline-device failure.
  const DeviceOfflineException(super.message, [super.cause]);
}

/// Wi-Fi provisioning completed but the device did not become available.
final class DeviceAvailabilityTimeoutException extends EswSdkException {
  /// Creates an availability timeout failure.
  const DeviceAvailabilityTimeoutException(super.message);
}

/// A command was rejected by the target device.
final class CommandRejectedException extends EswSdkException {
  /// Creates a rejected-command failure.
  const CommandRejectedException(super.message, [super.cause]);
}

/// A command did not receive a matching result before its deadline.
final class CommandTimeoutException extends EswSdkException {
  /// Creates a command-timeout failure.
  const CommandTimeoutException(super.message, [super.cause]);
}

/// Stable reason for a BLE provisioning failure.
enum ProvisioningFailureCode {
  permissionDenied,
  deviceUnavailable,
  bleConnection,
  incompatibleProtocol,
  wrongPop,
  wifiRejected,
  wifiAuthentication,
  wifiNotFound,
  disconnected,
  timeout,
}

/// BLE discovery or device provisioning failed.
final class ProvisioningException extends EswSdkException {
  /// Creates a provisioning failure.
  const ProvisioningException(this.code, super.message, [super.cause]);

  /// Machine-readable failure reason.
  final ProvisioningFailureCode code;
}

/// A device supplied malformed or incompatible protocol data.
final class DeviceDataException extends EswSdkException {
  /// Creates a device-data failure.
  const DeviceDataException(super.message, [super.cause]);
}
