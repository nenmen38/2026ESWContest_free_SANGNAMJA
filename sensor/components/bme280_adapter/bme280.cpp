#include "bme280.hpp"

#include "bme280.h"
#include "i2c_bus.h"

namespace bme280 {

Bme280::~Bme280()
{
    (void)end();
}

esp_err_t Bme280::begin(void* bus_handle, const Config& config)
{
    if (bus_handle == nullptr || config.address > 0x7f) {
        return ESP_ERR_INVALID_ARG;
    }
    if (sensor_ != nullptr) {
        return ESP_OK;
    }

    i2c_bus_handle_t bus = static_cast<i2c_bus_handle_t>(bus_handle);
    bme280_handle_t sensor = bme280_create(bus, config.address);
    if (sensor == nullptr) {
        return ESP_ERR_NOT_FOUND;
    }

    const esp_err_t ret = bme280_default_init(sensor);
    if (ret != ESP_OK) {
        (void)bme280_delete(&sensor);
        return ret;
    }

    bus_ = bus;
    sensor_ = sensor;
    return ESP_OK;
}

esp_err_t Bme280::end()
{
    esp_err_t ret = ESP_OK;
    if (sensor_ != nullptr) {
        bme280_handle_t sensor = static_cast<bme280_handle_t>(sensor_);
        ret = bme280_delete(&sensor);
        if (ret == ESP_OK) {
            sensor_ = nullptr;
        }
    }
    if (sensor_ == nullptr) {
        bus_ = nullptr;
    }
    return ret;
}

esp_err_t Bme280::read(Reading* out_reading)
{
    if (sensor_ == nullptr || out_reading == nullptr) {
        return ESP_ERR_INVALID_STATE;
    }

    bme280_handle_t sensor = static_cast<bme280_handle_t>(sensor_);
    float temperature = 0.0f;
    float humidity = 0.0f;
    float pressure = 0.0f;

    esp_err_t ret = bme280_read_temperature(sensor, &temperature);
    if (ret != ESP_OK) {
        return ret;
    }
    ret = bme280_read_humidity(sensor, &humidity);
    if (ret != ESP_OK) {
        return ret;
    }
    ret = bme280_read_pressure(sensor, &pressure);
    if (ret != ESP_OK) {
        return ret;
    }

    out_reading->temperature_c = temperature;
    out_reading->humidity_percent = humidity;
    out_reading->pressure_hpa = pressure;
    return ESP_OK;
}

}  // namespace bme280
