import 'package:intl/intl.dart';
import 'schedule_item.dart';
import 'today_model.dart';

/// The day's trophy: every task done (commitments do not count). Server-authoritative.
class DayCompleteStatus {
  final bool eligible;
  final bool claimed;
  final int xp;

  const DayCompleteStatus({this.eligible = false, this.claimed = false, this.xp = 0});

  factory DayCompleteStatus.fromJson(Map<String, dynamic>? json) => DayCompleteStatus(
        eligible: (json?['eligible'] as bool?) ?? false,
        claimed: (json?['claimed'] as bool?) ?? false,
        xp: (json?['xp'] as num?)?.toInt() ?? 0,
      );

  DayCompleteStatus copyWith({bool? eligible, bool? claimed, int? xp}) => DayCompleteStatus(
        eligible: eligible ?? this.eligible, claimed: claimed ?? this.claimed, xp: xp ?? this.xp);

  Map<String, dynamic> toJson() => {'eligible': eligible, 'claimed': claimed, 'xp': xp};
}

/// Authoritative day schedule model matching GET /api/v1/calendar/day
class DayScheduleResponse {
  final String date; // YYYY-MM-DD
  final bool isToday;
  final bool isPast;
  final List<ScheduleItem> timeline;
  final List<ScheduleItem> fixedCommitments;
  final List<ScheduleItem> completedTasks;
  final List<ScheduleItem> remainingTasks;
  final List<ScheduleItem> unscheduledTasks;
  /// Tasks skipped/deferred off this day, at their original slot (display-only history; is_skipped=true).
  /// Not part of [timeline]; the task itself now lives on a later day.
  final List<ScheduleItem> deviations;
  final List<String> conflicts;
  final WorkloadSummaryModel workload;
  final String? focusWindow;
  final int? readinessScore;
  final int totalPlannedMinutes;
  final int remainingCapacityMinutes;
  final DayCompleteStatus dayComplete;

  const DayScheduleResponse({
    required this.date,
    required this.isToday,
    required this.isPast,
    required this.timeline,
    this.fixedCommitments = const [],
    this.completedTasks = const [],
    this.remainingTasks = const [],
    this.unscheduledTasks = const [],
    this.deviations = const [],
    this.conflicts = const [],
    this.workload = const WorkloadSummaryModel(),
    this.focusWindow,
    this.readinessScore,
    this.totalPlannedMinutes = 0,
    this.remainingCapacityMinutes = 0,
    this.dayComplete = const DayCompleteStatus(),
  });

  DayScheduleResponse withDayComplete(DayCompleteStatus status) => DayScheduleResponse(
        date: date,
        isToday: isToday,
        isPast: isPast,
        timeline: timeline,
        fixedCommitments: fixedCommitments,
        completedTasks: completedTasks,
        remainingTasks: remainingTasks,
        unscheduledTasks: unscheduledTasks,
        deviations: deviations,
        conflicts: conflicts,
        workload: workload,
        focusWindow: focusWindow,
        readinessScore: readinessScore,
        totalPlannedMinutes: totalPlannedMinutes,
        remainingCapacityMinutes: remainingCapacityMinutes,
        dayComplete: status,
      );

  /// The same day with its task lists replaced (everything else is carried over untouched).
  DayScheduleResponse withItems({
    List<ScheduleItem>? timeline,
    List<ScheduleItem>? fixedCommitments,
    List<ScheduleItem>? completedTasks,
    List<ScheduleItem>? remainingTasks,
    List<ScheduleItem>? unscheduledTasks,
    List<ScheduleItem>? deviations,
  }) =>
      DayScheduleResponse(
        date: date,
        isToday: isToday,
        isPast: isPast,
        timeline: timeline ?? this.timeline,
        fixedCommitments: fixedCommitments ?? this.fixedCommitments,
        completedTasks: completedTasks ?? this.completedTasks,
        remainingTasks: remainingTasks ?? this.remainingTasks,
        unscheduledTasks: unscheduledTasks ?? this.unscheduledTasks,
        deviations: deviations ?? this.deviations,
        conflicts: conflicts,
        workload: workload,
        focusWindow: focusWindow,
        readinessScore: readinessScore,
        totalPlannedMinutes: totalPlannedMinutes,
        remainingCapacityMinutes: remainingCapacityMinutes,
        dayComplete: dayComplete,
      );

  factory DayScheduleResponse.fromJson(Map<String, dynamic> json) {
    final rawTimeline = json['timeline'] as List? ?? [];
    final rawFixed = json['fixed_commitments'] as List? ?? [];
    final rawCompleted = json['completed_tasks'] as List? ?? [];
    final rawRemaining = json['remaining_tasks'] as List? ?? [];
    final rawUnscheduled = json['unscheduled_tasks'] as List? ?? [];

    return DayScheduleResponse(
      date: json['date'] as String? ?? '',
      isToday: (json['is_today'] as bool?) ?? false,
      isPast: (json['is_past'] as bool?) ?? false,
      timeline: rawTimeline.map((i) => ScheduleItem.fromJson(i as Map<String, dynamic>)).toList(),
      fixedCommitments: rawFixed.map((i) => ScheduleItem.fromJson(i as Map<String, dynamic>)).toList(),
      completedTasks: rawCompleted.map((i) => ScheduleItem.fromJson(i as Map<String, dynamic>)).toList(),
      remainingTasks: rawRemaining.map((i) => ScheduleItem.fromJson(i as Map<String, dynamic>)).toList(),
      unscheduledTasks: rawUnscheduled.map((i) => ScheduleItem.fromJson(i as Map<String, dynamic>)).toList(),
      deviations: (json['deviations'] as List? ?? [])
          .map((i) => ScheduleItem.fromJson(i as Map<String, dynamic>))
          .toList(),
      conflicts: (json['conflicts'] as List?)?.map((c) => c.toString()).toList() ?? const [],
      workload: json['workload'] is Map<String, dynamic>
          ? WorkloadSummaryModel.fromJson(json['workload'] as Map<String, dynamic>)
          : const WorkloadSummaryModel(),
      focusWindow: json['focus_window'] as String?,
      readinessScore: (json['readiness_score'] as num?)?.toInt(),
      totalPlannedMinutes: (json['total_planned_minutes'] as num?)?.toInt() ?? 0,
      remainingCapacityMinutes: (json['remaining_capacity_minutes'] as num?)?.toInt() ?? 0,
      dayComplete: DayCompleteStatus.fromJson(json['day_complete'] as Map<String, dynamic>?),
    );
  }

  factory DayScheduleResponse.empty(String dateStr, {bool isToday = false, bool isPast = false}) {
    return DayScheduleResponse(
      date: dateStr,
      isToday: isToday,
      isPast: isPast,
      timeline: const [],
      fixedCommitments: const [],
      completedTasks: const [],
      remainingTasks: const [],
      unscheduledTasks: const [],
      conflicts: const [],
      workload: const WorkloadSummaryModel(),
      totalPlannedMinutes: 0,
      remainingCapacityMinutes: 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'is_today': isToday,
        'is_past': isPast,
        'timeline': timeline.map((i) => i.toJson()).toList(),
        'fixed_commitments': fixedCommitments.map((i) => i.toJson()).toList(),
        'completed_tasks': completedTasks.map((i) => i.toJson()).toList(),
        'remaining_tasks': remainingTasks.map((i) => i.toJson()).toList(),
        'unscheduled_tasks': unscheduledTasks.map((i) => i.toJson()).toList(),
        'deviations': deviations.map((i) => i.toJson()).toList(),
        'conflicts': conflicts,
        'workload': workload.toJson(),
        if (focusWindow != null) 'focus_window': focusWindow,
        if (readinessScore != null) 'readiness_score': readinessScore,
        'total_planned_minutes': totalPlannedMinutes,
        'remaining_capacity_minutes': remainingCapacityMinutes,
        'day_complete': dayComplete.toJson(),
      };
}

/// A single task diff entry in a proposed plan change
class TaskDiffItem {
  final String taskId;
  final String title;
  final String changeType; // "moved" | "new" | "unchanged" | "cancelled" | "unscheduled" | "protected"
  final String? oldTime;
  final String? newTime;
  final String? oldDate;
  final String? newDate;
  final bool isFixed;
  final int durationMinutes;
  final String? reason;
  /// Authoritative instants (local DateTime parsed from the server's aware ISO strings).
  /// Never rebuild these from the display strings above.
  final DateTime? newStart;
  final DateTime? newEnd;
  final String? newDateIso; // YYYY-MM-DD when moved to another day
  final bool timeLocked;
  /// A fixed block (going out): shown, never work. Always also timeLocked.
  final bool isCommitment;
  /// Whole intervals as the server renders them ("6:30 PM – 8:30 PM"); null from older servers.
  final String? oldTimeRange;
  final String? newTimeRange;
  final String? taskType;
  final String? priority;
  final DateTime? suggestionStart; // roll-over proposal for unscheduled items
  final DateTime? suggestionEnd;
  /// New tasks: index into the server's apply_request.new_tasks, so an edit can patch the exact entry.
  final int? applyIndex;
  /// The task still has the generic fallback name; it must be named before Apply.
  final bool needsTitle;

  const TaskDiffItem({
    required this.taskId,
    required this.title,
    required this.changeType,
    this.oldTime,
    this.newTime,
    this.oldDate,
    this.newDate,
    this.isFixed = false,
    this.durationMinutes = 45,
    this.reason,
    this.newStart,
    this.newEnd,
    this.newDateIso,
    this.timeLocked = false,
    this.isCommitment = false,
    this.oldTimeRange,
    this.newTimeRange,
    this.taskType,
    this.priority,
    this.suggestionStart,
    this.suggestionEnd,
    this.applyIndex,
    this.needsTitle = false,
  });

  /// A copy of a NEW task after the user edited it in the preview.
  TaskDiffItem withNewTaskEdit({
    required String title,
    required int minutes,
    DateTime? start,
    DateTime? end,
    String? newTime,
    String? newTimeRange,
  }) =>
      TaskDiffItem(
        taskId: taskId, title: title, changeType: changeType, oldTime: oldTime,
        newTime: newTime ?? this.newTime, oldDate: oldDate, newDate: newDate, isFixed: isFixed,
        durationMinutes: minutes, reason: reason, newStart: start ?? newStart, newEnd: end ?? newEnd,
        newDateIso: newDateIso, timeLocked: timeLocked, isCommitment: isCommitment, oldTimeRange: oldTimeRange,
        newTimeRange: newTimeRange ?? this.newTimeRange, taskType: taskType, priority: priority,
        suggestionStart: suggestionStart, suggestionEnd: suggestionEnd, applyIndex: applyIndex, needsTitle: false,
      );

  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  /// What the preview shows for this row: the whole interval when it did not change, `old → new` when it did.
  /// Falls back to the start-only labels for servers that don't send ranges.
  String get changeLabel {
    if (oldTimeRange == null && newTimeRange == null) {
      // older server: start times only, as before
      return '${oldTime ?? newTime ?? '--'} → ${newTime ?? oldTime ?? '--'}';
    }
    final from = oldTimeRange ?? newTimeRange!;
    final to = newTimeRange ?? oldTimeRange!;
    return from == to ? from : '$from → $to';
  }

  factory TaskDiffItem.fromJson(Map<String, dynamic> json) {
    return TaskDiffItem(
      taskId: json['task_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      changeType: json['change_type'] as String? ?? 'unchanged',
      oldTime: json['old_time'] as String?,
      newTime: json['new_time'] as String?,
      oldDate: json['old_date'] as String?,
      newDate: json['new_date'] as String?,
      isFixed: (json['is_fixed'] as bool?) ?? false,
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 45,
      reason: json['reason'] as String?,
      newStart: _dt(json['new_start']),
      newEnd: _dt(json['new_end']),
      newDateIso: json['new_date_iso'] as String?,
      timeLocked: (json['time_locked'] as bool?) ?? false,
      isCommitment: (json['is_commitment'] as bool?) ?? false,
      oldTimeRange: json['old_time_range'] as String?,
      newTimeRange: json['new_time_range'] as String?,
      taskType: json['task_type'] as String?,
      priority: json['priority'] as String?,
      suggestionStart: _dt(json['suggestion_start']),
      suggestionEnd: _dt(json['suggestion_end']),
      applyIndex: (json['apply_index'] as num?)?.toInt(),
      needsTitle: (json['needs_title'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'title': title,
        'change_type': changeType,
        if (oldTime != null) 'old_time': oldTime,
        if (newTime != null) 'new_time': newTime,
        if (oldDate != null) 'old_date': oldDate,
        if (newDate != null) 'new_date': newDate,
        'is_fixed': isFixed,
        'duration_minutes': durationMinutes,
        if (reason != null) 'reason': reason,
        if (newStart != null) 'new_start': newStart!.toUtc().toIso8601String(),
        if (newEnd != null) 'new_end': newEnd!.toUtc().toIso8601String(),
        if (newDateIso != null) 'new_date_iso': newDateIso,
        'time_locked': timeLocked,
        'is_commitment': isCommitment,
        if (oldTimeRange != null) 'old_time_range': oldTimeRange,
        if (newTimeRange != null) 'new_time_range': newTimeRange,
        if (taskType != null) 'task_type': taskType,
        if (priority != null) 'priority': priority,
        if (applyIndex != null) 'apply_index': applyIndex,
        'needs_title': needsTitle,
      };
}

/// Structured plan diff returned by POST /api/v1/ai/replan
/// A typed note about a proposed plan. [kind] is one of:
/// conflict | capacity | protected | ambiguous | not_found | unparsed | past | note.
class ReplanIssue {
  final String kind;
  final String message;

  const ReplanIssue({required this.kind, required this.message});

  factory ReplanIssue.fromJson(Map<String, dynamic> json) => ReplanIssue(
        kind: json['kind'] as String? ?? 'note',
        message: json['message'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'kind': kind, 'message': message};

  bool get isTrueConflict => kind == 'conflict';
}

/// One contextual choice under a [ReplanClarification]. Tapping it either re-sends [message] as a Replan
/// request or puts [prefill] in the composer for the user to finish (e.g. "move going out to ").
class ReplanClarificationOption {
  final String label;
  final String? message;
  final String? prefill;

  const ReplanClarificationOption({required this.label, this.message, this.prefill});

  factory ReplanClarificationOption.fromJson(Map<String, dynamic> json) => ReplanClarificationOption(
        label: json['label'] as String? ?? '',
        message: json['message'] as String?,
        prefill: json['prefill'] as String?,
      );
}

/// Noya recognised the task/intent but needs one more detail (or a choice). No plan is proposed yet.
class ReplanClarification {
  final String question;
  final List<ReplanClarificationOption> options;
  final String? taskId;
  final String? taskTitle;

  const ReplanClarification({required this.question, this.options = const [], this.taskId, this.taskTitle});

  factory ReplanClarification.fromJson(Map<String, dynamic> json) => ReplanClarification(
        question: json['question'] as String? ?? '',
        options: (json['options'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ReplanClarificationOption.fromJson)
            .where((o) => o.label.isNotEmpty)
            .toList(),
        taskId: json['task_id'] as String?,
        taskTitle: json['task_title'] as String?,
      );
}

class PlanDiff {
  final String planId;
  final String selectedDate;
  final DateTime? createdAt;
  final List<ScheduleItem> beforeSchedule;
  final List<ScheduleItem> afterSchedule;
  final List<TaskDiffItem> movedTasks;
  final List<TaskDiffItem> newlyScheduledTasks;
  final List<TaskDiffItem> unchangedTasks;
  final List<TaskDiffItem> cancelledTasks;
  final List<TaskDiffItem> unscheduledTasks;
  final List<String> conflicts;
  /// Same notes as [conflicts], typed. Older payloads without it fall back to neutral notes (never red).
  final List<ReplanIssue> issues;
  final String explanation;
  final List<TaskDiffItem> skippedImmutable; // completed / in-progress items that were protected
  final String? timezoneUsed;
  /// Server-authored apply payload. Post it back verbatim (plus a client clock): the client must
  /// not rebuild updates by matching titles or parsing display strings.
  final ApplyReplanRequest? serverApplyRequest;
  /// Set instead of a proposal when Noya needs a missing detail: show the question and its options.
  final ReplanClarification? clarification;

  const PlanDiff({
    required this.planId,
    required this.selectedDate,
    this.createdAt,
    this.beforeSchedule = const [],
    this.afterSchedule = const [],
    this.movedTasks = const [],
    this.newlyScheduledTasks = const [],
    this.unchangedTasks = const [],
    this.cancelledTasks = const [],
    this.unscheduledTasks = const [],
    this.conflicts = const [],
    this.issues = const [],
    this.explanation = '',
    this.skippedImmutable = const [],
    this.timezoneUsed,
    this.serverApplyRequest,
    this.clarification,
  });

  factory PlanDiff.fromJson(Map<String, dynamic> json) {
    final rawBefore = json['before_schedule'] as List? ?? [];
    final rawAfter = json['after_schedule'] as List? ?? [];
    final rawMoved = json['moved_tasks'] as List? ?? [];
    final rawNew = json['newly_scheduled_tasks'] as List? ?? [];
    final rawUnchanged = json['unchanged_tasks'] as List? ?? [];
    final rawCancelled = json['cancelled_tasks'] as List? ?? [];
    final rawUnscheduled = json['unscheduled_tasks'] as List? ?? [];
    final rawConflicts = json['conflicts'] as List? ?? [];

    DateTime? created;
    if (json['created_at'] != null) {
      created = DateTime.tryParse(json['created_at'].toString());
    }

    return PlanDiff(
      planId: json['plan_id'] as String? ?? '',
      selectedDate: json['selected_date'] as String? ?? '',
      createdAt: created,
      beforeSchedule: rawBefore.map((i) => ScheduleItem.fromJson(i as Map<String, dynamic>)).toList(),
      afterSchedule: rawAfter.map((i) => ScheduleItem.fromJson(i as Map<String, dynamic>)).toList(),
      movedTasks: rawMoved.map((i) => TaskDiffItem.fromJson(i as Map<String, dynamic>)).toList(),
      newlyScheduledTasks: rawNew.map((i) => TaskDiffItem.fromJson(i as Map<String, dynamic>)).toList(),
      unchangedTasks: rawUnchanged.map((i) => TaskDiffItem.fromJson(i as Map<String, dynamic>)).toList(),
      cancelledTasks: rawCancelled.map((i) => TaskDiffItem.fromJson(i as Map<String, dynamic>)).toList(),
      unscheduledTasks: rawUnscheduled.map((i) => TaskDiffItem.fromJson(i as Map<String, dynamic>)).toList(),
      conflicts: rawConflicts.map((c) => c.toString()).toList(),
      issues: json['issues'] is List
          ? (json['issues'] as List).map((i) => ReplanIssue.fromJson(i as Map<String, dynamic>)).toList()
          : rawConflicts.map((c) => ReplanIssue(kind: 'note', message: c.toString())).toList(),
      explanation: json['explanation'] as String? ?? '',
      skippedImmutable: (json['skipped_immutable'] as List? ?? [])
          .map((i) => TaskDiffItem.fromJson(i as Map<String, dynamic>))
          .toList(),
      timezoneUsed: json['timezone_used'] as String?,
      serverApplyRequest: json['apply_request'] is Map<String, dynamic>
          ? ApplyReplanRequest.fromServerJson(json['apply_request'] as Map<String, dynamic>)
          : null,
      clarification: json['clarification'] is Map<String, dynamic>
          ? ReplanClarification.fromJson(json['clarification'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'plan_id': planId,
        'selected_date': selectedDate,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        'before_schedule': beforeSchedule.map((i) => i.toJson()).toList(),
        'after_schedule': afterSchedule.map((i) => i.toJson()).toList(),
        'moved_tasks': movedTasks.map((i) => i.toJson()).toList(),
        'newly_scheduled_tasks': newlyScheduledTasks.map((i) => i.toJson()).toList(),
        'unchanged_tasks': unchangedTasks.map((i) => i.toJson()).toList(),
        'cancelled_tasks': cancelledTasks.map((i) => i.toJson()).toList(),
        'unscheduled_tasks': unscheduledTasks.map((i) => i.toJson()).toList(),
        'conflicts': conflicts,
        'issues': issues.map((i) => i.toJson()).toList(),
        'explanation': explanation,
        'skipped_immutable': skippedImmutable.map((i) => i.toJson()).toList(),
        if (timezoneUsed != null) 'timezone_used': timezoneUsed,
        if (serverApplyRequest != null) 'apply_request': serverApplyRequest!.toJson(),
      };

  /// True while a new task still carries the generic fallback name: Apply stays disabled until it is named.
  bool get hasUnnamedNewTask =>
      newlyScheduledTasks.any((t) => t.needsTitle) || unscheduledTasks.any((t) => t.needsTitle);

  /// The proposal after the user edited a NEW task before Apply. Only the draft changes: the server-authored
  /// `new_tasks[applyIndex]` entry, the preview rows and the day timeline are patched together, so what the
  /// user sees is exactly what Apply sends (the server still validates overlap/past on apply).
  PlanDiff withEditedNewTask({
    required int applyIndex,
    required String title,
    required int minutes,
    DateTime? start,
  }) {
    final cleanTitle = title.trim();
    final raw = serverApplyRequest?.raw;
    ApplyReplanRequest? patched = serverApplyRequest;
    if (raw != null && raw['new_tasks'] is List && (raw['new_tasks'] as List).length > applyIndex) {
      final next = Map<String, dynamic>.from(raw);
      final list = (next['new_tasks'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final nt = list[applyIndex];
      nt['title'] = cleanTitle;
      nt['estimated_minutes'] = minutes;
      DateTime? s = start ?? DateTime.tryParse('${nt['scheduled_start'] ?? ''}')?.toLocal();
      if (s != null) {
        nt['scheduled_start'] = s.toUtc().toIso8601String();
        nt['scheduled_end'] = s.add(Duration(minutes: minutes)).toUtc().toIso8601String();
        if (start != null) nt['time_locked'] = true; // an explicitly chosen time is kept as chosen
      }
      next['new_tasks'] = list;
      patched = ApplyReplanRequest.fromServerJson(next);
    }

    String? startLabel;
    String? rangeLabel;
    DateTime? newStart;
    DateTime? newEnd;
    List<TaskDiffItem> edit(List<TaskDiffItem> items) => items.map((t) {
          if (t.applyIndex != applyIndex || t.changeType != 'new' && t.changeType != 'unscheduled') return t;
          newStart = start ?? t.newStart;
          newEnd = newStart?.add(Duration(minutes: minutes));
          if (newStart != null) {
            startLabel = DateFormat('h:mm a').format(newStart!);
            rangeLabel = '$startLabel – ${DateFormat('h:mm a').format(newEnd!)}';
          }
          return t.withNewTaskEdit(
              title: cleanTitle, minutes: minutes, start: newStart, end: newEnd,
              newTime: startLabel, newTimeRange: rangeLabel);
        }).toList();

    final newItems = edit(newlyScheduledTasks);
    final unschedItems = edit(unscheduledTasks);
    final target = newItems.where((t) => t.applyIndex == applyIndex).toList();
    final targetId = target.isNotEmpty ? target.first.taskId : null;
    final after = afterSchedule.map((a) {
      if (targetId == null || (a.taskId != targetId && a.id != targetId)) return a;
      final st = newStart ?? a.startTime;
      return a.copyWith(
        title: cleanTitle,
        durationMinutes: minutes,
        startTime: st,
        endTime: st?.add(Duration(minutes: minutes)),
        time: st != null ? DateFormat('h:mm').format(st) : a.time,
        period: st != null ? DateFormat('a').format(st) : a.period,
      );
    }).toList();

    return PlanDiff(
      planId: planId, selectedDate: selectedDate, createdAt: createdAt, beforeSchedule: beforeSchedule,
      afterSchedule: after, movedTasks: movedTasks, newlyScheduledTasks: newItems, unchangedTasks: unchangedTasks,
      cancelledTasks: cancelledTasks, unscheduledTasks: unschedItems, conflicts: conflicts, issues: issues, explanation: explanation,
      skippedImmutable: skippedImmutable, timezoneUsed: timezoneUsed, serverApplyRequest: patched,
    );
  }

  List<ReplanIssue> issuesOfKind(Set<String> kinds) => issues.where((i) => kinds.contains(i.kind)).toList();

  /// True only when the plan clashes with something fixed. Capacity, protected blocks and unclear
  /// instructions are not failures and never turn the preview red.
  bool get hasTrueConflict => issues.any((i) => i.isTrueConflict);

  /// The scheduler's explanation without the notes that are already listed as issues.
  String get summaryText {
    var text = explanation;
    for (final c in conflicts) {
      text = text.replaceAll(c, '');
    }
    return text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// The payload for POST /api/v1/calendar/apply-replan.
  /// Uses the server-authored request whenever the server supplied one (always, for a real
  /// backend). The client-side fallback below exists only for offline/demo diffs.
  ApplyReplanRequest toApplyRequest() {
    if (serverApplyRequest != null) return serverApplyRequest!;
    final updates = <TaskScheduleUpdateModel>[];
    for (final moved in movedTasks) {
      if (moved.taskId.isEmpty) continue;
      // Match in afterSchedule
      final match = afterSchedule.firstWhere(
        (item) => (item.taskId != null && item.taskId == moved.taskId) || item.id == moved.taskId || item.title == moved.title,
        orElse: () => ScheduleItem(
          id: moved.taskId,
          taskId: moved.taskId,
          time: moved.newTime ?? '',
          period: '',
          title: moved.title,
          type: 'Focus',
          tagText: 'TASK',
        ),
      );

      DateTime? start = match.startTime;
      DateTime? end = match.endTime;

      if (start == null && moved.newTime != null) {
        start = _parseTimeWithDate(selectedDate, moved.newTime!);
        if (start != null) {
          end = start.add(Duration(minutes: moved.durationMinutes));
        }
      }

      updates.add(TaskScheduleUpdateModel(
        taskId: moved.taskId,
        scheduledStart: start,
        scheduledEnd: end,
      ));
    }

    final news = <NewTaskCreateModel>[];
    for (final nt in newlyScheduledTasks) {
      final match = afterSchedule.firstWhere(
        (item) => (item.taskId != null && item.taskId == nt.taskId) || item.title == nt.title,
        orElse: () => ScheduleItem(
          id: nt.taskId,
          taskId: nt.taskId,
          time: nt.newTime ?? '',
          period: '',
          title: nt.title,
          type: 'Focus',
          tagText: 'TASK',
        ),
      );

      DateTime? start = match.startTime;
      DateTime? end = match.endTime;

      if (start == null && nt.newTime != null) {
        start = _parseTimeWithDate(selectedDate, nt.newTime!);
        if (start != null) {
          end = start.add(Duration(minutes: nt.durationMinutes));
        }
      }

      news.add(NewTaskCreateModel(
        title: nt.title,
        estimatedMinutes: nt.durationMinutes > 0 ? nt.durationMinutes : 45,
        taskType: nt.taskType ?? 'deep_work',
        priority: nt.priority ?? 'medium',
        scheduledStart: start,
        scheduledEnd: end,
        source: 'manual',
      ));
    }

    final cancelledIds = cancelledTasks.map((c) => c.taskId).where((id) => id.isNotEmpty).toList();

    return ApplyReplanRequest(
      planId: planId,
      selectedDate: selectedDate,
      taskUpdates: updates,
      newTasks: news,
      cancelledTaskIds: cancelledIds,
    );
  }

  static DateTime? _parseTimeWithDate(String dateStr, String timeStr) {
    try {
      final dateParts = dateStr.split('-');
      if (dateParts.length < 3) return null;
      final y = int.parse(dateParts[0]);
      final m = int.parse(dateParts[1]);
      final d = int.parse(dateParts[2]);

      final match = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?', caseSensitive: false).firstMatch(timeStr.trim());
      if (match != null) {
        int h = int.parse(match.group(1)!);
        final min = int.parse(match.group(2) ?? '0');
        final period = match.group(3)?.toUpperCase();
        if (period == 'PM' && h < 12) h += 12;
        if (period == 'AM' && h == 12) h = 0;
        return DateTime(y, m, d, h, min);
      }
    } catch (_) {}
    return null;
  }
}

/// Replan response from POST /api/v1/ai/replan
class ReplanResponse {
  final bool success;
  final PlanDiff planDiff;
  final String userIntentSummary;

  const ReplanResponse({
    required this.success,
    required this.planDiff,
    required this.userIntentSummary,
  });

  factory ReplanResponse.fromJson(Map<String, dynamic> json) {
    return ReplanResponse(
      success: (json['success'] as bool?) ?? false,
      planDiff: json['plan_diff'] is Map<String, dynamic>
          ? PlanDiff.fromJson(json['plan_diff'] as Map<String, dynamic>)
          : PlanDiff(
              planId: 'diff-fallback',
              selectedDate: json['selected_date'] as String? ?? '',
            ),
      userIntentSummary: json['user_intent_summary'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'plan_diff': planDiff.toJson(),
        'user_intent_summary': userIntentSummary,
      };
}

/// Task schedule update for atomic replan application
class TaskScheduleUpdateModel {
  final String taskId;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? deadlineAt;

  const TaskScheduleUpdateModel({
    required this.taskId,
    this.scheduledStart,
    this.scheduledEnd,
    this.deadlineAt,
  });

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        if (scheduledStart != null) 'scheduled_start': scheduledStart!.toUtc().toIso8601String(),
        if (scheduledEnd != null) 'scheduled_end': scheduledEnd!.toUtc().toIso8601String(),
        if (deadlineAt != null) 'deadline_at': deadlineAt!.toUtc().toIso8601String(),
      };
}

/// Model for creating a new task when applying a replan
class NewTaskCreateModel {
  final String title;
  final String? description;
  final String? category;
  final String taskType;
  final String? difficulty;
  final String priority;
  final int estimatedMinutes;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? deadlineAt;
  final String source;

  const NewTaskCreateModel({
    required this.title,
    this.description,
    this.category,
    this.taskType = 'deep_work',
    this.difficulty = 'medium',
    this.priority = 'medium',
    this.estimatedMinutes = 45,
    this.scheduledStart,
    this.scheduledEnd,
    this.deadlineAt,
    this.source = 'quick_add',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        if (description != null) 'description': description,
        if (category != null) 'category': category,
        'task_type': taskType,
        if (difficulty != null) 'difficulty': difficulty,
        'priority': priority,
        'estimated_minutes': estimatedMinutes,
        if (scheduledStart != null) 'scheduled_start': scheduledStart!.toUtc().toIso8601String(),
        if (scheduledEnd != null) 'scheduled_end': scheduledEnd!.toUtc().toIso8601String(),
        if (deadlineAt != null) 'deadline_at': deadlineAt!.toUtc().toIso8601String(),
        'source': source,
      };
}

/// Payload for POST /api/v1/calendar/apply-replan
class ApplyReplanRequest {
  final String planId;
  final String selectedDate;
  final List<TaskScheduleUpdateModel> taskUpdates;
  final List<NewTaskCreateModel> newTasks;
  final List<String> cancelledTaskIds;
  final String? timezone;
  final DateTime? currentLocalTime;
  /// Exact server payload (keeps explicit nulls, e.g. clearing a slot, and concurrency tokens).
  final Map<String, dynamic>? raw;

  const ApplyReplanRequest({
    required this.planId,
    required this.selectedDate,
    this.taskUpdates = const [],
    this.newTasks = const [],
    this.cancelledTaskIds = const [],
    this.timezone,
    this.currentLocalTime,
    this.raw,
  });

  factory ApplyReplanRequest.fromServerJson(Map<String, dynamic> json) {
    return ApplyReplanRequest(
      planId: json['plan_id'] as String? ?? '',
      selectedDate: json['selected_date'] as String? ?? '',
      cancelledTaskIds: (json['cancelled_task_ids'] as List? ?? []).map((e) => e.toString()).toList(),
      timezone: json['timezone'] as String?,
      raw: Map<String, dynamic>.from(json),
    );
  }

  ApplyReplanRequest withClock(DateTime now, {String? timezoneName}) => ApplyReplanRequest(
        planId: planId,
        selectedDate: selectedDate,
        taskUpdates: taskUpdates,
        newTasks: newTasks,
        cancelledTaskIds: cancelledTaskIds,
        timezone: timezoneName ?? timezone,
        currentLocalTime: now,
        raw: raw,
      );

  Map<String, dynamic> toJson() {
    final base = raw != null
        ? Map<String, dynamic>.from(raw!)
        : <String, dynamic>{
            'plan_id': planId,
            'selected_date': selectedDate,
            'task_updates': taskUpdates.map((u) => u.toJson()).toList(),
            'new_tasks': newTasks.map((t) => t.toJson()).toList(),
            'cancelled_task_ids': cancelledTaskIds,
          };
    if (timezone != null) base['timezone'] = timezone;
    if (currentLocalTime != null) base['current_local_time'] = currentLocalTime!.toUtc().toIso8601String();
    return base;
  }
}

/// Response from POST /api/v1/calendar/apply-replan
class ApplyReplanResponse {
  final bool success;
  final int updatedCount;
  final int createdCount;
  final int cancelledCount;
  final String message;
  final List<Map<String, dynamic>> skipped; // [{task_id, reason}]
  final List<Map<String, dynamic>> persistedTasks; // rows exactly as stored; use to update local state
  final bool idempotentReplay;

  const ApplyReplanResponse({
    required this.success,
    this.updatedCount = 0,
    this.createdCount = 0,
    this.cancelledCount = 0,
    this.message = '',
    this.skipped = const [],
    this.persistedTasks = const [],
    this.idempotentReplay = false,
  });

  factory ApplyReplanResponse.fromJson(Map<String, dynamic> json) {
    return ApplyReplanResponse(
      success: (json['success'] as bool?) ?? false,
      updatedCount: (json['updated_count'] as num?)?.toInt() ?? 0,
      createdCount: (json['created_count'] as num?)?.toInt() ?? 0,
      cancelledCount: (json['cancelled_count'] as num?)?.toInt() ?? 0,
      message: json['message'] as String? ?? '',
      skipped: (json['skipped'] as List? ?? []).whereType<Map<String, dynamic>>().toList(),
      persistedTasks: (json['persisted_tasks'] as List? ?? []).whereType<Map<String, dynamic>>().toList(),
      idempotentReplay: (json['idempotent_replay'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'updated_count': updatedCount,
        'created_count': createdCount,
        'cancelled_count': cancelledCount,
        'message': message,
      };
}


