# MQTT v1 protocol

The stable device root is `v1/devices/{deviceId}`. A motor ID starts with
`motor-`; an air-quality ID starts with `sensor-`. The identifier in the topic
is the authoritative device identity for v1.

| Suffix | Direction | QoS | Retain | Purpose |
| --- | --- | --- | --- | --- |
| `presence` | device to clients | 1 | yes | `online` on connect and LWT `offline` |
| `command` | client to motor | 1 | no | validated motor command |
| `event` | motor to clients | 1 | no | command result correlated by `commandId` |
| `state` | motor to clients | 1 | yes | latest canonical motor state |
| `telemetry` | sensor to clients | 1 | no | latest independently valid sensor sample |

JSON emitted by current firmware includes integer `schemaVersion: 1`.
Motor-command parsing accepts a missing version only for v1 backward
compatibility; a present value with the wrong type or an unsupported value is
rejected. Payloads larger than the adapter's fixed buffer are rejected.

Motor commands require a nonempty `commandId`, known `action`, and `ttlMs` in
range. `set_position` additionally requires `position100ths` in `0..10000`.
Results contain the same `commandId`, a stable result code, and state revision.
Duplicate live command IDs are rejected. Safety-unavailable, stale-safety,
position-unknown, hardware-rejected, invalid-command, and duplicate-command
remain distinct outcomes.

Telemetry contains `timestampUs`, `revision`, `errorFlags`, `pmValid`,
`bmeValid`, `normalized`, and `raw`. A failed PM2008M sample does not invalidate
BME280 fields, and the inverse also holds.

Broker accounts are deployment inputs, not created by either firmware or the
Flutter SDK. A device account may publish only its own `presence`, `state`,
`event`, and `telemetry`, and may subscribe only to its own `command`. An app
account may subscribe to the device roots it owns and publish only their
`command` topics. Both roles require TLS, unique credentials, and server-side
revocation. The shared negative/positive JSON cases live in
`json-fixtures.json`.
