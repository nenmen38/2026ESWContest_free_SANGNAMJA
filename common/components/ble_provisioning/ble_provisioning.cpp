#include "ble_provisioning.hpp"

#include <cstdio>
#include <cstring>

#include "button_gpio.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "iot_button.h"
#include "network_provisioning/manager.h"
#include "network_provisioning/scheme_ble.h"
#include "nvs_flash.h"
#include "sdkconfig.h"

static_assert(sizeof(CONFIG_DEVICE_PROV_POP) > 1,
              "CONFIG_DEVICE_PROV_POP must be injected by the device build");
static_assert(sizeof(CONFIG_DEVICE_MQTT_URI) > 1,
              "CONFIG_DEVICE_MQTT_URI must be injected by the device build");
static_assert(sizeof(CONFIG_DEVICE_MQTT_URI) <=
                  device_common::BrokerConnectionProfile::kMaxUriLength + 1,
              "CONFIG_DEVICE_MQTT_URI is too long");
static_assert(sizeof(CONFIG_DEVICE_MQTT_USERNAME) <=
                  device_common::BrokerConnectionProfile::kMaxUsernameLength + 1,
              "CONFIG_DEVICE_MQTT_USERNAME is too long");
static_assert(sizeof(CONFIG_DEVICE_MQTT_USERNAME) > 1,
              "CONFIG_DEVICE_MQTT_USERNAME must be injected by the device build");
static_assert(sizeof(CONFIG_DEVICE_MQTT_PASSWORD) <=
                  device_common::BrokerConnectionProfile::kMaxPasswordLength + 1,
              "CONFIG_DEVICE_MQTT_PASSWORD is too long");
static_assert(sizeof(CONFIG_DEVICE_MQTT_PASSWORD) > 1,
              "CONFIG_DEVICE_MQTT_PASSWORD must be injected by the device build");

namespace {

constexpr const char* kTag = "ble_provision";
BrokerConnectionProfile buildBrokerProfile()
{
    BrokerConnectionProfile profile;
    std::strcpy(profile.uri.data(), CONFIG_DEVICE_MQTT_URI);
    std::strcpy(profile.username.data(), CONFIG_DEVICE_MQTT_USERNAME);
    std::strcpy(profile.password.data(), CONFIG_DEVICE_MQTT_PASSWORD);
    return profile.valid() ? profile : BrokerConnectionProfile{};
}

esp_err_t initializeNvs()
{
    esp_err_t error = nvs_flash_init();
    if (error == ESP_ERR_NVS_NO_FREE_PAGES || error == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        error = nvs_flash_erase();
        if (error == ESP_OK) error = nvs_flash_init();
    }
    return error;
}

}  // namespace

BleProvisioningRuntime::~BleProvisioningRuntime()
{
    if (reset_button_ != nullptr) {
        (void)iot_button_delete(reset_button_);
        reset_button_ = nullptr;
    }
}

bool BleProvisioningRuntime::begin(const BleProvisioningRuntimeConfig& config)
{
    if (initialized_) return true;
    if (config.role == nullptr ||
        (std::strcmp(config.role, "motor") != 0 && std::strcmp(config.role, "sensor") != 0)) {
        return false;
    }
    config_ = config;

    uint8_t mac[6] = {};
    if (esp_read_mac(mac, ESP_MAC_WIFI_STA) != ESP_OK) return false;
    std::snprintf(device_id_.data(), device_id_.size(),
                  "%s-%02x%02x%02x%02x%02x%02x", config.role,
                  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    std::snprintf(service_name_.data(), service_name_.size(),
                  "PROV-%s-%02X%02X",
                  std::strcmp(config.role, "motor") == 0 ? "MOTOR" : "SENSOR",
                  mac[4], mac[5]);

    broker_profile_ = buildBrokerProfile();
    if (!broker_profile_.valid()) {
        ESP_LOGE(kTag, "factory MQTT profile is missing or invalid");
        return false;
    }
    profile_ready_.store(true);
    if (!initializePlatform() || !initializeManager()) return false;

    bool wifi_provisioned = false;
    if (network_prov_mgr_is_wifi_provisioned(&wifi_provisioned) != ESP_OK) return false;
    const bool started = wifi_provisioned
        ? (network_prov_mgr_deinit() == ESP_OK && connectStoredWifi())
        : startProvisioning();
    if (!started || !initializeResetButton()) return false;
    initialized_ = true;
    return true;
}

bool BleProvisioningRuntime::initializePlatform()
{
    if (initializeNvs() != ESP_OK || esp_netif_init() != ESP_OK) return false;
    const esp_err_t loop_error = esp_event_loop_create_default();
    if (loop_error != ESP_OK && loop_error != ESP_ERR_INVALID_STATE) return false;
    if (esp_event_handler_register(WIFI_EVENT, WIFI_EVENT_STA_DISCONNECTED,
                                   &BleProvisioningRuntime::systemEventHandler, this) != ESP_OK ||
        esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                   &BleProvisioningRuntime::systemEventHandler, this) != ESP_OK) {
        return false;
    }
    if (esp_netif_create_default_wifi_sta() == nullptr) return false;
    wifi_init_config_t wifi_config = WIFI_INIT_CONFIG_DEFAULT();
    return esp_wifi_init(&wifi_config) == ESP_OK;
}

bool BleProvisioningRuntime::initializeManager()
{
    network_prov_mgr_config_t manager = {};
    manager.scheme = network_prov_scheme_ble;
    manager.scheme_event_handler = NETWORK_PROV_SCHEME_BLE_EVENT_HANDLER_FREE_BTDM;
    manager.app_event_handler.event_cb = &BleProvisioningRuntime::managerEventHandler;
    manager.app_event_handler.user_data = this;
    manager.network_prov_wifi_conn_cfg.wifi_conn_attempts = 5;
    return network_prov_mgr_init(manager) == ESP_OK;
}

bool BleProvisioningRuntime::startProvisioning()
{
    static const char* capabilities[] = {nullptr};
    if (network_prov_mgr_set_app_info("esw", "2", capabilities, 0) != ESP_OK ||
        network_prov_mgr_start_provisioning(NETWORK_PROV_SECURITY_1,
                                            CONFIG_DEVICE_PROV_POP,
                                            service_name_.data(), nullptr) != ESP_OK) {
        return false;
    }
    provisioning_active_.store(true);
    ESP_LOGI(kTag, "BLE Wi-Fi provisioning ready: service=%s security=1 protocol=2",
             service_name_.data());
    return true;
}

bool BleProvisioningRuntime::connectStoredWifi()
{
    if (esp_wifi_set_mode(WIFI_MODE_STA) != ESP_OK || esp_wifi_start() != ESP_OK) return false;
    return esp_wifi_connect() == ESP_OK;
}

bool BleProvisioningRuntime::getBrokerProfile(BrokerConnectionProfile* output) const
{
    if (output == nullptr || !profile_ready_.load()) return false;
    *output = broker_profile_;
    return true;
}

device_common::DeviceConnectionState BleProvisioningRuntime::connectionState() const
{
    if (!profile_ready_.load()) return device_common::DeviceConnectionState::Unprovisioned;
    return network_ready_.load() ? device_common::DeviceConnectionState::WifiReady
                                 : device_common::DeviceConnectionState::Unprovisioned;
}

void BleProvisioningRuntime::managerEventHandler(
    void* context, network_prov_cb_event_t event_id, void* event_data)
{
    static_cast<BleProvisioningRuntime*>(context)->handleManagerEvent(event_id, event_data);
}

void BleProvisioningRuntime::handleManagerEvent(network_prov_cb_event_t event_id, void*)
{
    if (event_id == NETWORK_PROV_WIFI_CRED_FAIL) {
        network_ready_.store(false);
        (void)network_prov_mgr_reset_wifi_sm_state_on_failure();
    } else if (event_id == NETWORK_PROV_END) {
        provisioning_active_.store(false);
        (void)network_prov_mgr_deinit();
    }
}

void BleProvisioningRuntime::systemEventHandler(
    void* context, const char* event_base, int32_t event_id, void*)
{
    static_cast<BleProvisioningRuntime*>(context)->handleSystemEvent(event_base, event_id);
}

void BleProvisioningRuntime::handleSystemEvent(const char* event_base, int32_t event_id)
{
    if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        network_ready_.store(profile_ready_.load());
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        network_ready_.store(false);
        if (!provisioning_active_.load()) (void)esp_wifi_connect();
    }
}

bool BleProvisioningRuntime::initializeResetButton()
{
    button_config_t button = {};
    button.long_press_time = CONFIG_DEVICE_PROV_RESET_HOLD_MS;
    button_gpio_config_t gpio = {};
    gpio.gpio_num = CONFIG_DEVICE_PROV_RESET_GPIO;
    gpio.active_level = 0;
    gpio.enable_power_save = false;
    gpio.disable_pull = false;
    if (iot_button_new_gpio_device(&button, &gpio, &reset_button_) != ESP_OK) {
        return false;
    }
    if (iot_button_register_cb(reset_button_, BUTTON_LONG_PRESS_START, nullptr,
                               &BleProvisioningRuntime::longPressStart, this) != ESP_OK ||
        iot_button_register_cb(reset_button_, BUTTON_LONG_PRESS_UP, nullptr,
                               &BleProvisioningRuntime::longPressUp, this) != ESP_OK) {
        (void)iot_button_delete(reset_button_);
        reset_button_ = nullptr;
        return false;
    }
    return true;
}

void BleProvisioningRuntime::longPressStart(void*, void* context)
{
    auto* runtime = static_cast<BleProvisioningRuntime*>(context);
    if (runtime != nullptr) runtime->handleLongPressStart();
}

void BleProvisioningRuntime::longPressUp(void* button, void* context)
{
    auto* runtime = static_cast<BleProvisioningRuntime*>(context);
    if (runtime != nullptr) runtime->handleLongPressUp(static_cast<button_handle_t>(button));
}

void BleProvisioningRuntime::handleLongPressStart()
{
    if (reset_committed_.load() || reset_armed_.exchange(true)) return;
    if (config_.reset_callback != nullptr &&
        !config_.reset_callback(config_.reset_context)) {
        reset_armed_.store(false);
        ESP_LOGE(kTag, "reset refused because device could not enter a safe state");
    }
}

void BleProvisioningRuntime::handleLongPressUp(button_handle_t button)
{
    if (!reset_armed_.exchange(false) || reset_committed_.exchange(true)) return;
    if (button == nullptr || iot_button_get_key_level(button) != BUTTON_INACTIVE) {
        reset_committed_.store(false);
        ESP_LOGE(kTag, "reset release was not stable");
        return;
    }
    if (!clearProvisioning()) {
        reset_committed_.store(false);
        if (config_.reset_failure_callback != nullptr) {
            config_.reset_failure_callback(config_.reset_context);
        }
        ESP_LOGE(kTag, "provisioning reset failed; keeping the device running");
        return;
    }
    esp_restart();
}

bool BleProvisioningRuntime::clearProvisioning()
{
    return network_prov_mgr_reset_wifi_provisioning() == ESP_OK;
}
