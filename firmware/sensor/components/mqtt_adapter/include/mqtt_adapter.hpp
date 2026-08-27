#pragma once

#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "mqtt_bridge.hpp"
#include "service.hpp"

class SensorMqttAdapter {
public:
    SensorMqttAdapter() = default;
    ~SensorMqttAdapter();

    SensorMqttAdapter(const SensorMqttAdapter&) = delete;
    SensorMqttAdapter& operator=(const SensorMqttAdapter&) = delete;

    bool begin(MqttBridge& bridge);
    bool enqueue(const SensorSnapshot& snapshot);
    void stop();

private:
    static void taskEntry(void* context);
    void taskLoop();
    void publish(const SensorSnapshot& snapshot);

    MqttBridge* bridge_ = nullptr;
    QueueHandle_t queue_ = nullptr;
    TaskHandle_t task_ = nullptr;
    volatile bool stop_requested_ = false;
};

