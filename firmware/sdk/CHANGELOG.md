# Changelog

## Unreleased

- Replaced separate connection and device feeds with seeded atomic SDK state.
- Added typed motor and air-quality device snapshots.
- Replaced direct provisioning access with guided `DeviceSetup` sessions.
- Added post-Wi-Fi domain-data readiness verification.
- Removed third-party BLE provisioning models from the public barrel.
- Rebuilt the example as a public-API-only SDK consumer.
- Made `EswDeviceSdk` implementable by application fakes while keeping internal
  transport construction out of the public barrel.
- Serialized MQTT connection replacement and ignored callbacks from superseded
  connection generations.
- Scoped retained snapshots to server, port, and account, and correlated motor
  results by both command and device ID.
- Consolidated provisioning models, split the Security 1 workflow from the
  platform adapter, and release completed setup secrets immediately.
- Simplified the example to direct SDK state providers and page-local setup
  state, and removed the Windows runner from the Android/iOS example.
