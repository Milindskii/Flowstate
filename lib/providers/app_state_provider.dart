import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_item.dart';
import '../models/personal_data.dart';
import '../models/readiness_model.dart';
import '../models/schedule_item.dart';
import '../models/feedback_log.dart';
import '../models/today_model.dart';
import '../engines/readiness_engine.dart';
import '../engines/scheduling_engine.dart';
import '../engines/personal_learning_engine.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/task_service.dart';
import '../services/readiness_service.dart';
import '../services/schedule_service.dart';
import '../services/feedback_service.dart';
import '../services/calendar_service.dart';
import '../services/health_service.dart';
import '../services/today_service.dart';
import '../utils/mock_data.dart';

/// Central App State Provider coordinating UI data and the backend single source of truth.
class AppStateProvider extends ChangeNotifier {
  // Local Deterministic Engines (Used for initial mock / demo state)
  final ReadinessEngine _readinessEngine = const ReadinessEngine();
  final SchedulingEngine _schedulingEngine = const SchedulingEngine();
  final PersonalLearningEngine _learningEngine = PersonalLearningEngine();

  // Service Layer
  late final ApiService apiService;
  late final AuthService authService;
  late final TaskService taskService;
  late final ReadinessService readinessService;
  late final ScheduleService scheduleService;
  late final FeedbackService feedbackService;
  late final CalendarService calendarService;
  late final HealthService healthService;
  late final TodayService todayService;

  // State
  PersonalData _personalData = MockData.initialPersonalData;
  List<TaskItem> _tasks = MockData.initialTasks;
  late ReadinessModel _readiness;
  late List<ScheduleItem> _schedule;

  TodayResponseModel? _todaySnapshot;
  DateTime? _lastUpdatedAt;
  bool _isOffline = false;

  AuthUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isDemoMode = true; // Demo mode default for instant development preview

  int _currentNavIndex = 0;
  String _selectedCategory = 'All';
  bool _isOptimizing = false;
  TaskItem? _activeFocusTask;
  bool _onboardingComplete = false;

  AppStateProvider({ApiService? customApi}) {
    apiService = customApi ?? ApiService();
    authService = AuthService(api: apiService);
    taskService = TaskService(api: apiService);
    readinessService = ReadinessService(api: apiService);
    scheduleService = ScheduleService(api: apiService);
    feedbackService = FeedbackService(api: apiService);
    calendarService = CalendarService(api: apiService);
    healthService = HealthService(api: apiService);
    todayService = TodayService(api: apiService);

    // Initial user context
    _currentUser = const AuthUser(
      id: 'user-demo-1',
      email: 'alex@flowstate.local',
      name: 'Alex',
    );

    _recalculateReadiness();
    _recalculateSchedule();
    _loadOnboardingState();
  }

  // Getters
  PersonalData get personalData => _personalData;
  List<TaskItem> get tasks => List.unmodifiable(_tasks);
  ReadinessModel get readiness => _readiness;
  List<ScheduleItem> get schedule => List.unmodifiable(_schedule);
  AuthUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isDemoMode => _isDemoMode;
  bool get isOffline => _isOffline;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;
  TodayResponseModel? get todaySnapshot => _todaySnapshot;
  TodayResponseModel? get todayData => _todaySnapshot;

  String get greetingName => _currentUser?.name ?? 'Friend';
  bool get onboardingComplete => _onboardingComplete;

  // Dynamic time-of-day greeting (no hardcoded time)
  String get timeOfDayGreeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get formattedGreeting {
    if (isNewUser) return '$timeOfDayGreeting 👋';
    return '$timeOfDayGreeting, $greetingName 👋';
  }

  // Progressive lifecycle state helpers
  TodayLifecycleState get lifecycleState {
    if (_todaySnapshot != null) {
      return _todaySnapshot!.lifecycleState;
    }
    if (_tasks.isEmpty) return TodayLifecycleState.newUser;
    if (!_readiness.isCalibrated) return TodayLifecycleState.learning;
    return TodayLifecycleState.calibrated;
  }

  bool get isNewUser => lifecycleState == TodayLifecycleState.newUser;
  bool get isLearningRhythm => lifecycleState == TodayLifecycleState.learning;
  bool get isMatureUser => lifecycleState == TodayLifecycleState.calibrated;

  int get currentNavIndex => _currentNavIndex;
  String get selectedCategory => _selectedCategory;
  bool get isOptimizing => _isOptimizing;
  TaskItem? get activeFocusTask => _activeFocusTask;
  PersonalLearningEngine get learningEngine => _learningEngine;

  // AI Brief
  AIBriefModel get aiBrief {
    if (_todaySnapshot != null) {
      return _todaySnapshot!.aiBrief;
    }
    if (isNewUser) {
      return const AIBriefModel(
        title: 'FLOWSTATE',
        message: 'Good morning. You haven’t planned any tasks yet. Add what you need to get done.',
        actionLabel: 'Add a task',
      );
    }
    final pendingCount = _tasks.where((t) => !t.isCompleted).length;
    final topTask = recommendedTask?.title ?? 'your top task';
    return AIBriefModel(
      title: 'FLOWSTATE',
      message: 'You have $pendingCount important tasks today.\nYour strongest focus window starts in 15 minutes.\nI’d tackle $topTask first.',
      actionLabel: 'Use this plan',
    );
  }

  // Workload Summary
  WorkloadSummaryModel get workloadSummary {
    if (_todaySnapshot != null) {
      return _todaySnapshot!.workloadSummary;
    }
    final totalMins = _tasks.where((t) => !t.isCompleted).fold<int>(0, (sum, t) => sum + t.durationMinutes);
    final hours = totalMins ~/ 60;
    final mins = totalMins % 60;
    final formatted = hours > 0 ? '${hours}h ${mins}m planned' : '${mins}m planned';
    final overloaded = totalMins > 390;

    return WorkloadSummaryModel(
      plannedMinutes: totalMins,
      formattedWorkload: formatted,
      message: totalMins == 0
          ? "Let's build your day."
          : (overloaded ? "You're trying to fit $formatted into 6h 30m." : "Your day looks manageable."),
      isOverloaded: overloaded,
      availableMinutes: 390,
    );
  }

  // Reasons for current recommendation
  List<String> get recommendationReasons {
    if (_todaySnapshot?.currentRecommendation != null &&
        _todaySnapshot!.currentRecommendation!.reasons.isNotEmpty) {
      return _todaySnapshot!.currentRecommendation!.reasons;
    }
    final rec = recommendedTask;
    if (rec == null) return const [];
    return [
      rec.isPriority ? 'High priority' : 'Aligned with goals',
      'Strong focus window',
      rec.deadline,
    ];
  }

  List<TaskItem> get filteredTasks {
    if (_selectedCategory == 'All') return _tasks;
    return _tasks.where((t) => t.category.toLowerCase() == _selectedCategory.toLowerCase()).toList();
  }

  List<TaskItem> get highPriorityTasks =>
      filteredTasks.where((t) => t.isPriority && !t.isCompleted).toList();

  List<TaskItem> get laterTasks =>
      filteredTasks.where((t) => !t.isPriority && !t.isCompleted).toList();

  List<TaskItem> get completedTasks =>
      _tasks.where((t) => t.isCompleted).toList();

  /// Primary "RIGHT NOW" execution recommendation
  TaskItem? get recommendedTask {
    if (_todaySnapshot?.currentRecommendation?.task != null) {
      return _todaySnapshot!.currentRecommendation!.task;
    }
    final pending = _tasks.where((t) => !t.isCompleted).toList();
    if (pending.isEmpty) return null;
    return pending.firstWhere(
      (t) => t.difficulty == TaskDifficulty.high && t.isPriority,
      orElse: () => pending.first,
    );
  }

  /// Get easier alternative for What Should I Do Now screen
  TaskItem? getEasierAlternativeTask(TaskItem current) {
    final candidates = _tasks.where((t) => !t.isCompleted && t.id != current.id).toList();
    if (candidates.isEmpty) return null;
    return candidates.firstWhere(
      (t) => t.difficulty != TaskDifficulty.high,
      orElse: () => candidates.first,
    );
  }

  // Navigation
  void setNavIndex(int index) {
    if (_currentNavIndex != index) {
      _currentNavIndex = index;
      notifyListeners();
    }
  }

  void setSelectedCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setDemoMode(bool enabled) {
    _isDemoMode = enabled;
    if (enabled && _tasks.isEmpty) {
      _tasks = List.from(MockData.initialTasks);
      _recalculateReadiness();
      _recalculateSchedule();
    }
    notifyListeners();
  }

  void clearAllTasksForNewUserState() {
    _tasks = [];
    _schedule = [];
    _readiness = ReadinessModel.uncalibrated();
    _todaySnapshot = null;
    notifyListeners();
  }

  void setLearningStateForTesting() {
    _tasks = [
      const TaskItem(
        id: 'task-test-1',
        title: 'Review Machine Learning Architecture',
        durationMinutes: 60,
        difficulty: TaskDifficulty.high,
        deadline: 'Due Tomorrow',
        category: 'Study',
        isPriority: true,
      ),
    ];
    _readiness = ReadinessModel.uncalibrated();
    _recalculateSchedule();
    notifyListeners();
  }

  void restoreDemoData() {
    _tasks = List.from(MockData.initialTasks);
    _recalculateReadiness();
    _recalculateSchedule();
    notifyListeners();
  }

  // Task Actions
  void toggleTaskCompletion(String taskId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final task = _tasks[index];
      final willComplete = !task.isCompleted;
      _tasks[index] = task.copyWith(isCompleted: willComplete);

      if (willComplete) {
        final feedback = FeedbackLog(
          taskId: task.id,
          completedAt: DateTime.now(),
          actualMinutes: task.durationMinutes,
          perceivedFocusScore: 5,
          energyFeeling: 'Energized',
        );
        _learningEngine.recordSessionFeedback(feedback);
        if (!_isDemoMode) {
          feedbackService.submitFeedback(feedback).catchError((_) {});
          taskService.completeTask(task.id, actualMinutes: task.durationMinutes, perceivedFocusScore: 5).catchError((_) {});
        }
        _recalculateReadiness();
      }
      _recalculateSchedule();
      notifyListeners();
    }
  }

  void addTask({
    required String title,
    required int durationMinutes,
    required TaskDifficulty difficulty,
    required String deadline,
    required String category,
    bool isPriority = false,
  }) {
    final newTask = TaskItem(
      id: 'task-${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      durationMinutes: durationMinutes,
      difficulty: difficulty,
      deadline: deadline,
      category: category,
      isPriority: isPriority,
    );

    _tasks.insert(0, newTask);
    if (!_isDemoMode) {
      taskService.createTask(newTask).catchError((_) => newTask);
    }

    _recalculateReadiness();
    _recalculateSchedule();
    notifyListeners();
  }

  // Optimization Trigger
  Future<void> optimizeSchedule() async {
    _isOptimizing = true;
    notifyListeners();

    if (!_isDemoMode) {
      try {
        final remoteSchedule = await scheduleService.optimizeSchedule();
        if (remoteSchedule.isNotEmpty) {
          _schedule = remoteSchedule;
          _isOptimizing = false;
          notifyListeners();
          return;
        }
      } catch (_) {}
    }

    await Future.delayed(const Duration(milliseconds: 350));
    _recalculateSchedule();
    _isOptimizing = false;
    notifyListeners();
  }

  void setActiveFocusTask(TaskItem? task) {
    _activeFocusTask = task;
    if (task != null) {
      _isBreakActive = false;
    }
    notifyListeners();
  }

  void clearActiveFocusTask() => setActiveFocusTask(null);

  // Break Session Management (15-Minute Recharge State)
  bool _isBreakActive = false;
  int _breakDurationMinutes = 15;
  int _breakElapsedSeconds = 0;

  bool get isBreakActive => _isBreakActive;
  int get breakDurationMinutes => _breakDurationMinutes;
  int get breakElapsedSeconds => _breakElapsedSeconds;

  void startBreakSession({int minutes = 15}) {
    _isBreakActive = true;
    _breakDurationMinutes = minutes;
    _breakElapsedSeconds = 0;
    _activeFocusTask = null;
    notifyListeners();
  }

  void updateBreakElapsed(int seconds) {
    _breakElapsedSeconds = seconds;
    notifyListeners();
  }

  void endBreakSession() {
    _isBreakActive = false;
    _breakElapsedSeconds = 0;
    notifyListeners();
  }

  /// Records post-task completion feedback into the Personal Learning Engine
  /// and triggers real-time schedule & readiness adaptation.
  void recordTaskFeedback({
    required String taskId,
    required int actualMinutes,
    required int feeling,
    String? durationFeedback,
    String? blockerNote,
  }) {
    final focusScore = feeling >= 4 ? 5 : (feeling == 3 ? 4 : (feeling == 2 ? 3 : 1));
    final energy = feeling >= 4 ? 'Energized' : (feeling == 3 ? 'Steady' : 'Drained');

    final log = FeedbackLog(
      taskId: taskId,
      completedAt: DateTime.now(),
      actualMinutes: actualMinutes,
      perceivedFocusScore: focusScore,
      energyFeeling: energy,
      notes: [
        if (durationFeedback != null) 'Duration: $durationFeedback',
        if (blockerNote != null) 'Blocker: $blockerNote',
      ].join('; '),
    );

    _learningEngine.recordSessionFeedback(log);
    _recalculateReadiness();
    _recalculateSchedule();
    notifyListeners();
  }

  // Update Personal Data
  void updatePersonalData(PersonalData updated) {
    _personalData = updated;
    _recalculateReadiness();
    _recalculateSchedule();
    notifyListeners();
  }

  void _recalculateReadiness() {
    final bias = _learningEngine.computeReadinessAdaptiveBias();
    _readiness = _readinessEngine.computeReadiness(
      personalData: _personalData,
      adaptiveBias: bias,
    );
  }

  void _recalculateSchedule() {
    _schedule = _schedulingEngine.generateOptimizedSchedule(
      tasks: _tasks,
      readiness: _readiness,
    );
  }

  /// Confirm a list of brain-dump parsed candidates, adding them all as tasks.
  /// Called when the user taps 'Looks good' in the onboarding or BrainDumpSheet flow.
  void confirmCandidates(List<TaskItem> candidates) {
    for (final candidate in candidates) {
      // Assign fresh IDs to avoid demo-stub ID collisions
      final task = candidate.copyWith(
        id: 'task-${DateTime.now().millisecondsSinceEpoch}-${candidates.indexOf(candidate)}',
      );
      _tasks.insert(0, task);
      if (!_isDemoMode) {
        taskService.createTask(task).catchError((_) => task);
      }
    }
    _recalculateReadiness();
    _recalculateSchedule();
    notifyListeners();
  }

  /// Persist onboarding completion status to SharedPreferences.
  Future<void> markOnboardingComplete() async {
    _onboardingComplete = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flowstate_onboarding_complete', true);
    } catch (_) {}
  }

  Future<void> _loadOnboardingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('flowstate_onboarding_complete') ?? false;
      if (done != _onboardingComplete) {
        _onboardingComplete = done;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> refreshTodayData() async {
    if (_isDemoMode) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final today = await todayService.getTodayExperience();
      _todaySnapshot = today;
      _lastUpdatedAt = today.lastUpdatedAt;
      _readiness = today.readiness;
      if (today.upcomingTimeline.isNotEmpty) {
        _schedule = today.upcomingTimeline;
      }
      _isOffline = false;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      // Check for cached offline data
      final cached = await todayService.getCachedToday();
      if (cached != null) {
        _todaySnapshot = cached;
        _lastUpdatedAt = cached.lastUpdatedAt;
        _readiness = cached.readiness;
        if (cached.upcomingTimeline.isNotEmpty) {
          _schedule = cached.upcomingTimeline;
        }
        _isOffline = true;
        _isLoading = false;
        notifyListeners();
      } else {
        _errorMessage = 'We couldn’t update your plan.';
        _isLoading = false;
        notifyListeners();
      }
    }
  }
}
