# ESW Device SDK

`esw_device_sdk` is the high-level Flutter API for ESW motor and air-quality
devices. Applications observe one atomic state, issue typed motor commands,
and use a guided setup session without handling topics, JSON, or BLE protocol
types.

The package is private (`publish_to: none`), supports Android and iOS, and
implements firmware contract v1 with BLE Security 1 provisioning.

## Install

Add the SDK package to the Flutter application's `pubspec.yaml`. A `path`
dependency is resolved relative to that `pubspec.yaml`, not relative to the
shell's current directory.

For example, given this layout:

```text
workspace/
├─ 2026-ESWContest-Firmware/
│  └─ sdk/
│     └─ pubspec.yaml
└─ my_flutter_app/
   └─ pubspec.yaml
```

configure the application as follows:

```yaml
dependencies:
  esw_device_sdk:
    path: ../2026-ESWContest-Firmware/sdk
```

If the application and SDK directories are siblings, use `path: ../sdk`
instead. The path must point to the SDK package root containing its
`pubspec.yaml`; do not point it at `sdk/example`. Forward slashes work on all
platforms and are recommended in YAML, including on Windows.

Then resolve the dependency from the application directory:

```sh
flutter pub get
```

Import only the SDK's public library from application code:

```dart
import 'package:esw_device_sdk/esw_device_sdk.dart';
```

The package's `publish_to: none` setting prevents publishing to pub.dev but
does not prevent using it as a local path dependency.

Android applications require API 23 or later. iOS applications require iOS 13
or later. See `example/README.md` for permissions.

## Connect and observe

Create one SDK for the application lifetime. Every `states` subscriber first
receives `currentState`, followed by atomic connection and device updates.

```dart
final sdk = EswDeviceSdk();

final subscription = sdk.states.listen((state) {
  print(state.connection);
  for (final device in state.devices) {
    switch (device) {
      case MotorDeviceSnapshot(:final id, :final latestState):
        print('$id: ${latestState?.currentPositionPercent}%');
      case AirQualityDeviceSnapshot(:final id, :final latestReading):
        print('$id: PM2.5 ${latestReading?.pm2_5}');
    }
  }
});

await sdk.connect(
  const EswConnectionConfig(
    server: 'control.example.com',
    account: 'mobile-app',
    secret: 'runtime-secret',
  ),
);
```

Connection credentials are never persisted by the SDK. The host application
must obtain them securely, store them with a platform security facility when
needed, and provide deletion.

Reconnects to the same server, port, and account retain the latest device
snapshots and mark them offline until new presence arrives. Connecting to a
different scope clears the device registry and any pending commands so data
from one account cannot appear in another.

`EswDeviceSdk` is an `interface class`, so application tests may implement the
public contract with a fake. Production applications should construct
`EswDeviceSdk()` and do not need access to transport or BLE dependencies.

## Control a motor

Motor state is read from `EswSdkState`; `MotorController` contains commands
only. Commands sent to offline devices return `deviceOffline`, and an operation
without a correlated firmware result returns `timeout` after five seconds. An
event completes a command only when both its command ID and target device ID
match.

```dart
final result = await sdk.motor('motor-aabbccddeeff').setPosition(percent: 25);
if (!result.isAccepted) {
  print(result.status);
}
```

Positions must be finite values from 0 through 100. Firmware remains the final
authority for calibration, limit, position, and protection safety checks.

## Add a device

The QR path discovers the exact printed BLE service and retains its Security 1
proof of possession inside a guided session.

```dart
final qr = ProvisioningQrPayload.parse(scannedQrText);
final setup = await sdk.startDeviceSetup(qr);
final networks = await setup.scanWifi();

final result = await setup.complete(
  network: networks.first,
  password: userEnteredWifiPassword,
  onProgress: (step) => print(step),
);
print('Ready: ${result.device.id}');
```

For manual fallback, call `discoverSetupDevices()`, let the user choose a
`SetupDevice`, then call `startManualDeviceSetup(device: ..., pop: ...)`.

`complete` succeeds only after Wi-Fi connects and the matching device publishes
a new motor state or sensor reading. Online presence alone is insufficient. The
default readiness timeout is 20 seconds. A failed setup may be retried; a
completed setup is consumed. Only one setup operation may run per SDK instance.

## Shutdown

```dart
await subscription.cancel();
await sdk.disconnect(); // optional when the instance will be reused
await sdk.dispose();
```

`dispose` is idempotent and invalidates controllers and setup sessions created
by the SDK.

## Documentation

- Architecture and ownership: `doc/architecture.md`
- Provisioning and security: `doc/provisioning.md`
- Troubleshooting: `doc/troubleshooting.md`
- Changelog: `CHANGELOG.md`

## Compatibility

| SDK | Firmware contract | Provisioning | Platforms |
| --- | --- | --- | --- |
| 0.1.x | `v1/devices/{deviceId}` | BLE Security 1 | Android, iOS |

Matter, OTA, account management, desktop platforms, arbitrary topic access,
and arbitrary payload publishing are outside this release.
