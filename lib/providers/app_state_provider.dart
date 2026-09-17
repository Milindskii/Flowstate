import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../models/personal_data.dart';
import '../models/readiness_model.dart';
import '../models/schedule_item.dart';
import '../models/feedback_log.dart';
import '../engines/readiness_engine.dart';
import '../engines/scheduling_engine.dart';
import '../engines/personal_learning_engine.dart';
import '../utils/mock_data.dart';

/// Central App State Provider coordinating data and the three engines
class AppStateProvider extends ChangeNotifier {
  final ReadinessEngine _readinessEngine = const ReadinessEngine();
  final SchedulingEngine _schedulingEngine = const SchedulingEngine();
  final PersonalLearningEngine _learningEngine = PersonalLearningEngine();

  PersonalData _personalData = MockData.initialPersonalData;
  List<TaskItem> _tasks = MockData.initialTasks;
  late ReadinessModel _readiness;
  late List<ScheduleItem> _schedule;

  int _currentNavIndex = 0;
  String _selectedCategory = 'All';
  bool _isOptimizing = false;
  TaskItem? _activeFocusTask;

  AppStateProvider() {
    _recalculateReadiness();
    _recalculateSchedule();
  }

  // Getters
  PersonalData get personalData => _personalData;
  List<TaskItem> get tasks => List.unmodifiable(_tasks);
  ReadinessModel get readiness => _readiness;
  List<ScheduleItem> get schedule => List.unmodifiable(_schedule);
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

  // Task Actions
  void toggleTaskCompletion(String taskId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final task = _tasks[index];
      final willComplete = !task.isCompleted;
      _tasks[index] = task.copyWith(isCompleted: willComplete);

      if (willComplete) {
        // Feedback loop triggers Personal Learning
        _learningEngine.recordSessionFeedback(
          FeedbackLog(
            taskId: task.id,
            completedAt: DateTime.now(),
            actualMinutes: task.durationMinutes,
            perceivedFocusScore: 5,
            energyFeeling: 'Energized',
          ),
        );
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
    _recalculateSchedule();
    notifyListeners();
  }

  // Optimization Trigger
  Future<void> optimizeSchedule() async {
    _isOptimizing = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 600));

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
}
