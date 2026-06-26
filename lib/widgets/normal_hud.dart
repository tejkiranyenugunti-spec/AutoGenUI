import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class NormalHud extends StatefulWidget {
  const NormalHud({super.key});

  @override
  State<NormalHud> createState() => _NormalHudState();
}

class _NormalHudState extends State<NormalHud>
    with SingleTickerProviderStateMixin {
  late Timer _clockTimer;
  late Timer _speedTimer;
  late AnimationController _pulseController;
  String _time = '';
  int _speed = 58;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    _speedTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (mounted) {
        setState(() => _speed = (_speed + _rng.nextInt(5) - 2).clamp(52, 68));
      }
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  void _updateTime() {
    if (!mounted) return;
    final now = DateTime.now();
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final min = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    setState(() => _time = '$hour:$min $ampm');
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _speedTimer.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: [Color(0xFF0D1117), Color(0xFF070A0E)],
            ),
          ),
        ),
        _scanLines(),
        SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(child: _centerContent()),
              _bottomBar(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scanLines() {
    return Opacity(
      opacity: 0.03,
      child: CustomPaint(
        painter: _ScanLinePainter(),
        size: Size.infinite,
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Row(
        children: [
          _navCard().animate().fadeIn(duration: 600.ms).slideX(begin: -0.1),
          const Spacer(),
          _statusCluster().animate().fadeIn(duration: 600.ms, delay: 100.ms),
        ],
      ),
    );
  }

  Widget _navCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_upward, color: Color(0xFF00D4FF), size: 16),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Market St · 0.3 mi',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2)),
              const SizedBox(height: 2),
              Text('ETA 12 min · via Van Ness Ave',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusCluster() {
    return Row(
      children: [
        _statusPill(Icons.wifi, '4G', const Color(0xFF00FF88)),
        const SizedBox(width: 10),
        _statusPill(Icons.thermostat, '68°F', Colors.white54),
        const SizedBox(width: 16),
        Text(
          _time,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w300,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _statusPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _centerContent() {
    return Row(
      children: [
        Expanded(child: _leftPanel()),
        _speedometer(),
        Expanded(child: _rightPanel()),
      ],
    );
  }

  Widget _leftPanel() {
    return Padding(
      padding: const EdgeInsets.only(left: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoCard(Icons.speed, 'SPEED LIMIT', '65', 'mph'),
          const SizedBox(height: 16),
          _infoCard(Icons.route, 'DISTANCE', '4.2', 'mi left'),
          const SizedBox(height: 16),
          _infoCard(Icons.local_gas_station, 'RANGE', '187', 'mi'),
        ],
      ),
    ).animate().fadeIn(duration: 700.ms, delay: 200.ms);
  }

  Widget _infoCard(IconData icon, String label, String value, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.3), size: 16),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 9,
                      letterSpacing: 1.5)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Text(unit,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _speedometer() {
    return SizedBox(
      width: 260,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return CustomPaint(
                painter: _SpeedArcPainter(
                  speed: _speed,
                  glowIntensity: 0.6 + _pulseController.value * 0.4,
                ),
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: 400.ms,
                          child: Text(
                            '$_speed',
                            key: ValueKey(_speed),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 80,
                              fontWeight: FontWeight.w200,
                              letterSpacing: -3,
                              height: 1,
                            ),
                          ),
                        ),
                        Text(
                          'mph',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 16,
                            letterSpacing: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'CRUISING',
            style: TextStyle(
              color: const Color(0xFF00FF88).withValues(alpha: 0.7),
              fontSize: 10,
              letterSpacing: 3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 800.ms);
  }

  Widget _rightPanel() {
    return Padding(
      padding: const EdgeInsets.only(right: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _batteryCard(),
          const SizedBox(height: 16),
          _engineCard(),
          const SizedBox(height: 16),
          _tirePressureCard(),
        ],
      ),
    ).animate().fadeIn(duration: 700.ms, delay: 300.ms);
  }

  Widget _batteryCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('BATTERY',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 9,
                  letterSpacing: 1.5)),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('78%',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  width: 60,
                  height: 8,
                  color: Colors.white.withValues(alpha: 0.1),
                  child: FractionallySizedBox(
                    widthFactor: 0.78,
                    alignment: Alignment.centerLeft,
                    child: Container(color: const Color(0xFF00FF88)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _engineCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(Icons.settings, color: Colors.white.withValues(alpha: 0.3), size: 14),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ENGINE',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 9,
                      letterSpacing: 1.5)),
              const Text('Normal',
                  style: TextStyle(
                      color: Color(0xFF00FF88),
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tirePressureCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(Icons.tire_repair, color: Colors.white.withValues(alpha: 0.3), size: 14),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TIRES',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 9,
                      letterSpacing: 1.5)),
              const Text('32 PSI · OK',
                  style: TextStyle(
                      color: Color(0xFF00FF88),
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      child: Row(
        children: [
          _laneWidget(),
          const Spacer(),
          _tripWidget(),
        ],
      ),
    ).animate().fadeIn(duration: 700.ms, delay: 400.ms);
  }

  Widget _laneWidget() {
    return Row(
      children: [
        Icon(Icons.swap_horiz, color: Colors.white.withValues(alpha: 0.25), size: 14),
        const SizedBox(width: 6),
        Text('Lane Assist · ON',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12)),
      ],
    );
  }

  Widget _tripWidget() {
    return Row(
      children: [
        Text('Trip A: 124.3 mi',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12)),
      ],
    );
  }
}

class _SpeedArcPainter extends CustomPainter {
  final int speed;
  final double glowIntensity;
  _SpeedArcPainter({required this.speed, required this.glowIntensity});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const startAngle = pi * 0.75;
    const sweepAngle = pi * 1.5;
    final speedFraction = (speed / 120).clamp(0.0, 1.0);

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle, false, bgPaint);

    // Speed arc
    final arcColor = speed < 65
        ? const Color(0xFF00D4FF)
        : speed < 80
            ? const Color(0xFFFFCC00)
            : const Color(0xFFFF2D2D);

    final arcPaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle * speedFraction,
        colors: [arcColor.withValues(alpha: 0.6), arcColor],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle * speedFraction, false, arcPaint);

    // Glow dot at tip
    final tipAngle = startAngle + sweepAngle * speedFraction;
    final tipX = center.dx + radius * cos(tipAngle);
    final tipY = center.dy + radius * sin(tipAngle);
    final glowPaint = Paint()
      ..color = arcColor.withValues(alpha: glowIntensity * 0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(tipX, tipY), 6, glowPaint);
    canvas.drawCircle(
        Offset(tipX, tipY), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SpeedArcPainter old) =>
      old.speed != speed || old.glowIntensity != glowIntensity;
}

class _ScanLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanLinePainter _) => false;
}
