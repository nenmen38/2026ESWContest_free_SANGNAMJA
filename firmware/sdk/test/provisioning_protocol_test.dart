import 'dart:convert';
import 'dart:typed_data';

import 'package:esw_device_sdk/src/provisioning_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts the ESP-IDF 6.x provisioning contract', () {
    final response = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'prov': {
            'ver': 'v1.1',
            'sec_ver': 1,
            'cap': ['wifi_prov', 'wifi_scan'],
          },
          'esw': {'ver': '2', 'cap': <String>[]},
        }),
      ),
    );
    expect(() => verifyProvisioningInfo(response), returnsNormally);
  });

  test('rejects incompatible security and capabilities', () {
    final response = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'prov': {
            'sec_ver': 2,
            'cap': ['wifi_prov'],
          },
          'esw': {'ver': '1', 'cap': <String>[]},
        }),
      ),
    );
    expect(
      () => verifyProvisioningInfo(response),
      throwsA(isA<ProvisioningProtocolError>()),
    );
  });

  test('rejects the legacy MQTT custom-data contract', () {
    final response = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'prov': {
            'sec_ver': 1,
            'cap': ['wifi_prov', 'wifi_scan'],
          },
          'esw': {
            'ver': '1',
            'cap': ['mqtt_config'],
          },
        }),
      ),
    );
    expect(
      () => verifyProvisioningInfo(response),
      throwsA(isA<ProvisioningProtocolError>()),
    );
  });
}
