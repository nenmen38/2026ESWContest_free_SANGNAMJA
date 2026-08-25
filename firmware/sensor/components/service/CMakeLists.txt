idf_component_register(
    SRCS "service.cpp"
    INCLUDE_DIRS "include"
    REQUIRES pm2008m bme280_adapter espressif__i2c_bus freertos esp_timer device_common
)
