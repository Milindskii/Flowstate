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
  final String? bedtime; // e.g. "23:00"

  const PersonalData({
    required this.sleepHours,
    required this.wakeTime,
    required this.sleepQuality,
    required this.focusPeak,
    required this.energyDipTime,
    required this.physicalActivityMinutes,
    required this.primaryGoal,
    this.bedtime,
  });

  double get bedtimeHour {
    if (bedtime != null && bedtime!.contains(':')) {
      final parts = bedtime!.split(':');
      final h = int.tryParse(parts[0]) ?? 23;
      final m = int.tryParse(parts[1]) ?? 0;
      return h + m / 60.0;
    }
    // Derive bedtime from wakeTime and sleepHours
    final digitsOnly = wakeTime.replaceAll(RegExp(r'[^\d:]'), '');
    final parts = digitsOnly.split(':');
    final wakeH = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 7) : 7;
    final wakeM = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    var bt = (wakeH + wakeM / 60.0) - sleepHours;
    while (bt < 0) {
      bt += 24.0;
    }
    return bt;
  }

  PersonalData copyWith({
    double? sleepHours,
    String? wakeTime,
    String? sleepQuality,
    String? focusPeak,
    String? energyDipTime,
    int? physicalActivityMinutes,
    String? primaryGoal,
    String? bedtime,
  }) {
    return PersonalData(
      sleepHours: sleepHours ?? this.sleepHours,
      wakeTime: wakeTime ?? this.wakeTime,
      sleepQuality: sleepQuality ?? this.sleepQuality,
      focusPeak: focusPeak ?? this.focusPeak,
      energyDipTime: energyDipTime ?? this.energyDipTime,
      physicalActivityMinutes: physicalActivityMinutes ?? this.physicalActivityMinutes,
      primaryGoal: primaryGoal ?? this.primaryGoal,
      bedtime: bedtime ?? this.bedtime,
    );
  }
}
