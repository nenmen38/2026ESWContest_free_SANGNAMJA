# Troubleshooting

## No nearby devices

- Confirm the firmware log reports `PROV-MOTOR-*` or `PROV-SENSOR-*`.
- Grant Nearby Devices/Bluetooth permission. Android 11 and older may also
  require location permission and location services.
- A previously provisioned device does not advertise. Hold GPIO9 BOOT for five
  seconds to clear registration data.

## Proof of possession is rejected

The phone value must exactly match `CONFIG_DEVICE_PROV_POP` from the flashed
image. Security 2 username/password values from older images are incompatible;
flash the Security 1 firmware before using this SDK.

## Server configuration is rejected

The firmware requires a secure server URI, a non-empty device account, and a
non-empty secret. The server certificate hostname must match the configured
host and chain to a trusted public root.

## Device registers but is not discovered

- Confirm the host application's control account can read the intended device
  presence and data channels.
- Confirm the device account can write its presence/state/telemetry and read
  its own command channel.
- Check that the device ID starts with `motor-` or `sensor-`.
- Watch `states` and `errors`; do not add raw transport logging to
  application code.

## Motor command is rejected

- `safetyUnavailable`: limit or protection feedback has not been established.
- `positionUnknown`: valid position feedback is absent.
- `hardwareRejected`: the motion driver rejected the target.
- `timeout`: the SDK did not receive a matching event in five seconds. Do not
  blindly retry motion; read the latest motor state first.

## Sensor value is null

The device explicitly marked that normalized measurement invalid. Inspect
`hasSensorError`, `errorFlags`, and `raw` for diagnostics instead of replacing
the value with zero.
