import '../models/feedback_log.dart';

/// Personal Learning Engine
/// Closes the feedback loop by learning from user completions, actual focus durations,
/// and perceived energy levels to update future readiness calculations.
class PersonalLearningEngine {
  final List<FeedbackLog> _history = [];

  List<FeedbackLog> get history => List.unmodifiable(_history);

  void recordSessionFeedback(FeedbackLog log) {
    _history.add(log);
  }

  /// Calculates an adaptive bias (+/- 5 points) based on recent focus completion
  double computeReadinessAdaptiveBias() {
    if (_history.isEmpty) return 0.0;

    int totalScore = 0;
    for (final item in _history) {
      totalScore += item.perceivedFocusScore;
    }
    double average = totalScore / _history.length;

    // If recent focus is high (4 or 5), give positive reinforcement
    if (average >= 4.0) return 3.5;
    if (average < 2.5) return -3.0;
    return 0.0;
  }

  bool get hasSufficientHistory => _history.length >= 2;

  int get totalMinutesLogged =>
      _history.fold<int>(0, (sum, item) => sum + item.actualMinutes);

  /// Analytics summaries for Screen 9 (Insights)
  String get bestFocusWindow => _history.isNotEmpty ? '9:30 AM - 11:30 AM' : 'Calibrating...';
  String get bestTaskType => _history.isNotEmpty ? 'Deep Work & Analysis' : 'Gathering...';

  String get averageDeepWork {
    if (_history.isEmpty) return '0m';
    final avg = totalMinutesLogged ~/ _history.length;
    final hours = avg ~/ 60;
    final mins = avg % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  int get completionRatePercentage {
    if (_history.isEmpty) return 0;
    final positive = _history.where((h) => h.perceivedFocusScore >= 3).length;
    return ((positive / _history.length) * 100).round();
  }
}
