# Sensor firmware

ESP32-C3 air-quality node using BLE Security 1 provisioning and MQTT 5 over
TLS. The existing layering is preserved:

```text
app_main -> SensorMqttAdapter -> MqttBridge
         -> SensorService -> PM2008M + BME280 HAL
```

`SensorService` owns one 100 kHz I2C bus on GPIO0 (SDA) and GPIO1 (SCL). Its
sampling callback performs no network operation; it only overwrites a one-item
queue. A separate adapter task publishes the latest snapshot every five
seconds.

## Provisioning

Inject a unique Security 1 proof of possession (PoP) as
`CONFIG_DEVICE_PROV_POP` for every device build. Empty values fail compilation.
The serial log prints only a service name such as `PROV-SENSOR-A1B2`; deliver
the PoP through a device label or managed installer record.

To ship a factory MQTT profile, set the following values in the local
`sdkconfig` (which is ignored by Git), either through `idf.py menuconfig` under
**Device BLE provisioning** or by the per-device build pipeline:

```ini
CONFIG_DEVICE_MQTT_URI="mqtts://broker.example.com:8883"
CONFIG_DEVICE_MQTT_USERNAME="sensor-device-account"
CONFIG_DEVICE_MQTT_PASSWORD="device-specific-secret"
```

Do not put credentials in the tracked `sdkconfig.defaults`. All three values
are required at build time. Use a unique device account whose broker ACL is
limited to that device's topics. BLE provisioning never receives or replaces
this factory profile.

```powershell
python ".\managed_components\espressif__network_provisioning\tool\esp_prov\esp_prov.py" --transport ble --service_name PROV-SENSOR-A1B2 --sec_ver 1 --pop '<device-pop>' --ssid 'MY-WIFI' --passphrase 'wifi-secret'
```

MQTT starts after Wi-Fi receives an IP and uses only the factory profile. Hold
active-low GPIO9 BOOT for five seconds to erase Wi-Fi provisioning and reboot;
the factory MQTT profile is unchanged.

## MQTT contract

The device/client ID is `sensor-<12-hex-base-mac>`. `presence` is retained with
an offline LWT. Telemetry is QoS 1, non-retained, and includes raw and
normalized values plus validity/error flags:

```text
v1/devices/{deviceId}/presence
v1/devices/{deviceId}/telemetry
v1/devices/{deviceId}/config       # reserved, not subscribed
```

Example telemetry shape:

```json
{"timestampUs":42000000,"revision":17,"errorFlags":0,"normalized":{"temperatureValid":true,"temperatureC":23.45,"humidityValid":true,"humidityPercent":48.12,"pressureValid":true,"pressureHpa":1013.25},"raw":{"pmStatus":0,"pmMeasurementMode":1,"pmCalibration":0,"grimmPm1_0":8,"grimmPm2_5":13,"grimmPm10":21,"tsiPm1_0":7,"tsiPm2_5":12,"tsiPm10":20,"particles0_3":100,"particles0_5":80,"particles1_0":40,"particles2_5":15,"particles5_0":4,"particles10_0":1,"bmeStatus":0}}
```

## Build

```powershell
. 'C:\Espressif\tools\Microsoft.v6.0.2.PowerShell_profile.ps1'
idf.py -B build build
```

## RGB status LED

The board-mounted single addressable RGB LED is driven on GPIO8 through the
`led_strip` RMT backend with a 32/255 brightness cap. In normal operation it
shows the GRIMM PM2.5 reading using the AirKorea bands: green 0-15, yellow
16-35, orange 36-75, and red 76 or higher (micrograms per cubic meter).

Sensor errors override air quality with a red blink. Blue breathing means BLE
provisioning, cyan blinking means Wi-Fi/MQTT is not connected, and a one-second
green indication confirms connection. A magenta fast blink confirms that the
five-second provisioning reset was accepted.

At boot the LED briefly shows red, green, and blue for board/color-order
verification. GPIO8 is an ESP32-C3 strapping pin and must not be shared with
another peripheral. AirKorea band reference:
https://airkorea.or.kr/web/irsttRealSearch
