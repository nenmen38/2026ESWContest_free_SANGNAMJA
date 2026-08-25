#include "status_led.hpp"

#include "driver/spi_master.h"
#include "esp_log.h"
#include "led_convert.h"
#include "led_indicator.h"
#include "led_indicator_strips.h"

namespace {

constexpr const char* kTag = "status_led";
constexpr uint8_t k = 32;

constexpr uint32_t packRgb(uint8_t red, uint8_t green, uint8_t blue)
{
    return (static_cast<uint32_t>(MAX_INDEX & 0x7F) << 25) |
           (static_cast<uint32_t>(red) << 16) |
           (static_cast<uint32_t>(green) << 8) |
           static_cast<uint32_t>(blue);
}

constexpr uint32_t packBrightness(uint8_t brightness)
{
    return (static_cast<uint32_t>(MAX_INDEX & 0x7F) << 25) |
           static_cast<uint32_t>(brightness);
}

#define RGB_STEP(r, g, b, ms) {LED_BLINK_RGB, packRgb(r, g, b), ms}
#define SOLID_STEPS(name, r, g, b) \
    static const blink_step_t name[] = {RGB_STEP(r, g, b, 1000), {LED_BLINK_LOOP, 0, 0}}
#define BLINK_STEPS(name, r, g, b, half_ms) \
    static const blink_step_t name[] = {RGB_STEP(r, g, b, half_ms), RGB_STEP(0, 0, 0, half_ms), {LED_BLINK_LOOP, 0, 0}}

SOLID_STEPS(kBlueSolid, 0, 0, k);
SOLID_STEPS(kPurpleSolid, 23, 0, k);
SOLID_STEPS(kCyanSolid, 0, k, k);
BLINK_STEPS(kYellowBlink, k, 23, 0, 350);
static const blink_step_t kAmberBreathe[] = {
    RGB_STEP(k, 10, 0, 0),
    {LED_BLINK_BREATHE, packBrightness(LED_STATE_OFF), 800},
    {LED_BLINK_BREATHE, packBrightness(LED_STATE_ON), 800},
    {LED_BLINK_LOOP, 0, 0},
};
BLINK_STEPS(kRedBlink, k, 0, 0, 200);
static const blink_step_t kBlueBreathe[] = {
    RGB_STEP(0, 0, k, 0),
    {LED_BLINK_BREATHE, packBrightness(LED_STATE_OFF), 900},
    {LED_BLINK_BREATHE, packBrightness(LED_STATE_ON), 900},
    {LED_BLINK_LOOP, 0, 0},
};
BLINK_STEPS(kCyanBlink, 0, k, k, 500);
SOLID_STEPS(kGreenSolid, 0, k, 0);
BLINK_STEPS(kMagentaFast, k, 0, k, 100);
SOLID_STEPS(kAmberSolid, k, 23, 0);
SOLID_STEPS(kOrangeSolid, k, 7, 0);
SOLID_STEPS(kRedSolid, k, 0, 0);
static const blink_step_t kStartupTest[] = {
    RGB_STEP(k, 0, 0, 200),
    RGB_STEP(0, k, 0, 200),
    RGB_STEP(0, 0, k, 200),
    RGB_STEP(0, 0, 0, 0),
    {LED_BLINK_STOP, 0, 0},
};

static blink_step_t const* kSignals[] = {
    kBlueSolid, kPurpleSolid, kCyanSolid, kYellowBlink, kAmberBreathe,
    kRedBlink, kBlueBreathe, kCyanBlink, kGreenSolid, kMagentaFast,
    kAmberSolid, kOrangeSolid, kRedSolid, kStartupTest,
};

static_assert(sizeof(kSignals) / sizeof(kSignals[0]) ==
              static_cast<std::size_t>(StatusLedSignal::Count));

}  // namespace

StatusLed::~StatusLed() { stop(); }

bool StatusLed::begin(const StatusLedConfig& config)
{
    if (initialized_.load()) return true;
    if (config.gpio < 0) return false;

    led_indicator_config_t indicator_config = {};
    indicator_config.blink_lists = kSignals;
    indicator_config.blink_list_num = static_cast<uint16_t>(StatusLedSignal::Count);

    led_indicator_strips_config_t strips = {};
    strips.led_strip_cfg.strip_gpio_num = config.gpio;
    strips.led_strip_cfg.max_leds = 1;
    strips.led_strip_cfg.led_model = LED_MODEL_WS2812;
    strips.led_strip_cfg.color_component_format =
        config.color_order == StatusLedColorOrder::Grb
            ? LED_STRIP_COLOR_COMPONENT_FMT_GRB
            : LED_STRIP_COLOR_COMPONENT_FMT_RGB;
    strips.led_strip_cfg.flags.invert_out = false;
    if (config.backend == StatusLedBackend::Rmt) {
        strips.led_strip_driver = LED_STRIP_RMT;
        strips.led_strip_rmt_cfg.clk_src = RMT_CLK_SRC_DEFAULT;
        strips.led_strip_rmt_cfg.resolution_hz = 10 * 1000 * 1000;
        strips.led_strip_rmt_cfg.mem_block_symbols = 0;
        strips.led_strip_rmt_cfg.flags.with_dma = false;
    } else {
        strips.led_strip_driver = LED_STRIP_SPI;
        strips.led_strip_spi_cfg.clk_src = SPI_CLK_SRC_DEFAULT;
        strips.led_strip_spi_cfg.spi_bus = SPI2_HOST;
        strips.led_strip_spi_cfg.flags.with_dma = false;
    }

    led_indicator_handle_t handle = nullptr;
    const esp_err_t error = led_indicator_new_strips_device(
        &indicator_config, &strips, &handle);
    if (error != ESP_OK) {
        ESP_LOGE(kTag, "initialization failed: %s", esp_err_to_name(error));
        return false;
    }
    indicator_ = handle;
    initialized_.store(true);
    if (config.startup_test) {
        active_signal_ = static_cast<int>(StatusLedSignal::StartupTest);
        (void)led_indicator_start(handle, active_signal_);
    }
    ESP_LOGI(kTag, "GPIO%d indicator initialized with %s backend",
             config.gpio, config.backend == StatusLedBackend::Rmt ? "RMT" : "SPI");
    return true;
}

void StatusLed::set(StatusLedLayer layer, StatusLedSignal signal)
{
    const auto layer_index = static_cast<std::size_t>(layer);
    if (!initialized_.load() || layer_index >= layers_.size() ||
        signal >= StatusLedSignal::Count) return;
    std::lock_guard<std::mutex> lock(mutex_);
    layers_[layer_index] = {signal, true};
    applyActiveLocked();
}

void StatusLed::clear(StatusLedLayer layer)
{
    const auto index = static_cast<std::size_t>(layer);
    if (!initialized_.load() || index >= layers_.size()) return;
    std::lock_guard<std::mutex> lock(mutex_);
    layers_[index].active = false;
    applyActiveLocked();
}

void StatusLed::clearAll()
{
    if (!initialized_.load()) return;
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& layer : layers_) layer.active = false;
    applyActiveLocked();
}

void StatusLed::updateConnectivity(bool network_ready,
                                   bool broker_connected,
                                   bool provisioning_active,
                                   uint64_t now_ms)
{
    const bool connected = network_ready && broker_connected;
    if (provisioning_active) {
        set(StatusLedLayer::Provisioning, StatusLedSignal::BlueBreathe);
    } else {
        clear(StatusLedLayer::Provisioning);
    }
    if (connected && !was_connected_) connected_at_ms_ = now_ms;
    if (!connected) {
        set(StatusLedLayer::Network, StatusLedSignal::CyanBlink);
    } else if (now_ms - connected_at_ms_ < 1000) {
        set(StatusLedLayer::Network, StatusLedSignal::GreenSolid);
    } else {
        clear(StatusLedLayer::Network);
    }
    was_connected_ = connected;
}

void StatusLed::applyActiveLocked()
{
    int desired = -1;
    for (std::size_t i = layers_.size(); i > 0; --i) {
        if (layers_[i - 1].active) {
            desired = static_cast<int>(layers_[i - 1].signal);
            break;
        }
    }
    if (desired == active_signal_) return;
    auto handle = static_cast<led_indicator_handle_t>(indicator_);
    if (active_signal_ >= 0) (void)led_indicator_stop(handle, active_signal_);
    active_signal_ = desired;
    if (active_signal_ >= 0) {
        (void)led_indicator_start(handle, active_signal_);
    } else {
        (void)led_indicator_set_rgb(handle, packRgb(0, 0, 0));
    }
}

void StatusLed::stop()
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto handle = static_cast<led_indicator_handle_t>(indicator_);
    if (handle != nullptr) {
        if (active_signal_ >= 0) (void)led_indicator_stop(handle, active_signal_);
        (void)led_indicator_set_rgb(handle, packRgb(0, 0, 0));
        (void)led_indicator_delete(handle);
    }
    indicator_ = nullptr;
    active_signal_ = -1;
    connected_at_ms_ = 0;
    was_connected_ = false;
    initialized_.store(false);
}
