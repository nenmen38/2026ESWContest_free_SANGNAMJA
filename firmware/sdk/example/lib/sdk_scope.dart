import 'dart:async';

import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sdkProvider = Provider<EswDeviceSdk>((ref) {
  final sdk = EswDeviceSdk();
  ref.onDispose(() => unawaited(sdk.dispose()));
  return sdk;
});

final sdkStateProvider = StreamProvider<EswSdkState>(
  (ref) => ref.watch(sdkProvider).states,
);
