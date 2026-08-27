#include "motor.hpp"

#include <cmath>
#include <cstdint>
#include <limits>
#include <new>

#include "FastAccelStepper.h"
#include "driver/gpio.h"
#include "esp_log.h"

namespace {

constexpr const char* TAG = "motor";
constexpr uint16_t kDirectionChangeDelayUs = 200;

bool isValidGpioNumber(int gpio)
{
    return gpio >= 0 && gpio < static_cast<int>(GPIO_NUM_MAX);
}

}  // namespace

MotorController::MotorController(const MotorConfig& config)
    : config_(config),
      steps_per_revolution_(static_cast<uint64_t>(config.full_steps_per_rev) *
                            static_cast<uint64_t>(config.microstep)),
      speed_rpm_(config.default_rpm)
{
}

MotorController::~MotorController()
{
    // FastAccelStepper 1.2.7 has no engine deinitialization API.  Its
    // background task can still reference the engine after this destructor,
    // so intentionally keep the engine allocation alive until reset.
    engine_ = nullptr;
    stepper_ = nullptr;
}

bool MotorController::validateConfiguration() const
{
    if (!isValidGpioNumber(config_.step_gpio) || !isValidGpioNumber(config_.dir_gpio)) {
        ESP_LOGE(TAG, "invalid GPIO configuration: STEP=%d DIR=%d",
                 config_.step_gpio, config_.dir_gpio);
        return false;
    }
    if (config_.step_gpio == config_.dir_gpio) {
        ESP_LOGE(TAG, "STEP and DIR must use different GPIOs");
        return false;
    }
    if (config_.full_steps_per_rev == 0 || config_.microstep == 0 ||
        steps_per_revolution_ == 0 ||
        steps_per_revolution_ > std::numeric_limits<uint32_t>::max()) {
        ESP_LOGE(TAG, "invalid steps/rev: full_steps=%lu microstep=%lu",
                 static_cast<unsigned long>(config_.full_steps_per_rev),
                 static_cast<unsigned long>(config_.microstep));
        return false;
    }
    if (!std::isfinite(config_.default_rpm) || config_.default_rpm <= 0.0f ||
        !std::isfinite(config_.max_rpm) || config_.max_rpm <= 0.0f ||
        config_.default_rpm > config_.max_rpm) {
        ESP_LOGE(TAG, "invalid RPM configuration: default=%.3f max=%.3f",
                 config_.default_rpm, config_.max_rpm);
        return false;
    }
    if (config_.acceleration == 0 ||
        config_.acceleration > static_cast<uint32_t>(INT32_MAX)) {
        ESP_LOGE(TAG, "invalid acceleration: %lu steps/s^2",
                 static_cast<unsigned long>(config_.acceleration));
        return false;
    }
    return true;
}

bool MotorController::rpmToFrequency(float rpm, uint32_t* frequency_hz) const
{
    if (frequency_hz == nullptr || !std::isfinite(rpm) || rpm <= 0.0f ||
        rpm > config_.max_rpm || steps_per_revolution_ == 0 ||
        steps_per_revolution_ > std::numeric_limits<uint32_t>::max()) {
        return false;
    }

    const double steps_per_second =
        static_cast<double>(rpm) * static_cast<double>(steps_per_revolution_) / 60.0;
    if (!std::isfinite(steps_per_second) || steps_per_second < 1.0 ||
        steps_per_second > static_cast<double>(std::numeric_limits<uint32_t>::max())) {
        return false;
    }

    const auto rounded_frequency = static_cast<uint64_t>(std::llround(steps_per_second));
    if (rounded_frequency == 0 ||
        rounded_frequency > std::numeric_limits<uint32_t>::max()) {
        return false;
    }

    *frequency_hz = static_cast<uint32_t>(rounded_frequency);
    return true;
}

bool MotorController::begin()
{
    if (initialized_) {
        return true;
    }
    if (!validateConfiguration()) {
        return false;
    }

    uint32_t initial_frequency_hz = 0;
    if (!rpmToFrequency(config_.default_rpm, &initial_frequency_hz)) {
        ESP_LOGE(TAG, "default RPM cannot be converted to a valid step frequency");
        return false;
    }

    engine_ = new (std::nothrow) FastAccelStepperEngine();
    if (engine_ == nullptr) {
        ESP_LOGE(TAG, "FastAccelStepper engine allocation failed");
        return false;
    }

    // FastAccelStepper 1.2.7 exposes init() as a void function.
    engine_->init();
    stepper_ = engine_->stepperConnectToPin(static_cast<uint8_t>(config_.step_gpio));
    if (stepper_ == nullptr) {
        ESP_LOGE(TAG, "FastAccelStepper could not allocate STEP GPIO %d",
                 config_.step_gpio);
        return false;
    }

    // dirHighCountsUp is the library's direction polarity switch.  It maps
    // directly to direction_inverted, including the inversion introduced by
    // the external NPN open-collector stage.
    stepper_->setDirectionPin(static_cast<uint8_t>(config_.dir_gpio),
                              !config_.direction_inverted,
                              kDirectionChangeDelayUs);

    if (stepper_->setSpeedInHz(initial_frequency_hz) != 0) {
        ESP_LOGE(TAG, "FastAccelStepper rejected initial speed: %lu Hz",
                 static_cast<unsigned long>(initial_frequency_hz));
        return false;
    }
    if (stepper_->setAcceleration(static_cast<int32_t>(config_.acceleration)) != 0) {
        ESP_LOGE(TAG, "FastAccelStepper rejected acceleration: %lu steps/s^2",
                 static_cast<unsigned long>(config_.acceleration));
        return false;
    }

    speed_rpm_ = config_.default_rpm;
    step_frequency_hz_ = initial_frequency_hz;
    initialized_ = true;

    ESP_LOGI(TAG,
             "Motor initialized: STEP GPIO=%d DIR GPIO=%d full steps/rev=%lu "
             "microstep=%lu steps/rev=%lu RPM=%.3f step frequency=%lu Hz "
             "acceleration=%lu direction_inverted=%s",
             config_.step_gpio, config_.dir_gpio,
             static_cast<unsigned long>(config_.full_steps_per_rev),
             static_cast<unsigned long>(config_.microstep),
             static_cast<unsigned long>(getStepsPerRevolution()),
             static_cast<double>(speed_rpm_),
             static_cast<unsigned long>(step_frequency_hz_),
             static_cast<unsigned long>(config_.acceleration),
             config_.direction_inverted ? "true" : "false");
    return true;
}

bool MotorController::applySpeedAndAcceleration()
{
    if (!initialized_ || stepper_ == nullptr) {
        ESP_LOGE(TAG, "motor is not initialized");
        return false;
    }
    if (stepper_->setSpeedInHz(step_frequency_hz_) != 0 ||
        stepper_->setAcceleration(static_cast<int32_t>(config_.acceleration)) != 0) {
        ESP_LOGE(TAG, "FastAccelStepper rejected speed/acceleration update");
        return false;
    }
    if (stepper_->isRunning()) {
        stepper_->applySpeedAcceleration();
    }
    return true;
}

bool MotorController::setSpeedRPM(float rpm)
{
    uint32_t frequency_hz = 0;
    if (!rpmToFrequency(rpm, &frequency_hz)) {
        ESP_LOGW(TAG, "invalid RPM %.3f (allowed range: >0 and <= %.3f)",
                 static_cast<double>(rpm), static_cast<double>(config_.max_rpm));
        return false;
    }
    if (!ready("setSpeedRPM")) return false;

    const float previous_rpm = speed_rpm_;
    const uint32_t previous_frequency_hz = step_frequency_hz_;
    speed_rpm_ = rpm;
    step_frequency_hz_ = frequency_hz;
    if (!applySpeedAndAcceleration()) {
        speed_rpm_ = previous_rpm;
        step_frequency_hz_ = previous_frequency_hz;
        return false;
    }

    ESP_LOGI(TAG, "speed set: RPM=%.3f step frequency=%lu Hz",
             static_cast<double>(speed_rpm_),
             static_cast<unsigned long>(step_frequency_hz_));
    return true;
}

bool MotorController::setAcceleration(uint32_t steps_per_sec2)
{
    if (steps_per_sec2 == 0 || steps_per_sec2 > static_cast<uint32_t>(INT32_MAX)) {
        ESP_LOGW(TAG, "invalid acceleration: %lu steps/s^2",
                 static_cast<unsigned long>(steps_per_sec2));
        return false;
    }
    if (!ready("setAcceleration")) return false;

    const uint32_t previous_acceleration = config_.acceleration;
    config_.acceleration = steps_per_sec2;
    if (!applySpeedAndAcceleration()) {
        config_.acceleration = previous_acceleration;
        return false;
    }

    ESP_LOGI(TAG, "acceleration set: %lu steps/s^2",
             static_cast<unsigned long>(config_.acceleration));
    return true;
}

bool MotorController::validateMoveTarget(int64_t target) const
{
    return target >= std::numeric_limits<int32_t>::min() &&
           target <= std::numeric_limits<int32_t>::max();
}

bool MotorController::ready(const char* operation) const
{
    if (initialized_ && stepper_ != nullptr) return true;
    ESP_LOGE(TAG, "%s called before begin()", operation);
    return false;
}

bool MotorController::moveSteps(int32_t steps)
{
    if (!ready("moveSteps")) return false;
    if (steps == 0) {
        ESP_LOGW(TAG, "moveSteps called with zero steps");
        return true;
    }

    const int64_t target = static_cast<int64_t>(getPosition()) + steps;
    if (!validateMoveTarget(target)) {
        ESP_LOGE(TAG, "move target overflow: current=%ld steps=%ld",
                 static_cast<long>(getPosition()), static_cast<long>(steps));
        return false;
    }

    const MoveResultCode result = stepper_->move(steps, false);
    if (result != MOVE_OK) {
        ESP_LOGE(TAG, "FastAccelStepper rejected move steps=%ld result=%d",
                 static_cast<long>(steps), static_cast<int>(result));
        return false;
    }

    ESP_LOGI(TAG, "move steps=%ld target position=%ld",
             static_cast<long>(steps), static_cast<long>(target));
    return true;
}

bool MotorController::moveTo(int32_t absolute_steps)
{
    if (!ready("moveTo")) return false;

    const MoveResultCode result = stepper_->moveTo(absolute_steps, false);
    if (result != MOVE_OK) {
        ESP_LOGE(TAG, "FastAccelStepper rejected target position=%ld result=%d",
                 static_cast<long>(absolute_steps), static_cast<int>(result));
        return false;
    }

    ESP_LOGI(TAG, "target position=%ld current position=%ld",
             static_cast<long>(absolute_steps), static_cast<long>(getPosition()));
    return true;
}

bool MotorController::runForward()
{
    if (!ready("runForward")) return false;

    const MoveResultCode result = stepper_->runForward();
    if (result != MOVE_OK) {
        ESP_LOGE(TAG, "FastAccelStepper rejected forward run result=%d",
                 static_cast<int>(result));
        return false;
    }
    ESP_LOGI(TAG, "continuous forward run started");
    return true;
}

bool MotorController::runBackward()
{
    if (!ready("runBackward")) return false;

    const MoveResultCode result = stepper_->runBackward();
    if (result != MOVE_OK) {
        ESP_LOGE(TAG, "FastAccelStepper rejected backward run result=%d",
                 static_cast<int>(result));
        return false;
    }
    ESP_LOGI(TAG, "continuous backward run started");
    return true;
}

void MotorController::stop()
{
    if (!initialized_ || stepper_ == nullptr) {
        ESP_LOGW(TAG, "stop called before begin()");
        return;
    }

    // stopMove() is asynchronous and applies the configured deceleration.
    stepper_->stopMove();
    ESP_LOGI(TAG, "stop requested at position=%ld",
             static_cast<long>(getPosition()));
}

void MotorController::emergencyStop()
{
    if (!initialized_ || stepper_ == nullptr) {
        ESP_LOGW(TAG, "emergencyStop called before begin()");
        return;
    }
    stepper_->forceStop();
    ESP_LOGW(TAG, "emergency stop at position=%ld",
             static_cast<long>(getPosition()));
}

bool MotorController::isRunning() const
{
    return initialized_ && stepper_ != nullptr && stepper_->isRunning();
}

int32_t MotorController::getPosition() const
{
    if (!initialized_ || stepper_ == nullptr) {
        return 0;
    }
    return stepper_->getCurrentPosition();
}

void MotorController::setPosition(int32_t position)
{
    if (!initialized_ || stepper_ == nullptr) {
        ESP_LOGW(TAG, "setPosition called before begin()");
        return;
    }
    if (isRunning()) {
        ESP_LOGW(TAG, "setPosition while running is approximate; stop first");
    }
    stepper_->setCurrentPosition(position);
    ESP_LOGI(TAG, "current position set to %ld", static_cast<long>(position));
}

float MotorController::getSpeedRPM() const
{
    return speed_rpm_;
}

uint32_t MotorController::getStepFrequencyHz() const
{
    return step_frequency_hz_;
}

uint32_t MotorController::getStepsPerRevolution() const
{
    if (steps_per_revolution_ > std::numeric_limits<uint32_t>::max()) {
        return 0;
    }
    return static_cast<uint32_t>(steps_per_revolution_);
}
