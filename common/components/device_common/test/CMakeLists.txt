# Included by an ESP-IDF Unity test application when device_common is tested.
idf_component_register(
    SRCS "test_device_common.cpp"
    INCLUDE_DIRS "../include"
    REQUIRES device_common unity
)
