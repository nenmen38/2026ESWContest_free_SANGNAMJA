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

    void stop() override { stop_called = true; }

    bool initialized = false;
    bool move_to_called = false;
    bool stop_called = false;
    int32_t last_target_steps = 0;
};

device_common::MotorCommand command(device_common::MotorCommandAction action,
                                    std::string_view id = "id-1")
{
    device_common::MotorCommand value;
    value.metadata.command_id = id;
    value.metadata.received_at_ms = 100;
    value.metadata.ttl_ms = 1000;
    value.action = action;
    value.position100ths = 2500;
    return value;
}

MotorFeedback freshPosition(uint32_t position100ths = 0,
                             uint64_t observed_at_ms = 100)
{
    MotorFeedback feedback;
    feedback.position_valid = true;
    feedback.position100ths = position100ths;
    feedback.observed_at_ms = observed_at_ms;
    return feedback;
}

}  // namespace

TEST_CASE("motor service rejects commands without fresh pulse feedback", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());

    const auto result = service.submit(command(device_common::MotorCommandAction::Open), 200, true);
    TEST_ASSERT_EQUAL(MotorCommandResult::FeedbackUnavailable, result);
    TEST_ASSERT_FALSE(actuator.move_to_called);
    TEST_ASSERT_TRUE((service.snapshot().errors & device_common::kMotorErrorFeedbackUnavailable) != 0);
}

TEST_CASE("pulse feedback initializes at the closed endpoint", "[service]")
{
    FakeMotorActuator actuator;
    MotorServiceConfig config;
    config.max_steps = 19500;
    MotorService service(actuator, config);
    TEST_ASSERT_TRUE(service.begin());
    service.updateFeedback(freshPosition(0));
    TEST_ASSERT_EQUAL(device_common::MotorMainState::Idle,
                      service.snapshot().main_state);

    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted,
                      service.submit(command(device_common::MotorCommandAction::Open), 200, true));
    TEST_ASSERT_TRUE(actuator.move_to_called);
    TEST_ASSERT_EQUAL_INT32(19500, actuator.last_target_steps);

    service.updateFeedback(freshPosition(10000, 250));
    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted,
                      service.submit(command(device_common::MotorCommandAction::Close,
                                             "close-id"),
                                     300, true));
    TEST_ASSERT_EQUAL_INT32(0, actuator.last_target_steps);
}

TEST_CASE("pulse feedback maps intermediate position to a bounded target", "[service]")
{
    FakeMotorActuator actuator;
    MotorServiceConfig config;
    config.max_steps = 19500;
    MotorService service(actuator, config);
    TEST_ASSERT_TRUE(service.begin());
    service.updateFeedback(freshPosition(2500));

    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted,
                      service.submit(command(device_common::MotorCommandAction::SetPosition), 200, true));
    TEST_ASSERT_EQUAL_INT32(4875, actuator.last_target_steps);
    TEST_ASSERT_EQUAL_UINT32(2500, service.snapshot().target_position100ths);
}

TEST_CASE("stale pulse feedback blocks movement", "[service]")
{
    FakeMotorActuator actuator;
    MotorServiceConfig config;
    config.feedback_stale_after_ms = 100;
    MotorService service(actuator, config);
    TEST_ASSERT_TRUE(service.begin());
    service.updateFeedback(freshPosition(0, 100));

    TEST_ASSERT_EQUAL(MotorCommandResult::FeedbackUnavailable,
                      service.submit(command(device_common::MotorCommandAction::Close), 300, true));
    TEST_ASSERT_FALSE(actuator.move_to_called);
}

TEST_CASE("position commands outside the canonical range are rejected", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());
    service.updateFeedback(freshPosition());

    auto invalid = command(device_common::MotorCommandAction::SetPosition);
    invalid.position100ths = 10001;
    TEST_ASSERT_EQUAL(MotorCommandResult::InvalidCommand,
                      service.submit(invalid, 200, true));
    TEST_ASSERT_FALSE(actuator.move_to_called);
}

TEST_CASE("stop remains available without position feedback", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());

    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted,
                      service.submit(command(device_common::MotorCommandAction::Stop), 0, false));
    TEST_ASSERT_TRUE(actuator.stop_called);
}

TEST_CASE("remote commands are deduplicated", "[service]")
{
    FakeMotorActuator actuator;
    MotorService service(actuator);
    TEST_ASSERT_TRUE(service.begin());
    service.updateFeedback(freshPosition());

    const auto value = command(device_common::MotorCommandAction::SetPosition);
    TEST_ASSERT_EQUAL(MotorCommandResult::Accepted, service.submit(value, 200, true));
    TEST_ASSERT_EQUAL(MotorCommandResult::DuplicateCommand, service.submit(value, 300, true));
}
