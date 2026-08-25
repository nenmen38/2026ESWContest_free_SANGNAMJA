#pragma once

#include <array>
#include <atomic>
#include <cstdint>

#include "esp_err.h"
#include "esp_event.h"
#include "button_types.h"
#include "device_common.hpp"
#include "network_provisioning/manager.h"

using ProvisioningResetCallback = bool (*)(void* context);
using ProvisioningResetFailureCallback = void (*)(void* context);
using BrokerConnectionProfile = device_common::BrokerConnectionProfile;

struct BleProvisioningRuntimeConfig {
    const char* role = nullptr;
    ProvisioningResetCallback reset_callback = nullptr;
    ProvisioningResetFailureCallback reset_failure_callback = nullptr;
    void* reset_context = nullptr;
};

class BleProvisioningRuntime {
public:
    BleProvisioningRuntime() = default;
    ~BleProvisioningRuntime();

    BleProvisioningRuntime(const BleProvisioningRuntime&) = delete;
    BleProvisioningRuntime& operator=(const BleProvisioningRuntime&) = delete;

    bool begin(const BleProvisioningRuntimeConfig& config);
    bool networkReady() const { return network_ready_.load(); }
    bool brokerProfileReady() const { return profile_ready_.load(); }
    bool provisioningActive() const { return provisioning_active_.load(); }
    device_common::DeviceConnectionState connectionState() const;
    bool getBrokerProfile(BrokerConnectionProfile* output) const;
    const char* deviceId() const { return device_id_.data(); }
    const char* serviceName() const { return service_name_.data(); }

private:
    static void managerEventHandler(void* context,
                                    network_prov_cb_event_t event_id,
                                    void* event_data);
    static void systemEventHandler(void* context,
                                   const char* event_base,
                                   int32_t event_id,
                                   void* event_data);
    static void longPressStart(void* button, void* context);
    static void longPressUp(void* button, void* context);

    void handleManagerEvent(network_prov_cb_event_t event_id, void* event_data);
    void handleSystemEvent(const char* event_base, int32_t event_id);
    bool initializePlatform();
    bool initializeManager();
    bool startProvisioning();
    bool connectStoredWifi();
    bool initializeResetButton();
    bool clearProvisioning();
    void handleLongPressStart();
    void handleLongPressUp(button_handle_t button);

    BleProvisioningRuntimeConfig config_;
    BrokerConnectionProfile broker_profile_;
    std::array<char, 40> device_id_{};
    std::array<char, 32> service_name_{};
    std::atomic<bool> network_ready_{false};
    std::atomic<bool> profile_ready_{false};
    std::atomic<bool> provisioning_active_{false};
    std::atomic<bool> reset_armed_{false};
    std::atomic<bool> reset_committed_{false};
    button_handle_t reset_button_ = nullptr;
    bool initialized_ = false;
};
