import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class VoiceListeningOverlay extends StatelessWidget {
  final String transcript;

  const VoiceListeningOverlay({super.key, required this.transcript});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0A0A0F),
            const Color(0xFF0D1117).withOpacity(0.95),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _pulsingMic(),
            const SizedBox(height: 40),
            if (transcript.isNotEmpty)
              Text(
                '"$transcript"',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w300,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: 300.ms)
            else
              Text(
                'Listening...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 20,
                  letterSpacing: 2,
                ),
              ).animate().fadeIn().then().shimmer(duration: 1500.ms, delay: 0.ms),
          ],
        ),
      ),
    );
  }

  Widget _pulsingMic() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF00D4FF).withOpacity(0.1),
          ),
        ).animate(onPlay: (c) => c.repeat()).scale(
              begin: const Offset(1, 1),
              end: const Offset(1.4, 1.4),
              duration: 1000.ms,
              curve: Curves.easeOut,
            ).then().scale(
              begin: const Offset(1.4, 1.4),
              end: const Offset(1, 1),
              duration: 1000.ms,
            ),
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF00D4FF),
          ),
          child: const Icon(Icons.mic, color: Colors.black, size: 32),
        ),
      ],
    );
  }
}

class ProcessingOverlay extends StatelessWidget {
  final String transcript;

  const ProcessingOverlay({super.key, required this.transcript});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0A0F),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: Color(0xFF00D4FF),
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '"$transcript"',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w300,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Gemini generating response...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 14,
                letterSpacing: 1.5,
              ),
            ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms),
          ],
        ),
      ),
    );
  }
}
