/// Personal Data Model
/// Captures Sleep, Circadian Energy preferences, and Activity load.
class PersonalData {
  final double sleepHours;
  final String wakeTime;
  final String sleepQuality; // "Deep & Restful", "Moderate", "Light"
  final String focusPeak; // "Morning", "Afternoon", "Evening", "Varies"
  final String energyDipTime; // e.g. "2:30 PM"
  final int physicalActivityMinutes;
  final String primaryGoal; // "College", "Work", "Personal projects", "Fitness", "General productivity"

  const PersonalData({
    required this.sleepHours,
    required this.wakeTime,
    required this.sleepQuality,
    required this.focusPeak,
    required this.energyDipTime,
    required this.physicalActivityMinutes,
    required this.primaryGoal,
  });

  PersonalData copyWith({
    double? sleepHours,
    String? wakeTime,
    String? sleepQuality,
    String? focusPeak,
    String? energyDipTime,
    int? physicalActivityMinutes,
    String? primaryGoal,
  }) {
    return PersonalData(
      sleepHours: sleepHours ?? this.sleepHours,
      wakeTime: wakeTime ?? this.wakeTime,
      sleepQuality: sleepQuality ?? this.sleepQuality,
      focusPeak: focusPeak ?? this.focusPeak,
      energyDipTime: energyDipTime ?? this.energyDipTime,
      physicalActivityMinutes: physicalActivityMinutes ?? this.physicalActivityMinutes,
      primaryGoal: primaryGoal ?? this.primaryGoal,
    );
  }
}
