#include "mqtt_adapter.hpp"

#include <array>
#include <cstdio>

#include "unity.h"

TEST_CASE("all motor MQTT actions parse", "[mqtt_adapter]")
{
    struct Case {
        const char* name;
        device_common::MotorCommandAction action;
    };
    constexpr std::array<Case, 6> cases{{
        {"open", device_common::MotorCommandAction::Open},
        {"close", device_common::MotorCommandAction::Close},
        {"stop", device_common::MotorCommandAction::Stop},
        {"ventilate", device_common::MotorCommandAction::Ventilate},
        {"set_position", device_common::MotorCommandAction::SetPosition},
        {"calibrate", device_common::MotorCommandAction::Calibrate},
    }};
    for (const auto& item : cases) {
        char json[160] = {};
        std::snprintf(json, sizeof(json),
                      "{\"commandId\":\"id-1\",\"action\":\"%s\",\"ttlMs\":1000,\"position100ths\":2500}",
                      item.name);
        ParsedMotorMqttCommand parsed;
        TEST_ASSERT_TRUE(parseMotorMqttCommand(json, 123, &parsed));
        TEST_ASSERT_EQUAL(item.action, parsed.command.action);
        TEST_ASSERT_EQUAL_UINT64(123, parsed.command.metadata.received_at_ms);
        TEST_ASSERT_EQUAL_STRING("id-1", parsed.command_id.data());
    }
}

TEST_CASE("set position requires a bounded position", "[mqtt_adapter]")
{
    ParsedMotorMqttCommand command;
    TEST_ASSERT_FALSE(parseMotorMqttCommand(
        "{\"commandId\":\"id\",\"action\":\"set_position\",\"ttlMs\":1000}", 0, &command));
    TEST_ASSERT_FALSE(parseMotorMqttCommand(
        "{\"commandId\":\"id\",\"action\":\"set_position\",\"ttlMs\":1000,\"position100ths\":10001}",
        0, &command));
}

TEST_CASE("motor MQTT parser rejects malformed required fields", "[mqtt_adapter]")
{
    ParsedMotorMqttCommand command;
    TEST_ASSERT_FALSE(parseMotorMqttCommand("{}", 0, &command));
    TEST_ASSERT_FALSE(parseMotorMqttCommand(
        "{\"commandId\":\"\",\"action\":\"stop\",\"ttlMs\":1000}", 0, &command));
    TEST_ASSERT_FALSE(parseMotorMqttCommand(
        "{\"commandId\":\"id\",\"action\":\"unknown\",\"ttlMs\":1000}", 0, &command));
    TEST_ASSERT_FALSE(parseMotorMqttCommand(
        "{\"commandId\":\"id\",\"action\":\"stop\",\"ttlMs\":0}", 0, &command));
}

TEST_CASE("motor MQTT parser validates schema version type and value", "[mqtt_adapter]")
{
    ParsedMotorMqttCommand command;
    TEST_ASSERT_TRUE(parseMotorMqttCommand(
        "{\"schemaVersion\":1,\"commandId\":\"id\",\"action\":\"stop\",\"ttlMs\":1000}",
        0, &command));
    TEST_ASSERT_FALSE(parseMotorMqttCommand(
        "{\"schemaVersion\":\"1\",\"commandId\":\"id\",\"action\":\"stop\",\"ttlMs\":1000}",
        0, &command));
    TEST_ASSERT_FALSE(parseMotorMqttCommand(
        "{\"schemaVersion\":99,\"commandId\":\"id\",\"action\":\"stop\",\"ttlMs\":1000}",
        0, &command));
}
