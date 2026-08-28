# Motor controller firmware

ESP32-C3 motor node using BLE Security 1 provisioning and MQTT 5 over TLS.
`MotorService` remains the protocol-independent command/state boundary and the
local `MotorMqttAdapter` only translates JSON. Position-changing commands require
fresh pulse-derived position feedback.

## Motor position contract

The firmware uses `PULSE_ONLY` exclusively. Place the mechanism at the
fully-closed position before every boot; firmware sets that position to zero
and reports position from the commanded FastAccelStepper pulse count.
Open, close, ventilation, and percentage commands use bounded absolute targets
in `0..CONFIG_MOTOR_FULL_TRAVEL_STEPS`. This project deploys with
`CONFIG_MOTOR_FULL_TRAVEL_STEPS=19500`.

The contract cannot detect an incorrect boot position, missed motor steps,
manual movement, obstruction, or a mechanical end stop. Power loss during a
move does not provide automatic position recovery, so re-establish the closed
position before the next boot. The configured microstep value must match the
TB6600 DIP switches.

## Provisioning

Inject a unique Security 1 proof of possession (PoP) as
`CONFIG_DEVICE_PROV_POP` for every device build. Empty values fail compilation.
The serial log prints only a service name such as `PROV-MOTOR-A1B2`; deliver
the PoP through a device label or managed installer record.

To ship a factory MQTT profile, set the following values in the local
`sdkconfig` (which is ignored by Git), either through `idf.py menuconfig` under
**Device BLE provisioning** or by the per-device build pipeline:

```ini
CONFIG_DEVICE_MQTT_URI="mqtts://broker.example.com:8883"
CONFIG_DEVICE_MQTT_USERNAME="motor-device-account"
CONFIG_DEVICE_MQTT_PASSWORD="device-specific-secret"
```

Do not put credentials in the tracked `sdkconfig.defaults`. All three values
are required at build time. Use a unique device account whose broker ACL is
limited to that device's topics. BLE provisioning never receives or replaces
this factory profile.

With the IDF 6.0.2 environment active, provision only the Wi-Fi credentials.
The MQTT profile remains the one injected by the per-device build pipeline.

```powershell
python ".\managed_components\espressif__network_provisioning\tool\esp_prov\esp_prov.py" --transport ble --service_name PROV-MOTOR-A1B2 --sec_ver 1 --pop '<device-pop>' --ssid 'MY-WIFI' --passphrase 'wifi-secret'
```

Only `mqtts://` URIs with non-empty username and password are accepted. TLS
uses the ESP certificate bundle and hostname verification. MQTT starts after
Wi-Fi receives an IP. Hold the active-low GPIO9 BOOT button for five seconds
to request a safe stop, erase only Wi-Fi provisioning, and reboot.

## MQTT contract

The device/client ID is `motor-<12-hex-base-mac>`. All messages use QoS 1 and
JSON content type.

- `v1/devices/{deviceId}/presence`: retained online/offline status and retained LWT.
- `v1/devices/{deviceId}/state`: retained canonical motor state on revision changes and reconnect.
- `v1/devices/{deviceId}/command`: non-retained commands; retained commands are rejected.
- `v1/devices/{deviceId}/event`: non-retained command result and current revision.
- `v1/devices/{deviceId}/config`: reserved; not subscribed in this release.

```json
{"commandId":"cmd-42","action":"set_position","ttlMs":5000,"position100ths":2500}
```

Actions are `open`, `close`, `stop`, `ventilate`, and `set_position`.
`position100ths` is required only for `set_position` and ranges
from 0 to 10000.

```json
{"commandId":"cmd-42","result":"accepted","revision":12}
```

## Build

```powershell
. 'C:\Espressif\tools\Microsoft.v6.0.2.PowerShell_profile.ps1'
idf.py -B build build
```

## RGB status LED

The board-mounted single addressable RGB LED uses GPIO8 at a 32/255 brightness
cap. This motor image drives it through the `led_strip` SPI2 backend so the
FastAccelStepper RMT channels remain dedicated to motion.

- blue: opening
- purple: closing
- cyan: ventilating
- yellow blink: stopping
- red blink: fault
- blue breathe / cyan blink: provisioning / network connection
- magenta fast blink: provisioning reset accepted

At boot the LED briefly shows red, green, and blue for board/color-order
verification. GPIO8 is an ESP32-C3 strapping pin; do not share it with another
peripheral. SPI2 is reserved by the RGB LED in this image.
