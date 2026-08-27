#pragma once

#include <cstdint>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "motor.hpp"
#include "service.hpp"

enum class MotorFeedbackMode : uint8_t {
    PulseOnly,
    LimitHome,
};

struct MotorFeedbackInputConfig {
    MotorFeedbackMode mode = MotorFeedbackMode::PulseOnly;
    int open_limit_gpio = 4;
    int close_limit_gpio = 5;
    int protection_gpio = 6;
    int step_gpio = 0;
    int dir_gpio = 1;
    int status_led_gpio = 8;
    int reset_gpio = 9;
    int32_t min_steps = 0;
    int32_t max_steps = 1600;
    uint32_t sample_period_ms = 20;
    uint32_t debounce_ms = 30;
    uint32_t homing_timeout_ms = 30000;
    bool limit_active_low = true;
    bool protection_active_high = true;
    bool use_pullup = true;
    bool auto_home = true;
};

/**
 * Publishes pulse-derived position feedback. Product mode additionally reads
 * two limit switches and a fail-safe protection loop and performs boot homing.
 */
class MotorFeedbackInput {
public:
    MotorFeedbackInput(MotorController& motor,
                       MotorService& service,
                       const MotorFeedbackInputConfig& config);

    bool begin();

private:
    struct DebouncedInput {
        bool candidate = false;
        bool stable = false;
        bool initialized = false;
        bool settled = false;
        uint64_t candidate_since_ms = 0;

        void update(bool value, uint64_t now_ms, uint32_t debounce_ms);
    };

    static void taskEntry(void* context);
    void taskLoop();
    bool validateConfiguration() const;
    bool configureInputs() const;
    bool readActive(int gpio, bool active_high) const;
    void sample(uint64_t now_ms);
    void publish(uint64_t now_ms);
    void updateHoming(uint64_t now_ms);

    MotorController& motor_;
    MotorService& service_;
    MotorFeedbackInputConfig config_;
    DebouncedInput open_limit_;
    DebouncedInput close_limit_;
    DebouncedInput protection_;
    TaskHandle_t task_ = nullptr;
    bool homed_ = false;
    bool homing_started_ = false;
    bool homing_failed_ = false;
    uint64_t homing_started_at_ms_ = 0;
};
