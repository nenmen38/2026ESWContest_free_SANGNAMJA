#pragma once

#include <cstdint>

#include "bme280.hpp"
#include "device_common.hpp"
#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "pm2008m.hpp"

struct SensorServiceConfig {
    int i2c_port = 0;
    int sda_io = 0;
    int scl_io = 1;
    uint32_t pm_timeout_ms = 1000;
    uint32_t sample_period_ms = 2000;
    bool enable_internal_pullups = false;
};

using SensorSnapshot = device_common::SensorCanonicalState;

using SensorSampleCallback = void (*)(const SensorSnapshot& snapshot, void* context);

/**
 * @brief Owns the shared sensor bus, sampling task, and latest snapshot.
 *
 * The callback executes on the sampling task. It must not block or perform
 * network/I2C work; consumers should enqueue the snapshot for another task.
 */
class SensorService {
public:
    explicit SensorService(const SensorServiceConfig& config = SensorServiceConfig());
    ~SensorService();

    SensorService(const SensorService&) = delete;
    SensorService& operator=(const SensorService&) = delete;

    bool begin();
    bool start(SensorSampleCallback callback, void* context = nullptr);
    void stop();

    bool getLatest(SensorSnapshot* out_snapshot) const;
    bool initialized() const { return initialized_; }
    bool running() const { return task_ != nullptr; }

protected:
    // These seams keep the aggregation logic unit-testable without hardware.
    virtual esp_err_t readPm(pm2008m::Data* out_data);
    virtual esp_err_t readBme(bme280::Reading* out_reading);
    void sampleOnce(SensorSnapshot* out_snapshot);

private:
    static void taskEntry(void* context);
    void taskLoop();
    void releaseHardware();

    SensorServiceConfig config_;
    void* bus_ = nullptr;
    pm2008m::Pm2008m pm2008m_;
    bme280::Bme280 bme280_;

    SemaphoreHandle_t snapshot_mutex_ = nullptr;
    TaskHandle_t task_ = nullptr;
    volatile bool stop_requested_ = false;
    SensorSampleCallback callback_ = nullptr;
    void* callback_context_ = nullptr;
    SensorSnapshot latest_;
    bool has_latest_ = false;
    bool initialized_ = false;
    bool pm_ready_ = false;
    bool bme_ready_ = false;
    uint64_t revision_ = 0;
};
