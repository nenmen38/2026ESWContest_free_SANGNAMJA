#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>

namespace device_common {

struct BrokerConnectionProfile {
    static constexpr std::size_t kMaxUriLength = 255;
    static constexpr std::size_t kMaxUsernameLength = 64;
    static constexpr std::size_t kMaxPasswordLength = 128;

    std::array<char, kMaxUriLength + 1> uri{};
    std::array<char, kMaxUsernameLength + 1> username{};
    std::array<char, kMaxPasswordLength + 1> password{};

    bool valid() const;
};

enum class DeviceConnectionState : uint8_t {
    Unprovisioned,
    WifiReady,
    BrokerConnecting,
    Online,
};

inline constexpr uint32_t kPositionMin100ths = 0;
inline constexpr uint32_t kPositionMax100ths = 10000;

inline constexpr uint32_t kMotorErrorSafetyUnavailable = 1u << 0;
inline constexpr uint32_t kMotorErrorPositionUnknown = 1u << 1;
inline constexpr uint32_t kMotorErrorHardwareRejected = 1u << 2;

enum class MotorCommandAction : uint8_t {
    Open,
    Close,
    Stop,
    Ventilate,
    SetPosition,
    Calibrate,
};

const char* motorCommandActionName(MotorCommandAction action);
bool motorCommandNeedsPosition(MotorCommandAction action);

struct CommandMetadata {
    std::string_view command_id;
    uint64_t received_at_ms = 0;
    uint32_t ttl_ms = 0;
};

struct MotorCommand {
    CommandMetadata metadata;
    MotorCommandAction action = MotorCommandAction::Stop;
    uint32_t position100ths = 0;
};

enum class CommandValidationResult : uint8_t {
    Ok,
    EmptyCommandId,
    CommandIdTooLong,
    UnsupportedAction,
    PositionRequired,
    PositionOutOfRange,
    InvalidTtl,
    Expired,
};

CommandValidationResult validateMotorCommand(const MotorCommand& command,
                                             uint64_t now_ms,
                                             bool require_ttl);

bool isPosition100thsValid(uint32_t position100ths);
bool isCommandExpired(const CommandMetadata& metadata, uint64_t now_ms);

/**
 * @brief Fixed-allocation command id cache for remote command idempotency.
 *
 * The cache copies command IDs so callers may pass a temporary payload
 * view. It is intentionally small and deterministic for embedded use.
 */
class CommandDeduplicator {
public:
    static constexpr std::size_t kCapacity = 8;
    static constexpr std::size_t kMaxCommandIdLength = 39;

    bool accept(std::string_view command_id, uint64_t now_ms, uint32_t ttl_ms);
    void clear();

private:
    struct Entry {
        std::array<char, kMaxCommandIdLength + 1> command_id{};
        std::size_t length = 0;
        uint64_t expires_at_ms = 0;
        bool occupied = false;
    };

    std::array<Entry, kCapacity> entries_{};
    std::size_t next_slot_ = 0;
};

/** Maps a canonical 0..10000 position to an inclusive step range. */
bool position100thsToSteps(uint32_t position100ths,
                           int32_t min_steps,
                           int32_t max_steps,
                           int32_t* out_steps);

/** Maps an inclusive step range back to canonical 0..10000 position. */
bool stepsToPosition100ths(int32_t steps,
                           int32_t min_steps,
                           int32_t max_steps,
                           uint32_t* out_position100ths);

enum class MotorMainState : uint8_t {
    Unknown,
    Idle,
    Opening,
    Closing,
    Ventilating,
    Stopping,
    Calibrating,
    Fault,
    Protected,
};

enum class CalibrationState : uint8_t {
    Unknown,
    Required,
    InProgress,
    Complete,
    Failed,
};

struct MotorCanonicalState {
    MotorMainState main_state = MotorMainState::Unknown;
    uint32_t current_position100ths = 0;
    uint32_t target_position100ths = 0;
    uint32_t errors = 0;
    CalibrationState calibration_state = CalibrationState::Unknown;
    uint32_t protection_state = 0;
    bool position_valid = false;
    uint64_t revision = 0;
};

struct SensorRawState {
    int32_t pm_status = 0;
    uint16_t pm_measurement_mode = 0;
    uint16_t pm_calibration = 0;

    uint16_t grimm_pm1_0 = 0;
    uint16_t grimm_pm2_5 = 0;
    uint16_t grimm_pm10 = 0;
    uint16_t tsi_pm1_0 = 0;
    uint16_t tsi_pm2_5 = 0;
    uint16_t tsi_pm10 = 0;

    uint16_t particles_0_3 = 0;
    uint16_t particles_0_5 = 0;
    uint16_t particles_1_0 = 0;
    uint16_t particles_2_5 = 0;
    uint16_t particles_5_0 = 0;
    uint16_t particles_10_0 = 0;

    int32_t bme_status = 0;
};

inline constexpr uint32_t kSensorErrorPm = 1u << 0;
inline constexpr uint32_t kSensorErrorBme = 1u << 1;

struct SensorNormalizedState {
    bool temperature_valid = false;
    float temperature_c = 0.0f;
    bool humidity_valid = false;
    float humidity_percent = 0.0f;
    bool pressure_valid = false;
    float pressure_hpa = 0.0f;
};

struct SensorCanonicalState {
    uint64_t timestamp_us = 0;
    bool pm_valid = false;
    bool bme_valid = false;
    SensorRawState raw;
    SensorNormalizedState normalized;
    uint32_t error_flags = 0;
    uint64_t revision = 0;
};

}  // namespace device_common
