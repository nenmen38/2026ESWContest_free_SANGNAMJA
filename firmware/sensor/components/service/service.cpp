#include "service.hpp"

#include <cmath>
#include <limits>

#include "esp_log.h"
#include "esp_timer.h"
#include "i2c_bus.h"

namespace {

constexpr const char* kTag = "service";
constexpr uint32_t kI2cClockHz = 100000;
constexpr uint32_t kTaskStackSize = 4096;
constexpr UBaseType_t kTaskPriority = 5;

bool validPeriod(uint32_t period_ms)
{
    if (period_ms == 0 || period_ms > std::numeric_limits<TickType_t>::max()) {
        return false;
    }
    return pdMS_TO_TICKS(period_ms) > 0;
}

bool validTemperature(float value)
{
    return std::isfinite(value) && value >= -40.0f && value <= 85.0f;
}

bool validHumidity(float value)
{
    return std::isfinite(value) && value >= 0.0f && value <= 100.0f;
}

bool validPressure(float value)
{
    return std::isfinite(value) && value > 0.0f && value <= 1200.0f;
}

}  // namespace

SensorService::SensorService(const SensorServiceConfig& config)
    : config_(config)
{
}

SensorService::~SensorService()
{
    stop();
    releaseHardware();
    if (snapshot_mutex_ != nullptr) {
        vSemaphoreDelete(snapshot_mutex_);
        snapshot_mutex_ = nullptr;
    }
}

bool SensorService::begin()
{
    if (initialized_) {
        return true;
    }
    if (config_.sda_io == config_.scl_io || config_.pm_timeout_ms == 0 ||
        !validPeriod(config_.sample_period_ms)) {
        ESP_LOGE(kTag, "invalid sensor service configuration");
        return false;
    }

    snapshot_mutex_ = xSemaphoreCreateMutex();
    if (snapshot_mutex_ == nullptr) {
        ESP_LOGE(kTag, "failed to create snapshot mutex");
        return false;
    }

    i2c_config_t bus_config = {};
    bus_config.mode = I2C_MODE_MASTER;
    bus_config.sda_io_num = config_.sda_io;
    bus_config.scl_io_num = config_.scl_io;
    bus_config.sda_pullup_en = config_.enable_internal_pullups;
    bus_config.scl_pullup_en = config_.enable_internal_pullups;
    bus_config.master.clk_speed = kI2cClockHz;

    i2c_bus_handle_t bus = i2c_bus_create(static_cast<i2c_port_t>(config_.i2c_port), &bus_config);
    if (bus == nullptr) {
        ESP_LOGE(kTag, "failed to create I2C bus");
        releaseHardware();
        return false;
    }
    bus_ = bus;

    pm2008m::Config pm_config;
    pm_config.timeout_ms = config_.pm_timeout_ms;
    i2c_master_bus_handle_t master_bus = i2c_bus_get_internal_bus_handle(bus);
    if (master_bus == nullptr) {
        ESP_LOGE(kTag, "failed to obtain the shared I2C master bus");
        releaseHardware();
        return false;
    }
    esp_err_t ret = pm2008m_.begin(master_bus, pm_config);
    pm_ready_ = ret == ESP_OK;
    if (!pm_ready_) {
        ESP_LOGW(kTag, "PM2008M unavailable: %s", esp_err_to_name(ret));
    }

    ret = bme280_.begin(bus_);
    bme_ready_ = ret == ESP_OK;
    if (!bme_ready_) {
        ESP_LOGW(kTag, "BME280 unavailable: %s", esp_err_to_name(ret));
    }
    if (!pm_ready_ && !bme_ready_) {
        ESP_LOGE(kTag, "no sensor initialized");
        releaseHardware();
        return false;
    }

    latest_ = SensorSnapshot();
    has_latest_ = false;
    initialized_ = true;
    ESP_LOGI(kTag, "initialized on I2C port %d, SDA=%d SCL=%d, period=%lu ms",
             config_.i2c_port, config_.sda_io, config_.scl_io,
             static_cast<unsigned long>(config_.sample_period_ms));
    return true;
}

bool SensorService::start(SensorSampleCallback callback, void* context)
{
    if (!initialized_ || callback == nullptr || task_ != nullptr) {
        return false;
    }

    callback_ = callback;
    callback_context_ = context;
    stop_requested_ = false;

    const BaseType_t result = xTaskCreate(&SensorService::taskEntry, "sensor_sample",
                                          kTaskStackSize, this, kTaskPriority, &task_);
    if (result != pdPASS) {
        callback_ = nullptr;
        callback_context_ = nullptr;
        task_ = nullptr;
        ESP_LOGE(kTag, "failed to create sensor sampling task");
        return false;
    }
    return true;
}

void SensorService::stop()
{
    TaskHandle_t task = task_;
    if (task == nullptr) {
        return;
    }

    stop_requested_ = true;
    xTaskNotifyGive(task);
    while (task_ != nullptr) {
        vTaskDelay(1);
    }
    callback_ = nullptr;
    callback_context_ = nullptr;
}

bool SensorService::getLatest(SensorSnapshot* out_snapshot) const
{
    if (out_snapshot == nullptr || snapshot_mutex_ == nullptr) {
        return false;
    }
    if (xSemaphoreTake(snapshot_mutex_, portMAX_DELAY) != pdTRUE) {
        return false;
    }
    if (!has_latest_) {
        xSemaphoreGive(snapshot_mutex_);
        return false;
    }
    *out_snapshot = latest_;
    xSemaphoreGive(snapshot_mutex_);
    return true;
}

esp_err_t SensorService::readPm(pm2008m::Data* out_data)
{
    if (!pm_ready_) return ESP_ERR_INVALID_STATE;
    return pm2008m_.read(out_data);
}

esp_err_t SensorService::readBme(bme280::Reading* out_reading)
{
    if (!bme_ready_) return ESP_ERR_INVALID_STATE;
    return bme280_.read(out_reading);
}

void SensorService::sampleOnce(SensorSnapshot* out_snapshot)
{
    if (out_snapshot == nullptr) {
        return;
    }

    *out_snapshot = SensorSnapshot();
    out_snapshot->timestamp_us = static_cast<uint64_t>(esp_timer_get_time());
    out_snapshot->revision = ++revision_;

    pm2008m::Data pm_data;
    const esp_err_t pm_status = readPm(&pm_data);
    out_snapshot->raw.pm_status = static_cast<int32_t>(pm_status);
    out_snapshot->pm_valid = pm_status == ESP_OK;
    if (pm_status == ESP_OK) {
        out_snapshot->raw.pm_measurement_mode = pm_data.measurement_mode;
        out_snapshot->raw.pm_calibration = pm_data.calibration;
        out_snapshot->raw.grimm_pm1_0 = pm_data.grimm.pm1_0;
        out_snapshot->raw.grimm_pm2_5 = pm_data.grimm.pm2_5;
        out_snapshot->raw.grimm_pm10 = pm_data.grimm.pm10;
        out_snapshot->raw.tsi_pm1_0 = pm_data.tsi.pm1_0;
        out_snapshot->raw.tsi_pm2_5 = pm_data.tsi.pm2_5;
        out_snapshot->raw.tsi_pm10 = pm_data.tsi.pm10;
        out_snapshot->raw.particles_0_3 = pm_data.particles.particles_0_3;
        out_snapshot->raw.particles_0_5 = pm_data.particles.particles_0_5;
        out_snapshot->raw.particles_1_0 = pm_data.particles.particles_1_0;
        out_snapshot->raw.particles_2_5 = pm_data.particles.particles_2_5;
        out_snapshot->raw.particles_5_0 = pm_data.particles.particles_5_0;
        out_snapshot->raw.particles_10_0 = pm_data.particles.particles_10_0;
    } else {
        out_snapshot->error_flags |= device_common::kSensorErrorPm;
    }

    bme280::Reading bme_reading;
    const esp_err_t bme_status = readBme(&bme_reading);
    out_snapshot->raw.bme_status = static_cast<int32_t>(bme_status);
    out_snapshot->bme_valid = bme_status == ESP_OK;
    if (bme_status == ESP_OK) {
        if (validTemperature(bme_reading.temperature_c)) {
            out_snapshot->normalized.temperature_valid = true;
            out_snapshot->normalized.temperature_c = bme_reading.temperature_c;
        } else {
            out_snapshot->error_flags |= device_common::kSensorErrorBme;
        }
        if (validHumidity(bme_reading.humidity_percent)) {
            out_snapshot->normalized.humidity_valid = true;
            out_snapshot->normalized.humidity_percent = bme_reading.humidity_percent;
        } else {
            out_snapshot->error_flags |= device_common::kSensorErrorBme;
        }
        if (validPressure(bme_reading.pressure_hpa)) {
            out_snapshot->normalized.pressure_valid = true;
            out_snapshot->normalized.pressure_hpa = bme_reading.pressure_hpa;
        } else {
            out_snapshot->error_flags |= device_common::kSensorErrorBme;
        }
    } else {
        out_snapshot->error_flags |= device_common::kSensorErrorBme;
    }
}

void SensorService::taskEntry(void* context)
{
    static_cast<SensorService*>(context)->taskLoop();
}

void SensorService::taskLoop()
{
    const TickType_t period_ticks = pdMS_TO_TICKS(config_.sample_period_ms);
    while (!stop_requested_) {
        SensorSnapshot snapshot;
        sampleOnce(&snapshot);

        if (xSemaphoreTake(snapshot_mutex_, portMAX_DELAY) == pdTRUE) {
            latest_ = snapshot;
            has_latest_ = true;
            xSemaphoreGive(snapshot_mutex_);
        }

        if (!stop_requested_ && callback_ != nullptr) {
            callback_(snapshot, callback_context_);
        }

        if (!stop_requested_) {
            (void)ulTaskNotifyTake(pdTRUE, period_ticks);
        }
    }

    task_ = nullptr;
    vTaskDelete(nullptr);
}

void SensorService::releaseHardware()
{
    (void)bme280_.end();
    (void)pm2008m_.end();
    if (bus_ != nullptr) {
        i2c_bus_handle_t bus = static_cast<i2c_bus_handle_t>(bus_);
        (void)i2c_bus_delete(&bus);
        bus_ = nullptr;
    }
    initialized_ = false;
    pm_ready_ = false;
    bme_ready_ = false;
    has_latest_ = false;
}
