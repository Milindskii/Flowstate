import 'package:intl/intl.dart';
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
  final bool isRecurring;
  final List<String> dependencies;
  final double confidence;
  final bool needsConfirmation;
  final DateTime? recommendedSlotStart;
  final DateTime? recommendedSlotEnd;
  final String? recommendedSlotDisplay;
  final String? schedulingExplanation;
  final Map<String, dynamic>? schedulingReasons;

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
    this.isRecurring = false,
    this.dependencies = const [],
    this.confidence = 1.0,
    this.needsConfirmation = false,
    this.recommendedSlotStart,
    this.recommendedSlotEnd,
    this.recommendedSlotDisplay,
    this.schedulingExplanation,
    this.schedulingReasons,
  });

  bool get isPriorityExplicit => prioritySource == 'explicit';
  bool get isPriorityInferred => prioritySource == 'inferred';
  bool get isPriorityUnspecified => prioritySource == 'unspecified' || priority == null;

  factory ExtractedTaskItem.fromJson(Map<String, dynamic> json) {
    final rawPrio = json['priority'] as String?;
    final prioSrc = json['priority_source'] as String? ??
        (rawPrio != null ? 'inferred' : 'unspecified');

    DateTime? recStart;
    if (json['recommended_slot_start'] != null) {
      recStart = DateTime.tryParse(json['recommended_slot_start'].toString());
    }
    DateTime? recEnd;
    if (json['recommended_slot_end'] != null) {
      recEnd = DateTime.tryParse(json['recommended_slot_end'].toString());
    }

    return ExtractedTaskItem(
      title: json['title'] as String? ?? 'Untitled Task',
      description: json['description'] as String?,
      type: json['type'] as String? ?? 'deep_work',
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt() ?? 45,
      difficulty: json['difficulty'] as String? ?? 'medium',
      priority: rawPrio,
      prioritySource: prioSrc,
      deadline: json['deadline'] as String?,
      fixedStart: json['fixed_start'] as String?,
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
    );
  }

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
      'fixed_start': fixedStart,
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
      scheduledStart = DateTime(now.year, now.month, now.day, hour, minute);
      scheduledTimeStr = DateFormat('h:mm a').format(scheduledStart);
    }

    // Deadline parsing
    DateTime? deadlineAt;
    String deadlineStr = 'Today';
    if (deadline != null && deadline!.isNotEmpty) {
      deadlineStr = deadline!;
      try {
        final parsed = DateTime.tryParse(deadline!);
        if (parsed != null) {
          deadlineAt = parsed;
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

    final finalSchedStart = scheduledStart ?? recommendedSlotStart;
    final finalSchedEnd = finalSchedStart != null ? finalSchedStart.add(Duration(minutes: estimatedMinutes)) : null;

    return TaskItem(
      id: customId ?? 'task-ai-${now.millisecondsSinceEpoch}',
      title: title,
      description: description,
      durationMinutes: estimatedMinutes,
      difficulty: diff,
      priority: prio,
      prioritySource: prioritySource,
      isPriority: prio == TaskPriority.high || prio == TaskPriority.urgent,
      deadline: deadlineStr,
      deadlineAt: deadlineAt,
      scheduledTime: scheduledTimeStr ?? recommendedSlotDisplay,
      scheduledStart: finalSchedStart,
      scheduledEnd: finalSchedEnd,
      taskType: tType,
      category: tType == TaskType.study
          ? 'Study'
          : (tType == TaskType.physical ? 'Fitness' : (tType == TaskType.admin ? 'Admin' : 'Work')),
      source: TaskSource.aiParsed,
      confidence: confidence,
      ambiguities: ambiguities,
      schedulingExplanation: schedulingExplanation,
      recommendedSlotDisplay: recommendedSlotDisplay,
      schedulingReasons: schedulingReasons,
    );
  }
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
  });

  factory AIUsageStatus.fromJson(Map<String, dynamic> json) {
    return AIUsageStatus(
      isPro: json['is_pro'] as bool? ?? false,
      subscriptionTier: json['subscription_tier'] as String? ?? 'free',
      freeUseAvailable: json['free_use_available'] as bool? ?? true,
      freeUsesConsumed: json['free_uses_consumed'] as int? ?? 0,
      shieldsAvailable: json['shields_available'] as int? ?? 2,
      shieldFundedUses: json['shield_funded_uses'] as int? ?? 0,
      canUseAi: json['can_use_ai'] as bool? ?? true,
      requiresShield: json['requires_shield'] as bool? ?? false,
      hourlyRequestsRemaining: json['hourly_requests_remaining'] as int? ?? 5,
    );
  }

  factory AIUsageStatus.defaultFreeInitial() {
    return const AIUsageStatus(
      isPro: false,
      subscriptionTier: 'free',
      freeUseAvailable: true,
      freeUsesConsumed: 0,
      shieldsAvailable: 2,
      shieldFundedUses: 0,
      canUseAi: true,
      requiresShield: false,
      hourlyRequestsRemaining: 5,
    );
  }
}

/// Result returned from POST /api/v1/ai/plan
class AIPlanResult {
  final List<ExtractedTaskItem> tasks;
  final List<String> ambiguities;
  final bool needsConfirmation;
  final AIUsageStatus? usage;

  const AIPlanResult({
    required this.tasks,
    this.ambiguities = const [],
    this.needsConfirmation = false,
    this.usage,
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
