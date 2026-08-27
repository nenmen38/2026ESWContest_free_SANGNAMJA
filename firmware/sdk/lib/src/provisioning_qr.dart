import 'dart:convert';

/// Validated device identity and proof of possession read from a provisioning
/// QR code.
final class ProvisioningQrPayload {
  const ProvisioningQrPayload._({required this.name, required this.pop});

  static final RegExp _serviceName = RegExp(
    r'^PROV-(?:MOTOR|SENSOR)-[0-9A-F]{4}$',
  );

  /// BLE provisioning service name encoded by the device label.
  final String name;

  /// Security 1 proof of possession encoded by the device label.
  final String pop;

  /// Parses the ESP provisioning v1 JSON payload used by printed labels.
  ///
  /// Throws a [FormatException] when [rawValue] is not a supported BLE
  /// provisioning payload.
  static ProvisioningQrPayload parse(String rawValue) {
    if (rawValue.length > 1024) {
      throw const FormatException('Provisioning QR payload is too large.');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(rawValue);
    } on FormatException {
      throw const FormatException('QR code is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('QR code is not a provisioning object.');
    }

    final version = decoded['ver'];
    final name = decoded['name'];
    final pop = decoded['pop'];
    final transport = decoded['transport'];
    if (version != 'v1' || transport != 'ble') {
      throw const FormatException('Unsupported provisioning QR code.');
    }
    if (name is! String || !_serviceName.hasMatch(name)) {
      throw const FormatException('Invalid provisioning service name.');
    }
    if (pop is! String || pop.isEmpty) {
      throw const FormatException('Provisioning PoP is missing.');
    }
    return ProvisioningQrPayload._(name: name, pop: pop);
  }
}
