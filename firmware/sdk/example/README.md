# ESW Device SDK example

This Android/iOS app demonstrates the complete high-level SDK consumer flow. Its Dart
source imports only `package:esw_device_sdk/esw_device_sdk.dart`; transport,
wire protocol, BLE matching, and readiness logic remain inside the SDK.

## Prepare

1. Flash both devices with the Security 1 firmware and a unique non-default
   proof of possession.
2. Prepare a control-service application account with access to the intended
   devices.
3. Prepare printed provisioning QR labels or the PoP for manual fallback.
4. Do not place account secrets in source or committed `--dart-define` values.

The example persists one JSON connection record containing
`EswConnectionConfig` fields with platform secure storage and deletes only that
record. Device MQTT credentials are factory-injected and never pass through the
app.

## Run

```shell
flutter pub get
flutter run
```

Android requires API 23 or later with Nearby Devices and Camera permissions.
iOS requires iOS 13 or later with Bluetooth and Camera usage descriptions.
The educational project declares `flutter_blue_plus`'s nonprofit license
inside the SDK transport; commercial reuse requires the appropriate license.

The public broker hostname and port may be prefilled without embedding account
credentials:

```powershell
flutter run --dart-define=MQTT_HOST=mqtt.example.com --dart-define=MQTT_PORT=8883
```

## Demonstration flow

1. Enter and save the control-service connection. The Riverpod adapter observes
   the SDK's seeded `states` stream.
2. Scan a printed QR. The app passes `ProvisioningQrPayload` to
   `startDeviceSetup`; the SDK finds the matching BLE device.
3. Choose a network returned by `DeviceSetup.scanWifi` and enter its password.
4. Follow `DeviceSetupStep` while `complete` applies Wi-Fi and waits for data.
5. The completed typed snapshot appears on the home screen.
6. Motor cards use `sdk.motor(id)`; sensor cards read the latest value directly
   from `AirQualityDeviceSnapshot`.

Manual fallback uses `discoverSetupDevices` and `startManualDeviceSetup`.
Registration succeeds only after Wi-Fi and a fresh motor state or sensor
reading. BLE completion or online presence alone is not final acceptance.
