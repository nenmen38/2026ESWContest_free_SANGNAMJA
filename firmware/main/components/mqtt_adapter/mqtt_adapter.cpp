#include "mqtt_adapter.hpp"

#include <cstring>

#include "esp_log.h"
#include "esp_timer.h"
#include "json_generator.h"
#include "json_parser.h"

namespace {

constexpr const char* kTag = "motor_mqtt";
constexpr int kSchemaVersion = 1;

bool actionFromName(const char* name, device_common::MotorCommandAction* output)
{
    if (name == nullptr || output == nullptr) return false;
    if (std::strcmp(name, "open") == 0) *output = device_common::MotorCommandAction::Open;
    else if (std::strcmp(name, "close") == 0) *output = device_common::MotorCommandAction::Close;
    else if (std::strcmp(name, "stop") == 0) *output = device_common::MotorCommandAction::Stop;
    else if (std::strcmp(name, "ventilate") == 0) *output = device_common::MotorCommandAction::Ventilate;
    else if (std::strcmp(name, "set_position") == 0) *output = device_common::MotorCommandAction::SetPosition;
    else if (std::strcmp(name, "calibrate") == 0) *output = device_common::MotorCommandAction::Calibrate;
    else return false;
    return true;
}

bool finishJson(json_gen_str_t* generator,
                bool valid,
                std::size_t capacity,
                std::size_t* output_length)
{
    const int bytes = json_gen_str_end(generator);
    if (!valid || bytes <= 0 || static_cast<std::size_t>(bytes) > capacity) return false;
    *output_length = static_cast<std::size_t>(bytes - 1);
    return true;
}

bool copyView(std::string_view value, char* output, std::size_t capacity)
{
    if (output == nullptr || capacity == 0 || value.size() >= capacity) return false;
    std::memcpy(output, value.data(), value.size());
    output[value.size()] = '\0';
    return true;
}

bool hasTopLevelField(const jparse_ctx_t& parser, std::string_view name)
{
    for (int index = 1; index < parser.num_tokens; ++index) {
        const json_tok_t& token = parser.tokens[index];
        if (token.parent == 0 && token.type == JSMN_STRING &&
            token.end - token.start == static_cast<int>(name.size()) &&
            std::memcmp(parser.js + token.start, name.data(), name.size()) == 0) {
            return true;
        }
    }
    return false;
}

}  // namespace

bool parseMotorMqttCommand(std::string_view payload,
                           uint64_t received_at_ms,
                           ParsedMotorMqttCommand* output)
{
    if (payload.empty() || payload.size() > 512 || output == nullptr) return false;

    json_tok_t tokens[24] = {};
    jparse_ctx_t parser = {};
    if (json_parse_start_static(&parser, payload.data(), static_cast<int>(payload.size()),
                                tokens, 24) != OS_SUCCESS ||
        tokens[0].type != JSMN_OBJECT) {
        return false;
    }

    char action[20] = {};
    int64_t ttl = 0;
    int schema_version = kSchemaVersion;
    const int schema_result = json_obj_get_int(&parser, "schemaVersion", &schema_version);
    const bool schema_present = hasTopLevelField(parser, "schemaVersion");
    bool valid = ((!schema_present && schema_result != OS_SUCCESS) ||
                  (schema_result == OS_SUCCESS && schema_version == kSchemaVersion)) &&
                 json_obj_get_string(&parser, "commandId", output->command_id.data(),
                                     output->command_id.size()) == OS_SUCCESS &&
                 json_obj_get_string(&parser, "action", action, sizeof(action)) == OS_SUCCESS &&
                 json_obj_get_int64(&parser, "ttlMs", &ttl) == OS_SUCCESS &&
                 ttl >= 1 && ttl <= UINT32_MAX;

    device_common::MotorCommand parsed;
    valid = valid && actionFromName(action, &parsed.action);
    if (valid && parsed.action == device_common::MotorCommandAction::SetPosition) {
        int64_t position = -1;
        valid = json_obj_get_int64(&parser, "position100ths", &position) == OS_SUCCESS &&
                position >= device_common::kPositionMin100ths &&
                position <= device_common::kPositionMax100ths;
        if (valid) parsed.position100ths = static_cast<uint32_t>(position);
    }
    (void)json_parse_end_static(&parser);
    if (!valid) return false;

    const std::size_t command_id_length = std::strlen(output->command_id.data());
    if (command_id_length == 0 ||
        command_id_length > device_common::CommandDeduplicator::kMaxCommandIdLength) {
        return false;
    }
    parsed.metadata.command_id = std::string_view(output->command_id.data(), command_id_length);
    parsed.metadata.received_at_ms = received_at_ms;
    parsed.metadata.ttl_ms = static_cast<uint32_t>(ttl);
    output->command = parsed;
    return true;
}

bool MotorMqttAdapter::begin(MqttBridge& bridge,
                             const BrokerConnectionProfile& profile,
                             const char* device_id)
{
    if (bridge_ != nullptr) return true;
    bridge_ = &bridge;
    MqttBridgeConfig config;
    config.device_id = device_id;
    config.profile = profile;
    config.command_callback = &MotorMqttAdapter::commandCallback;
    config.command_context = this;
    if (!bridge.begin(config)) {
        bridge_ = nullptr;
        return false;
    }
    return true;
}

void MotorMqttAdapter::report(const device_common::MotorCanonicalState& state, bool force)
{
    std::lock_guard<std::mutex> lock(report_mutex_);
    if (bridge_ == nullptr || !bridge_->connected()) return;
    const uint32_t generation = bridge_->connectionGeneration();
    force = force || generation != last_connection_generation_;
    if (!force && state.revision == last_reported_revision_) return;

    char json[512] = {};
    json_gen_str_t generator;
    json_gen_str_start(&generator, json, sizeof(json), nullptr, nullptr);
    bool ok = json_gen_start_object(&generator) == 0;
    ok = ok && json_gen_obj_set_int(&generator, "schemaVersion", kSchemaVersion) == 0;
    ok = ok && json_gen_obj_set_string(&generator, "mainState", stateName(state.main_state)) == 0;
    ok = ok && json_gen_obj_set_int64(&generator, "currentPosition100ths", state.current_position100ths) == 0;
    ok = ok && json_gen_obj_set_int64(&generator, "targetPosition100ths", state.target_position100ths) == 0;
    ok = ok && json_gen_obj_set_bool(&generator, "positionValid", state.position_valid) == 0;
    ok = ok && json_gen_obj_set_int64(&generator, "errors", state.errors) == 0;
    ok = ok && json_gen_obj_set_string(&generator, "calibrationState", calibrationName(state.calibration_state)) == 0;
    ok = ok && json_gen_obj_set_int64(&generator, "protectionState", state.protection_state) == 0;
    ok = ok && json_gen_obj_set_int64(&generator, "revision", static_cast<int64_t>(state.revision)) == 0;
    ok = ok && json_gen_end_object(&generator) == 0;
    std::size_t length = 0;
    if (!finishJson(&generator, ok, sizeof(json), &length)) return;
    if (bridge_->publish(MqttTopicSuffix::State, std::string_view(json, length), true)) {
        last_reported_revision_ = state.revision;
        last_connection_generation_ = generation;
    }
}

void MotorMqttAdapter::commandCallback(std::string_view payload,
                                       bool retained,
                                       void* context)
{
    auto* adapter = static_cast<MotorMqttAdapter*>(context);
    if (adapter != nullptr) adapter->handleCommand(payload, retained);
}

void MotorMqttAdapter::handleCommand(std::string_view payload, bool retained)
{
    ParsedMotorMqttCommand parsed;
    const uint64_t now_ms = static_cast<uint64_t>(esp_timer_get_time() / 1000);
    if (retained) {
        publishResult(parseMotorMqttCommand(payload, now_ms, &parsed)
                          ? parsed.command.metadata.command_id : std::string_view(),
                      MotorCommandResult::InvalidCommand);
        return;
    }
    if (!parseMotorMqttCommand(payload, now_ms, &parsed)) {
        publishResult({}, MotorCommandResult::InvalidCommand);
        return;
    }
    const MotorCommandResult result = service_.submit(parsed.command, now_ms, true);
    publishResult(parsed.command.metadata.command_id, result);
    report(service_.snapshot(), true);
}

void MotorMqttAdapter::publishResult(std::string_view command_id,
                                     MotorCommandResult result)
{
    if (bridge_ == nullptr) return;
    char id[device_common::CommandDeduplicator::kMaxCommandIdLength + 1] = {};
    if (!copyView(command_id, id, sizeof(id))) return;
    char json[256] = {};
    json_gen_str_t generator;
    json_gen_str_start(&generator, json, sizeof(json), nullptr, nullptr);
    bool ok = json_gen_start_object(&generator) == 0;
    ok = ok && json_gen_obj_set_int(&generator, "schemaVersion", kSchemaVersion) == 0;
    ok = ok && json_gen_obj_set_string(&generator, "commandId", id) == 0;
    ok = ok && json_gen_obj_set_string(&generator, "result", resultName(result)) == 0;
    ok = ok && json_gen_obj_set_int64(&generator, "revision",
                                       static_cast<int64_t>(service_.snapshot().revision)) == 0;
    ok = ok && json_gen_end_object(&generator) == 0;
    std::size_t length = 0;
    if (finishJson(&generator, ok, sizeof(json), &length)) {
        (void)bridge_->publish(MqttTopicSuffix::Event, std::string_view(json, length), false);
    }
}

const char* MotorMqttAdapter::stateName(device_common::MotorMainState state)
{
    switch (state) {
    case device_common::MotorMainState::Unknown: return "unknown";
    case device_common::MotorMainState::Idle: return "idle";
    case device_common::MotorMainState::Opening: return "opening";
    case device_common::MotorMainState::Closing: return "closing";
    case device_common::MotorMainState::Ventilating: return "ventilating";
    case device_common::MotorMainState::Stopping: return "stopping";
    case device_common::MotorMainState::Calibrating: return "calibrating";
    case device_common::MotorMainState::Fault: return "fault";
    case device_common::MotorMainState::Protected: return "protected";
    }
    return "unknown";
}

const char* MotorMqttAdapter::calibrationName(device_common::CalibrationState state)
{
    switch (state) {
    case device_common::CalibrationState::Unknown: return "unknown";
    case device_common::CalibrationState::Required: return "required";
    case device_common::CalibrationState::InProgress: return "in_progress";
    case device_common::CalibrationState::Complete: return "complete";
    case device_common::CalibrationState::Failed: return "failed";
    }
    return "unknown";
}

const char* MotorMqttAdapter::resultName(MotorCommandResult result)
{
    switch (result) {
    case MotorCommandResult::Accepted: return "accepted";
    case MotorCommandResult::InvalidCommand: return "invalid_command";
    case MotorCommandResult::DuplicateCommand: return "duplicate_command";
    case MotorCommandResult::SafetyUnavailable: return "safety_unavailable";
    case MotorCommandResult::PositionUnknown: return "position_unknown";
    case MotorCommandResult::HardwareRejected: return "hardware_rejected";
    }
    return "invalid_command";
}
