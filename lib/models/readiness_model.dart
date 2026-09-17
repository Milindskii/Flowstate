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

  final double confidence; // 0.0 to 1.0
  final String modelVersion; // "v1.0.0-deterministic"
  final bool isCalibrated; // false = "Learning your rhythm"
  final List<String> factors;

  const ReadinessModel({
    required this.score,
    required this.maxScore,
    required this.statusMessage,
    required this.focusWindowRange,
    required this.explanation,
    required this.hourlyRhythm,
    this.confidence = 0.85,
    this.modelVersion = 'v1.0.0-deterministic',
    this.isCalibrated = true,
    this.factors = const [
      'Consistent wake-up schedule',
      'Optimal sleep duration for focus',
      'Circadian morning peak alignment',
    ],
  });

  /// Factory for new users with insufficient data
  factory ReadinessModel.uncalibrated() {
    return const ReadinessModel(
      score: 0,
      maxScore: 100,
      statusMessage: 'Learning your rhythm...',
      focusWindowRange: 'Calculating...',
      explanation: 'Complete a few check-ins to personalize your recommendations.',
      hourlyRhythm: [],
      confidence: 0.0,
      isCalibrated: false,
      factors: ['Awaiting initial sleep & task logs'],
    );
  }

  factory ReadinessModel.fromJson(Map<String, dynamic> json) {
    final rhythmList = (json['hourly_rhythm'] as List?)
            ?.map((p) => EnergyPoint(
                  p['label'] as String? ?? '',
                  (p['level'] as num?)?.toDouble() ?? 0.5,
                ))
            .toList() ??
        [];

    final factorsList = (json['factors'] as List?)
            ?.map((f) => f.toString())
            .toList() ??
        const [
          'Consistent wake-up schedule',
          'Circadian focus window active',
        ];

    return ReadinessModel(
      score: (json['score'] as num?)?.toInt() ?? 75,
      maxScore: (json['max_score'] as num?)?.toInt() ?? 100,
      statusMessage: json['status_message'] as String? ?? 'Strong focus window active',
      focusWindowRange: json['focus_window_range'] as String? ?? '9:30 AM - 11:30 AM',
      explanation: json['explanation'] as String? ?? 'Based on your recent rhythm.',
      hourlyRhythm: rhythmList,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.85,
      modelVersion: json['model_version'] as String? ?? 'v1.0.0-deterministic',
      isCalibrated: json['is_calibrated'] as bool? ?? true,
      factors: factorsList,
    );
  }

  Map<String, dynamic> toJson() => {
        'score': score,
        'max_score': maxScore,
        'status_message': statusMessage,
        'focus_window_range': focusWindowRange,
        'explanation': explanation,
        'confidence': confidence,
        'model_version': modelVersion,
        'is_calibrated': isCalibrated,
        'factors': factors,
        'hourly_rhythm': hourlyRhythm
            .map((p) => {'label': p.label, 'level': p.level})
            .toList(),
      };

  ReadinessModel copyWith({
    int? score,
    int? maxScore,
    String? statusMessage,
    String? focusWindowRange,
    String? explanation,
    List<EnergyPoint>? hourlyRhythm,
    double? confidence,
    String? modelVersion,
    bool? isCalibrated,
    List<String>? factors,
  }) {
    return ReadinessModel(
      score: score ?? this.score,
      maxScore: maxScore ?? this.maxScore,
      statusMessage: statusMessage ?? this.statusMessage,
      focusWindowRange: focusWindowRange ?? this.focusWindowRange,
      explanation: explanation ?? this.explanation,
      hourlyRhythm: hourlyRhythm ?? this.hourlyRhythm,
      confidence: confidence ?? this.confidence,
      modelVersion: modelVersion ?? this.modelVersion,
      isCalibrated: isCalibrated ?? this.isCalibrated,
      factors: factors ?? this.factors,
    );
  }
}
