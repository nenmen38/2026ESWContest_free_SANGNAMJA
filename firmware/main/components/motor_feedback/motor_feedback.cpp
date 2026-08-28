#include "motor_feedback.hpp"

#include <algorithm>

#include "device_common.hpp"
#include "esp_log.h"
#include "esp_timer.h"

namespace {

constexpr const char* kTag = "motor_feedback";
constexpr uint32_t kTaskStackSize = 4096;
constexpr UBaseType_t kTaskPriority = 7;

}  // namespace

MotorFeedbackInput::MotorFeedbackInput(MotorController& motor,
                                       MotorService& service,
                                       const MotorFeedbackInputConfig& config)
    : motor_(motor), service_(service), config_(config)
{
}

bool MotorFeedbackInput::validateConfiguration() const
{
    return config_.min_steps == 0 && config_.max_steps > config_.min_steps &&
           config_.sample_period_ms != 0;
}

bool MotorFeedbackInput::begin()
{
    if (task_ != nullptr) return true;
    if (!validateConfiguration()) {
        ESP_LOGE(kTag, "invalid pulse position configuration");
        return false;
    }

    // The operating contract requires the mechanism to be fully closed before
    // every boot, so the closed endpoint is always the software origin.
    motor_.setPosition(config_.min_steps);
    ESP_LOGW(kTag,
             "PULSE_ONLY: assuming fully closed at boot; software travel=0..%ld pulses",
             static_cast<long>(config_.max_steps));

    if (xTaskCreate(&MotorFeedbackInput::taskEntry, "motor_feedback",
                    kTaskStackSize, this, kTaskPriority, &task_) != pdPASS) {
        task_ = nullptr;
        ESP_LOGE(kTag, "failed to create feedback task");
        return false;
    }
    return true;
}

void MotorFeedbackInput::publish(uint64_t now_ms)
{
    MotorFeedback feedback;
    feedback.observed_at_ms = now_ms;
    feedback.position_valid = device_common::stepsToPosition100ths(
        motor_.getPosition(), config_.min_steps, config_.max_steps,
        &feedback.position100ths);
    service_.updateFeedback(feedback);
}

void MotorFeedbackInput::taskEntry(void* context)
{
    static_cast<MotorFeedbackInput*>(context)->taskLoop();
}

void MotorFeedbackInput::taskLoop()
{
    while (true) {
        const uint64_t now_ms = static_cast<uint64_t>(esp_timer_get_time()) / 1000ULL;
        publish(now_ms);
        vTaskDelay(std::max<TickType_t>(1, pdMS_TO_TICKS(config_.sample_period_ms)));
    }
}
