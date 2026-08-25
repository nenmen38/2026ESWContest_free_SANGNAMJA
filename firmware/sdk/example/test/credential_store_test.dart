import 'package:esw_device_sdk_example/demo_controller.dart';
import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('broker credentials can be saved restored and cleared', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = CredentialStore();
    const expected = EswConnectionConfig(
      server: 'broker.example.com',
      port: 8883,
      account: 'app',
      secret: 'secret',
    );

    await store.save(expected);
    final restored = await store.load();
    expect(restored?.server, expected.server);
    expect(restored?.port, expected.port);
    expect(restored?.account, expected.account);
    expect(restored?.secret, expected.secret);

    await store.clear();
    expect(await store.load(), isNull);
  });

  test(
    'clearing credentials preserves storage owned by the host app',
    () async {
      FlutterSecureStorage.setMockInitialValues({'unrelated': 'keep'});
      final store = CredentialStore();
      await store.save(
        const EswConnectionConfig(
          server: 'broker.example.com',
          account: 'app',
          secret: 'secret',
        ),
      );

      await store.clear();

      expect(await const FlutterSecureStorage().read(key: 'unrelated'), 'keep');
    },
  );
}
