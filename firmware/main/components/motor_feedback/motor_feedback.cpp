#include "motor_feedback.hpp"

#include <algorithm>
#include <array>

#include "device_common.hpp"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"

namespace {

constexpr const char* kTag = "motor_feedback";
constexpr uint32_t kFeedbackFaultBit = 1u << 16;
constexpr uint32_t kTaskStackSize = 4096;
constexpr UBaseType_t kTaskPriority = 7;

bool validGpio(int gpio)
{
    return gpio >= 0 && gpio < static_cast<int>(GPIO_NUM_MAX);
}

}  // namespace

MotorFeedbackInput::MotorFeedbackInput(MotorController& motor,
                                       MotorService& service,
                                       const MotorFeedbackInputConfig& config)
    : motor_(motor), service_(service), config_(config)
{
}

void MotorFeedbackInput::DebouncedInput::update(bool value,
                                                uint64_t now_ms,
                                                uint32_t debounce_ms)
{
    if (!initialized) {
        candidate = value;
        stable = value;
        initialized = true;
        settled = debounce_ms == 0;
        candidate_since_ms = now_ms;
        return;
    }
    if (value != candidate) {
        candidate = value;
        candidate_since_ms = now_ms;
        settled = false;
        return;
    }
    if (!settled && now_ms >= candidate_since_ms &&
        now_ms - candidate_since_ms >= debounce_ms) {
        stable = candidate;
        settled = true;
    }
}

bool MotorFeedbackInput::validateConfiguration() const
{
    if (config_.max_steps <= config_.min_steps || config_.sample_period_ms == 0) {
        return false;
    }
    if (config_.mode == MotorFeedbackMode::PulseOnly) return true;

    const std::array<int, 3> inputs{
        config_.open_limit_gpio,
        config_.close_limit_gpio,
        config_.protection_gpio,
    };
    for (std::size_t i = 0; i < inputs.size(); ++i) {
        if (!validGpio(inputs[i])) return false;
        for (std::size_t j = i + 1; j < inputs.size(); ++j) {
            if (inputs[i] == inputs[j]) return false;
        }
        if (inputs[i] == config_.step_gpio || inputs[i] == config_.dir_gpio ||
            inputs[i] == config_.status_led_gpio || inputs[i] == config_.reset_gpio) {
            return false;
        }
    }
    return config_.homing_timeout_ms > 0;
}

bool MotorFeedbackInput::configureInputs() const
{
    gpio_config_t io = {};
    io.pin_bit_mask = (1ULL << config_.open_limit_gpio) |
                      (1ULL << config_.close_limit_gpio) |
                      (1ULL << config_.protection_gpio);
    io.mode = GPIO_MODE_INPUT;
    io.pull_up_en = config_.use_pullup ? GPIO_PULLUP_ENABLE : GPIO_PULLUP_DISABLE;
    io.pull_down_en = GPIO_PULLDOWN_DISABLE;
    io.intr_type = GPIO_INTR_DISABLE;
    return gpio_config(&io) == ESP_OK;
}

bool MotorFeedbackInput::begin()
{
    if (task_ != nullptr) return true;
    if (!validateConfiguration()) {
        ESP_LOGE(kTag, "invalid or conflicting feedback GPIO/configuration");
        return false;
    }
    if (config_.mode == MotorFeedbackMode::LimitHome && !configureInputs()) {
        ESP_LOGE(kTag, "failed to configure feedback GPIOs");
        return false;
    }
    if (config_.mode == MotorFeedbackMode::PulseOnly) {
        motor_.setPosition(config_.min_steps);
        homed_ = true;
        ESP_LOGW(kTag,
                 "PULSE_ONLY: assuming fully closed at boot; physical limits "
                 "and obstruction protection are unavailable");
    }
    if (xTaskCreate(&MotorFeedbackInput::taskEntry, "motor_feedback",
                    kTaskStackSize, this, kTaskPriority, &task_) != pdPASS) {
        task_ = nullptr;
        ESP_LOGE(kTag, "failed to create feedback task");
        return false;
    }
    if (config_.mode == MotorFeedbackMode::LimitHome) {
        ESP_LOGI(kTag,
                 "LIMIT_HOME: open=%d close=%d protection=%d travel=%ld pulses",
                 config_.open_limit_gpio, config_.close_limit_gpio,
                 config_.protection_gpio, static_cast<long>(config_.max_steps));
    } else {
        ESP_LOGI(kTag, "PULSE_ONLY: software travel=0..%ld pulses",
                 static_cast<long>(config_.max_steps));
    }
    return true;
}

bool MotorFeedbackInput::readActive(int gpio, bool active_high) const
{
    const bool high = gpio_get_level(static_cast<gpio_num_t>(gpio)) != 0;
    return active_high ? high : !high;
}

void MotorFeedbackInput::sample(uint64_t now_ms)
{
    if (config_.mode == MotorFeedbackMode::PulseOnly) return;
    open_limit_.update(readActive(config_.open_limit_gpio,
                                  !config_.limit_active_low),
                       now_ms, config_.debounce_ms);
    close_limit_.update(readActive(config_.close_limit_gpio,
                                   !config_.limit_active_low),
                        now_ms, config_.debounce_ms);
    protection_.update(readActive(config_.protection_gpio,
                                  config_.protection_active_high),
                       now_ms, config_.debounce_ms);

    if (open_limit_.settled && open_limit_.stable) homed_ = true;
    if (close_limit_.settled && close_limit_.stable) homed_ = true;
}

void MotorFeedbackInput::publish(uint64_t now_ms)
{
    MotorFeedback feedback;
    if (config_.mode == MotorFeedbackMode::PulseOnly) {
        feedback.safety.available = true;
        feedback.safety.observed_at_ms = now_ms;
        feedback.safety.limits_valid = true;
        feedback.safety.protection_valid = true;
        feedback.position_valid = device_common::stepsToPosition100ths(
            motor_.getPosition(), config_.min_steps, config_.max_steps,
            &feedback.position100ths);
        service_.updateFeedback(feedback);
        return;
    }
    const bool limits_settled = open_limit_.settled && close_limit_.settled;
    const bool contradictory_limits = limits_settled &&
                                      open_limit_.stable && close_limit_.stable;

    feedback.safety.observed_at_ms = now_ms;
    feedback.safety.limits_valid = limits_settled && !contradictory_limits;
    feedback.safety.open_limit_active = open_limit_.settled && open_limit_.stable;
    feedback.safety.close_limit_active = close_limit_.settled && close_limit_.stable;
    feedback.safety.protection_valid = protection_.settled;
    feedback.safety.protection_active =
        (protection_.settled && protection_.stable) || contradictory_limits ||
        homing_failed_;
    feedback.safety.protection_state = feedback.safety.protection_active
                                           ? kFeedbackFaultBit
                                           : 0;
    feedback.homing_failed = homing_failed_;
    feedback.safety.available = feedback.safety.limits_valid &&
                                feedback.safety.protection_valid;

    if (homed_) {
        if (feedback.safety.close_limit_active) {
            feedback.position_valid = true;
            feedback.position100ths = device_common::kPositionMin100ths;
        } else if (feedback.safety.open_limit_active) {
            feedback.position_valid = true;
            feedback.position100ths = device_common::kPositionMax100ths;
        } else {
            feedback.position_valid = device_common::stepsToPosition100ths(
                motor_.getPosition(), config_.min_steps, config_.max_steps,
                &feedback.position100ths);
        }
    }
    service_.updateFeedback(feedback);
}

void MotorFeedbackInput::updateHoming(uint64_t now_ms)
{
    if (config_.mode != MotorFeedbackMode::LimitHome || !config_.auto_home ||
        homing_failed_) return;
    if (close_limit_.settled && close_limit_.stable) {
        if (homing_started_) ESP_LOGI(kTag, "homing complete at closed limit");
        homed_ = true;
        homing_started_ = false;
        return;
    }
    if (!homing_started_) {
        if (!open_limit_.settled || !close_limit_.settled || !protection_.settled ||
            protection_.stable || (open_limit_.stable && close_limit_.stable)) {
            return;
        }
        device_common::MotorCommand command;
        command.action = device_common::MotorCommandAction::Calibrate;
        if (service_.submit(command, now_ms, false) != MotorCommandResult::Accepted) {
            ESP_LOGE(kTag, "automatic homing command was rejected");
            homing_failed_ = true;
            return;
        }
        homing_started_ = true;
        homing_started_at_ms_ = now_ms;
        ESP_LOGI(kTag, "automatic homing started toward the closed limit");
        return;
    }
    if (now_ms >= homing_started_at_ms_ &&
        now_ms - homing_started_at_ms_ > config_.homing_timeout_ms) {
        device_common::MotorCommand stop;
        stop.action = device_common::MotorCommandAction::Stop;
        (void)service_.submit(stop, now_ms, false);
        homing_failed_ = true;
        homing_started_ = false;
        ESP_LOGE(kTag, "homing timed out; movement remains safety-blocked");
    }
}

void MotorFeedbackInput::taskEntry(void* context)
{
    static_cast<MotorFeedbackInput*>(context)->taskLoop();
}

void MotorFeedbackInput::taskLoop()
{
    while (true) {
        const uint64_t now_ms = static_cast<uint64_t>(esp_timer_get_time()) / 1000ULL;
        sample(now_ms);
        publish(now_ms);
        updateHoming(now_ms);
        const TickType_t delay = std::max<TickType_t>(
            1, pdMS_TO_TICKS(config_.sample_period_ms));
        vTaskDelay(delay);
    }
}
