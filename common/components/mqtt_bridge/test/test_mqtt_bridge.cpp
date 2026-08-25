#include "mqtt_bridge.hpp"

#include <cstring>

#include "unity.h"

namespace {

BrokerConnectionProfile settings(const char* uri = "mqtts://broker.example.com:8883")
{
    BrokerConnectionProfile value;
    std::strcpy(value.uri.data(), uri);
    std::strcpy(value.username.data(), "user");
    std::strcpy(value.password.data(), "secret");
    return value;
}

}  // namespace

TEST_CASE("MQTT settings require TLS and credentials", "[mqtt_bridge]")
{
    TEST_ASSERT_TRUE(settings().valid());
    TEST_ASSERT_FALSE(settings("mqtt://broker.example.com:1883").valid());
    auto empty_user = settings();
    empty_user.username[0] = '\0';
    TEST_ASSERT_FALSE(empty_user.valid());
    auto unterminated = settings();
    unterminated.password.fill('x');
    TEST_ASSERT_FALSE(unterminated.valid());
}

TEST_CASE("MQTT topic suffix contract is stable", "[mqtt_bridge]")
{
    TEST_ASSERT_EQUAL_STRING("presence", mqttTopicSuffixName(MqttTopicSuffix::Presence));
    TEST_ASSERT_EQUAL_STRING("state", mqttTopicSuffixName(MqttTopicSuffix::State));
    TEST_ASSERT_EQUAL_STRING("event", mqttTopicSuffixName(MqttTopicSuffix::Event));
    TEST_ASSERT_EQUAL_STRING("telemetry", mqttTopicSuffixName(MqttTopicSuffix::Telemetry));
    TEST_ASSERT_EQUAL_STRING("command", mqttTopicSuffixName(MqttTopicSuffix::Command));
    TEST_ASSERT_EQUAL_STRING("config", mqttTopicSuffixName(MqttTopicSuffix::Config));
}

TEST_CASE("MQTT topics use the v1 device contract", "[mqtt_bridge]")
{
    char topic[96] = {};
    TEST_ASSERT_TRUE(buildMqttTopic("motor-aabbccddeeff", MqttTopicSuffix::Command,
                                    topic, sizeof(topic)));
    TEST_ASSERT_EQUAL_STRING("v1/devices/motor-aabbccddeeff/command", topic);
    TEST_ASSERT_FALSE(buildMqttTopic("motor-aabbccddeeff", MqttTopicSuffix::Command,
                                     topic, 8));
}
