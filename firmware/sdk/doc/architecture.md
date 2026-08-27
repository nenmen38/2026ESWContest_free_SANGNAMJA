# Architecture and ownership

## Public data flow

```text
Flutter application
  -> EswDeviceSdk
     -> currentState + states
        -> MotorDeviceSnapshot / AirQualityDeviceSnapshot
     -> MotorController
     -> DeviceSetup
```

`EswDeviceSdk` owns one control transport, one device registry, pending motor
commands, and the BLE setup adapter. It combines connection, presence, motor
state, and sensor telemetry into immutable `EswSdkState` values. A subscriber
does not need to merge streams or wait for an initial event because `states`
starts with `currentState`.

The registry retains the latest domain data when a transport disconnects while
marking every known device offline. Motor commands remain separate from the
snapshot model so immutable UI state cannot accidentally represent a live
transport handle.

## Setup flow

`DeviceSetup` retains the selected BLE candidate and proof of possession, but
does not keep a BLE connection open between UI steps. Wi-Fi scanning and final
provisioning each use a short-lived Security 1 session. After Wi-Fi succeeds,
the SDK matches the provisioning service kind and suffix to the MQTT device ID
and waits for fresh domain data.

One SDK instance permits one discovery, Wi-Fi scan, or completion operation at
a time. A failed setup remains retryable. A successful setup is consumed, and
all setup sessions become invalid when their SDK is disposed.

## Internal compatibility boundary

Wire details stay in `lib/src` and are never exported:

```text
v1/devices/{deviceId}/presence
v1/devices/{deviceId}/state
v1/devices/{deviceId}/event
v1/devices/{deviceId}/telemetry
v1/devices/{deviceId}/command
```

Firmware retains presence and motor state. Commands, command events, and sensor
telemetry are non-retained. The SDK validates schema versions, required fields,
ranges, command correlation, and identifiers before updating public state.

## SDK and application responsibilities

The SDK owns:

- protocol parsing, topic selection, command IDs, and delivery policy;
- atomic connection and typed device state;
- BLE device matching and guided provisioning;
- domain readiness and timeout decisions.

The host application owns:

- account creation and secure credential persistence;
- Riverpod, Bloc, or other UI state-management integration;
- QR camera UI, navigation, selections, localization, and user messages;
- requesting user confirmation before commands where product UX requires it.

The example imports only `package:esw_device_sdk/esw_device_sdk.dart`. Any new
public API requires Dartdoc, a domain-level unit test, and an example path that
does not expose wire or BLE implementation types.
