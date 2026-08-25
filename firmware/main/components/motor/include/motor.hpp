#pragma once

#include <cstdint>

/**
 * @brief Stepper motor configuration expressed in pulses and RPM.
 *
 * The GPIO numbers are intentionally kept in the configuration rather than
 * hard-coded in MotorController.  With the default TB6600 setup, GPIO0 is
 * connected to STEP/PUL through an NPN open-collector stage and GPIO1 is
 * connected to DIR in the same way.
 */
struct MotorConfig {
    int step_gpio = 0;
    int dir_gpio = 1;

    uint32_t full_steps_per_rev = 200;
    uint32_t microstep = 8;

    float default_rpm = 100.0f;
    float max_rpm = 150.0f;

    uint32_t acceleration = 1000;

    // Set so positive pulse positions physically open the mechanism.
    bool direction_inverted = false;
};

/**
 * @brief Non-blocking step/direction motor controller.
 *
 * Position values are step/pulse counts.  Window percentages, homing,
 * calibration, sensors, and network protocol handling belong in a higher
 * layer such as WindowController.  After begin(), keep this object alive for
 * the lifetime of the application because FastAccelStepper owns a background
 * task and 1.2.7 does not expose an engine deinitialization API.
 */
class MotorController {
public:
    explicit MotorController(const MotorConfig& config = MotorConfig());
    ~MotorController();

    MotorController(const MotorController&) = delete;
    MotorController& operator=(const MotorController&) = delete;

    bool begin();

    bool setSpeedRPM(float rpm);
    bool setAcceleration(uint32_t steps_per_sec2);

    bool moveSteps(int32_t steps);
    bool moveTo(int32_t absolute_steps);

    bool runForward();
    bool runBackward();

    /** @brief Stop with FastAccelStepper's normal deceleration ramp. */
    void stop();

    /** @brief Immediately stop pulse output for a limit or protection event. */
    void emergencyStop();

    bool isRunning() const;

    int32_t getPosition() const;
    void setPosition(int32_t position);

    float getSpeedRPM() const;
    uint32_t getStepFrequencyHz() const;
    uint32_t getStepsPerRevolution() const;

private:
    bool validateConfiguration() const;
    bool rpmToFrequency(float rpm, uint32_t* frequency_hz) const;
    bool validateMoveTarget(int64_t target) const;
    bool applySpeedAndAcceleration();
    bool ready(const char* operation) const;

    MotorConfig config_;
    uint64_t steps_per_revolution_ = 0;
    float speed_rpm_ = 0.0f;
    uint32_t step_frequency_hz_ = 0;

    // Kept opaque in the public header so users of motor.hpp do not need to
    // include FastAccelStepper headers directly.
    class FastAccelStepperEngine* engine_ = nullptr;
    class FastAccelStepper* stepper_ = nullptr;
    bool initialized_ = false;
};
