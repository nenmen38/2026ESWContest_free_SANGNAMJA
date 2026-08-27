/// A high-level SDK for discovering, provisioning, controlling, and observing
/// ESW motor and air-quality devices.
///
/// Applications use domain operations such as [MotorController.open] and never
/// handle topics, payloads, delivery levels, or retained messages.
// ignore: unnecessary_library_name
library esw_device_sdk;

export 'src/errors.dart';
export 'src/device_setup.dart';
export 'src/models.dart';
export 'src/provisioning_qr.dart' show ProvisioningQrPayload;
export 'src/sdk.dart' show EswDeviceSdk, MotorController;
