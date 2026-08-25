# Motor controller firmware

ESP32-C3 motor node using BLE Security 1 provisioning and MQTT 5 over TLS.
`MotorService` remains the protocol-independent command/state boundary and the
local `MotorMqttAdapter` only translates JSON. Position-changing commands require
the position and safety state supplied by the selected feedback mode.

## Motor position modes

Configure the position mode with `idf.py menuconfig` under **Motor node
hardware**. The current default is `PULSE_ONLY`, intended only to operate the
prototype before limit switches are installed.

### PULSE_ONLY development mode

Place the mechanism at the fully-closed position before every boot. Firmware
sets the boot pulse position to zero and reports position from the commanded
step count. Open, close, ventilation, and percentage commands use bounded
absolute targets in `0..CONFIG_MOTOR_FULL_TRAVEL_STEPS`; they never start an
unbounded continuous run. The `calibrate` action is rejected because there is
no physical home sensor to stop it.

This mode cannot detect an incorrect boot position, missed motor steps, manual
movement, obstruction, or a mechanical end stop. A reset or loss of motor power
invalidates the physical meaning of the calculated position. Use low speed,
keep an operator at the emergency power disconnect, and do not ship this mode.

### LIMIT_HOME product mode

Select `LIMIT_HOME` after installing the switches and protection loop. This
mode samples physical inputs, homes toward the closed limit after boot, and
derives the 0–100% position from the homed FastAccelStepper pulse position.

Default product-mode wiring:

- GPIO0: TB6600 STEP/PUL output through the existing interface.
- GPIO1: TB6600 DIR output through the existing interface.
- GPIO4: normally-open fully-open limit switch to GND.
- GPIO5: normally-open fully-closed limit switch to GND.
- GPIO6: normally-closed protection loop to GND.
- GPIO8: onboard RGB LED; never share it with a feedback input.
- GPIO9: active-low provisioning-reset button; never share it.

GPIO4/5 use internal pull-ups and are active-low. GPIO6 also uses a pull-up but
is active-high, so an open protection wire is treated as a fault. The motor
does not home or accept position-changing commands until the protection loop
is closed and all three inputs have passed debounce.

The configured prototype uses `CONFIG_MOTOR_FULL_TRAVEL_STEPS=36000`, calculated
from 900 mm at 40 pulses/mm. Verify that pulse density and travel on the actual
mechanism before relying on percentage control. The configured microstep value
must also match the TB6600 DIP switches. Boot homing has a 30-second default timeout; a
timeout, contradictory limits, or an open protection loop immediately stops
pulses and keeps movement blocked.

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

Actions are `open`, `close`, `stop`, `ventilate`, `set_position`, and
`calibrate`. `position100ths` is required only for `set_position` and ranges
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
- yellow blink: stopping or calibrating
- red blink: fault or protection state
- blue breathe / cyan blink: provisioning / network connection
- magenta fast blink: provisioning reset accepted

At boot the LED briefly shows red, green, and blue for board/color-order
verification. GPIO8 is an ESP32-C3 strapping pin; do not share it with another
peripheral. SPI2 is reserved by the RGB LED in this image.
