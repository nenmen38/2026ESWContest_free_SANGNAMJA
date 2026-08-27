#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <string_view>

#include "device_common.hpp"
#include "mqtt_client.h"

using BrokerConnectionProfile = device_common::BrokerConnectionProfile;

enum class MqttTopicSuffix : uint8_t {
    Presence,
    State,
    Event,
    Telemetry,
    Command,
    Config,
};

const char* mqttTopicSuffixName(MqttTopicSuffix suffix);
bool buildMqttTopic(std::string_view device_id,
                    MqttTopicSuffix suffix,
                    char* output,
                    std::size_t output_size);

using MqttCommandCallback = void (*)(std::string_view payload,
                                     bool retained,
                                     void* context);

struct MqttBridgeConfig {
    const char* device_id = nullptr;
    BrokerConnectionProfile profile;
    MqttCommandCallback command_callback = nullptr;
    void* command_context = nullptr;
};

class MqttBridge {
public:
    MqttBridge() = default;
    ~MqttBridge();

    MqttBridge(const MqttBridge&) = delete;
    MqttBridge& operator=(const MqttBridge&) = delete;

    bool begin(const MqttBridgeConfig& config);
    void stop();
    bool connected() const { return connected_.load(); }
    device_common::DeviceConnectionState connectionState() const
    {
        return connection_state_.load();
    }
    uint32_t connectionGeneration() const { return connection_generation_.load(); }

    bool publish(MqttTopicSuffix suffix, std::string_view payload, bool retained);
    bool buildTopic(MqttTopicSuffix suffix, char* output, std::size_t output_size) const;
    const char* deviceId() const { return device_id_.data(); }

private:
    static void eventHandler(void* handler_args,
                             esp_event_base_t base,
                             int32_t event_id,
                             void* event_data);
    void handleEvent(esp_mqtt_event_handle_t event);
    bool publishPresence(const char* status);

    esp_mqtt_client_handle_t client_ = nullptr;
    BrokerConnectionProfile profile_;
    std::array<char, 40> device_id_{};
    std::array<char, 96> command_topic_{};
    std::array<char, 96> presence_topic_{};
    MqttCommandCallback command_callback_ = nullptr;
    void* command_context_ = nullptr;
    std::atomic<bool> connected_{false};
    std::atomic<device_common::DeviceConnectionState> connection_state_{
        device_common::DeviceConnectionState::WifiReady};
    std::atomic<uint32_t> connection_generation_{0};
    mutable std::mutex publish_mutex_;
};
