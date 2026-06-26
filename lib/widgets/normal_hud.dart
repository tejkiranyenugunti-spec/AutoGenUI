import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class NormalHud extends StatefulWidget {
  const NormalHud({super.key});

  @override
  State<NormalHud> createState() => _NormalHudState();
}

class _NormalHudState extends State<NormalHud> {
  int _speed = 65;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0A0F), Color(0xFF0D1117)],
        ),
      ),
      child: Column(
        children: [
          _topBar(),
          Expanded(child: _centerSpeed()),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: Row(
        children: [
          _navCard(),
          const Spacer(),
          _timeCard(),
        ],
      ),
    );
  }

  Widget _navCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.arrow_upward, color: Color(0xFF00D4FF), size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Market St · 0.3 mi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                'ETA 12 min',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms);
  }

  Widget _timeCard() {
    return Text(
      '7:42 PM',
      style: TextStyle(
        color: Colors.white.withOpacity(0.6),
        fontSize: 18,
        fontWeight: FontWeight.w300,
        letterSpacing: 2,
      ),
    );
  }

  Widget _centerSpeed() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$_speed',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 120,
            fontWeight: FontWeight.w200,
            letterSpacing: -4,
            height: 1,
          ),
        ).animate().fadeIn(duration: 800.ms),
        Text(
          'mph',
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 22,
            fontWeight: FontWeight.w300,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Speed Limit 65',
          style: TextStyle(
            color: Colors.white.withOpacity(0.25),
            fontSize: 13,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _bottomBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
      child: Row(
        children: [
          _batteryWidget(),
          const Spacer(),
          _tempWidget(),
        ],
      ),
    );
  }

  Widget _batteryWidget() {
    return Row(
      children: [
        const Icon(Icons.battery_charging_full, color: Color(0xFF00FF88), size: 18),
        const SizedBox(width: 8),
        Container(
          width: 80,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            widthFactor: 0.78,
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF00FF88),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '78%',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _tempWidget() {
    return Row(
      children: [
        Icon(Icons.thermostat, color: Colors.white.withOpacity(0.4), size: 16),
        const SizedBox(width: 4),
        Text(
          '68°F',
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
