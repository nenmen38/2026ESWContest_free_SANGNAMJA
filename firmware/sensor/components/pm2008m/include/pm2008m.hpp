#pragma once

#include <cstdint>

#include "driver/i2c_master.h"
#include "esp_err.h"

namespace pm2008m {

struct Config {
    uint32_t timeout_ms = 1000;
};

struct Mass {
    uint16_t pm1_0 = 0;
    uint16_t pm2_5 = 0;
    uint16_t pm10 = 0;
};

struct Particles {
    uint16_t particles_0_3 = 0;
    uint16_t particles_0_5 = 0;
    uint16_t particles_1_0 = 0;
    uint16_t particles_2_5 = 0;
    uint16_t particles_5_0 = 0;
    uint16_t particles_10_0 = 0;
};

struct Data {
    uint8_t status = 0;
    uint16_t measurement_mode = 0;
    uint16_t calibration = 0;

    Mass grimm;
    Mass tsi;
    Particles particles;
};

/**
 * @brief RAII wrapper for a PM2008M device on an application-owned I2C bus.
 *
 * The object owns only its device handle. The master bus remains owned by the
 * caller and must outlive this object after begin() succeeds.
 */
class Pm2008m {
public:
    Pm2008m() = default;
    ~Pm2008m();

    Pm2008m(const Pm2008m&) = delete;
    Pm2008m& operator=(const Pm2008m&) = delete;

    esp_err_t begin(i2c_master_bus_handle_t bus, const Config& config = Config());
    esp_err_t end();
    esp_err_t read(Data* out_data);

    bool initialized() const { return device_ != nullptr; }

private:
    i2c_master_bus_handle_t bus_ = nullptr;
    i2c_master_dev_handle_t device_ = nullptr;
    uint32_t timeout_ms_ = 1000;
};

}  // namespace pm2008m
