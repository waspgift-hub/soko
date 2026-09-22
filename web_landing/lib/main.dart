import 'package:flutter/material.dart';
import 'pages/landing_page.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const SokoVibeWebApp());
}

class SokoVibeWebApp extends StatelessWidget {
  const SokoVibeWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Soko Vibe — Soko la Tanzania',
      theme: SokoWebTheme.light(),
      home: const LandingPage(),
    );
  }
}
