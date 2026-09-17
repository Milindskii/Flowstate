import '../models/personal_data.dart';
import '../models/readiness_model.dart';

/// Readiness Model Engine
/// Synthesizes personal sleep, activity, and circadian data to calculate
/// cognitive readiness and optimal focus windows.
/// (STRICTLY NON-MEDICAL - NO CORTISOL OR CLINICAL CLAIMS)
class ReadinessEngine {
  const ReadinessEngine();

  ReadinessModel computeReadiness({
    required PersonalData personalData,
    double adaptiveBias = 0.0,
  }) {
    // Base calculation from sleep duration (ideal: 7.5 - 8.5 hours)
    double sleepScore = (personalData.sleepHours / 8.0) * 45.0;
    if (sleepScore > 45.0) sleepScore = 45.0;

    // Circadian alignment factor
    double rhythmScore = 35.0;
    if (personalData.focusPeak == 'Morning') {
      rhythmScore = 38.0;
    } else if (personalData.focusPeak == 'Varies') {
      rhythmScore = 30.0;
    }

    // Physical recovery factor
    double activityFactor = (personalData.physicalActivityMinutes > 0) ? -2.0 : 0.0;

    int totalScore = (sleepScore + rhythmScore + activityFactor + adaptiveBias).round();
    totalScore = totalScore.clamp(40, 98);

    // Determine focus window based on user peak
    String windowRange = '9:30 AM - 11:45 AM';
    String status = 'Strong focus window coming up';

    if (personalData.focusPeak == 'Afternoon') {
      windowRange = '2:00 PM - 4:15 PM';
      status = 'Afternoon focus peak projected';
    } else if (personalData.focusPeak == 'Evening') {
      windowRange = '7:00 PM - 9:30 PM';
      status = 'Evening deep work peak';
    }

    // Circadian energy curve points (6am to 6pm)
    final List<EnergyPoint> rhythm = [
      const EnergyPoint('6a', 0.28),
      const EnergyPoint('8a', 0.52),
      const EnergyPoint('10a', 0.88), // Morning peak
      const EnergyPoint('12p', 0.72),
      const EnergyPoint('2p', 0.42),  // Post-lunch dip
      const EnergyPoint('4p', 0.65),  // Second surge
      const EnergyPoint('6p', 0.55),
    ];

    return ReadinessModel(
      score: totalScore,
      maxScore: 100,
      statusMessage: status,
      focusWindowRange: windowRange,
      explanation: 'Based on your recent sleep, schedule and activity.',
      hourlyRhythm: rhythm,
    );
  }
}
