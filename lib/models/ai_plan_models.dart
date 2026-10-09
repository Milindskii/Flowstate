import 'package:intl/intl.dart';
import '../core/config/brain_dump_limit.dart';
import 'routine.dart';
import 'task_item.dart';

/// Structured task item returned by the Gemini input-understanding layer.
class ExtractedTaskItem {
  final String title;
  final String? description;
  final String type; // 'deep_work', 'study', 'physical', 'admin', 'recovery', etc.
  final int estimatedMinutes;
  final String difficulty; // 'light', 'medium', 'high', 'physical'
  final String? priority; // 'low', 'medium', 'high', 'urgent', or null
  final String prioritySource; // 'explicit', 'inferred', or 'unspecified'
  final String? deadline; // e.g. "2026-09-26" or "tomorrow"
  final String? fixedStart; // e.g. "18:00"
  final String? targetDate; // e.g. "2026-10-02" — calendar day for fixed_start
  final bool isDurationExplicit;
  final bool isRecurring;
  final List<String> dependencies;
  final double confidence;
  final bool needsConfirmation;
  final DateTime? recommendedSlotStart;
  final DateTime? recommendedSlotEnd;
  final String? recommendedSlotDisplay;
  final String? schedulingExplanation;
  final Map<String, dynamic>? schedulingReasons;
  /// Server verdict: the user stated this exact clock time (lock source L1). Never true for
  /// scheduler recommendations.
  final bool timeLocked;
  final bool isCommitment; // server-persisted fixed block ("Going out 6:30-8:30")
  final String? recommendedSlotDate; // user-local YYYY-MM-DD of the recommended slot
  final String? unscheduledReason; // e.g. explicit_time_in_past, no_capacity
  final List<Map<String, dynamic>> validationIssues; // [{code, field, message}]
  final DateTime? suggestedSlotStart; // roll-over proposal, never auto-applied
  final String? suggestedSlotDisplay;
  final DateTime? deadlineAt; // full deadline instant from the backend (keeps the time, e.g. 23:00)
  final String? plannedDate; // backend-chosen owning day, YYYY-MM-DD
  final String? candidateId; // stable id; depends_on refers to it
  final String? durationSource;
  final String? focusLevel;
  final String? focusSource;
  final String? deadlineKind;
  final List<String> dependsOn;
  final DateTime? preferredStart; // top-level preferred times are user-stated only
  final DateTime? preferredWindowStart;
  final DateTime? preferredWindowEnd;
  /// This explicit one-day request replaces that day's routine occurrence (routine itself unchanged).
  final String? routineOverrideId;
  final String? routineOverrideDate; // YYYY-MM-DD

  const ExtractedTaskItem({
    required this.title,
    this.description,
    required this.type,
    required this.estimatedMinutes,
    required this.difficulty,
    this.priority,
    required this.prioritySource,
    this.deadline,
    this.fixedStart,
    this.targetDate,
    this.isDurationExplicit = false,
    this.isRecurring = false,
    this.dependencies = const [],
    this.confidence = 1.0,
    this.needsConfirmation = false,
    this.recommendedSlotStart,
    this.recommendedSlotEnd,
    this.recommendedSlotDisplay,
    this.schedulingExplanation,
    this.schedulingReasons,
    this.timeLocked = false,
    this.isCommitment = false,
    this.recommendedSlotDate,
    this.unscheduledReason,
    this.validationIssues = const [],
    this.suggestedSlotStart,
    this.suggestedSlotDisplay,
    this.deadlineAt,
    this.plannedDate,
    this.candidateId,
    this.durationSource,
    this.focusLevel,
    this.focusSource,
    this.deadlineKind,
    this.dependsOn = const [],
    this.preferredStart,
    this.preferredWindowStart,
    this.preferredWindowEnd,
    this.routineOverrideId,
    this.routineOverrideDate,
  });

  bool get isPriorityExplicit => prioritySource == 'explicit';
  bool get isPriorityInferred => prioritySource == 'inferred';
  bool get isPriorityUnspecified => prioritySource == 'unspecified' || priority == null;

  factory ExtractedTaskItem.fromJson(Map<String, dynamic> json) {
    final rawPrio = json['priority'] as String?;
    final prioSrc = json['priority_source'] as String? ??
        (rawPrio != null ? 'inferred' : 'unspecified');

    final missing = (json['missing_fields'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    final durExplicit = json['is_duration_explicit'] as bool? ??
        (json['field_provenance']?['duration']?['source'] != null
            ? json['field_provenance']['duration']['source'] == 'explicit'
            : !missing.contains('duration'));

    DateTime? recStart;
    if (json['recommended_slot_start'] != null) {
      recStart = DateTime.tryParse(json['recommended_slot_start'].toString())?.toLocal();
    }
    DateTime? recEnd;
    if (json['recommended_slot_end'] != null) {
      recEnd = DateTime.tryParse(json['recommended_slot_end'].toString())?.toLocal();
    }

    final temporal = json['temporal'] as Map<String, dynamic>?;

    String? targetDate = json['target_date'] as String? ?? temporal?['target_date'] as String?;
    String? fixedStart = json['fixed_start'] as String?;
    if (fixedStart == null) {
      final temporalFixed = temporal?['fixed_start']?.toString();
      final schedStart = json['scheduled_start']?.toString();
      final rawFixed = temporalFixed ?? schedStart;
      if (rawFixed != null) {
        final parsed = DateTime.tryParse(rawFixed);
        if (parsed != null) {
          fixedStart = DateFormat('HH:mm').format(parsed.toLocal());
          targetDate ??= DateFormat('yyyy-MM-dd').format(parsed.toLocal());
        }
      }
    }
    if (targetDate == null && json['scheduled_start'] != null) {
      final parsed = DateTime.tryParse(json['scheduled_start'].toString());
      if (parsed != null) {
        targetDate = DateFormat('yyyy-MM-dd').format(parsed.toLocal());
      }
    }

    // deadline_at is the authoritative instant; `deadline` is only a display date (it has no time).
    final DateTime? deadlineAt =
        json['deadline_at'] != null ? DateTime.tryParse(json['deadline_at'].toString())?.toLocal() : null;
    String? deadline = json['deadline'] as String?;
    if (deadline == null && deadlineAt != null) {
      deadline = DateFormat('yyyy-MM-dd').format(deadlineAt);
    }

    return ExtractedTaskItem(
      title: json['title'] as String? ?? 'Untitled Task',
      description: json['description'] as String?,
      // The backend field is `task_type`; `type` was the old Gemini-only name.
      type: json['task_type'] as String? ?? json['type'] as String? ?? 'deep_work',
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt() ?? 45,
      difficulty: json['difficulty'] as String? ?? 'medium',
      priority: rawPrio,
      prioritySource: prioSrc,
      deadline: deadline,
      deadlineAt: deadlineAt,
      plannedDate: json['planned_date'] as String?,
      fixedStart: fixedStart,
      targetDate: targetDate,
      isDurationExplicit: durExplicit,
      isRecurring: json['is_recurring'] as bool? ?? false,
      dependencies: (json['dependencies'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      needsConfirmation: json['needs_confirmation'] as bool? ?? false,
      recommendedSlotStart: recStart,
      recommendedSlotEnd: recEnd,
      recommendedSlotDisplay: json['recommended_slot_display'] as String?,
      schedulingExplanation: json['scheduling_explanation'] as String?,
      schedulingReasons: json['scheduling_reasons'] as Map<String, dynamic>?,
      timeLocked: json['time_locked'] as bool? ?? false,
      isCommitment: json['is_commitment'] as bool? ?? false,
      recommendedSlotDate: json['recommended_slot_date'] as String?,
      unscheduledReason: json['unscheduled_reason'] as String?,
      validationIssues: (json['validation_issues'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [],
      suggestedSlotStart: json['suggested_slot_start'] != null
          ? DateTime.tryParse(json['suggested_slot_start'].toString())?.toLocal()
          : null,
      suggestedSlotDisplay: json['suggested_slot_display'] as String?,
      candidateId: json['candidate_id'] as String?,
      durationSource: json['duration_source'] as String?,
      focusLevel: json['focus_level'] as String?,
      focusSource: json['focus_source'] as String?,
      deadlineKind: json['deadline_kind'] as String?,
      dependsOn: (json['depends_on'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      preferredStart: _instant(json['preferred_start']),
      preferredWindowStart: _instant(json['preferred_window_start']),
      preferredWindowEnd: _instant(json['preferred_window_end']),
      routineOverrideId: json['routine_override_id'] as String?,
      routineOverrideDate: json['routine_override_date'] as String?,
    );
  }

  static DateTime? _instant(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'type': type,
      'estimated_minutes': estimatedMinutes,
      'difficulty': difficulty,
      'priority': priority,
      'priority_source': prioritySource,
      'deadline': deadline,
      'deadline_at': deadlineAt?.toUtc().toIso8601String(),
      'planned_date': plannedDate,
      'fixed_start': fixedStart,
      'target_date': targetDate,
      'is_recurring': isRecurring,
      'dependencies': dependencies,
      'confidence': confidence,
      'needs_confirmation': needsConfirmation,
      'recommended_slot_start': recommendedSlotStart?.toIso8601String(),
      'recommended_slot_end': recommendedSlotEnd?.toIso8601String(),
      'recommended_slot_display': recommendedSlotDisplay,
      'scheduling_explanation': schedulingExplanation,
      'scheduling_reasons': schedulingReasons,
    };
  }

  /// Maps this Gemini-extracted representation into a core Flowstate [TaskItem]
  /// ready for input into the deterministic scheduling engine.
  TaskItem toTaskItem({String? customId}) {
    final now = DateTime.now();

    // Map difficulty
    TaskDifficulty diff = TaskDifficulty.medium;
    switch (difficulty.toLowerCase()) {
      case 'high':
        diff = TaskDifficulty.high;
        break;
      case 'light':
        diff = TaskDifficulty.light;
        break;
      case 'physical':
        diff = TaskDifficulty.physical;
        break;
      case 'medium':
      default:
        diff = TaskDifficulty.medium;
        break;
    }

    // Map priority
    TaskPriority prio = TaskPriority.medium;
    if (priority != null) {
      switch (priority!.toLowerCase()) {
        case 'urgent':
          prio = TaskPriority.urgent;
          break;
        case 'high':
          prio = TaskPriority.high;
          break;
        case 'low':
          prio = TaskPriority.low;
          break;
        case 'medium':
        default:
          prio = TaskPriority.medium;
          break;
      }
    }

    // Map task type
    TaskType tType = TaskType.deepWork;
    switch (type.toLowerCase()) {
      case 'study':
        tType = TaskType.study;
        break;
      case 'physical':
      case 'fitness':
        tType = TaskType.physical;
        break;
      case 'personal':
        tType = TaskType.personal;
        break;
      case 'admin':
      case 'errand':
        tType = TaskType.admin;
        break;
      case 'meeting':
        tType = TaskType.meeting;
        break;
      case 'creative':
        tType = TaskType.creative;
        break;
      case 'shallow_work':
        tType = TaskType.shallowWork;
        break;
      case 'deep_work':
      default:
        tType = TaskType.deepWork;
        break;
    }

    // Fixed time parsing
    DateTime? scheduledStart;
    String? scheduledTimeStr;
    if (fixedStart != null && fixedStart!.contains(':')) {
      final parts = fixedStart!.split(':');
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

      // Prefer the backend-supplied target day for the fixed slot;
      // fall back to today when target_date is absent or unparseable.
      final DateTime targetDay = (targetDate != null && targetDate!.isNotEmpty)
          ? (DateTime.tryParse(targetDate!) ?? now)
          : now;

      scheduledStart = DateTime(
        targetDay.year,
        targetDay.month,
        targetDay.day,
        hour,
        minute,
      );
      scheduledTimeStr = DateFormat('h:mm a').format(scheduledStart);
    }

    // Deadline parsing
    DateTime? deadlineAt = this.deadlineAt;
    String deadlineStr = 'Today';
    if (deadline != null && deadline!.isNotEmpty) {
      deadlineStr = deadline!;
      try {
        final parsed = DateTime.tryParse(deadline!);
        if (parsed != null) {
          // A date-only string is midnight; never let it replace the real deadline instant.
          deadlineAt ??= parsed;
          deadlineStr = DateFormat('MMM d').format(parsed);
        }
      } catch (_) {}
    }

    final ambiguities = <String>[];
    if (needsConfirmation) {
      ambiguities.add('needs_confirmation');
    }
    if (prioritySource == 'inferred') {
      ambiguities.add('inferred_priority');
    } else if (prioritySource == 'unspecified') {
      ambiguities.add('priority_unspecified');
    }

    // An explicit user time wins over the recommendation; the recommendation is NOT a user lock.
    final finalSchedStart = scheduledStart ?? recommendedSlotStart;
    final lockedByUser = timeLocked && scheduledStart != null;
    final finalSchedEnd = finalSchedStart?.add(Duration(minutes: estimatedMinutes));

    return TaskItem(
      // The candidate id doubles as the confirm client_ref so sibling depends_on references resolve.
      id: customId ?? candidateId ?? 'task-ai-${now.millisecondsSinceEpoch}',
      title: title,
      description: description,
      durationMinutes: estimatedMinutes,
      difficulty: diff,
      priority: prio,
      prioritySource: prioritySource,
      isPriority: prio == TaskPriority.high || prio == TaskPriority.urgent,
      deadline: deadlineStr,
      deadlineAt: deadlineAt,
      plannedDate: plannedDate != null ? DateTime.tryParse(plannedDate!) : null,
      scheduledTime: scheduledTimeStr ?? recommendedSlotDisplay,
      scheduledStart: finalSchedStart,
      scheduledEnd: finalSchedEnd,
      taskType: tType,
      category: tType == TaskType.study
          ? 'Study'
          : (tType == TaskType.physical
              ? 'Fitness'
              : (tType == TaskType.admin || tType == TaskType.personal ? 'Personal' : 'Work')),
      source: TaskSource.aiParsed,
      confidence: confidence,
      missingFields: isDurationExplicit ? const [] : const ['duration'],
      ambiguities: ambiguities,
      // An unplaced task explains why (the server's real reason), never a made-up slot.
      schedulingExplanation: unscheduledReason != null
          ? (validationIssues
                  .where((i) => i['code'] == unscheduledReason)
                  .map((i) => i['message']?.toString())
                  .firstWhere((m) => m != null && m.isNotEmpty, orElse: () => null) ??
              schedulingExplanation)
          : schedulingExplanation,
      recommendedSlotDisplay: recommendedSlotDisplay,
      schedulingReasons: schedulingReasons,
      timeLocked: lockedByUser,
      isCommitment: isCommitment && lockedByUser,
      candidateId: candidateId,
      durationSource: durationSource ?? (isDurationExplicit ? 'explicit' : 'inferred'),
      focusLevel: focusLevel,
      focusSource: focusSource,
      deadlineKind: deadlineKind,
      dependsOn: dependsOn,
      preferredStart: preferredStart,
      preferredWindowStart: preferredWindowStart,
      preferredWindowEnd: preferredWindowEnd,
      unscheduledReason: unscheduledReason,
      routineOverrideId: routineOverrideId,
      routineOverrideDate: routineOverrideDate,
    );
  }
}

/// A preview edit made by the user: every field the user changed becomes `explicit`, and a changed
/// start time becomes a user-fixed (locked) time. Untouched fields keep their original source.
TaskItem applyPreviewEdit(TaskItem original, TaskItem edited) {
  final startChanged = edited.scheduledStart != null && edited.scheduledStart != original.scheduledStart;
  return edited.copyWith(
    durationSource: edited.durationMinutes != original.durationMinutes ? 'explicit' : null,
    prioritySource: edited.priority != original.priority ? 'explicit' : null,
    focusSource: edited.focusLevel != original.focusLevel ? 'explicit' : null,
    timeLocked: startChanged ? true : null,
  );
}

/// Server-owned AI usage & entitlement state
class AIUsageStatus {
  final bool isPro;
  final String subscriptionTier;
  final bool freeUseAvailable;
  final int freeUsesConsumed;
  final int shieldsAvailable;
  final int shieldFundedUses;
  final bool canUseAi;
  final bool requiresShield;
  final int hourlyRequestsRemaining;

  /// Shields one AI plan costs. Owned by the server (`shield_cost`); the app only displays it, so a price change
  /// never needs an app release. "Shields pay for Noya's AI planning" is the whole rule: there is no free-plan side track.
  final int shieldCost;
  final int shieldCostReplan;

  /// The most Shields an account holds, and the SERVER instant its next free one lands (null at the maximum).
  /// The app only counts down to it: eligibility and the grant are the server's.
  final int shieldMax;
  final DateTime? nextShieldRefillAt;

  /// True until the one-time "2 Shields added" welcome has been shown (server state: once per account, not per device).
  final bool shieldWelcomePending;

  /// How long until the next free Shield, measured from the server's own clock at the moment this was read, so a
  /// wrong device clock cannot shorten (or lengthen) it. Null when no cooldown is running.
  final Duration? untilNextShield;

  /// Device time at which [untilNextShield] was read (only the elapsed time since then is taken from the device).
  final DateTime? readAt;

  /// Time left at [now]: the server-measured wait minus what has elapsed since it was read. Never negative.
  Duration? untilNextShieldAt(DateTime now) {
    final base = untilNextShield;
    final at = readAt;
    if (base == null || at == null) return base;
    final elapsed = now.difference(at);
    final left = base - (elapsed.isNegative ? Duration.zero : elapsed);
    return left.isNegative ? Duration.zero : left;
  }

  /// True when the Shield price can be paid right now (Pro never pays Shields).
  bool get canAffordShieldPlan => shieldsAvailable >= shieldCost;
  bool get canAffordShieldReplan => shieldsAvailable >= shieldCostReplan;

  /// Words one Build My Day dump may hold. Owned by the server (`max_input_words`), same for Basic and Pro today.
  final int maxInputWords;

  const AIUsageStatus({
    required this.isPro,
    required this.subscriptionTier,
    required this.freeUseAvailable,
    required this.freeUsesConsumed,
    required this.shieldsAvailable,
    required this.shieldFundedUses,
    required this.canUseAi,
    required this.requiresShield,
    required this.hourlyRequestsRemaining,
    this.shieldCost = defaultShieldCost,
    this.shieldCostReplan = defaultReplanShieldCost,
    this.maxInputWords = kDefaultBrainDumpMaxWords,
    this.shieldMax = 3,
    this.shieldWelcomePending = false,
    this.nextShieldRefillAt,
    this.untilNextShield,
    this.readAt,
  });

  static const int defaultShieldCost = 1;
  static const int defaultReplanShieldCost = 1;

  factory AIUsageStatus.fromJson(Map<String, dynamic> json) {
    final freeRemaining = json['free_uses_remaining'] as int?;
    final freeTotal = json['free_uses_total'] as int? ?? 0;
    final canPlanFree = json['can_plan_free'] as bool?;

    // No free trial plan exists any more: an answer that does not say otherwise means Shields pay.
    final freeAvailable = json['free_use_available'] as bool? ??
        (canPlanFree ?? (freeRemaining != null ? freeRemaining > 0 : false));

    final freeConsumed = json['free_uses_consumed'] as int? ??
        (freeRemaining != null ? (freeTotal - freeRemaining) : 0);

    final nextRefill = DateTime.tryParse(json['next_shield_refill_at'] as String? ?? '');
    final serverNow = DateTime.tryParse(json['server_now'] as String? ?? '');
    return AIUsageStatus(
      isPro: json['is_pro'] as bool? ?? false,
      subscriptionTier: json['subscription_tier'] as String? ?? 'free',
      freeUseAvailable: freeAvailable,
      freeUsesConsumed: freeConsumed,
      // never invent a balance: a response without one is a balance of zero, not two
      shieldsAvailable: json['shields_available'] as int? ?? 0,
      shieldFundedUses: json['shield_funded_uses'] as int? ?? 0,
      canUseAi: json['can_use_ai'] as bool? ?? (canPlanFree ?? true),
      requiresShield: json['requires_shield'] as bool? ?? (!freeAvailable),
      hourlyRequestsRemaining: json['hourly_requests_remaining'] as int? ?? 5,
      shieldCost: json['shield_cost'] as int? ?? defaultShieldCost,
      shieldCostReplan: json['shield_cost_replan'] as int? ?? defaultReplanShieldCost,
      maxInputWords: json['max_input_words'] as int? ?? kDefaultBrainDumpMaxWords,
      shieldMax: json['shield_max'] as int? ?? 3,
      shieldWelcomePending: json['shield_welcome_pending'] as bool? ?? false,
      nextShieldRefillAt: nextRefill,
      untilNextShield: (nextRefill != null && serverNow != null) ? nextRefill.difference(serverNow) : null,
      readAt: DateTime.now(),
    );
  }
}

/// Result returned from POST /api/v1/ai/plan
class AIPlanResult {
  final List<ExtractedTaskItem> tasks;
  final List<String> ambiguities;
  final bool needsConfirmation;
  final AIUsageStatus? usage;
  final String? timezoneUsed; // IANA zone the server planned in
  final String? schedulingError; // non-null => tasks came back without slots
  final List<Map<String, dynamic>> conflicts;
  /// Routines found in the dump. NONE is saved until the user confirms it.
  final List<RoutineProposal> routineProposals;

  /// True when this plan was paid with a Shield (server fact, from `shield_consumed`).
  final bool shieldConsumed;

  const AIPlanResult({
    required this.tasks,
    this.ambiguities = const [],
    this.needsConfirmation = false,
    this.usage,
    this.timezoneUsed,
    this.schedulingError,
    this.conflicts = const [],
    this.routineProposals = const [],
    this.shieldConsumed = false,
  });

  factory AIPlanResult.fromJson(Map<String, dynamic> json) {
    final rawTasks = json['tasks'] as List<dynamic>? ?? [];
    final tasks = rawTasks
        .whereType<Map<String, dynamic>>()
        .map((t) => ExtractedTaskItem.fromJson(t))
        .toList();

    final ambiguities = (json['ambiguities'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    final needsConfirmation = json['needs_confirmation'] as bool? ??
        tasks.any((t) => t.needsConfirmation || t.prioritySource == 'inferred');

    AIUsageStatus? usageStatus;
    if (json['usage'] is Map<String, dynamic>) {
      usageStatus = AIUsageStatus.fromJson(json['usage'] as Map<String, dynamic>);
    }

    return AIPlanResult(
      tasks: tasks,
      ambiguities: ambiguities,
      needsConfirmation: needsConfirmation,
      usage: usageStatus,
      timezoneUsed: json['timezone_used'] as String?,
      shieldConsumed: json['shield_consumed'] as bool? ?? false,
      schedulingError: json['scheduling_error'] as String?,
      conflicts: (json['conflicts'] as List<dynamic>?)?.whereType<Map<String, dynamic>>().toList() ?? const [],
      routineProposals: (json['routine_proposals'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(RoutineProposal.fromJson)
              .toList() ??
          const [],
    );
  }
}

/// Server-owned Pro subscription entitlement
class SubscriptionStatus {
  final bool isPro;
  final String subscriptionTier;
  final String status;
  final String? expirationDate;
  final bool autoRenew;

  const SubscriptionStatus({
    required this.isPro,
    required this.subscriptionTier,
    required this.status,
    this.expirationDate,
    this.autoRenew = false,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      isPro: json['is_pro'] as bool? ?? false,
      subscriptionTier: json['subscription_tier'] as String? ?? 'free',
      status: json['status'] as String? ?? 'inactive',
      expirationDate: json['expiration_date'] as String?,
      autoRenew: json['auto_renew'] as bool? ?? false,
    );
  }
}
