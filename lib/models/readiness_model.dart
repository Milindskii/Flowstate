/// Hourly energy datapoint for circadian rhythm curve
class EnergyPoint {
  final String label; // "6a", "8a", "10a", "12p", "2p", "4p", "6p"
  final double level; // 0.0 to 1.0

  const EnergyPoint(this.label, this.level);
}

/// Readiness Model
/// Strictly non-medical. Evaluates user readiness for cognitive focus.
class ReadinessModel {
  final int score; // 76
  final int maxScore; // 100
  final String statusMessage; // "Strong focus window coming up"
  final String focusWindowRange; // "9:30 AM - 11:45 AM"
  final String explanation; // "Based on your recent sleep, schedule and activity."
  final List<EnergyPoint> hourlyRhythm;

  const ReadinessModel({
    required this.score,
    required this.maxScore,
    required this.statusMessage,
    required this.focusWindowRange,
    required this.explanation,
    required this.hourlyRhythm,
  });

  ReadinessModel copyWith({
    int? score,
    int? maxScore,
    String? statusMessage,
    String? focusWindowRange,
    String? explanation,
    List<EnergyPoint>? hourlyRhythm,
  }) {
    return ReadinessModel(
      score: score ?? this.score,
      maxScore: maxScore ?? this.maxScore,
      statusMessage: statusMessage ?? this.statusMessage,
      focusWindowRange: focusWindowRange ?? this.focusWindowRange,
      explanation: explanation ?? this.explanation,
      hourlyRhythm: hourlyRhythm ?? this.hourlyRhythm,
    );
  }
}
