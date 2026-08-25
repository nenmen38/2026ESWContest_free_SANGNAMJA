import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('example source uses only the SDK public barrel', () {
    final sourceFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in sourceFiles) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:esw_device_sdk/src/')));
      expect(source, isNot(contains('package:mqtt_client/')));
      expect(source, isNot(contains('package:esp_provisioning_ble/')));
      expect(source, isNot(contains('package:flutter_blue_plus/')));
    }
  });
}
