idf_component_register(
    SRCS "main.cpp"
    INCLUDE_DIRS "."
    REQUIRES motor motor_feedback service device_common ble_provisioning mqtt_bridge mqtt_adapter status_led esp_timer
)
