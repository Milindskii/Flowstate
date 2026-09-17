import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../models/personal_data.dart';
import '../models/readiness_model.dart';
import '../models/schedule_item.dart';
import '../models/feedback_log.dart';
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
import '../utils/mock_data.dart';

/// Central App State Provider coordinating UI data, the local deterministic engines,
/// and backend service communications.
class AppStateProvider extends ChangeNotifier {
  // Local Deterministic Engines
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

  // State
  PersonalData _personalData = MockData.initialPersonalData;
  List<TaskItem> _tasks = MockData.initialTasks;
  late ReadinessModel _readiness;
  late List<ScheduleItem> _schedule;

  AuthUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isDemoMode = true; // Demo mode enabled by default for instant local responsiveness

  int _currentNavIndex = 0;
  String _selectedCategory = 'All';
  bool _isOptimizing = false;
  TaskItem? _activeFocusTask;

  AppStateProvider({ApiService? customApi}) {
    apiService = customApi ?? ApiService();
    authService = AuthService(api: apiService);
    taskService = TaskService(api: apiService);
    readinessService = ReadinessService(api: apiService);
    scheduleService = ScheduleService(api: apiService);
    feedbackService = FeedbackService(api: apiService);
    calendarService = CalendarService(api: apiService);
    healthService = HealthService(api: apiService);

    // Initial user context
    _currentUser = const AuthUser(
      id: 'user-demo-1',
      email: 'alex@flowstate.local',
      name: 'Alex',
    );

    _recalculateReadiness();
    _recalculateSchedule();
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

  String get greetingName => _currentUser?.name ?? 'Friend';

  // Progressive lifecycle state helpers
  bool get isNewUser => _tasks.isEmpty;
  bool get isLearningRhythm => !_readiness.isCalibrated;
  bool get isMatureUser => _tasks.isNotEmpty && _readiness.isCalibrated;

  int get currentNavIndex => _currentNavIndex;
  String get selectedCategory => _selectedCategory;
  bool get isOptimizing => _isOptimizing;
  TaskItem? get activeFocusTask => _activeFocusTask;
  PersonalLearningEngine get learningEngine => _learningEngine;

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
    final pending = _tasks.where((t) => !t.isCompleted).toList();
    if (pending.isEmpty) return null;
    return pending.firstWhere(
      (t) => t.difficulty == TaskDifficulty.high && t.isPriority,
      orElse: () => pending.first,
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
      taskService.createTask(newTask).then((_) {}).catchError((_) => newTask);
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
      } catch (_) {
        // Fall back to local calculation
      }
    }

    await Future.delayed(const Duration(milliseconds: 400));
    _recalculateSchedule();
    _isOptimizing = false;
    notifyListeners();
  }

  void setActiveFocusTask(TaskItem? task) {
    _activeFocusTask = task;
    notifyListeners();
  }

  // Update Personal Data (from Onboarding or Settings)
  void updatePersonalData(PersonalData updated) {
    _personalData = updated;
    _recalculateReadiness();
    _recalculateSchedule();
    notifyListeners();
  }

  // Engine recalculations
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

  /// Sync data from the backend
  Future<void> refreshTodayData() async {
    if (_isDemoMode) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final todayTasks = await taskService.getTodayTasks();
      final todayReadiness = await readinessService.getTodayReadiness();
      final todaySchedule = await scheduleService.getTodaySchedule();

      _tasks = todayTasks;
      _readiness = todayReadiness;
      _schedule = todaySchedule.isNotEmpty ? todaySchedule : _schedulingEngine.generateOptimizedSchedule(tasks: _tasks, readiness: _readiness);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'We couldn’t update your plan.';
      _isLoading = false;
      notifyListeners();
    }
  }
}
