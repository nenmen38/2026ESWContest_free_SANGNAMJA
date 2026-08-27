import 'dart:async';

import 'package:esw_device_sdk/esw_device_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/landing_page.dart';
import 'sdk_scope.dart';

class StartupGate extends ConsumerStatefulWidget {
  const StartupGate({required this.home, super.key});

  final Widget home;

  @override
  ConsumerState<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<StartupGate> {
  bool? _onboardingSeen;

  @override
  void initState() {
    super.initState();
    Future.microtask(_restore);
  }

  Future<void> _restore() async {
    final storage = ref.read(appStorageProvider);
    final seen = await storage.readOnboardingSeen();
    final credentials = await storage.readCredentials();
    if (mounted) setState(() => _onboardingSeen = seen);
    if (credentials != null) {
      unawaited(_reconnect(credentials));
    }
  }

  Future<void> _reconnect(EswConnectionConfig credentials) async {
    try {
      await ref.read(sdkProvider).connect(credentials);
    } on Object {
      // 연결 오류는 장치 관리 화면에서 사용자에게 복구 경로를 제공한다.
    }
  }

  Future<void> _finishOnboarding() async {
    await ref.read(appStorageProvider).writeOnboardingSeen(true);
    if (mounted) setState(() => _onboardingSeen = true);
  }

  @override
  Widget build(BuildContext context) {
    final seen = _onboardingSeen;
    if (seen == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return seen ? widget.home : LandingPage(onFinished: _finishOnboarding);
  }
}
