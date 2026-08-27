#include "service.hpp"

#include "unity.h"

namespace {

class FakeMotorActuator final : public MotorActuator {
public:
    bool begin() override
    {
        initialized = true;
        return true;
    }

    bool moveTo(int32_t absolute_steps) override
    {
        last_target_steps = absolute_steps;
        move_to_called = true;
        return initialized;
    }

    bool runForward() override
    {
        forward_called = true;
        return initialized;
    }

    bool runBackward() override
    {
        backward_called = true;
        return initialized;
    }

    void stop() override { stop_called = true; }
    void emergencyStop() override { emergency_stop_called = true; }
    void setPositionSteps(int32_t position) override
    {
        current_position_steps = position;
    }

    bool initialized = false;
    bool move_to_called = false;
    bool forward_called = false;
    bool backward_called = false;
    bool stop_called = false;
    bool emergency_stop_called = false;
    int32_t last_target_steps = 0;
    int32_t current_position_steps = 0;
};

device_common::MotorCommand setPositionCommand(std::string_view id,
                                                uint64_t received_at_ms)
{
    device_common::MotorCommand command;
    command.metadata.command_id = id;
    command.metadata.received_at_ms = received_at_ms;
    command.metadata.ttl_ms = 1000;
    command.action = device_common::MotorCommandAction::SetPosition;
    command.position100ths = 2500;
    return command;
}

}  // namespace

TEST_CASE("motor service rejects position command without safety feedback", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());

    const auto result = service.submit(setPositionCommand("id-1", 100), 200, true);
    TEST_ASSERT_EQUAL(MotorCommandResult::SafetyUnavailable, result);
    TEST_ASSERT_FALSE(actuator.move_to_called);
    const auto state = service.snapshot();
    TEST_ASSERT_EQUAL(device_common::MotorMainState::Fault, state.main_state);
    TEST_ASSERT_TRUE((state.errors & device_common::kMotorErrorSafetyUnavailable) != 0);
}

TEST_CASE("motor service sends canonical position to actuator", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());

    MotorFeedback feedback;
    feedback.position_valid = true;
    feedback.position100ths = 0;
    feedback.safety.available = true;
    feedback.safety.observed_at_ms = 150;
    feedback.safety.limits_valid = true;
    feedback.safety.protection_valid = true;
    service.updateFeedback(feedback);

    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted,
                      service.submit(setPositionCommand("id-1", 100), 200, true));
    TEST_ASSERT_TRUE(actuator.move_to_called);
    const auto state = service.snapshot();
    TEST_ASSERT_EQUAL_UINT32(2500, state.target_position100ths);
    TEST_ASSERT_EQUAL(device_common::MotorMainState::Opening,
                      state.main_state);
}

TEST_CASE("endpoint movement waits for a known position", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());

    MotorFeedback feedback;
    feedback.safety.available = true;
    feedback.safety.limits_valid = true;
    feedback.safety.protection_valid = true;
    service.updateFeedback(feedback);

    device_common::MotorCommand command;
    command.action = device_common::MotorCommandAction::Open;
    TEST_ASSERT_EQUAL(MotorCommandResult::PositionUnknown,
                      service.submit(command, 0, false));
    TEST_ASSERT_FALSE(actuator.forward_called);
}

TEST_CASE("pulse-only mode rejects unbounded calibration", "[service]")
{
    FakeMotorActuator actuator;
    MotorServiceConfig config;
    config.homing_supported = false;
    MotorService service(actuator, config);
    TEST_ASSERT_TRUE(service.begin());

    MotorFeedback feedback;
    feedback.position_valid = true;
    feedback.safety.available = true;
    feedback.safety.limits_valid = true;
    feedback.safety.protection_valid = true;
    service.updateFeedback(feedback);

    device_common::MotorCommand command;
    command.action = device_common::MotorCommandAction::Calibrate;
    TEST_ASSERT_EQUAL(MotorCommandResult::InvalidCommand,
                      service.submit(command, 0, false));
    TEST_ASSERT_FALSE(actuator.backward_called);
}

TEST_CASE("motor service rejects duplicate remote command", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());

    MotorFeedback feedback;
    feedback.position_valid = true;
    feedback.safety.available = true;
    feedback.safety.observed_at_ms = 150;
    feedback.safety.limits_valid = true;
    feedback.safety.protection_valid = true;
    service.updateFeedback(feedback);

    const auto command = setPositionCommand("id-1", 100);
    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted,
                      service.submit(command, 200, true));
    TEST_ASSERT_EQUAL(MotorCommandResult::DuplicateCommand,
                      service.submit(command, 300, true));
}

TEST_CASE("motor service exposes ventilating state", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());

    MotorFeedback feedback;
    feedback.position_valid = true;
    feedback.position100ths = 0;
    feedback.safety.available = true;
    feedback.safety.observed_at_ms = 0;
    feedback.safety.limits_valid = true;
    feedback.safety.protection_valid = true;
    service.updateFeedback(feedback);

    device_common::MotorCommand command;
    command.action = device_common::MotorCommandAction::Ventilate;
    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted,
                      service.submit(command, 0, false));
    TEST_ASSERT_TRUE(actuator.move_to_called);
    TEST_ASSERT_EQUAL(device_common::MotorMainState::Ventilating,
                      service.snapshot().main_state);
}

TEST_CASE("motor service rejects stale safety feedback", "[service]")
{
    FakeMotorActuator actuator;
    MotorServiceConfig config;
    config.safety_stale_after_ms = 100;
    MotorService service(actuator, config);
    TEST_ASSERT_TRUE(service.begin());

    MotorFeedback feedback;
    feedback.position_valid = true;
    feedback.safety.available = true;
    feedback.safety.observed_at_ms = 100;
    feedback.safety.limits_valid = true;
    feedback.safety.protection_valid = true;
    service.updateFeedback(feedback);

    TEST_ASSERT_EQUAL(MotorCommandResult::SafetyUnavailable,
                      service.submit(setPositionCommand("stale", 300), 300, true));
    TEST_ASSERT_FALSE(actuator.move_to_called);
}

TEST_CASE("active protection blocks movement and stops immediately", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());

    MotorFeedback feedback;
    feedback.position_valid = true;
    feedback.safety.available = true;
    feedback.safety.limits_valid = true;
    feedback.safety.protection_valid = true;
    feedback.safety.protection_active = true;
    feedback.safety.protection_state = 1u << 16;
    service.updateFeedback(feedback);

    TEST_ASSERT_TRUE(actuator.emergency_stop_called);
    TEST_ASSERT_EQUAL(MotorCommandResult::SafetyUnavailable,
                      service.submit(setPositionCommand("protected", 0), 0, true));
}

TEST_CASE("closed limit establishes the homed zero position", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());

    MotorFeedback feedback;
    feedback.position_valid = true;
    feedback.position100ths = 0;
    feedback.safety.available = true;
    feedback.safety.limits_valid = true;
    feedback.safety.close_limit_active = true;
    feedback.safety.protection_valid = true;
    service.updateFeedback(feedback);

    const auto state = service.snapshot();
    TEST_ASSERT_TRUE(actuator.emergency_stop_called);
    TEST_ASSERT_EQUAL_INT32(0, actuator.current_position_steps);
    TEST_ASSERT_TRUE(state.position_valid);
    TEST_ASSERT_EQUAL_UINT32(0, state.current_position100ths);
    TEST_ASSERT_EQUAL(device_common::CalibrationState::Complete,
                      state.calibration_state);
}

TEST_CASE("open and close use bounded software endpoints", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());

    MotorFeedback feedback;
    feedback.position_valid = true;
    feedback.safety.available = true;
    feedback.safety.limits_valid = true;
    feedback.safety.protection_valid = true;
    service.updateFeedback(feedback);

    device_common::MotorCommand command;
    command.action = device_common::MotorCommandAction::Open;
    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted, service.submit(command, 0, false));
    TEST_ASSERT_TRUE(actuator.move_to_called);
    TEST_ASSERT_EQUAL_INT32(1600, actuator.last_target_steps);
    TEST_ASSERT_EQUAL(device_common::MotorMainState::Opening,
                      service.snapshot().main_state);

    feedback.position100ths = device_common::kPositionMax100ths;
    service.updateFeedback(feedback);
    TEST_ASSERT_EQUAL(device_common::MotorMainState::Idle,
                      service.snapshot().main_state);

    command.action = device_common::MotorCommandAction::Close;
    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted, service.submit(command, 0, false));
    TEST_ASSERT_EQUAL_INT32(0, actuator.last_target_steps);
    TEST_ASSERT_EQUAL(device_common::MotorMainState::Closing,
                      service.snapshot().main_state);

    command.action = device_common::MotorCommandAction::Calibrate;
    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted, service.submit(command, 0, false));
    TEST_ASSERT_EQUAL(device_common::CalibrationState::InProgress,
                      service.snapshot().calibration_state);

    command.action = device_common::MotorCommandAction::Stop;
    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted, service.submit(command, 0, false));
    const auto state = service.snapshot();
    TEST_ASSERT_TRUE(actuator.stop_called);
    TEST_ASSERT_EQUAL(device_common::MotorMainState::Stopping, state.main_state);
    TEST_ASSERT_EQUAL_UINT64(6, state.revision);
}
