#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "ble_provisioning.hpp"
#include "motor.hpp"
#include "mqtt_adapter.hpp"
#include "mqtt_bridge.hpp"
#include "motor_feedback.hpp"
#include "service.hpp"
#include "status_led.hpp"
#include "sdkconfig.h"

namespace {

constexpr const char* kTag = "motor_app";

MotorConfig makeMotorConfig()
{
    MotorConfig config;
    config.step_gpio = CONFIG_MOTOR_STEP_GPIO;
    config.dir_gpio = CONFIG_MOTOR_DIR_GPIO;
    config.full_steps_per_rev = CONFIG_MOTOR_FULL_STEPS_PER_REV;
    config.microstep = CONFIG_MOTOR_MICROSTEP;
    config.default_rpm = static_cast<float>(CONFIG_MOTOR_DEFAULT_RPM);
    config.max_rpm = static_cast<float>(CONFIG_MOTOR_MAX_RPM);
    config.acceleration = CONFIG_MOTOR_ACCELERATION;
#ifdef CONFIG_MOTOR_DIRECTION_INVERTED
    config.direction_inverted = true;
#endif
    return config;
}

MotorServiceConfig makeServiceConfig()
{
    MotorServiceConfig config;
    config.min_steps = 0;
    config.max_steps = CONFIG_MOTOR_FULL_TRAVEL_STEPS;
    config.ventilation_position100ths = CONFIG_MOTOR_VENTILATION_POSITION_100THS;
    config.safety_stale_after_ms = CONFIG_MOTOR_SAFETY_STALE_MS;
#ifdef CONFIG_MOTOR_FEEDBACK_MODE_LIMIT_HOME
    config.homing_supported = true;
#else
    config.homing_supported = false;
#endif
    return config;
}

MotorFeedbackInputConfig makeFeedbackConfig()
{
    MotorFeedbackInputConfig config;
#ifdef CONFIG_MOTOR_FEEDBACK_MODE_LIMIT_HOME
    config.mode = MotorFeedbackMode::LimitHome;
    config.open_limit_gpio = CONFIG_MOTOR_OPEN_LIMIT_GPIO;
    config.close_limit_gpio = CONFIG_MOTOR_CLOSE_LIMIT_GPIO;
    config.protection_gpio = CONFIG_MOTOR_PROTECTION_GPIO;
#else
    config.mode = MotorFeedbackMode::PulseOnly;
#endif
    config.step_gpio = CONFIG_MOTOR_STEP_GPIO;
    config.dir_gpio = CONFIG_MOTOR_DIR_GPIO;
    config.status_led_gpio = 8;
    config.reset_gpio = CONFIG_DEVICE_PROV_RESET_GPIO;
    config.min_steps = 0;
    config.max_steps = CONFIG_MOTOR_FULL_TRAVEL_STEPS;
    config.sample_period_ms = CONFIG_MOTOR_FEEDBACK_PERIOD_MS;
#ifdef CONFIG_MOTOR_FEEDBACK_MODE_LIMIT_HOME
    config.debounce_ms = CONFIG_MOTOR_FEEDBACK_DEBOUNCE_MS;
#ifdef CONFIG_MOTOR_AUTO_HOME
    config.homing_timeout_ms = CONFIG_MOTOR_HOMING_TIMEOUT_MS;
    config.auto_home = true;
#else
    config.auto_home = false;
#endif
#ifdef CONFIG_MOTOR_LIMIT_ACTIVE_LOW
    config.limit_active_low = true;
#else
    config.limit_active_low = false;
#endif
#ifdef CONFIG_MOTOR_PROTECTION_ACTIVE_HIGH
    config.protection_active_high = true;
#else
    config.protection_active_high = false;
#endif
#ifdef CONFIG_MOTOR_FEEDBACK_USE_PULLUP
    config.use_pullup = true;
#else
    config.use_pullup = false;
#endif
#else
    config.auto_home = false;
#endif
    return config;
}

struct ResetContext {
    MotorService* service = nullptr;
    StatusLed* led = nullptr;
};

bool stopForProvisioningReset(void* context)
{
    auto* reset = static_cast<ResetContext*>(context);
    if (reset == nullptr || reset->service == nullptr) return false;
    if (reset->led != nullptr) {
        reset->led->set(StatusLedLayer::Resetting, StatusLedSignal::MagentaFast);
    }
    device_common::MotorCommand command;
    command.action = device_common::MotorCommandAction::Stop;
    const bool stopped = reset->service->submit(command, 0, false) ==
                         MotorCommandResult::Accepted;
    if (!stopped && reset->led != nullptr) {
        reset->led->set(StatusLedLayer::Fault, StatusLedSignal::RedBlink);
    }
    return stopped;
}

void showProvisioningResetFailure(void* context)
{
    auto* reset = static_cast<ResetContext*>(context);
    if (reset != nullptr && reset->led != nullptr) {
        reset->led->set(StatusLedLayer::Fault, StatusLedSignal::RedBlink);
    }
}

void updateMotorLed(StatusLed& led, const device_common::MotorCanonicalState& state)
{
    if (state.errors != 0 || state.main_state == device_common::MotorMainState::Fault ||
        state.main_state == device_common::MotorMainState::Protected) {
        led.set(StatusLedLayer::Fault, StatusLedSignal::RedBlink);
        led.clear(StatusLedLayer::Device);
        return;
    }
    led.clear(StatusLedLayer::Fault);
    switch (state.main_state) {
    case device_common::MotorMainState::Idle:
        led.clear(StatusLedLayer::Device);
        break;
    case device_common::MotorMainState::Opening:
        led.set(StatusLedLayer::Device, StatusLedSignal::BlueSolid);
        break;
    case device_common::MotorMainState::Closing:
        led.set(StatusLedLayer::Device, StatusLedSignal::PurpleSolid);
        break;
    case device_common::MotorMainState::Ventilating:
        led.set(StatusLedLayer::Device, StatusLedSignal::CyanSolid);
        break;
    case device_common::MotorMainState::Calibrating:
    case device_common::MotorMainState::Stopping:
        led.set(StatusLedLayer::Device, StatusLedSignal::YellowBlink);
        break;
    case device_common::MotorMainState::Unknown:
        led.set(StatusLedLayer::Device, StatusLedSignal::AmberBreathe);
        break;
    case device_common::MotorMainState::Fault:
    case device_common::MotorMainState::Protected:
        break;
    }
}

}  // namespace

extern "C" void app_main(void)
{
    static const MotorConfig motor_config = makeMotorConfig();
    static const MotorServiceConfig service_config = makeServiceConfig();
    static MotorController motor(motor_config);
    static MotorControllerActuator actuator(motor);
    static MotorService service(actuator, service_config);
    static const MotorFeedbackInputConfig feedback_config = makeFeedbackConfig();
    static MotorFeedbackInput feedback(motor, service, feedback_config);
    static BleProvisioningRuntime provisioning;
    static MqttBridge mqtt;
    static MotorMqttAdapter adapter(service);
    static StatusLed led;
    static ResetContext reset_context{&service, &led};

    StatusLedConfig led_config;
    led_config.backend = StatusLedBackend::Spi;
    if (!led.begin(led_config)) {
        ESP_LOGW(kTag, "RGB status LED initialization failed; continuing without LED");
    }

    if (!service.begin()) {
        led.set(StatusLedLayer::Fault, StatusLedSignal::RedBlink);
        ESP_LOGE(kTag, "motor service initialization failed");
        return;
    }

    if (!feedback.begin()) {
        led.set(StatusLedLayer::Fault, StatusLedSignal::RedBlink);
        ESP_LOGE(kTag, "motor feedback initialization failed");
        return;
    }

    BleProvisioningRuntimeConfig provisioning_config;
    provisioning_config.role = "motor";
    provisioning_config.reset_callback = &stopForProvisioningReset;
    provisioning_config.reset_failure_callback = &showProvisioningResetFailure;
    provisioning_config.reset_context = &reset_context;
    if (!provisioning.begin(provisioning_config)) {
        led.set(StatusLedLayer::Fault, StatusLedSignal::RedBlink);
        ESP_LOGE(kTag, "BLE provisioning initialization failed");
        return;
    }

    bool mqtt_started = false;
    uint64_t last_report_ms = 0;
    while (true) {
        if (!mqtt_started && provisioning.networkReady()) {
            BrokerConnectionProfile profile;
            if (provisioning.getBrokerProfile(&profile)) {
                mqtt_started = adapter.begin(mqtt, profile, provisioning.deviceId());
                if (!mqtt_started) ESP_LOGE(kTag, "MQTT 5 start failed; retrying");
            }
        }
        const auto state = service.snapshot();
        updateMotorLed(led, state);
        const uint64_t now_ms = static_cast<uint64_t>(esp_timer_get_time()) / 1000ULL;
        led.updateConnectivity(provisioning.networkReady(), mqtt.connected(),
                               provisioning.provisioningActive(), now_ms);
        if (now_ms - last_report_ms >= 2000) {
            adapter.report(state);
            last_report_ms = now_ms;
        }
        vTaskDelay(pdMS_TO_TICKS(250));
    }
}
