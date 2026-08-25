// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import 'package:esp_provisioning_ble/esp_provisioning_ble.dart';
import 'package:esw_device_sdk/src/ble_prov_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ESP-IDF 6.x transport exposes only standard provisioning endpoints',
    () {
      expect(
        BleProvTransport.serviceUuid,
        '1775244d-6b43-439b-877c-060f2d9bed07',
      );
      expect(BleProvTransport.endpoints, hasLength(4));
      expect(BleProvTransport.endpoints, isNot(contains('custom-data')));
    },
  );

  test(
    'a disconnected fake BLE transport fails without leaking resources',
    () async {
      final transport = _FakeBleTransport();
      final provisioner = EspProv(
        transport: transport,
        security: Security1(pop: 'test-only-pop'),
      );

      expect(
        await provisioner.establishSession(),
        EstablishSessionStatus.disconnected,
      );
      await provisioner.dispose();
      expect(transport.disconnectCalls, 1);
    },
  );
}

final class _FakeBleTransport implements ProvTransport {
  int disconnectCalls = 0;

  @override
  Future<bool> checkConnect() async => false;

  @override
  Future<bool> connect() async => false;

  @override
  Future<bool> disconnect() async {
    disconnectCalls += 1;
    return true;
  }

  @override
  Future<Uint8List> sendReceive(String epName, Uint8List data) {
    throw StateError('A disconnected transport must not exchange data.');
  }
}
