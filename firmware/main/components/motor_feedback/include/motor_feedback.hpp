#pragma once

#include <cstdint>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "motor.hpp"
#include "service.hpp"

struct MotorFeedbackInputConfig {
    int32_t min_steps = 0;
    int32_t max_steps = 1600;
    uint32_t sample_period_ms = 20;
};

/** Publishes pulse-derived position feedback for the PULSE_ONLY contract. */
class MotorFeedbackInput {
public:
    MotorFeedbackInput(MotorController& motor,
                       MotorService& service,
                       const MotorFeedbackInputConfig& config);

    bool begin();

private:
    static void taskEntry(void* context);
    void taskLoop();
    bool validateConfiguration() const;
    void publish(uint64_t now_ms);

    MotorController& motor_;
    MotorService& service_;
    MotorFeedbackInputConfig config_;
    TaskHandle_t task_ = nullptr;
};
