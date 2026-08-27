# Shared device components

This directory contains protocol-independent contracts and the two shared
network components used by the independent motor and sensor firmware images.

- `device_common`: canonical state, position mapping, command validation, TTL,
  fixed-size command-ID deduplication, and sensor contracts.
- `ble_provisioning`: NimBLE Security 1 lifecycle, Wi-Fi and `mqtt-config`
  provisioning, NVS persistence, IP readiness, and GPIO9 BOOT-button events
  delegated to `espressif/button`.
- `mqtt_bridge`: MQTT 5 MQTTS connection, public CA bundle verification,
  automatic reconnect, retained presence/LWT, QoS 1 JSON publishing, topic
  construction, and optional motor command delivery.
- `status_led`: a thin domain-priority facade over `espressif/led_indicator`;
  board-specific SPI/RMT selection is configuration only.

The versioned topics, QoS, retain behavior, payload requirements, and broker
ACL contract are maintained in [`protocol/mqtt-v1.md`](protocol/mqtt-v1.md).

Device-specific JSON mapping stays in each firmware project's local
`mqtt_adapter`; sensor and motor HAL/service APIs remain independent of BLE and
MQTT.
