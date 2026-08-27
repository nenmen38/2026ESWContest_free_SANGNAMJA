idf_component_register(
    SRCS "motor.cpp"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES gin66__fastaccelstepper esp_driver_gpio
)
