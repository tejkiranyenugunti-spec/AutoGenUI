import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/emergency_response.dart';

class EmergencyHud extends StatelessWidget {
  final EmergencyResponse response;
  final VoidCallback onDismiss;

  const EmergencyHud({
    super.key,
    required this.response,
    required this.onDismiss,
  });

  Color get _severityColor {
    return switch (response.severity) {
      'critical' => const Color(0xFFFF2D2D),
      'high' => const Color(0xFFFF6B00),
      _ => const Color(0xFFFFCC00),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _severityColor.withOpacity(0.12),
            const Color(0xFF0A0A0F),
          ],
        ),
      ),
      child: Column(
        children: [
          _header(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _stepsRow(),
                  const SizedBox(height: 24),
                  if (response.detectedTools.isNotEmpty) _toolsBar(),
                  const SizedBox(height: 16),
                  _actionsRow(),
                  if (response.additionalContext.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _contextBar(),
                  ],
                ],
              ),
            ),
          ),
          _dismissBar(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _severityColor.withOpacity(0.3)),
        ),
        color: _severityColor.withOpacity(0.08),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _severityColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_rounded, color: Colors.black, size: 16),
                const SizedBox(width: 6),
                Text(
                  response.emergencyType,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).slideX(begin: -0.2),
          const SizedBox(width: 16),
          Text(
            response.headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text(
              'AI GENERATED',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 10,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: response.steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _stepCard(step, index),
          ),
        );
      }).toList(),
    );
  }

  Widget _stepCard(EmergencyStep step, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: index == 0
              ? _severityColor.withOpacity(0.5)
              : Colors.white.withOpacity(0.08),
          width: index == 0 ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: index == 0 ? _severityColor : Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: index == 0 ? Colors.black : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                step.emoji,
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            step.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.description,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, delay: Duration(milliseconds: 150 * index))
        .slideY(begin: 0.15, end: 0);
  }

  Widget _toolsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(Icons.build_outlined, color: Colors.white.withOpacity(0.4), size: 14),
          const SizedBox(width: 10),
          Text(
            'Tools detected: ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
          ...response.detectedTools.map((tool) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF88).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFF00FF88).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    tool,
                    style: const TextStyle(
                      color: Color(0xFF00FF88),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms, delay: 400.ms);
  }

  Widget _actionsRow() {
    return Row(
      children: response.actions.map((action) {
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _actionButton(action),
        );
      }).toList(),
    ).animate().fadeIn(duration: 500.ms, delay: 500.ms);
  }

  Widget _actionButton(EmergencyAction action) {
    final isPrimary = action.type == 'call';
    return ElevatedButton.icon(
      onPressed: () {},
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? _severityColor : Colors.white.withOpacity(0.08),
        foregroundColor: isPrimary ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
        side: isPrimary
            ? null
            : BorderSide(color: Colors.white.withOpacity(0.15)),
      ),
      icon: Icon(
        _iconForType(action.type),
        size: 16,
        color: isPrimary ? Colors.black : Colors.white,
      ),
      label: Text(
        action.label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: isPrimary ? Colors.black : Colors.white,
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'call' => Icons.phone,
      'navigate' => Icons.navigation,
      'hazard' => Icons.warning,
      _ => Icons.info_outline,
    };
  }

  Widget _contextBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Text(
        response.additionalContext,
        style: TextStyle(
          color: Colors.white.withOpacity(0.45),
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
    ).animate().fadeIn(duration: 500.ms, delay: 600.ms);
  }

  Widget _dismissBar() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: TextButton.icon(
        onPressed: onDismiss,
        icon: Icon(Icons.close, size: 16, color: Colors.white.withOpacity(0.3)),
        label: Text(
          'Dismiss — return to HUD',
          style: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
