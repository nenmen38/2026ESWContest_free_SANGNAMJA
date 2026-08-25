#pragma once

#include <cstdint>

#include "esp_err.h"

namespace bme280 {

struct Config {
    uint8_t address = 0x76;
};

struct Reading {
    float temperature_c = 0.0f;
    float humidity_percent = 0.0f;
    float pressure_hpa = 0.0f;
};

/** Project-local BME280 component backed by the registry driver. */
class Bme280 {
public:
    Bme280() = default;
    ~Bme280();

    Bme280(const Bme280&) = delete;
    Bme280& operator=(const Bme280&) = delete;

    esp_err_t begin(void* bus, const Config& config = Config());
    esp_err_t end();
    esp_err_t read(Reading* out_reading);

    bool initialized() const { return sensor_ != nullptr; }

private:
    void* bus_ = nullptr;
    void* sensor_ = nullptr;
};

}  // namespace bme280
