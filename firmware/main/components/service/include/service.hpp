#pragma once

#include <cstdint>
#include <array>
#include <mutex>

#include "device_common.hpp"
#include "motor.hpp"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

enum class MotorCommandResult : uint8_t {
    Accepted,
    InvalidCommand,
    DuplicateCommand,
    SafetyUnavailable,
    PositionUnknown,
    HardwareRejected,
};

struct SafetySnapshot {
    bool available = false;
    uint64_t observed_at_ms = 0;
    bool limits_valid = false;
    bool open_limit_active = false;
    bool close_limit_active = false;
    bool protection_valid = false;
    bool protection_active = false;
    uint32_t protection_state = 0;
};

struct MotorFeedback {
    bool position_valid = false;
    uint32_t position100ths = 0;
    bool homing_failed = false;
    SafetySnapshot safety;
};

struct MotorServiceConfig {
    int32_t min_steps = 0;
    int32_t max_steps = 1600;
    uint32_t ventilation_position100ths = 2500;
    uint32_t safety_stale_after_ms = 2000;
    bool homing_supported = true;
};

class MotorActuator {
public:
    virtual ~MotorActuator() = default;

    virtual bool begin() = 0;
    virtual bool moveTo(int32_t absolute_steps) = 0;
    virtual bool runForward() = 0;
    virtual bool runBackward() = 0;
    virtual void stop() = 0;
    virtual void emergencyStop() = 0;
    virtual void setPositionSteps(int32_t position) = 0;
};

/** Adapter that keeps the existing FastAccelStepper HAL behind the service. */
class MotorControllerActuator final : public MotorActuator {
public:
    explicit MotorControllerActuator(MotorController& motor) : motor_(motor) {}

    bool begin() override { return motor_.begin(); }
    bool moveTo(int32_t absolute_steps) override { return motor_.moveTo(absolute_steps); }
    bool runForward() override { return motor_.runForward(); }
    bool runBackward() override { return motor_.runBackward(); }
    void stop() override { motor_.stop(); }
    void emergencyStop() override { motor_.emergencyStop(); }
    void setPositionSteps(int32_t position) override { motor_.setPosition(position); }

private:
    MotorController& motor_;
};

/**
 * @brief Owns the motor command/state boundary below protocol adapters.
 *
 * This service deliberately does not read GPIOs itself. A board-specific
 * input layer must call updateFeedback() with encoder/limit/protection state.
 * Position-changing commands are rejected until the required safety inputs
 * are known, so a missing feedback wire cannot look like a valid position.
 */
class MotorService {
public:
    MotorService(MotorActuator& motor,
                 const MotorServiceConfig& config = MotorServiceConfig());
    ~MotorService();

    bool begin();

    MotorCommandResult submit(const device_common::MotorCommand& command,
                              uint64_t now_ms,
                              bool remote_command);

    void updateFeedback(const MotorFeedback& feedback);
    device_common::MotorCanonicalState snapshot() const;
    MotorFeedback feedbackSnapshot() const;

private:
    enum class RequestKind : uint8_t { Command, Feedback, Shutdown };
    struct Request {
        RequestKind kind = RequestKind::Command;
        device_common::MotorCommand command;
        std::array<char, device_common::CommandDeduplicator::kMaxCommandIdLength + 1> command_id{};
        uint64_t now_ms = 0;
        bool remote_command = false;
        MotorFeedback feedback;
        MotorCommandResult result = MotorCommandResult::HardwareRejected;
        StaticSemaphore_t completion_storage{};
        SemaphoreHandle_t completion = nullptr;
    };

    static void taskEntry(void* context);
    void taskLoop();
    bool dispatch(Request* request);
    MotorCommandResult processCommand(const device_common::MotorCommand& command,
                                      uint64_t now_ms,
                                      bool remote_command);
    void processFeedback(const MotorFeedback& feedback);
    MotorCommandResult moveToPosition(uint32_t position100ths);
    MotorCommandResult reject(MotorCommandResult result,
                              uint32_t error,
                              device_common::MotorMainState state);
    MotorCommandResult rejectSafety();
    bool safetyInputsAvailable(uint64_t now_ms) const;
    void updateStateFromMotion(uint32_t target_position100ths);

    MotorActuator& motor_;
    MotorServiceConfig config_;
    MotorFeedback feedback_;
    device_common::MotorCanonicalState state_;
    device_common::CommandDeduplicator deduplicator_;
    mutable std::mutex mutex_;
    QueueHandle_t request_queue_ = nullptr;
    TaskHandle_t task_ = nullptr;
    bool initialized_ = false;
};
