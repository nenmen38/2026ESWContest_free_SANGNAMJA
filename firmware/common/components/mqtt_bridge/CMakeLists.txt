idf_component_register(
    SRCS "mqtt_bridge.cpp"
    INCLUDE_DIRS "include"
    REQUIRES device_common espressif__mqtt mbedtls esp_event
)
