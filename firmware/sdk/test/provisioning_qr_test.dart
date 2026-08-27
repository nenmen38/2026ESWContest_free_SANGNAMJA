import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a generated motor provisioning label', () {
    final payload = ProvisioningQrPayload.parse(
      '{"ver":"v1","name":"PROV-MOTOR-A1B2",'
      '"pop":"device-secret","transport":"ble"}',
    );

    expect(payload.name, 'PROV-MOTOR-A1B2');
    expect(payload.pop, 'device-secret');
  });

  test('accepts standard extra fields', () {
    final payload = ProvisioningQrPayload.parse(
      '{"ver":"v1","name":"PROV-SENSOR-00FF",'
      '"username":"unused","pop":"p","transport":"ble"}',
    );

    expect(payload.name, 'PROV-SENSOR-00FF');
  });

  test('rejects unrelated and malformed QR values', () {
    for (final value in [
      'https://example.com',
      '[]',
      '{"ver":"v2","name":"PROV-MOTOR-A1B2","pop":"p","transport":"ble"}',
      '{"ver":"v1","name":"OTHER-A1B2","pop":"p","transport":"ble"}',
      '{"ver":"v1","name":"PROV-MOTOR-A1B2","pop":"","transport":"ble"}',
      '{"ver":"v1","name":"PROV-MOTOR-A1B2","pop":"p","transport":"softap"}',
    ]) {
      expect(() => ProvisioningQrPayload.parse(value), throwsFormatException);
    }
  });
}
