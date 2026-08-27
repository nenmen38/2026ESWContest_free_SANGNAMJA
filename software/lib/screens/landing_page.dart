import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pairing/pairing_flow.dart';
import 'installation_location_page.dart';

class LandingPage extends ConsumerStatefulWidget {
  const LandingPage({required this.onFinished, super.key});

  final Future<void> Function() onFinished;

  @override
  ConsumerState<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends ConsumerState<LandingPage> {
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    final completed = await openDevicePairing(
      context,
      ref,
      requireMotorAndSensor: true,
    );
    if (!mounted) return;
    if (completed) {
      final locationSaved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const InstallationLocationPage(initialSetup: true),
        ),
      );
      if (locationSaved == true) await widget.onFinished();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _skip() async {
    setState(() => _busy = true);
    await widget.onFinished();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6F8),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Container(
                  height: 250,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFDCEEFF), Color(0xFFF5FAFF)],
                    ),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.window_outlined,
                        size: 142,
                        color: Color(0xFF3182F6),
                      ),
                      Positioned(
                        right: 42,
                        top: 44,
                        child: _FeatureBubble(icon: Icons.shield_outlined),
                      ),
                      Positioned(
                        left: 44,
                        bottom: 40,
                        child: _FeatureBubble(icon: Icons.air),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 34),
                Text(
                  '안전하고 쾌적한\n스마트 창문 생활',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w900, height: 1.25),
                ),
                const SizedBox(height: 14),
                Text(
                  '장치를 연결하면 비와 공기 상태에 맞춰 창문을 더 편리하게 관리할 수 있어요.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF6B7684),
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _busy ? null : _connect,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.add_link),
                  label: const Text(
                    '장치 연결하기',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _skip,
                  child: const Text('나중에 하기'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _FeatureBubble extends StatelessWidget {
  const _FeatureBubble({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 50,
    height: 50,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x183182F6),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Icon(icon, color: const Color(0xFF3182F6)),
  );
}
