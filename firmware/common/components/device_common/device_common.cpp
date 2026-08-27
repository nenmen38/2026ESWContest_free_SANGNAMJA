#include "device_common.hpp"

#include <algorithm>
#include <cstring>
#include <limits>

namespace device_common {

namespace {

constexpr std::size_t kMaxCommandIdLength = CommandDeduplicator::kMaxCommandIdLength;

bool isKnownAction(MotorCommandAction action)
{
    switch (action) {
    case MotorCommandAction::Open:
    case MotorCommandAction::Close:
    case MotorCommandAction::Stop:
    case MotorCommandAction::Ventilate:
    case MotorCommandAction::SetPosition:
    case MotorCommandAction::Calibrate:
        return true;
    }
    return false;
}

bool safeAdd(uint64_t left, uint64_t right, uint64_t* out)
{
    if (out == nullptr || right > std::numeric_limits<uint64_t>::max() - left) {
        return false;
    }
    *out = left + right;
    return true;
}

bool terminatedWithin(const char* value, std::size_t capacity)
{
    return value != nullptr && std::memchr(value, '\0', capacity) != nullptr;
}

}  // namespace

bool BrokerConnectionProfile::valid() const
{
    if (!terminatedWithin(uri.data(), uri.size()) ||
        !terminatedWithin(username.data(), username.size()) ||
        !terminatedWithin(password.data(), password.size())) {
        return false;
    }
    constexpr std::string_view kScheme = "mqtts://";
    const std::string_view uri_view(uri.data());
    return uri_view.size() > kScheme.size() &&
           uri_view.substr(0, kScheme.size()) == kScheme &&
           username[0] != '\0' && password[0] != '\0';
}

const char* motorCommandActionName(MotorCommandAction action)
{
    switch (action) {
    case MotorCommandAction::Open:
        return "open";
    case MotorCommandAction::Close:
        return "close";
    case MotorCommandAction::Stop:
        return "stop";
    case MotorCommandAction::Ventilate:
        return "ventilate";
    case MotorCommandAction::SetPosition:
        return "set_position";
    case MotorCommandAction::Calibrate:
        return "calibrate";
    }
    return "unknown";
}

bool motorCommandNeedsPosition(MotorCommandAction action)
{
    return action == MotorCommandAction::SetPosition;
}

CommandValidationResult validateMotorCommand(const MotorCommand& command,
                                             uint64_t now_ms,
                                             bool require_ttl)
{
    if (command.metadata.command_id.empty()) {
        return CommandValidationResult::EmptyCommandId;
    }
    if (command.metadata.command_id.size() > kMaxCommandIdLength) {
        return CommandValidationResult::CommandIdTooLong;
    }
    if (!isKnownAction(command.action)) {
        return CommandValidationResult::UnsupportedAction;
    }
    if (motorCommandNeedsPosition(command.action) &&
        !isPosition100thsValid(command.position100ths)) {
        return CommandValidationResult::PositionOutOfRange;
    }
    if (require_ttl && command.metadata.ttl_ms == 0) {
        return CommandValidationResult::InvalidTtl;
    }
    if (command.metadata.ttl_ms != 0 && isCommandExpired(command.metadata, now_ms)) {
        return CommandValidationResult::Expired;
    }
    return CommandValidationResult::Ok;
}

bool isPosition100thsValid(uint32_t position100ths)
{
    return position100ths >= kPositionMin100ths &&
           position100ths <= kPositionMax100ths;
}

bool isCommandExpired(const CommandMetadata& metadata, uint64_t now_ms)
{
    if (metadata.ttl_ms == 0 || now_ms < metadata.received_at_ms) {
        return false;
    }
    return now_ms - metadata.received_at_ms >= metadata.ttl_ms;
}

bool CommandDeduplicator::accept(std::string_view command_id,
                                 uint64_t now_ms,
                                 uint32_t ttl_ms)
{
    if (command_id.empty() || command_id.size() > kMaxCommandIdLength || ttl_ms == 0) {
        return false;
    }

    uint64_t expires_at_ms = 0;
    if (!safeAdd(now_ms, ttl_ms, &expires_at_ms)) {
        return false;
    }

    for (Entry& entry : entries_) {
        if (!entry.occupied) {
            continue;
        }
        if (now_ms >= entry.expires_at_ms) {
            entry.occupied = false;
            continue;
        }
        if (entry.length == command_id.size() &&
            std::memcmp(entry.command_id.data(), command_id.data(), entry.length) == 0) {
            return false;
        }
    }

    Entry& entry = entries_[next_slot_];
    next_slot_ = (next_slot_ + 1) % entries_.size();
    std::copy(command_id.begin(), command_id.end(), entry.command_id.begin());
    entry.command_id[command_id.size()] = '\0';
    entry.length = command_id.size();
    entry.expires_at_ms = expires_at_ms;
    entry.occupied = true;
    return true;
}

void CommandDeduplicator::clear()
{
    for (Entry& entry : entries_) {
        entry = Entry{};
    }
    next_slot_ = 0;
}

bool position100thsToSteps(uint32_t position100ths,
                           int32_t min_steps,
                           int32_t max_steps,
                           int32_t* out_steps)
{
    if (out_steps == nullptr || !isPosition100thsValid(position100ths) ||
        max_steps < min_steps) {
        return false;
    }

    const int64_t range = static_cast<int64_t>(max_steps) - min_steps;
    const int64_t scaled = range * static_cast<int64_t>(position100ths);
    const int64_t rounded = (scaled + kPositionMax100ths / 2) / kPositionMax100ths;
    const int64_t result = static_cast<int64_t>(min_steps) + rounded;
    if (result < std::numeric_limits<int32_t>::min() ||
        result > std::numeric_limits<int32_t>::max()) {
        return false;
    }
    *out_steps = static_cast<int32_t>(result);
    return true;
}

bool stepsToPosition100ths(int32_t steps,
                           int32_t min_steps,
                           int32_t max_steps,
                           uint32_t* out_position100ths)
{
    if (out_position100ths == nullptr || max_steps <= min_steps ||
        steps < min_steps || steps > max_steps) {
        return false;
    }

    const int64_t numerator =
        (static_cast<int64_t>(steps) - min_steps) * kPositionMax100ths;
    const int64_t denominator = static_cast<int64_t>(max_steps) - min_steps;
    const int64_t rounded = (numerator + denominator / 2) / denominator;
    if (rounded < kPositionMin100ths || rounded > kPositionMax100ths) {
        return false;
    }
    *out_position100ths = static_cast<uint32_t>(rounded);
    return true;
}

}  // namespace device_common
