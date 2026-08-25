#pragma once

#include <array>
#include <cstdint>
#include <mutex>
#include <string_view>

#include "device_common.hpp"
#include "mqtt_bridge.hpp"
#include "service.hpp"

struct ParsedMotorMqttCommand {
    device_common::MotorCommand command;
    std::array<char, device_common::CommandDeduplicator::kMaxCommandIdLength + 1> command_id{};
};

bool parseMotorMqttCommand(std::string_view payload,
                           uint64_t received_at_ms,
                           ParsedMotorMqttCommand* output);

class MotorMqttAdapter {
public:
    explicit MotorMqttAdapter(MotorService& service) : service_(service) {}

    bool begin(MqttBridge& bridge,
               const BrokerConnectionProfile& profile,
               const char* device_id);
    void report(const device_common::MotorCanonicalState& state, bool force = false);

private:
    static void commandCallback(std::string_view payload, bool retained, void* context);
    void handleCommand(std::string_view payload, bool retained);
    void publishResult(std::string_view command_id, MotorCommandResult result);
    static const char* stateName(device_common::MotorMainState state);
    static const char* calibrationName(device_common::CalibrationState state);
    static const char* resultName(MotorCommandResult result);

    MotorService& service_;
    MqttBridge* bridge_ = nullptr;
    uint64_t last_reported_revision_ = UINT64_MAX;
    uint32_t last_connection_generation_ = 0;
    std::mutex report_mutex_;
};
