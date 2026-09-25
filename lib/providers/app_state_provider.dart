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

/// Explicit Today Network Status (kept separate from content/task lifecycle state)
enum TodayNetworkState {
  loading,
  networkFailure,
  serverError,
  emptySuccess,
  tasksSuccess,
  @Deprecated('Use tasksSuccess or emptySuccess')
  success,
}

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
  DateTime? _lastBackendSyncAt;  // guards local recomputation
  bool _isOffline = false;
  TodayNetworkState _todayNetworkState = TodayNetworkState.emptySuccess;

  AuthUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isDemoMode = false;

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

    // Check if session is already restored from Supabase client
    _currentUser = authService.currentUser;
    if (_currentUser != null) {
      _isDemoMode = false;
      _tasks = [];
      loadUserTasks();
      refreshTodayData();
    } else {
      _tasks = [];
      _schedule = [];
      _readiness = ReadinessModel.uncalibrated();
    }

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

  TodayNetworkState get todayNetworkState => _todayNetworkState;
  bool get hasTodayTasks => _todaySnapshot != null
      ? (_todaySnapshot!.hasActionableTasks || _tasks.any((t) => !t.isCompleted))
      : _tasks.any((t) => !t.isCompleted);
  bool get isTodayEmpty => _todaySnapshot != null
      ? (_todaySnapshot!.lifecycleState == TodayLifecycleState.newUser && _tasks.isEmpty)
      : _tasks.isEmpty;
  bool get isTodayCompleted => _todaySnapshot != null
      ? _todaySnapshot!.lifecycleState == TodayLifecycleState.completed
      : (_tasks.isNotEmpty && _tasks.every((t) => t.isCompleted));

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
    final hasTasks = _tasks.isNotEmpty;
    final allCompleted = hasTasks && _tasks.every((t) => t.isCompleted);
    if (allCompleted) return TodayLifecycleState.completed;
    if (_todaySnapshot != null) {
      return _todaySnapshot!.lifecycleState;
    }
    if (_tasks.isEmpty) return TodayLifecycleState.newUser;
    if (!_readiness.isCalibrated) return TodayLifecycleState.learning;
    return TodayLifecycleState.calibrated;
  }

  TodayState get todayState => lifecycleState;
  bool get isNewUser => lifecycleState == TodayLifecycleState.newUser;
  bool get isLearningRhythm => lifecycleState == TodayLifecycleState.learning;
  bool get isMatureUser => lifecycleState == TodayLifecycleState.calibrated;
  bool get isDayCompleted => lifecycleState == TodayLifecycleState.completed;

  int get currentNavIndex => _currentNavIndex;
  String get selectedCategory => _selectedCategory;
  bool get isOptimizing => _isOptimizing;
  TaskItem? get activeFocusTask => _activeFocusTask;
  PersonalLearningEngine get learningEngine => _learningEngine;

  // AI Brief — always from backend when available
  AIBriefModel get aiBrief {
    if (_todaySnapshot != null) {
      return _todaySnapshot!.aiBrief;
    }
    if (isNewUser) {
      return const AIBriefModel(
        title: 'FLOWSTATE',
        message: 'Good morning. You haven\'t planned any tasks yet. Add what you need to get done.',
        actionLabel: 'Add a task',
      );
    }
    final pendingCount = _tasks.where((t) => !t.isCompleted).length;
    final topTask = recommendedTask?.title ?? 'your top task';
    return AIBriefModel(
      title: 'FLOWSTATE',
      message: 'You have $pendingCount task${pendingCount == 1 ? '' : 's'} today. Start with "$topTask".',
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

  // Reasons for current recommendation (from backend engine output)
  List<String> get recommendationReasons {
    if (_todaySnapshot?.currentRecommendation != null &&
        _todaySnapshot!.currentRecommendation!.reasons.isNotEmpty) {
      return _todaySnapshot!.currentRecommendation!.reasons;
    }
    final rec = recommendedTask;
    if (rec == null) return const [];
    // Fallback: derive reasons from task data only (no fabricated readiness claims)
    final reasons = <String>[];
    if (rec.isPriority) reasons.add('High priority');
    if (rec.deadline.isNotEmpty) reasons.add(rec.deadline);
    return reasons;
  }

  /// The current recommendation decision ID for tracking accept/override/later
  String? get currentDecisionId => _todaySnapshot?.decisionId;

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
    notifyListeners();
  }

  /// One-click instant guest mode.
  Future<void> enterGuestMode({bool startWithOnboarding = true}) async {
    final guest = await authService.loginAsGuest();
    _currentUser = guest;
    _isDemoMode = false;
    _onboardingComplete = !startWithOnboarding;
    _currentNavIndex = 0;
    _tasks = [];
    _schedule = [];
    _readiness = ReadinessModel.uncalibrated();
    _todayNetworkState = TodayNetworkState.emptySuccess;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flowstate_onboarding_complete', !startWithOnboarding);
    } catch (_) {}
    notifyListeners();
  }

  /// Create local guest session with entered email when Supabase is offline
  Future<void> enterOfflineDemoUser(String email, {bool startWithOnboarding = true}) async {
    final cleanEmail = email.trim();
    final name = cleanEmail.contains('@') ? cleanEmail.split('@').first : 'Guest';
    _currentUser = AuthUser(
      id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
      email: cleanEmail,
      name: name,
      onboardingCompleted: !startWithOnboarding,
    );
    _isDemoMode = false;
    _onboardingComplete = !startWithOnboarding;
    _currentNavIndex = 0;
    _tasks = [];
    _schedule = [];
    _readiness = ReadinessModel.uncalibrated();
    _todayNetworkState = TodayNetworkState.emptySuccess;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flowstate_onboarding_complete', !startWithOnboarding);
    } catch (_) {}
    notifyListeners();
  }

  void setCalibratedStateForTesting() {
    _tasks = [
      const TaskItem(
        id: 'task-test-1',
        title: 'Finish ML Assignment',
        durationMinutes: 90,
        difficulty: TaskDifficulty.high,
        deadline: 'Due Tomorrow',
        category: 'Study',
        taskType: TaskType.deepWork,
        isPriority: true,
      ),
      const TaskItem(
        id: 'task-test-2',
        title: 'Review DBMS Notes',
        durationMinutes: 45,
        difficulty: TaskDifficulty.medium,
        deadline: 'Due Friday',
        category: 'Study',
        taskType: TaskType.study,
        isPriority: false,
      ),
    ];
    _readiness = const ReadinessModel(
      score: 78,
      statusMessage: 'Ready for a good session',
      focusWindowRange: '9:30 AM – 11:30 AM',
      explanation: 'Your readiness is based on recent sleep, your usual rhythm, and previous work sessions.',
      hourlyRhythm: [
        EnergyPoint('6a', 0.4),
        EnergyPoint('8a', 0.7),
        EnergyPoint('10a', 0.9),
        EnergyPoint('12p', 0.6),
        EnergyPoint('2p', 0.5),
        EnergyPoint('4p', 0.7),
        EnergyPoint('6p', 0.5),
      ],
      isCalibrated: true,
      factors: ['Consistent wake-up schedule', 'Optimal sleep duration for focus', 'Circadian morning peak alignment'],
      confidence: 0.85,
    );
    _todayNetworkState = TodayNetworkState.tasksSuccess;
    _recalculateSchedule();
    notifyListeners();
  }


  void clearAllTasksForNewUserState() {
    _tasks = [];
    _schedule = [];
    _readiness = ReadinessModel.uncalibrated();
    _todaySnapshot = null;
    _todayNetworkState = TodayNetworkState.emptySuccess;
    _errorMessage = null;
    _isOffline = false;
    notifyListeners();
  }

  void setTodayNetworkStateForTesting(TodayNetworkState state, {String? errorMessage}) {
    _todayNetworkState = state;
    _errorMessage = errorMessage;
    notifyListeners();
  }

  void setOnboardingCompleteForTesting(bool complete) {
    _onboardingComplete = complete;
    _currentNavIndex = 0;
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
    _todayNetworkState = TodayNetworkState.tasksSuccess;
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

  void updateTask(TaskItem task) {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = task;
      if (!_isDemoMode) {
        taskService.updateTask(task).catchError((_) => task);
      }
      _recalculateReadiness();
      _recalculateSchedule();
      notifyListeners();
    }
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

  /// Guards local readiness recomputation from overwriting fresh backend data.
  /// When backend data is < 5 minutes old, skip client-side computation.
  bool get _isBackendDataFresh {
    if (_lastBackendSyncAt == null) return false;
    return DateTime.now().difference(_lastBackendSyncAt!).inMinutes < 5;
  }

  void _recalculateReadiness() {
    // Skip local computation when backend data is fresh — it would be wrong
    if (_isBackendDataFresh && _todaySnapshot != null) return;
    final bias = _learningEngine.computeReadinessAdaptiveBias();
    _readiness = _readinessEngine.computeReadiness(
      personalData: _personalData,
      adaptiveBias: bias,
    );
  }

  void _recalculateSchedule() {
    // Skip local schedule computation when backend data is fresh
    if (_isBackendDataFresh && _todaySnapshot != null) {
      _schedule = _todaySnapshot!.upcomingTimeline;
      return;
    }
    _schedule = _schedulingEngine.generateOptimizedSchedule(
      tasks: _tasks,
      readiness: _readiness,
    );
  }

  /// Records a user override (Later / Choose different task) to the backend.
  /// Returns the backend response containing next_window if available.
  /// Never blocks the user — fails silently if backend is unavailable.
  Future<Map<String, dynamic>?> recordOverride({
    String? reason,
    String? chosenTaskId,
  }) async {
    final decisionId = currentDecisionId;
    if (decisionId == null || _currentUser == null) return null;
    try {
      final res = await apiService.post('/api/v1/today/override', body: {
        'decision_id': decisionId,
        if (chosenTaskId != null) 'chosen_task_id': chosenTaskId,
        if (reason != null) 'reason': reason,
      });
      if (res is Map<String, dynamic>) {
        return res;
      }
    } catch (_) {
      // Non-critical — never block the user for analytics failures
    }
    return null;
  }

  /// Confirm a list of brain-dump parsed candidates, adding them all as tasks.
  /// Persists them to PostgreSQL via taskService and refreshes Today.
  Future<void> confirmCandidates(List<TaskItem> candidates) async {
    final List<TaskItem> createdTasks = [];
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final tempTask = candidate.copyWith(
        id: 'task-${DateTime.now().millisecondsSinceEpoch}-$i',
      );
      _tasks.insert(0, tempTask);
      createdTasks.add(tempTask);
    }
    _recalculateReadiness();
    _recalculateSchedule();
    notifyListeners();

    for (final tempTask in createdTasks) {
      try {
        final persisted = await taskService.createTask(tempTask);
        final idx = _tasks.indexWhere((t) => t.id == tempTask.id);
        if (idx != -1) {
          _tasks[idx] = persisted;
        }
      } catch (e) {
        debugPrint('Error creating task in backend: $e');
      }
    }
    notifyListeners();
    await refreshTodayData();
  }

  /// Persist onboarding completion status to SharedPreferences.
  Future<void> markOnboardingComplete() async {
    _onboardingComplete = true;
    _currentNavIndex = 0;
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
    _isLoading = true;
    _todayNetworkState = TodayNetworkState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final today = await todayService.getTodayExperience();
      _todaySnapshot = today;
      _lastUpdatedAt = today.lastUpdatedAt;
      _lastBackendSyncAt = DateTime.now();
      _readiness = today.readiness;
      _schedule = today.upcomingTimeline;
      _isOffline = false;
      _isLoading = false;
      final hasTasks = _tasks.isNotEmpty || today.upcomingTimeline.isNotEmpty || today.currentRecommendation != null;
      _todayNetworkState = hasTasks ? TodayNetworkState.tasksSuccess : TodayNetworkState.emptySuccess;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      // Check for cached offline data
      final cached = await todayService.getCachedToday();
      if (cached != null) {
        _todaySnapshot = cached;
        _lastUpdatedAt = cached.lastUpdatedAt;
        _readiness = cached.readiness;
        _schedule = cached.upcomingTimeline;
        _isOffline = true;
        _isLoading = false;
        _todayNetworkState = TodayNetworkState.networkFailure;
        notifyListeners();
      } else {
        if (e is ApiException && e.statusCode != null && e.statusCode! >= 500) {
          _todayNetworkState = TodayNetworkState.serverError;
          _errorMessage = 'Server error. Please try again later.';
        } else {
          _todayNetworkState = TodayNetworkState.networkFailure;
          _errorMessage = 'We couldn’t update your plan.';
        }
        _isOffline = true;
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Called when a real user signs in, signs up, or restores a Supabase session.
  /// Wipes all demo data, disables demo mode, loads real tasks, and fetches real Today plan.
  Future<void> onUserAuthenticated(AuthUser user) async {
    _currentUser = user;
    _isDemoMode = false;
    _tasks = [];
    _schedule = [];
    _readiness = ReadinessModel.uncalibrated();
    _todaySnapshot = null;

    if (user.onboardingCompleted) {
      _onboardingComplete = true;
      _currentNavIndex = 0;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('flowstate_onboarding_complete', true);
      } catch (_) {}
    } else {
      _currentNavIndex = 0;
    }

    notifyListeners();

    // Query backend single source of truth for onboarding/profile state
    try {
      final profile = await authService.fetchUserProfile();
      if (profile != null) {
        _currentUser = profile;
        if (profile.onboardingCompleted) {
          _onboardingComplete = true;
          _currentNavIndex = 0;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('flowstate_onboarding_complete', true);
          } catch (_) {}
        }
      }
    } catch (_) {}

    notifyListeners();

    await loadUserTasks();
    await refreshTodayData();
  }

  /// Fetches real tasks belonging exclusively to the authenticated user from the database.
  Future<void> loadUserTasks() async {
    try {
      final remoteTasks = await taskService.getTasks();
      _tasks = remoteTasks;
      _recalculateReadiness();
      _recalculateSchedule();
      notifyListeners();
    } catch (_) {}
  }

  /// Pull-to-refresh helper to refresh both tasks and today snapshot concurrently
  Future<void> refreshAllData() async {
    await Future.wait([
      loadUserTasks(),
      refreshTodayData(),
    ]);
  }


  /// Sign out current user, wipe in-memory tasks & schedule, clear persistent onboarding state.
  Future<void> logout() async {
    await authService.logout();
    _currentUser = null;
    _tasks = [];
    _schedule = [];
    _todaySnapshot = null;
    _readiness = ReadinessModel.uncalibrated();
    _onboardingComplete = false;
    _currentNavIndex = 0;
    _todayNetworkState = TodayNetworkState.emptySuccess;
    _errorMessage = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('flowstate_onboarding_complete');
    } catch (_) {}
  }
}

