import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_page.dart';

void main() => runApp(const ProviderScope(child: EswDemoApp()));

class EswDemoApp extends StatelessWidget {
  const EswDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ESW Home',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B5B)),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    ),
    home: const HomePage(),
  );
}
