import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class VoiceListeningOverlay extends StatefulWidget {
  final String transcript;
  const VoiceListeningOverlay({super.key, required this.transcript});

  @override
  State<VoiceListeningOverlay> createState() => _VoiceListeningOverlayState();
}

class _VoiceListeningOverlayState extends State<VoiceListeningOverlay>
    with TickerProviderStateMixin {
  late final List<AnimationController> _barControllers;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _barControllers = List.generate(12, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 300 + _rng.nextInt(400)),
      )..repeat(reverse: true);
      Future.delayed(Duration(milliseconds: i * 60), () {
        if (mounted) ctrl.forward();
      });
      return ctrl;
    });
  }

  @override
  void dispose() {
    for (final c in _barControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [Color(0xFF001A2E), Color(0xFF070A0E)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _waveform(),
          const SizedBox(height: 40),
          _micButton(),
          const SizedBox(height: 36),
          _transcriptArea(),
          const SizedBox(height: 16),
          _hint(),
        ],
      ),
    );
  }

  Widget _waveform() {
    return SizedBox(
      height: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barControllers.length, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedBuilder(
              animation: _barControllers[i],
              builder: (context, _) {
                final height = 12 + _barControllers[i].value * 56;
                return AnimatedContainer(
                  duration: 100.ms,
                  width: 5,
                  height: height,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D4FF)
                        .withValues(alpha: 0.4 + _barControllers[i].value * 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _micButton() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF00D4FF).withValues(alpha: 0.08),
          ),
        )
            .animate(onPlay: (c) => c.repeat())
            .scale(begin: const Offset(1, 1), end: const Offset(1.5, 1.5), duration: 1200.ms)
            .fadeOut(duration: 1200.ms),
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [Color(0xFF00E5FF), Color(0xFF0096C7)],
            ),
          ),
          child: const Icon(Icons.mic, color: Colors.black, size: 30),
        ),
      ],
    );
  }

  Widget _transcriptArea() {
    return AnimatedSwitcher(
      duration: 300.ms,
      child: widget.transcript.isEmpty
          ? Text(
              'Speak now...',
              key: const ValueKey('hint'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 16,
                letterSpacing: 1,
              ),
            )
          : Container(
              key: const ValueKey('transcript'),
              margin: const EdgeInsets.symmetric(horizontal: 80),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Text(
                '"${widget.transcript}"',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w300,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1),
    );
  }

  Widget _hint() {
    return Text(
      'Guardian is listening · Say your emergency clearly',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.2),
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    );
  }
}

class ProcessingOverlay extends StatelessWidget {
  final String transcript;
  const ProcessingOverlay({super.key, required this.transcript});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [Color(0xFF0A001A), Color(0xFF070A0E)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _spinner(),
          const SizedBox(height: 40),
          if (transcript.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 80),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Text(
                '"$transcript"',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w300,
                ),
                textAlign: TextAlign.center,
              ),
            ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: 32),
          Text(
            'Guardian AI is generating your safety response...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1800.ms),
          const SizedBox(height: 8),
          Text(
            'Powered by Fireworks AI · GLM-5P2',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.15),
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _spinner() {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        SizedBox(
          width: 60,
          height: 60,
          child: CircularProgressIndicator(
            color: const Color(0xFF7C3AED),
            strokeWidth: 2,
          ),
        ),
        const Icon(Icons.auto_awesome, color: Color(0xFF7C3AED), size: 22),
      ],
    ).animate(onPlay: (c) => c.repeat()).rotate(duration: 3000.ms, begin: 0, end: 0.5);
  }
}
