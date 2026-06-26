class EmergencyStep {
  final String title;
  final String description;
  final String emoji;

  EmergencyStep({
    required this.title,
    required this.description,
    required this.emoji,
  });

  factory EmergencyStep.fromJson(Map<String, dynamic> json) {
    return EmergencyStep(
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      emoji: json['emoji'] ?? '⚠️',
    );
  }
}

class EmergencyAction {
  final String label;
  final String type; // 'call', 'navigate', 'info'
  final String value;

  EmergencyAction({
    required this.label,
    required this.type,
    required this.value,
  });

  factory EmergencyAction.fromJson(Map<String, dynamic> json) {
    return EmergencyAction(
      label: json['label'] ?? '',
      type: json['type'] ?? 'info',
      value: json['value'] ?? '',
    );
  }
}

class EmergencyResponse {
  final String emergencyType;
  final String severity; // 'critical', 'high', 'medium'
  final String headline;
  final List<EmergencyStep> steps;
  final List<EmergencyAction> actions;
  final List<String> detectedTools;
  final String additionalContext;

  EmergencyResponse({
    required this.emergencyType,
    required this.severity,
    required this.headline,
    required this.steps,
    required this.actions,
    required this.detectedTools,
    required this.additionalContext,
  });

  factory EmergencyResponse.fromJson(Map<String, dynamic> json) {
    return EmergencyResponse(
      emergencyType: json['emergency_type'] ?? 'Unknown',
      severity: json['severity'] ?? 'high',
      headline: json['headline'] ?? 'Emergency Detected',
      steps: (json['steps'] as List<dynamic>? ?? [])
          .map((s) => EmergencyStep.fromJson(s as Map<String, dynamic>))
          .toList(),
      actions: (json['actions'] as List<dynamic>? ?? [])
          .map((a) => EmergencyAction.fromJson(a as Map<String, dynamic>))
          .toList(),
      detectedTools: List<String>.from(json['detected_tools'] ?? []),
      additionalContext: json['additional_context'] ?? '',
    );
  }
}
