#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <mutex>

enum class StatusLedLayer : uint8_t {
    Device,
    Network,
    Provisioning,
    Resetting,
    Fault,
    Count,
};

enum class StatusLedSignal : uint8_t {
    BlueSolid,
    PurpleSolid,
    CyanSolid,
    YellowBlink,
    AmberBreathe,
    RedBlink,
    BlueBreathe,
    CyanBlink,
    GreenSolid,
    MagentaFast,
    AmberSolid,
    OrangeSolid,
    RedSolid,
    StartupTest,
    Count,
};

enum class StatusLedBackend : uint8_t { Rmt, Spi };
enum class StatusLedColorOrder : uint8_t { Grb, Rgb };

struct StatusLedConfig {
    int gpio = 8;
    StatusLedBackend backend = StatusLedBackend::Rmt;
    StatusLedColorOrder color_order = StatusLedColorOrder::Grb;
    bool startup_test = true;
};

/** Thin domain facade over espressif/led_indicator. */
class StatusLed {
public:
    StatusLed() = default;
    ~StatusLed();

    StatusLed(const StatusLed&) = delete;
    StatusLed& operator=(const StatusLed&) = delete;

    bool begin(const StatusLedConfig& config = StatusLedConfig());
    void set(StatusLedLayer layer, StatusLedSignal signal);
    void clear(StatusLedLayer layer);
    void clearAll();
    void updateConnectivity(bool network_ready,
                            bool broker_connected,
                            bool provisioning_active,
                            uint64_t now_ms);
    void stop();

    bool initialized() const { return initialized_.load(); }

private:
    struct LayerState {
        StatusLedSignal signal = StatusLedSignal::BlueSolid;
        bool active = false;
    };

    void applyActiveLocked();

    std::array<LayerState, static_cast<std::size_t>(StatusLedLayer::Count)> layers_{};
    std::mutex mutex_;
    void* indicator_ = nullptr;
    int active_signal_ = -1;
    uint64_t connected_at_ms_ = 0;
    bool was_connected_ = false;
    std::atomic<bool> initialized_{false};
};
