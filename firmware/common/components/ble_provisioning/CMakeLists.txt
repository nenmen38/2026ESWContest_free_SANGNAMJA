idf_component_register(
    SRCS "ble_provisioning.cpp"
    INCLUDE_DIRS "include"
    REQUIRES device_common espressif__network_provisioning protocomm
             espressif__button nvs_flash esp_wifi
             esp_netif esp_event esp_system
)
