# ESW Android compatibility fork

This directory vendors `esp_provisioning_ble 1.1.0` under its MIT license.
The Dart provisioning protocol and iOS implementation are unchanged.

The Android bridge is maintained here because the upstream release fixes its
library at compile SDK 33 and applies an obsolete Kotlin Gradle configuration.
The ESW fork uses compile SDK 37, minimum SDK 23, Java 17, and a Java
implementation of the same `esp_provisioning_ble` method channel.

When upgrading upstream, retain the method-channel contract and rerun both the
SDK test suite and the SDK example/app Android builds before removing this
fork.
