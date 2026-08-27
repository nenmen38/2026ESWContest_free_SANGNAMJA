// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';

final class ProvisioningProtocolError implements Exception {
  const ProvisioningProtocolError(this.message);
  final String message;
  @override
  String toString() => message;
}

void verifyProvisioningInfo(Uint8List bytes) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object catch (error) {
    throw ProvisioningProtocolError('Invalid proto-ver response: $error');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const ProvisioningProtocolError('Invalid proto-ver response.');
  }
  final prov = decoded['prov'];
  final app = decoded['esw'];
  final provCapabilities = prov is Map<String, dynamic> ? prov['cap'] : null;
  final appCapabilities = app is Map<String, dynamic> ? app['cap'] : null;
  if (prov is! Map<String, dynamic> ||
      app is! Map<String, dynamic> ||
      prov['sec_ver'] != 1 ||
      provCapabilities is! List ||
      !provCapabilities.contains('wifi_prov') ||
      !provCapabilities.contains('wifi_scan') ||
      app['ver'] != '2' ||
      appCapabilities is! List ||
      appCapabilities.isNotEmpty) {
    throw const ProvisioningProtocolError(
      'The device provisioning contract is incompatible.',
    );
  }
}
