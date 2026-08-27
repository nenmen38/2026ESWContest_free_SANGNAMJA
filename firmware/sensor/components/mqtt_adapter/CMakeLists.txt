idf_component_register(
    SRCS "mqtt_adapter.cpp"
    INCLUDE_DIRS "include"
    REQUIRES service mqtt_bridge espressif__json_generator freertos
)
