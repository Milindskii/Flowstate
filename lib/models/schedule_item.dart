import '../engines/task_state.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/flow_colors.dart';

/// Schedule Item Model
/// Timeblock representation for Today's Schedule and Calendar.
class ScheduleItem {
  final String id;
  final String? taskId;
  final String time; // "9:30"
  final String period; // "AM" or "PM"
  final String title; // "ML Assignment"
  final String type; // "High Focus"
  final String tagText; // "DEEP WORK"
  final Color tagBg;
  final Color tagColor;
  final bool isActive;
  final bool isCompleted;
  final bool isFixed;
  final bool isConflict;
  final int durationMinutes;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? primaryReason;
  final String? explanation;
  /// Placement proposed for a task with no stored slot (not saved until the user confirms).
  final bool isSuggested;
  /// Stored slot has passed and the task was never started.
  final bool isMissed;
  /// Explicitly skipped or bypassed when the user chose another task to do now.
  final bool isSkipped;
  /// "skipped" | "deferred" when this is a history node from DayScheduleResponse.deviations.
  final String? deviation;
  /// Completed after earlier being skipped/deviated from the planned route.
  final bool isCompletedAfterDeviation;
  /// Task planned window has expired without completion.
  final bool isFailed;
  /// A fixed block the user is away for (e.g. going out): shown everywhere, never work (no complete/skip/redo).
  final bool isCommitment;
  /// Server-derived state: scheduled | active | missed | failed | completed (history nodes: skipped | deferred | missed).
  final String? state;
  /// Where this task's stop belongs on the day path: the slot it was PLANNED for on this day (server `anchor_start`).
  /// A completed task keeps its planned slot here even though [startTime] is when the session ran.
  final DateTime? anchorStart;

  const ScheduleItem({
    required this.id,
    this.taskId,
    required this.time,
    required this.period,
    required this.title,
    required this.type,
    required this.tagText,
    this.tagBg = FlowColors.tagDeepWorkBg,
    this.tagColor = FlowColors.tagDeepWorkText,
    this.isActive = false,
    this.isCompleted = false,
    this.isFixed = false,
    this.isConflict = false,
    this.durationMinutes = 60,
    this.startTime,
    this.endTime,
    this.primaryReason,
    this.explanation,
    this.isSuggested = false,
    this.isMissed = false,
    this.isSkipped = false,
    this.deviation,
    this.isCompletedAfterDeviation = false,
    this.isFailed = false,
    this.isCommitment = false,
    this.state,
    this.anchorStart,
  });

  ScheduleItem copyWith({
    String? id,
    String? taskId,
    String? time,
    String? period,
    String? title,
    String? type,
    String? tagText,
    Color? tagBg,
    Color? tagColor,
    bool? isActive,
    bool? isCompleted,
    bool? isFixed,
    bool? isConflict,
    int? durationMinutes,
    DateTime? startTime,
    DateTime? endTime,
    String? primaryReason,
    String? explanation,
    bool? isSuggested,
    bool? isMissed,
    bool? isSkipped,
    bool? isCompletedAfterDeviation,
    bool? isFailed,
    bool? isCommitment,
    String? state,
    DateTime? anchorStart,
  }) {
    return ScheduleItem(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      time: time ?? this.time,
      period: period ?? this.period,
      title: title ?? this.title,
      type: type ?? this.type,
      tagText: tagText ?? this.tagText,
      tagBg: tagBg ?? this.tagBg,
      tagColor: tagColor ?? this.tagColor,
      isActive: isActive ?? this.isActive,
      isCompleted: isCompleted ?? this.isCompleted,
      isFixed: isFixed ?? this.isFixed,
      isConflict: isConflict ?? this.isConflict,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      primaryReason: primaryReason ?? this.primaryReason,
      explanation: explanation ?? this.explanation,
      isSuggested: isSuggested ?? this.isSuggested,
      isMissed: isMissed ?? this.isMissed,
      isSkipped: isSkipped ?? this.isSkipped,
      deviation: deviation,
      isCompletedAfterDeviation: isCompletedAfterDeviation ?? this.isCompletedAfterDeviation,
      isFailed: isFailed ?? this.isFailed,
      isCommitment: isCommitment ?? this.isCommitment,
      state: state ?? this.state,
      anchorStart: anchorStart ?? this.anchorStart,
    );
  }

  /// Recomputes scheduled/missed/failed from this item's own slot, [now] and the user's bedtime with the one
  /// rule shared with the backend (engines/task_state.dart). Never trusts a stale stored flag: a restart, a date
  /// change or the clock moving on re-derives it. History nodes keep the kind recorded for them.
  ScheduleItem withDerivedState({required DateTime now, required double bedtimeHours}) {
    if (deviation != null) return this;
    // A suggested or unscheduled item has no real slot of its own, so the clock passing it is never a miss.
    if (!isCompleted && !isActive && (isSuggested || tagText == 'UNSCHEDULED')) {
      return copyWith(state: 'scheduled', isMissed: false, isFailed: false);
    }
    final derived = deriveSlotState(
      completed: isCompleted,
      cancelled: false,
      active: isActive,
      start: startTime,
      end: endTime,
      now: now,
      bedtimeHours: bedtimeHours,
      commitment: isCommitment,
    );
    return copyWith(
      state: derived.name,
      isMissed: derived == TaskState.missed,
      isFailed: derived == TaskState.failed,
    );
  }

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'Focus';
    final isFixed = (json['is_fixed'] as bool?) ?? false;
    final isConflict = (json['is_conflict'] as bool?) ?? false;
    final isCompleted = (json['is_completed'] as bool?) ?? false;
    final isActive = (json['is_active'] as bool?) ?? false;

    Color bg = FlowColors.tagDeepWorkBg;
    Color fg = FlowColors.tagDeepWorkText;
    String tag = json['tag_text'] as String? ?? (isFixed ? 'FIXED' : 'DEEP WORK');

    if (isFixed) {
      bg = FlowColors.tagMediumBg;
      fg = FlowColors.tagMediumText;
      tag = 'FIXED';
    } else if (isConflict) {
      bg = Colors.red.withValues(alpha: 0.15);
      fg = Colors.red;
      tag = 'CONFLICT';
    } else if (typeStr.toLowerCase().contains('study') || typeStr.toLowerCase().contains('medium')) {
      bg = FlowColors.tagMediumBg;
      fg = FlowColors.tagMediumText;
      tag = 'MEDIUM';
    } else if (typeStr.toLowerCase().contains('rest') || typeStr.toLowerCase().contains('break')) {
      bg = FlowColors.tagRestBg;
      fg = FlowColors.tagRestText;
      tag = 'REST';
    } else if (typeStr.toLowerCase().contains('admin') || typeStr.toLowerCase().contains('light')) {
      bg = FlowColors.tagLightBg;
      fg = FlowColors.tagLightText;
      tag = 'LIGHT';
    } else if (typeStr.toLowerCase().contains('physical') || typeStr.toLowerCase().contains('fitness')) {
      bg = FlowColors.tagPhysicalBg;
      fg = FlowColors.tagPhysicalText;
      tag = 'PHYSICAL';
    }

    DateTime? startTime;
    if (json['start_time'] != null) {
      startTime = DateTime.tryParse(json['start_time'].toString())?.toLocal();
    }
    DateTime? endTime;
    if (json['end_time'] != null) {
      endTime = DateTime.tryParse(json['end_time'].toString())?.toLocal();
    }

    String timeStr = json['time'] as String? ?? '';
    String periodStr = json['period'] as String? ?? '';
    if (timeStr.isEmpty && startTime != null) {
      timeStr = DateFormat('h:mm').format(startTime.toLocal());
      periodStr = DateFormat('a').format(startTime.toLocal());
    } else if (timeStr.isEmpty) {
      timeStr = '9:00';
      periodStr = 'AM';
    }

    return ScheduleItem(
      id: json['id'] as String? ?? 'sched-${DateTime.now().millisecondsSinceEpoch}',
      taskId: json['task_id'] as String?,
      time: timeStr,
      period: periodStr,
      title: json['title'] as String? ?? 'Focus Block',
      type: typeStr,
      tagText: json['tag_text'] as String? ?? tag,
      tagBg: bg,
      tagColor: fg,
      isActive: isActive,
      isCompleted: isCompleted,
      isFixed: isFixed,
      isConflict: isConflict,
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 60,
      startTime: startTime,
      endTime: endTime,
      primaryReason: json['primary_reason'] as String?,
      explanation: json['explanation'] as String?,
      isSuggested: (json['is_suggested'] as bool?) ?? false,
      isMissed: (json['is_missed'] as bool?) ?? false,
      isSkipped: (json['is_skipped'] as bool?) ?? false,
      deviation: json['deviation'] as String?,
      isCompletedAfterDeviation: (json['is_completed_after_deviation'] as bool?) ?? false,
      anchorStart: json['anchor_start'] == null ? null : DateTime.tryParse(json['anchor_start'].toString())?.toLocal(),
      isFailed: (json['is_failed'] as bool?) ?? false,
      isCommitment: (json['is_commitment'] as bool?) ?? false,
      state: json['state'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (taskId != null) 'task_id': taskId,
        'time': time,
        'period': period,
        'title': title,
        'type': type,
        'tag_text': tagText,
        'is_active': isActive,
        'is_completed': isCompleted,
        'is_fixed': isFixed,
        'is_conflict': isConflict,
        'duration_minutes': durationMinutes,
        if (startTime != null) 'start_time': startTime!.toUtc().toIso8601String(),
        if (endTime != null) 'end_time': endTime!.toUtc().toIso8601String(),
        if (primaryReason != null) 'primary_reason': primaryReason,
        if (explanation != null) 'explanation': explanation,
        'is_suggested': isSuggested,
        'is_missed': isMissed,
        'is_skipped': isSkipped,
        if (deviation != null) 'deviation': deviation,
        'is_completed_after_deviation': isCompletedAfterDeviation,
        if (anchorStart != null) 'anchor_start': anchorStart!.toUtc().toIso8601String(),
        'is_failed': isFailed,
        'is_commitment': isCommitment,
        if (state != null) 'state': state,
      };
}
