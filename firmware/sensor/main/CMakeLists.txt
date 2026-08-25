idf_component_register(
    SRCS "main.cpp"
    INCLUDE_DIRS "."
    REQUIRES service device_common ble_provisioning mqtt_bridge mqtt_adapter status_led esp_timer
)
