// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import 'package:esp_provisioning_ble/esp_provisioning_ble.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

final class BleProvTransport implements ProvTransport {
  BleProvTransport(this.device);

  final BluetoothDevice device;
  Map<String, BluetoothCharacteristic> _characteristics = const {};

  static const serviceUuid = '1775244d-6b43-439b-877c-060f2d9bed07';
  static const endpoints = <String, String>{
    'prov-scan': 'ff50',
    'prov-session': 'ff51',
    'prov-config': 'ff52',
    'proto-ver': 'ff53',
  };

  @override
  Future<bool> connect() async {
    await disconnect();
    try {
      // This contest/educational application uses the package's nonprofit tier.
      await device.connect(license: License.nonprofit, autoConnect: false);
      try {
        await device.requestMtu(256);
      } on Object {
        // iOS negotiates MTU and some Android stacks reject explicit requests.
      }
      final services = await device.discoverServices();
      final targetUuids = {
        for (final entry in endpoints.entries)
          characteristicUuid(serviceUuid, entry.value): entry.key,
      };
      final found = <String, BluetoothCharacteristic>{};
      for (final service in services) {
        if (service.uuid.toString().toLowerCase() != serviceUuid) continue;
        for (final characteristic in service.characteristics) {
          final endpoint =
              targetUuids[characteristic.uuid.toString().toLowerCase()];
          if (endpoint != null) found[endpoint] = characteristic;
        }
      }
      if (!endpoints.keys.every(found.containsKey)) {
        await disconnect();
        return false;
      }
      _characteristics = found;
      return true;
    } on Object {
      await disconnect();
      return false;
    }
  }

  static String characteristicUuid(String serviceUuid, String shortUuid) =>
      '${serviceUuid.substring(0, 4)}$shortUuid${serviceUuid.substring(8)}';

  @override
  Future<bool> checkConnect() async => device.isConnected;

  @override
  Future<bool> disconnect() async {
    if (!device.isConnected) return true;
    try {
      await device.disconnect();
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<Uint8List> sendReceive(String epName, Uint8List data) async {
    final characteristic = _characteristics[epName];
    if (characteristic == null) {
      throw StateError('Provisioning endpoint unavailable: $epName');
    }
    if (data.isNotEmpty) {
      await characteristic.write(data, withoutResponse: false);
    }
    return Uint8List.fromList(await characteristic.read());
  }
}
