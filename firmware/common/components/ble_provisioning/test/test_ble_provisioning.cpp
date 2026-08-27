#include "ble_provisioning.hpp"

#include <cstring>

#include "unity.h"

TEST_CASE("factory MQTT profile accepts complete secure settings", "[ble_provisioning]")
{
    BrokerConnectionProfile settings;
    std::strcpy(settings.uri.data(), "mqtts://broker.example.com:8883");
    std::strcpy(settings.username.data(), "device");
    std::strcpy(settings.password.data(), "secret");
    TEST_ASSERT_TRUE(settings.valid());
}

TEST_CASE("factory MQTT profile rejects missing credentials", "[ble_provisioning]")
{
    BrokerConnectionProfile settings;
    std::strcpy(settings.uri.data(), "mqtts://broker.example.com:8883");
    std::strcpy(settings.username.data(), "device");
    TEST_ASSERT_FALSE(settings.valid());
}
