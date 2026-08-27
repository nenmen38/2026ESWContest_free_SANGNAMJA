#include "device_common.hpp"

#include "unity.h"

TEST_CASE("position mapping preserves endpoints", "[device_common]")
{
    int32_t steps = 0;
    TEST_ASSERT_TRUE(device_common::position100thsToSteps(0, -100, 900, &steps));
    TEST_ASSERT_EQUAL_INT32(-100, steps);
    TEST_ASSERT_TRUE(device_common::position100thsToSteps(10000, -100, 900, &steps));
    TEST_ASSERT_EQUAL_INT32(900, steps);

    uint32_t position = 0;
    TEST_ASSERT_TRUE(device_common::stepsToPosition100ths(400, -100, 900, &position));
    TEST_ASSERT_EQUAL_UINT32(5000, position);
}

TEST_CASE("remote command validation rejects expired commands", "[device_common]")
{
    device_common::MotorCommand command;
    command.metadata.command_id = "test-command";
    command.metadata.received_at_ms = 1000;
    command.metadata.ttl_ms = 100;
    command.action = device_common::MotorCommandAction::SetPosition;
    command.position100ths = 2500;

    TEST_ASSERT_EQUAL(device_common::CommandValidationResult::Ok,
                      device_common::validateMotorCommand(command, 1099, true));
    TEST_ASSERT_EQUAL(device_common::CommandValidationResult::Expired,
                      device_common::validateMotorCommand(command, 1100, true));
}

TEST_CASE("command deduplicator accepts only once within ttl", "[device_common]")
{
    device_common::CommandDeduplicator deduplicator;
    TEST_ASSERT_TRUE(deduplicator.accept("id-1", 100, 1000));
    TEST_ASSERT_FALSE(deduplicator.accept("id-1", 200, 1000));
    TEST_ASSERT_TRUE(deduplicator.accept("id-1", 1100, 1000));
}
