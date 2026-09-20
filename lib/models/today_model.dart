import 'readiness_model.dart';
import 'schedule_item.dart';
import 'task_item.dart';

enum TodayLifecycleState {
  newUser,
  learning,
  calibrated;

  static TodayLifecycleState fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'learning':
        return TodayLifecycleState.learning;
      case 'calibrated':
        return TodayLifecycleState.calibrated;
      case 'new_user':
      default:
        return TodayLifecycleState.newUser;
    }
  }

  String get value {
    switch (this) {
      case TodayLifecycleState.learning:
        return 'learning';
      case TodayLifecycleState.calibrated:
        return 'calibrated';
      case TodayLifecycleState.newUser:
        return 'new_user';
    }
  }
}

class TodayUserContextModel {
  final String id;
  final String email;
  final String name;
  final String timezone;

  const TodayUserContextModel({
    required this.id,
    required this.email,
    required this.name,
    this.timezone = 'Asia/Kolkata',
  });

  factory TodayUserContextModel.fromJson(Map<String, dynamic> json) {
    return TodayUserContextModel(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? 'Friend',
      timezone: json['timezone'] as String? ?? 'Asia/Kolkata',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'timezone': timezone,
      };
}

class AIBriefModel {
  final String title;
  final String message;
  final String actionLabel;

  const AIBriefModel({
    this.title = 'FLOWSTATE',
    required this.message,
    this.actionLabel = 'Use this plan',
  });

  factory AIBriefModel.fromJson(Map<String, dynamic> json) {
    return AIBriefModel(
      title: json['title'] as String? ?? 'FLOWSTATE',
      message: json['message'] as String? ?? '',
      actionLabel: json['action_label'] as String? ?? 'Use this plan',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'message': message,
        'action_label': actionLabel,
      };
}

class WorkloadSummaryModel {
  final int plannedMinutes;
  final String formattedWorkload;
  final String message;
  final bool isOverloaded;
  final int availableMinutes;

  const WorkloadSummaryModel({
    this.plannedMinutes = 0,
    this.formattedWorkload = '0m planned',
    this.message = "Let's build your day.",
    this.isOverloaded = false,
    this.availableMinutes = 390,
  });

  factory WorkloadSummaryModel.fromJson(Map<String, dynamic> json) {
    return WorkloadSummaryModel(
      plannedMinutes: (json['planned_minutes'] as num?)?.toInt() ?? 0,
      formattedWorkload: json['formatted_workload'] as String? ?? '0m planned',
      message: json['message'] as String? ?? "Let's build your day.",
      isOverloaded: json['is_overloaded'] as bool? ?? false,
      availableMinutes: (json['available_minutes'] as num?)?.toInt() ?? 390,
    );
  }

  Map<String, dynamic> toJson() => {
        'planned_minutes': plannedMinutes,
        'formatted_workload': formattedWorkload,
        'message': message,
        'is_overloaded': isOverloaded,
        'available_minutes': availableMinutes,
      };
}

class CurrentRecommendationModel {
  final TaskItem? task;
  final List<String> reasons;

  const CurrentRecommendationModel({
    this.task,
    this.reasons = const [],
  });

  factory CurrentRecommendationModel.fromJson(Map<String, dynamic> json) {
    TaskItem? taskItem;
    if (json['task'] != null && json['task'] is Map<String, dynamic>) {
      taskItem = TaskItem.fromJson(json['task'] as Map<String, dynamic>);
    }
    final reasonsList = (json['reasons'] as List?)?.map((r) => r.toString()).toList() ?? [];

    return CurrentRecommendationModel(
      task: taskItem,
      reasons: reasonsList,
    );
  }

  Map<String, dynamic> toJson() => {
        'task': task?.toJson(),
        'reasons': reasons,
      };
}

class TodayResponseModel {
  final TodayUserContextModel user;
  final String date;
  final TodayLifecycleState lifecycleState;
  final ReadinessModel readiness;
  final CurrentRecommendationModel? currentRecommendation;
  final AIBriefModel aiBrief;
  final WorkloadSummaryModel workloadSummary;
  final TaskItem? activeTask;
  final List<ScheduleItem> upcomingTimeline;
  final DateTime lastUpdatedAt;

  const TodayResponseModel({
    required this.user,
    required this.date,
    required this.lifecycleState,
    required this.readiness,
    this.currentRecommendation,
    required this.aiBrief,
    required this.workloadSummary,
    this.activeTask,
    this.upcomingTimeline = const [],
    required this.lastUpdatedAt,
  });

  CurrentRecommendationModel? get recommendation => currentRecommendation;

  factory TodayResponseModel.fromJson(Map<String, dynamic> json, {DateTime? fetchedAt}) {
    final userContext = json['user'] is Map<String, dynamic>
        ? TodayUserContextModel.fromJson(json['user'] as Map<String, dynamic>)
        : const TodayUserContextModel(id: 'guest', email: '', name: 'Friend');

    final readinessObj = json['readiness'] is Map<String, dynamic>
        ? ReadinessModel.fromJson(json['readiness'] as Map<String, dynamic>)
        : ReadinessModel.uncalibrated();

    CurrentRecommendationModel? rec;
    if (json['current_recommendation'] is Map<String, dynamic>) {
      rec = CurrentRecommendationModel.fromJson(json['current_recommendation'] as Map<String, dynamic>);
    }

    final brief = json['ai_brief'] is Map<String, dynamic>
        ? AIBriefModel.fromJson(json['ai_brief'] as Map<String, dynamic>)
        : const AIBriefModel(message: "Let's build your day.");

    final workload = json['workload_summary'] is Map<String, dynamic>
        ? WorkloadSummaryModel.fromJson(json['workload_summary'] as Map<String, dynamic>)
        : const WorkloadSummaryModel();

    TaskItem? active;
    if (json['active_task'] is Map<String, dynamic>) {
      active = TaskItem.fromJson(json['active_task'] as Map<String, dynamic>);
    }

    final timelineList = (json['upcoming_timeline'] as List?)
            ?.map((s) => ScheduleItem.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [];

    return TodayResponseModel(
      user: userContext,
      date: json['date'] as String? ?? '',
      lifecycleState: TodayLifecycleState.fromString(json['lifecycle_state'] as String?),
      readiness: readinessObj,
      currentRecommendation: rec,
      aiBrief: brief,
      workloadSummary: workload,
      activeTask: active,
      upcomingTimeline: timelineList,
      lastUpdatedAt: fetchedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'date': date,
        'lifecycle_state': lifecycleState.value,
        'readiness': readiness.toJson(),
        'current_recommendation': currentRecommendation?.toJson(),
        'ai_brief': aiBrief.toJson(),
        'workload_summary': workloadSummary.toJson(),
        'active_task': activeTask?.toJson(),
        'upcoming_timeline': upcomingTimeline.map((s) => s.toJson()).toList(),
        'last_updated_at': lastUpdatedAt.toIso8601String(),
      };
}
