#include "service.hpp"

#include <algorithm>

#include "esp_log.h"

namespace {

constexpr const char* kTag = "service";
constexpr std::string_view kLocalCommandId = "local";
constexpr std::size_t kRequestQueueDepth = 8;
constexpr uint32_t kWorkerStackSize = 4096;
constexpr UBaseType_t kWorkerPriority = 6;

}  // namespace

MotorService::MotorService(MotorActuator& motor, const MotorServiceConfig& config)
    : motor_(motor), config_(config)
{
}

MotorService::~MotorService()
{
    if (task_ != nullptr) {
        Request request;
        request.kind = RequestKind::Shutdown;
        (void)dispatch(&request);
        while (task_ != nullptr) vTaskDelay(1);
    }
    if (request_queue_ != nullptr) {
        vQueueDelete(request_queue_);
        request_queue_ = nullptr;
    }
}

bool MotorService::begin()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (initialized_) {
        return true;
    }
    if (config_.min_steps != 0 || config_.max_steps <= config_.min_steps ||
        config_.feedback_stale_after_ms == 0) {
        ESP_LOGE(kTag, "invalid motor service position configuration");
        return false;
    }
    if (!motor_.begin()) {
        return false;
    }
    state_ = device_common::MotorCanonicalState();
    state_.main_state = device_common::MotorMainState::Unknown;
    request_queue_ = xQueueCreate(kRequestQueueDepth, sizeof(Request*));
    if (request_queue_ == nullptr ||
        xTaskCreate(&MotorService::taskEntry, "motor_service", kWorkerStackSize,
                    this, kWorkerPriority, &task_) != pdPASS) {
        if (request_queue_ != nullptr) {
            vQueueDelete(request_queue_);
            request_queue_ = nullptr;
        }
        ESP_LOGE(kTag, "failed to create motor service worker");
        return false;
    }
    initialized_ = true;
    return true;
}

bool MotorService::positionFeedbackAvailable(uint64_t now_ms) const
{
    return feedback_.position_valid &&
           now_ms >= feedback_.observed_at_ms &&
           now_ms - feedback_.observed_at_ms <= config_.feedback_stale_after_ms;
}

void MotorService::updateStateFromMotion(uint32_t target_position100ths)
{
    state_.target_position100ths = target_position100ths;
    if (!feedback_.position_valid) {
        state_.main_state = device_common::MotorMainState::Unknown;
        return;
    }
    if (target_position100ths > feedback_.position100ths) {
        state_.main_state = device_common::MotorMainState::Opening;
    } else if (target_position100ths < feedback_.position100ths) {
        state_.main_state = device_common::MotorMainState::Closing;
    } else {
        state_.main_state = device_common::MotorMainState::Idle;
    }
}

MotorCommandResult MotorService::moveToPosition(uint32_t position100ths)
{
    if (!feedback_.position_valid) {
        return MotorCommandResult::PositionUnknown;
    }

    int32_t target_steps = 0;
    if (!device_common::position100thsToSteps(position100ths,
                                              config_.min_steps,
                                              config_.max_steps,
                                              &target_steps)) {
        return MotorCommandResult::InvalidCommand;
    }
    if (!motor_.moveTo(target_steps)) {
        return MotorCommandResult::HardwareRejected;
    }
    updateStateFromMotion(position100ths);
    return MotorCommandResult::Accepted;
}

MotorCommandResult MotorService::reject(MotorCommandResult result,
                                        uint32_t error,
                                        device_common::MotorMainState state)
{
    state_.errors |= error;
    state_.main_state = state;
    state_.revision++;
    return result;
}

MotorCommandResult MotorService::rejectFeedbackUnavailable()
{
    return reject(MotorCommandResult::FeedbackUnavailable,
                  device_common::kMotorErrorFeedbackUnavailable,
                  device_common::MotorMainState::Fault);
}

MotorCommandResult MotorService::processCommand(const device_common::MotorCommand& incoming,
                                                uint64_t now_ms,
                                                bool remote_command)
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!initialized_) {
        return MotorCommandResult::HardwareRejected;
    }

    device_common::MotorCommand command = incoming;
    if (!remote_command && command.metadata.command_id.empty()) {
        command.metadata.command_id = kLocalCommandId;
    }

    const auto validation = device_common::validateMotorCommand(
        command, now_ms, remote_command);
    if (validation != device_common::CommandValidationResult::Ok) {
        return MotorCommandResult::InvalidCommand;
    }
    if (remote_command && !deduplicator_.accept(command.metadata.command_id,
                                                now_ms,
                                                command.metadata.ttl_ms)) {
        return MotorCommandResult::DuplicateCommand;
    }

    switch (command.action) {
    case device_common::MotorCommandAction::Stop:
        motor_.stop();
        state_.main_state = device_common::MotorMainState::Stopping;
        state_.revision++;
        return MotorCommandResult::Accepted;

    case device_common::MotorCommandAction::SetPosition:
        if (!positionFeedbackAvailable(now_ms)) {
            return rejectFeedbackUnavailable();
        }
        state_.revision++;
        {
            const auto result = moveToPosition(command.position100ths);
            if (result == MotorCommandResult::PositionUnknown) {
                return reject(result, device_common::kMotorErrorPositionUnknown,
                              device_common::MotorMainState::Unknown);
            } else if (result == MotorCommandResult::HardwareRejected) {
                return reject(result, device_common::kMotorErrorHardwareRejected,
                              device_common::MotorMainState::Fault);
            }
            return result;
        }

    case device_common::MotorCommandAction::Open:
        if (!positionFeedbackAvailable(now_ms)) {
            return rejectFeedbackUnavailable();
        }
        if (!feedback_.position_valid) {
            return reject(MotorCommandResult::PositionUnknown,
                          device_common::kMotorErrorPositionUnknown,
                          device_common::MotorMainState::Unknown);
        }
        state_.revision++;
        return moveToPosition(device_common::kPositionMax100ths);

    case device_common::MotorCommandAction::Close:
        if (!positionFeedbackAvailable(now_ms)) {
            return rejectFeedbackUnavailable();
        }
        if (!feedback_.position_valid) {
            return reject(MotorCommandResult::PositionUnknown,
                          device_common::kMotorErrorPositionUnknown,
                          device_common::MotorMainState::Unknown);
        }
        state_.revision++;
        return moveToPosition(device_common::kPositionMin100ths);

    }

    return MotorCommandResult::InvalidCommand;
}

void MotorService::processFeedback(const MotorFeedback& feedback)
{
    std::lock_guard<std::mutex> lock(mutex_);
    feedback_ = feedback;
    state_.position_valid = feedback_.position_valid;
    if (feedback_.position_valid) {
        state_.current_position100ths = feedback_.position100ths;
    }
    if (feedback_.position_valid) {
        state_.errors &= ~device_common::kMotorErrorFeedbackUnavailable;
        state_.errors &= ~device_common::kMotorErrorPositionUnknown;
    } else {
        state_.main_state = device_common::MotorMainState::Unknown;
    }
    const bool reached_target = feedback_.position_valid &&
        feedback_.position100ths == state_.target_position100ths;
    if (reached_target &&
        (state_.main_state == device_common::MotorMainState::Opening ||
         state_.main_state == device_common::MotorMainState::Closing ||
         state_.main_state == device_common::MotorMainState::Unknown)) {
        state_.main_state = device_common::MotorMainState::Idle;
    }
    state_.revision++;
}

bool MotorService::dispatch(Request* request)
{
    if (request == nullptr || request_queue_ == nullptr || task_ == nullptr) return false;
    request->completion = xSemaphoreCreateBinaryStatic(&request->completion_storage);
    if (request->completion == nullptr ||
        xQueueSend(request_queue_, &request, portMAX_DELAY) != pdTRUE) return false;
    return xSemaphoreTake(request->completion, portMAX_DELAY) == pdTRUE;
}

MotorCommandResult MotorService::submit(const device_common::MotorCommand& command,
                                        uint64_t now_ms,
                                        bool remote_command)
{
    Request request;
    request.kind = RequestKind::Command;
    request.command = command;
    if (command.metadata.command_id.size() >= request.command_id.size()) {
        return MotorCommandResult::InvalidCommand;
    }
    std::copy(command.metadata.command_id.begin(), command.metadata.command_id.end(),
              request.command_id.begin());
    request.command_id[command.metadata.command_id.size()] = '\0';
    request.command.metadata.command_id = std::string_view(
        request.command_id.data(), command.metadata.command_id.size());
    request.now_ms = now_ms;
    request.remote_command = remote_command;
    return dispatch(&request) ? request.result : MotorCommandResult::HardwareRejected;
}

void MotorService::updateFeedback(const MotorFeedback& feedback)
{
    Request request;
    request.kind = RequestKind::Feedback;
    request.feedback = feedback;
    (void)dispatch(&request);
}

void MotorService::taskEntry(void* context)
{
    static_cast<MotorService*>(context)->taskLoop();
}

void MotorService::taskLoop()
{
    bool running = true;
    while (running) {
        Request* request = nullptr;
        if (xQueueReceive(request_queue_, &request, portMAX_DELAY) != pdTRUE || request == nullptr) {
            continue;
        }
        switch (request->kind) {
        case RequestKind::Command:
            request->result = processCommand(request->command, request->now_ms,
                                             request->remote_command);
            break;
        case RequestKind::Feedback:
            processFeedback(request->feedback);
            break;
        case RequestKind::Shutdown:
            motor_.stop();
            running = false;
            break;
        }
        xSemaphoreGive(request->completion);
    }
    task_ = nullptr;
    vTaskDelete(nullptr);
}

device_common::MotorCanonicalState MotorService::snapshot() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return state_;
}

MotorFeedback MotorService::feedbackSnapshot() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return feedback_;
}
