# Provisioning and Security 1

## Firmware configuration

Production builds inject a unique `CONFIG_DEVICE_PROV_POP` for every device.
There is no default PoP; an empty build value fails compilation. Deliver the
same value through a device label or managed installer record. Firmware never
prints it or creates a QR code.

The host-side `tools/generate_provisioning_qr.py` utility creates a label with
the provisioning v1 name, PoP, and BLE transport. `ProvisioningQrPayload.parse`
validates it. `startDeviceSetup` scans for the exact advertised name and retains
the PoP inside a guided session. `discoverSetupDevices` and
`startManualDeviceSetup` provide the manual fallback.

## Package-owned flow

1. Firmware starts `espressif/network_provisioning` with Security 1. Its MQTT
   profile was injected by the per-device build pipeline.
2. The SDK connects through its BLE adapter and checks `proto-ver` for the ESW
   v2 Wi-Fi-only contract, Security 1, and Wi-Fi scan capability.
3. The SDK establishes Security 1 and optionally scans Wi-Fi from the device.
4. `DeviceSetup.complete` sends and applies Wi-Fi credentials and reports the
   connection result and optional IP address.
5. The BLE session is disposed once on every terminal path.
6. The SDK waits for the matching MQTT device to publish a new motor state or
   sensor reading. Presence alone does not complete setup.

Firmware accepts only a complete factory profile with an `mqtts://` URI and
non-empty per-device username and password. Runtime provisioning has no
endpoint capable of replacing it.

## Public state machine

`DeviceSetup.complete` reports these steps in order:

```text
connecting -> checkingProtocol -> securing -> applyingWifi
  -> waitingForWifi -> waitingForDevice -> completed
```

BLE or Wi-Fi failures throw `ProvisioningException` with a stable
`ProvisioningFailureCode`. Failure to observe fresh domain data within the
default 20 seconds throws `DeviceAvailabilityTimeoutException`. The SDK must be
connected to the control service before completion so readiness can be checked.

Only one discovery, device Wi-Fi scan, or completion operation may run on an
SDK instance. Concurrent attempts throw `StateError`. A failed setup may be
retried; a completed setup and any setup owned by a disposed SDK are unusable.

## Reset and retry

Hold the active-low GPIO9 BOOT button for five seconds. Firmware invokes the
application stop callback, clears only Wi-Fi provisioning, and restarts. The
factory MQTT profile, sensor calibration, and unrelated application data remain
intact.

After a PoP, Wi-Fi, or readiness failure, repeat `scanWifi` or `complete` on the
same setup as appropriate. Wi-Fi failures reset manager state so new
credentials can be accepted without rebooting.
