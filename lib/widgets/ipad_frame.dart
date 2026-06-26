import 'package:flutter/material.dart';

/// Wraps the app in a realistic iPad (landscape) device shell — aluminum rim,
/// black bezel, front camera, home indicator, screen gloss — and tilts it in
/// 3D space with a perspective transform so it reads as a real object sitting
/// on a desk, not an edge-to-edge frame.
///
/// The child receives the inner screen area as its only constraint, so every
/// Positioned widget and MediaQuery inside the HUD resolves against the iPad
/// screen, not the window. A true glTF/3D-engine renderer can't composite live
/// Flutter UI onto the device screen, so we use Flutter's native `Transform`
/// with a perspective `Matrix4` — the live UI stays interactive while the body
/// gets real 3D tilt, shading, and shadow.
class IpadFrame extends StatelessWidget {
  final Widget child;
  const IpadFrame({super.key, required this.child});

  // iPad landscape is 4:3.
  static const double _aspect = 4.0 / 3.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Desk / room backdrop behind the device.
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.5,
          colors: [Color(0xFF2E3138), Color(0xFF0E1014)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final availW = c.maxWidth;
          final availH = c.maxHeight;

          // Keep the device well inside the window — never edge to edge.
          const margin = 64.0;
          final maxW = availW - margin * 2;
          final maxH = availH - margin * 2;

          // Size to ~82% of the available area so it reads as a smaller device.
          double screenH = (maxH * 0.82).clamp(320.0, 900.0);
          double screenW = screenH * _aspect;
          if (screenW > maxW) {
            screenW = maxW;
            screenH = screenW / _aspect;
          }

          // Modern iPad: thin uniform bezels, slim aluminum rim.
          final bezel = (screenH * 0.022).clamp(8.0, 16.0);
          final rim = (screenH * 0.012).clamp(3.0, 6.0);
          final radius = (screenH * 0.04).clamp(16.0, 34.0);

          final deviceRadius = radius + bezel + rim;

          final device = _DeviceBody(
            screenW: screenW,
            screenH: screenH,
            bezel: bezel,
            rim: rim,
            radius: radius,
            deviceRadius: deviceRadius,
            child: child,
          );

          // Straight on — no tilt.
          return Center(child: device);
        },
      ),
    );
  }
}

class _DeviceBody extends StatelessWidget {
  final double screenW;
  final double screenH;
  final double bezel;
  final double rim;
  final double radius;
  final double deviceRadius;
  final Widget child;

  const _DeviceBody({
    required this.screenW,
    required this.screenH,
    required this.bezel,
    required this.rim,
    required this.radius,
    required this.deviceRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: screenW + (bezel + rim) * 2,
      height: screenH + (bezel + rim) * 2,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(deviceRadius),
        // Space-gray aluminum body with a brushed highlight.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.35, 0.7, 1.0],
          colors: [
            Color(0xFF6B6D71),
            Color(0xFF43454A),
            Color(0xFF2D2F33),
            Color(0xFF3A3C41),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 0.75,
        ),
        boxShadow: [
          // Contact shadow under the device.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 50,
            offset: const Offset(0, 28),
          ),
          // Long, soft ground shadow.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 90,
            spreadRadius: -20,
            offset: const Offset(0, 60),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Black bezel + screen, inset by the aluminum rim.
          Padding(
            padding: EdgeInsets.all(rim),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(deviceRadius - rim),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF050608), Color(0xFF000000)],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(bezel),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // The live screen.
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: Material(
                          color: const Color(0xFF070A0E),
                          child: child,
                        ),
                      ),
                    ),
                    // Glass gloss — diagonal sheen across the top-left.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.center,
                                stops: const [0.0, 0.5],
                                colors: [
                                  Colors.white.withValues(alpha: 0.07),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Front camera dot — centered on the top bezel (landscape).
          Positioned(
            top: rim + bezel / 2,
            child: _CameraDot(),
          ),
          // Home indicator pill — centered on the bottom bezel.
          Positioned(
            bottom: rim + bezel * 0.4,
            child: Container(
              width: screenW * 0.12,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: const Color(0xFF05070A),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.2),
            blurRadius: 1,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }
}
