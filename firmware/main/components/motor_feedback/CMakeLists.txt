idf_component_register(
    SRCS "motor_feedback.cpp"
    INCLUDE_DIRS "include"
    REQUIRES service motor device_common esp_driver_gpio esp_timer
)
