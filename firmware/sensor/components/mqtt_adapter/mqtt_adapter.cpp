#include "mqtt_adapter.hpp"

#include <cmath>

#include "esp_log.h"
#include "json_generator.h"

namespace {

constexpr const char* kTag = "sensor_mqtt";
constexpr TickType_t kPublishPeriod = pdMS_TO_TICKS(5000);
constexpr int kSchemaVersion = 1;

bool addFiniteNumber(json_gen_str_t* generator,
                     const char* name,
                     bool valid,
                     float value)
{
    if (valid && std::isfinite(value)) {
        return json_gen_obj_set_float(generator, name, value) == 0;
    }
    return json_gen_obj_set_null(generator, name) == 0;
}

}  // namespace

SensorMqttAdapter::~SensorMqttAdapter()
{
    stop();
}

bool SensorMqttAdapter::begin(MqttBridge& bridge)
{
    if (task_ != nullptr) return true;
    bridge_ = &bridge;
    queue_ = xQueueCreate(1, sizeof(SensorSnapshot));
    if (queue_ == nullptr) return false;
    stop_requested_ = false;
    if (xTaskCreate(&SensorMqttAdapter::taskEntry, "sensor_mqtt", 5120,
                    this, 4, &task_) != pdPASS) {
        vQueueDelete(queue_);
        queue_ = nullptr;
        return false;
    }
    return true;
}

bool SensorMqttAdapter::enqueue(const SensorSnapshot& snapshot)
{
    return queue_ != nullptr && xQueueOverwrite(queue_, &snapshot) == pdTRUE;
}

void SensorMqttAdapter::stop()
{
    if (task_ == nullptr) return;
    stop_requested_ = true;
    xTaskNotifyGive(task_);
    while (task_ != nullptr) vTaskDelay(1);
    if (queue_ != nullptr) {
        vQueueDelete(queue_);
        queue_ = nullptr;
    }
}

void SensorMqttAdapter::taskEntry(void* context)
{
    static_cast<SensorMqttAdapter*>(context)->taskLoop();
}

void SensorMqttAdapter::taskLoop()
{
    SensorSnapshot latest;
    bool has_latest = false;
    TickType_t last_publish = 0;
    while (!stop_requested_) {
        SensorSnapshot received;
        if (xQueueReceive(queue_, &received, pdMS_TO_TICKS(250)) == pdTRUE) {
            latest = received;
            has_latest = true;
        }
        const TickType_t now = xTaskGetTickCount();
        if (has_latest && bridge_ != nullptr && bridge_->connected() &&
            (last_publish == 0 || now - last_publish >= kPublishPeriod)) {
            publish(latest);
            last_publish = now;
        }
    }
    task_ = nullptr;
    vTaskDelete(nullptr);
}

void SensorMqttAdapter::publish(const SensorSnapshot& snapshot)
{
    char json[1536] = {};
    json_gen_str_t generator;
    json_gen_str_start(&generator, json, sizeof(json), nullptr, nullptr);
    bool ok = json_gen_start_object(&generator) == 0;
    ok = ok && json_gen_obj_set_int(&generator, "schemaVersion", kSchemaVersion) == 0;
    ok = ok && json_gen_obj_set_int64(&generator, "timestampUs",
                                       static_cast<int64_t>(snapshot.timestamp_us)) == 0;
    ok = ok && json_gen_obj_set_int64(&generator, "revision",
                                       static_cast<int64_t>(snapshot.revision)) == 0;
    ok = ok && json_gen_obj_set_int64(&generator, "errorFlags", snapshot.error_flags) == 0;
    ok = ok && json_gen_obj_set_bool(&generator, "pmValid", snapshot.pm_valid) == 0;
    ok = ok && json_gen_obj_set_bool(&generator, "bmeValid", snapshot.bme_valid) == 0;

    ok = ok && json_gen_push_object(&generator, "normalized") == 0;
    ok = ok && json_gen_obj_set_bool(&generator, "temperatureValid",
                                      snapshot.normalized.temperature_valid) == 0;
    ok = ok && addFiniteNumber(&generator, "temperatureC",
                               snapshot.normalized.temperature_valid,
                               snapshot.normalized.temperature_c);
    ok = ok && json_gen_obj_set_bool(&generator, "humidityValid",
                                      snapshot.normalized.humidity_valid) == 0;
    ok = ok && addFiniteNumber(&generator, "humidityPercent",
                               snapshot.normalized.humidity_valid,
                               snapshot.normalized.humidity_percent);
    ok = ok && json_gen_obj_set_bool(&generator, "pressureValid",
                                      snapshot.normalized.pressure_valid) == 0;
    ok = ok && addFiniteNumber(&generator, "pressureHpa",
                               snapshot.normalized.pressure_valid,
                               snapshot.normalized.pressure_hpa);
    ok = ok && json_gen_pop_object(&generator) == 0;

    ok = ok && json_gen_push_object(&generator, "raw") == 0;
#define ADD_RAW(name, value) \
    ok = ok && json_gen_obj_set_int64(&generator, name, static_cast<int64_t>(value)) == 0
    ADD_RAW("pmStatus", snapshot.raw.pm_status);
    ADD_RAW("pmMeasurementMode", snapshot.raw.pm_measurement_mode);
    ADD_RAW("pmCalibration", snapshot.raw.pm_calibration);
    ADD_RAW("grimmPm1_0", snapshot.raw.grimm_pm1_0);
    ADD_RAW("grimmPm2_5", snapshot.raw.grimm_pm2_5);
    ADD_RAW("grimmPm10", snapshot.raw.grimm_pm10);
    ADD_RAW("tsiPm1_0", snapshot.raw.tsi_pm1_0);
    ADD_RAW("tsiPm2_5", snapshot.raw.tsi_pm2_5);
    ADD_RAW("tsiPm10", snapshot.raw.tsi_pm10);
    ADD_RAW("particles0_3", snapshot.raw.particles_0_3);
    ADD_RAW("particles0_5", snapshot.raw.particles_0_5);
    ADD_RAW("particles1_0", snapshot.raw.particles_1_0);
    ADD_RAW("particles2_5", snapshot.raw.particles_2_5);
    ADD_RAW("particles5_0", snapshot.raw.particles_5_0);
    ADD_RAW("particles10_0", snapshot.raw.particles_10_0);
    ADD_RAW("bmeStatus", snapshot.raw.bme_status);
#undef ADD_RAW
    ok = ok && json_gen_pop_object(&generator) == 0;
    ok = ok && json_gen_end_object(&generator) == 0;
    const int bytes = json_gen_str_end(&generator);
    if (!ok || bytes <= 0 || bytes > static_cast<int>(sizeof(json))) {
        ESP_LOGE(kTag, "telemetry JSON exceeded fixed buffer");
        return;
    }
    if (!bridge_->publish(MqttTopicSuffix::Telemetry,
                          std::string_view(json, static_cast<std::size_t>(bytes - 1)), false)) {
        ESP_LOGW(kTag, "telemetry publish failed");
    }
}
