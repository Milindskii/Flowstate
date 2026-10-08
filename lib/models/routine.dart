/// A routine detected in a Build My Day dump. Nothing is saved until the user confirms it.
class RoutineProposal {
  final String proposalId;
  final String? candidateId;
  final String title;
  final String taskType;
  final String category;
  final int estimatedMinutes;
  final String kind; // fixed | preferred | earliest | avoid
  final String recurrence; // daily | weekly
  final List<int> weekdays; // Monday = 0
  final String? startHhmm;
  final String? endHhmm;
  final String summary; // "Every day · 4:00 PM"
  final List<DateTime> planDates; // dates a confirm would plan (bounded horizon)
  final int horizonDays;

  const RoutineProposal({
    required this.proposalId,
    this.candidateId,
    required this.title,
    this.taskType = 'personal',
    this.category = 'General',
    this.estimatedMinutes = 45,
    required this.kind,
    required this.recurrence,
    this.weekdays = const [],
    this.startHhmm,
    this.endHhmm,
    required this.summary,
    this.planDates = const [],
    this.horizonDays = 7,
  });

  /// Only fixed/preferred routines create task rows; earliest/avoid just shape future planning.
  bool get createsTasks => kind == 'fixed' || kind == 'preferred';

  factory RoutineProposal.fromJson(Map<String, dynamic> json) {
    return RoutineProposal(
      proposalId: json['proposal_id'] as String? ?? '',
      candidateId: json['candidate_id'] as String?,
      title: json['title'] as String? ?? 'Routine',
      taskType: json['task_type'] as String? ?? 'personal',
      category: json['category'] as String? ?? 'General',
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt() ?? 45,
      kind: json['kind'] as String? ?? 'fixed',
      recurrence: json['recurrence'] as String? ?? 'daily',
      weekdays: (json['weekdays'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [],
      startHhmm: json['start_hhmm'] as String?,
      endHhmm: json['end_hhmm'] as String?,
      summary: json['summary'] as String? ?? '',
      planDates: (json['plan_dates'] as List<dynamic>?)
              ?.map((e) => DateTime.tryParse(e.toString()))
              .whereType<DateTime>()
              .toList() ??
          const [],
      horizonDays: (json['horizon_days'] as num?)?.toInt() ?? 7,
    );
  }

  Map<String, dynamic> toCreateJson({required String idempotencyKey, String? timezone, DateTime? now}) => {
        'title': title,
        'task_type': taskType,
        'category': category,
        'estimated_minutes': estimatedMinutes,
        'kind': kind,
        'recurrence': recurrence,
        if (recurrence == 'weekly') 'weekdays': weekdays,
        if (startHhmm != null) 'start_hhmm': startHhmm,
        if (endHhmm != null) 'end_hhmm': endHhmm,
        'idempotency_key': idempotencyKey,
        if (timezone != null) 'timezone': timezone,
        if (now != null) 'current_local_time': now.toIso8601String(),
      };
}

/// A saved routine template.
class Routine {
  final String id;
  final String title;
  final String kind;
  final String recurrence;
  final List<int> weekdays;
  final String? startHhmm;
  final String? endHhmm;
  final int estimatedMinutes;
  final String summary;

  /// Weekly cycle (server-owned): occurrences are planned through [confirmedThrough]; when [continuationDue] Noya asks
  /// "Continue your routine next week?"; [paused] after a "Not now" once that week is over.
  final DateTime? confirmedThrough;
  final bool continuationDue;
  final bool paused;

  const Routine({
    required this.id,
    required this.title,
    required this.kind,
    required this.recurrence,
    this.weekdays = const [],
    this.startHhmm,
    this.endHhmm,
    this.estimatedMinutes = 45,
    required this.summary,
    this.confirmedThrough,
    this.continuationDue = false,
    this.paused = false,
  });

  bool get createsTasks => kind == 'fixed' || kind == 'preferred';

  static const List<String> dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// "Mon · Wed · Fri", "Every day", "Weekdays".
  String get daysLabel {
    if (recurrence != 'weekly' || weekdays.isEmpty || weekdays.length == 7) return 'Every day';
    final sorted = [...weekdays]..sort();
    if (sorted.join(',') == '0,1,2,3,4') return 'Weekdays';
    return sorted.map((d) => dayNames[d.clamp(0, 6)]).join(' · ');
  }

  /// "7:00 PM" from "19:00" (empty without a time).
  String get timeLabel {
    final hhmm = startHhmm;
    if (hhmm == null || hhmm.length < 5) return '';
    final h = int.tryParse(hhmm.substring(0, 2)) ?? 0;
    final m = hhmm.substring(3, 5);
    return '${h % 12 == 0 ? 12 : h % 12}:$m ${h < 12 ? 'AM' : 'PM'}';
  }

  /// The cycle end as the server's local date string (sent back as replay protection).
  String? get cycleEndParam => confirmedThrough == null
      ? null
      : '${confirmedThrough!.year.toString().padLeft(4, '0')}-${confirmedThrough!.month.toString().padLeft(2, '0')}-${confirmedThrough!.day.toString().padLeft(2, '0')}';

  factory Routine.fromJson(Map<String, dynamic> json) {
    return Routine(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Routine',
      kind: json['kind'] as String? ?? 'fixed',
      recurrence: json['recurrence'] as String? ?? 'daily',
      weekdays: (json['weekdays'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [],
      startHhmm: json['start_hhmm'] as String?,
      endHhmm: json['end_hhmm'] as String?,
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt() ?? 45,
      summary: json['summary'] as String? ?? '',
      confirmedThrough: DateTime.tryParse(json['confirmed_through'] as String? ?? ''),
      continuationDue: json['continuation_due'] as bool? ?? false,
      paused: json['paused'] as bool? ?? false,
    );
  }
}
