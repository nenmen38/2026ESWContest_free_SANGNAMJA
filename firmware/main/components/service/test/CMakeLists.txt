# Included by an ESP-IDF Unity test application when service is tested.
idf_component_register(
    SRCS "test_service.cpp"
    INCLUDE_DIRS "../include"
    REQUIRES service unity
)
