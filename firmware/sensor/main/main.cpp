#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "ble_provisioning.hpp"
#include "mqtt_adapter.hpp"
#include "mqtt_bridge.hpp"
#include "service.hpp"
#include "status_led.hpp"

namespace {

constexpr const char* kTag = "sensor_app";

constexpr uint16_t kPm25GoodMax = 15;
constexpr uint16_t kPm25ModerateMax = 35;
constexpr uint16_t kPm25BadMax = 75;

struct ResetContext {
    SensorService* service = nullptr;
    StatusLed* led = nullptr;
};

void sampleCallback(const SensorSnapshot& snapshot, void* context)
{
    auto* adapter = static_cast<SensorMqttAdapter*>(context);
    if (adapter != nullptr) {
        (void)adapter->enqueue(snapshot);
    }
}

bool stopForProvisioningReset(void* context)
{
    auto* reset = static_cast<ResetContext*>(context);
    if (reset == nullptr) return false;
    if (reset->led != nullptr) {
        reset->led->set(StatusLedLayer::Resetting, StatusLedSignal::MagentaFast);
    }
    if (reset->service != nullptr) reset->service->stop();
    return true;
}

void showProvisioningResetFailure(void* context)
{
    auto* reset = static_cast<ResetContext*>(context);
    if (reset != nullptr && reset->led != nullptr) {
        reset->led->set(StatusLedLayer::Fault, StatusLedSignal::RedBlink);
    }
}

void updateSensorLed(StatusLed& led, const SensorSnapshot& snapshot)
{
    if (snapshot.error_flags != 0) {
        led.set(StatusLedLayer::Fault, StatusLedSignal::RedBlink);
        led.clear(StatusLedLayer::Device);
        return;
    }
    led.clear(StatusLedLayer::Fault);
    const uint16_t pm25 = snapshot.raw.grimm_pm2_5;
    if (pm25 <= kPm25GoodMax) {
        led.set(StatusLedLayer::Device, StatusLedSignal::GreenSolid);
    } else if (pm25 <= kPm25ModerateMax) {
        led.set(StatusLedLayer::Device, StatusLedSignal::AmberSolid);
    } else if (pm25 <= kPm25BadMax) {
        led.set(StatusLedLayer::Device, StatusLedSignal::OrangeSolid);
    } else {
        led.set(StatusLedLayer::Device, StatusLedSignal::RedSolid);
    }
}

}  // namespace

extern "C" void app_main(void)
{
    SensorServiceConfig sensor_config;
    sensor_config.i2c_port = 0;
    sensor_config.sda_io = 0;
    sensor_config.scl_io = 1;
    sensor_config.pm_timeout_ms = 1000;
    sensor_config.sample_period_ms = 2000;
    sensor_config.enable_internal_pullups = false;

    static SensorService service(sensor_config);
    static BleProvisioningRuntime provisioning;
    static MqttBridge mqtt;
    static SensorMqttAdapter adapter;
    static StatusLed led;
    static ResetContext reset_context{&service, &led};

    StatusLedConfig led_config;
    led_config.backend = StatusLedBackend::Rmt;
    if (!led.begin(led_config)) {
        ESP_LOGW(kTag, "RGB status LED initialization failed; continuing without LED");
    }

    if (!service.begin()) {
        led.set(StatusLedLayer::Fault, StatusLedSignal::RedBlink);
        ESP_LOGE(kTag, "sensor service initialization failed");
        return;
    }

    BleProvisioningRuntimeConfig provisioning_config;
    provisioning_config.role = "sensor";
    provisioning_config.reset_callback = &stopForProvisioningReset;
    provisioning_config.reset_failure_callback = &showProvisioningResetFailure;
    provisioning_config.reset_context = &reset_context;
    if (!provisioning.begin(provisioning_config) || !adapter.begin(mqtt)) {
        led.set(StatusLedLayer::Fault, StatusLedSignal::RedBlink);
        ESP_LOGE(kTag, "BLE provisioning/MQTT adapter initialization failed");
        return;
    }
    if (!service.start(&sampleCallback, &adapter)) {
        led.set(StatusLedLayer::Fault, StatusLedSignal::RedBlink);
        ESP_LOGE(kTag, "sensor sampling task start failed");
        return;
    }

    bool mqtt_started = false;
    while (true) {
        if (!mqtt_started && provisioning.networkReady()) {
            BrokerConnectionProfile profile;
            if (provisioning.getBrokerProfile(&profile)) {
                MqttBridgeConfig mqtt_config;
                mqtt_config.device_id = provisioning.deviceId();
                mqtt_config.profile = profile;
                mqtt_started = mqtt.begin(mqtt_config);
                if (!mqtt_started) ESP_LOGE(kTag, "MQTT 5 start failed; retrying");
            }
        }
        SensorSnapshot snapshot;
        if (service.getLatest(&snapshot)) {
            updateSensorLed(led, snapshot);
        }
        const uint64_t now_ms = static_cast<uint64_t>(esp_timer_get_time()) / 1000ULL;
        led.updateConnectivity(provisioning.networkReady(), mqtt.connected(),
                               provisioning.provisioningActive(), now_ms);
        vTaskDelay(pdMS_TO_TICKS(250));
    }
}
