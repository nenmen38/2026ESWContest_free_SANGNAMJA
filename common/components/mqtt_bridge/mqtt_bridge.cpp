#include "mqtt_bridge.hpp"

#include <cstdio>
#include <cstring>

#include "esp_crt_bundle.h"
#include "esp_log.h"
#include "mqtt5_client.h"

namespace {

constexpr const char* kTag = "mqtt_bridge";
constexpr const char* kTopicPrefix = "v1/devices";
constexpr const char* kOnlinePayload = "{\"status\":\"online\"}";
constexpr const char* kOfflinePayload = "{\"status\":\"offline\"}";

}  // namespace

const char* mqttTopicSuffixName(MqttTopicSuffix suffix)
{
    switch (suffix) {
    case MqttTopicSuffix::Presence: return "presence";
    case MqttTopicSuffix::State: return "state";
    case MqttTopicSuffix::Event: return "event";
    case MqttTopicSuffix::Telemetry: return "telemetry";
    case MqttTopicSuffix::Command: return "command";
    case MqttTopicSuffix::Config: return "config";
    }
    return "unknown";
}

bool buildMqttTopic(std::string_view device_id,
                    MqttTopicSuffix suffix,
                    char* output,
                    std::size_t output_size)
{
    if (device_id.empty() || output == nullptr || output_size == 0) return false;
    const int written = std::snprintf(output, output_size, "%s/%.*s/%s",
                                      kTopicPrefix, static_cast<int>(device_id.size()),
                                      device_id.data(), mqttTopicSuffixName(suffix));
    return written > 0 && static_cast<std::size_t>(written) < output_size;
}

MqttBridge::~MqttBridge()
{
    stop();
}

bool MqttBridge::buildTopic(MqttTopicSuffix suffix,
                            char* output,
                            std::size_t output_size) const
{
    if (output == nullptr || output_size == 0 || device_id_[0] == '\0') {
        return false;
    }
    return buildMqttTopic(device_id_.data(), suffix, output, output_size);
}

bool MqttBridge::begin(const MqttBridgeConfig& config)
{
    if (client_ != nullptr || config.device_id == nullptr ||
        config.device_id[0] == '\0' || !config.profile.valid()) {
        return client_ != nullptr;
    }
    if (std::strlen(config.device_id) >= device_id_.size()) {
        return false;
    }

    profile_ = config.profile;
    std::strcpy(device_id_.data(), config.device_id);
    command_callback_ = config.command_callback;
    command_context_ = config.command_context;
    if (!buildTopic(MqttTopicSuffix::Presence, presence_topic_.data(), presence_topic_.size()) ||
        !buildTopic(MqttTopicSuffix::Command, command_topic_.data(), command_topic_.size())) {
        return false;
    }

    esp_mqtt_client_config_t mqtt_config = {};
    mqtt_config.broker.address.uri = profile_.uri.data();
    mqtt_config.broker.verification.crt_bundle_attach = esp_crt_bundle_attach;
    mqtt_config.credentials.client_id = device_id_.data();
    mqtt_config.credentials.username = profile_.username.data();
    mqtt_config.credentials.authentication.password = profile_.password.data();
    mqtt_config.session.protocol_ver = MQTT_PROTOCOL_V_5;
    mqtt_config.session.disable_clean_session = false;
    mqtt_config.session.keepalive = 60;
    mqtt_config.session.last_will.topic = presence_topic_.data();
    mqtt_config.session.last_will.msg = kOfflinePayload;
    mqtt_config.session.last_will.msg_len = std::strlen(kOfflinePayload);
    mqtt_config.session.last_will.qos = 1;
    mqtt_config.session.last_will.retain = true;
    mqtt_config.network.disable_auto_reconnect = false;

    client_ = esp_mqtt_client_init(&mqtt_config);
    if (client_ == nullptr) {
        return false;
    }
    connection_state_.store(device_common::DeviceConnectionState::BrokerConnecting);

    esp_mqtt5_connection_property_config_t properties = {};
    properties.session_expiry_interval = 0;
    properties.maximum_packet_size = 4096;
    properties.receive_maximum = 8;
    properties.request_problem_info = true;
    properties.payload_format_indicator = true;
    properties.message_expiry_interval = 120;
    properties.content_type = "application/json";
    if (esp_mqtt5_client_set_connect_property(client_, &properties) != ESP_OK ||
        esp_mqtt_client_register_event(client_,
                                       static_cast<esp_mqtt_event_id_t>(ESP_EVENT_ANY_ID),
                                       &MqttBridge::eventHandler, this) != ESP_OK ||
        esp_mqtt_client_start(client_) != ESP_OK) {
        esp_mqtt_client_destroy(client_);
        client_ = nullptr;
        connection_state_.store(device_common::DeviceConnectionState::WifiReady);
        return false;
    }

    ESP_LOGI(kTag, "MQTT 5 client started for %s", device_id_.data());
    return true;
}

void MqttBridge::stop()
{
    std::lock_guard<std::mutex> lock(publish_mutex_);
    if (client_ == nullptr) {
        return;
    }
    if (connected_.load()) {
        (void)esp_mqtt_client_publish(client_, presence_topic_.data(),
                                      kOfflinePayload, 0, 1, true);
    }
    (void)esp_mqtt_client_stop(client_);
    (void)esp_mqtt_client_destroy(client_);
    client_ = nullptr;
    connected_.store(false);
    connection_state_.store(device_common::DeviceConnectionState::WifiReady);
}

bool MqttBridge::publish(MqttTopicSuffix suffix,
                         std::string_view payload,
                         bool retained)
{
    if (payload.empty() || !connected_.load()) {
        return false;
    }
    char topic[96] = {};
    if (!buildTopic(suffix, topic, sizeof(topic))) {
        return false;
    }

    std::lock_guard<std::mutex> lock(publish_mutex_);
    esp_mqtt5_publish_property_config_t properties = {};
    properties.payload_format_indicator = true;
    properties.content_type = "application/json";
    if (esp_mqtt5_client_set_publish_property(client_, &properties) != ESP_OK) {
        return false;
    }
    const int message_id = esp_mqtt_client_publish(
        client_, topic, payload.data(), static_cast<int>(payload.size()), 1, retained);
    return message_id >= 0;
}

bool MqttBridge::publishPresence(const char* status)
{
    return publish(MqttTopicSuffix::Presence,
                   std::strcmp(status, "online") == 0 ? kOnlinePayload : kOfflinePayload,
                   true);
}

void MqttBridge::eventHandler(void* handler_args,
                              esp_event_base_t,
                              int32_t,
                              void* event_data)
{
    auto* self = static_cast<MqttBridge*>(handler_args);
    if (self != nullptr && event_data != nullptr) {
        self->handleEvent(static_cast<esp_mqtt_event_handle_t>(event_data));
    }
}

void MqttBridge::handleEvent(esp_mqtt_event_handle_t event)
{
    switch (event->event_id) {
    case MQTT_EVENT_CONNECTED:
        connected_.store(true);
        connection_state_.store(device_common::DeviceConnectionState::Online);
        connection_generation_.fetch_add(1);
        if (command_callback_ != nullptr) {
            (void)esp_mqtt_client_subscribe(client_, command_topic_.data(), 1);
        }
        (void)publishPresence("online");
        ESP_LOGI(kTag, "connected");
        break;
    case MQTT_EVENT_DISCONNECTED:
        connected_.store(false);
        connection_state_.store(device_common::DeviceConnectionState::BrokerConnecting);
        ESP_LOGW(kTag, "disconnected; automatic reconnect remains enabled");
        break;
    case MQTT_EVENT_DATA:
        if (command_callback_ == nullptr || event->topic == nullptr || event->data == nullptr ||
            event->current_data_offset != 0 || event->data_len != event->total_data_len ||
            event->topic_len != static_cast<int>(std::strlen(command_topic_.data())) ||
            std::memcmp(event->topic, command_topic_.data(), event->topic_len) != 0) {
            break;
        }
        command_callback_(std::string_view(event->data, event->data_len),
                          event->retain, command_context_);
        break;
    case MQTT_EVENT_ERROR:
        ESP_LOGE(kTag, "MQTT transport error");
        break;
    default:
        break;
    }
}
