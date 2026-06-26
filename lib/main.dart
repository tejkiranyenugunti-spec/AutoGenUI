import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/hud_screen.dart';

Future<void> main() async {
  // Load .env (FIREWORKS_API_KEY, optional FIREWORKS_MODEL /
  // FIREWORKS_VISION_MODEL) so secrets aren't baked into the build. Falls back
  // silently if .env is absent — the transport also honors --dart-define.
  await dotenv.load(fileName: '.env', isOptional: true);
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
