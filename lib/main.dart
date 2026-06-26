import 'package:flutter/material.dart';
import 'screens/hud_screen.dart';

void main() {
  runApp(const GuardianHudApp());
}

class GuardianHudApp extends StatelessWidget {
  const GuardianHudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guardian HUD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4FF),
          surface: Color(0xFF0D1117),
        ),
      ),
      home: const HudScreen(),
    );
  }
}
