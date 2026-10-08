import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engines/task_state.dart';
import '../utils/single_flight.dart';
import '../models/task_item.dart';
import '../models/task_reflection.dart';
import '../services/reflection_store.dart';
import '../models/personal_data.dart';
import '../models/readiness_model.dart';
import '../models/schedule_item.dart';
import '../models/calendar_models.dart';
import '../models/feedback_log.dart';
import '../models/today_model.dart';
import '../services/flow_clock.dart';
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
import '../services/timezone_service.dart';
import '../services/noya_busy.dart';
import '../services/day_path_anchor_store.dart';
import '../engines/day_path_order.dart';
import '../services/plan_confirm_exception.dart';
import '../services/smart_reminder_service.dart';
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
class AppStateProvider extends ChangeNotifier with WidgetsBindingObserver {
  /// Rapid repeated taps on the same AI/action button become ONE request.
  final SingleFlight _flight = SingleFlight();

  // Local Deterministic Engines (Used for initial mock / demo state)
  final ReadinessEngine _readinessEngine = const ReadinessEngine();
  final SchedulingEngine _schedulingEngine = const SchedulingEngine();
  final PersonalLearningEngine _learningEngine = PersonalLearningEngine();

  // Reflections ("How did that feel?") kept on this device, keyed by task id.
  final ReflectionStore _reflectionStore = ReflectionStore();
  final Map<String, TaskReflection> _reflections = {};
  Future<void> _reflectionsReady = Future.value();
  Future<void> _reflectionsSaved = Future.value();

  /// Whether real async work is pending (Noya's shared "thinking" state). See [NoyaBusy].
  final NoyaBusy busy = NoyaBusy();

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
  DayScheduleResponse? _selectedDateSchedule;
  final Map<String, DayScheduleResponse> _dayScheduleCache = {};
  Map<String, DayScheduleResponse> get dayScheduleCache => _dayScheduleCache;
  bool _isLoadingCalendarDay = false;
  DateTime _selectedCalendarDate = _dayOnly(_clockNow());
  int _calendarDayRequestId = 0;

  /// Tasks the user deleted here whose DELETE is not yet confirmed and re-read. Any day the server sends in the
  /// meantime (a clock tick, a resume, an older request) is stripped of them, so a deleted stop can never come back.
  final Set<String> _deletedTaskIds = {};

  /// Tasks created / edited / moved here that the server has not confirmed yet. A day read that started before the
  /// save landed is re-projected from the live task list, so the stop never flickers back to its old slot.
  final Set<String> _unsyncedTaskIds = {};

  /// Unsynced tasks leaving their day by a skip / defer: until the server answers, their old stop stays drawn
  /// (it becomes the history node). An explicit move to another day leaves the day at once instead.
  final Set<String> _keptStopTaskIds = {};

  /// Today and the Calendar day both write [_schedule] from network reads. Each read takes a ticket when it is
  /// issued; an answer may replace [_schedule] only if no later-issued read has written it already.
  int _scheduleWriteSeq = 0;
  int _scheduleAppliedSeq = 0;
  int _todayRequestId = 0;

  /// Task-list reads are numbered like Calendar day reads: an older answer never replaces a newer one.
  int _tasksRequestId = 0;
  int _tasksAppliedId = 0;

  /// Edits the user made that the server has not confirmed yet. A read that was already in flight when the edit
  /// was made predates it, so every task-list and day read is re-checked against these before it is adopted
  /// (one source of truth: the server answer, with the unconfirmed edits laid on top until it catches up).
  final Set<String> _pendingCompletions = {};

  /// taskId -> the day strings it is being removed from (deleted: [_everyDay]; moved to another day: that day).
  final Map<String, Set<String>> _pendingRemovals = {};
  static const String _everyDay = '*';

  /// Trophy claims in flight / done this session, by day: a repeated tap shares the one request.
  final Map<String, Future<Map<String, dynamic>?>> _claimsInFlight = {};
  final Set<String> _claimedDays = {};

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
  String? _preferredActiveTaskId;
  /// The local day the "Do this now" pick was made: it never carries over to another day.
  DateTime? _preferredActiveDate;
  final Set<String> _deferredTaskIds = {};
  final Set<String> _skippedTaskIds = {};
  /// taskId -> yyyy-MM-dd of the day it was skipped on. A skip marks THAT day's stop only.
  final Map<String, String> _skipDates = {};
  /// Where each task's Calendar stop was first placed on a day (device ledger, see DayPathAnchorStore).
  final DayPathAnchorStore _anchorStore = DayPathAnchorStore();
  DateTime? _lastCalendarFetchAt;
  DateTime? _lastClockTickAt;
  bool _calendarRefreshInFlight = false;
  bool _clockSubscribed = false;

  /// The time without creating the FlowClock singleton (whose minute timer belongs to the screens that use it).
  static DateTime _clockNow() => FlowClock.currentTime();

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The local date the app last acted on. The ONE thing that decides "the day changed": midnight in the
  /// foreground (clock tick) and waking up the next morning (resume) both go through [_rollOverIfNewDay].
  DateTime _lastKnownToday = _dayOnly(_clockNow());

  /// The local date changed since the app last looked: tomorrow's tasks are today's now. Moves the viewed Calendar
  /// day along (only if it was the old today: a day the user navigated to stays), drops everything cached under the
  /// old date, and re-reads Today and the day from the server (the server owns the new day's plan).
  /// Returns true when the date had changed.
  bool _rollOverIfNewDay() {
    final today = _dayOnly(_clockNow());
    if (today == _lastKnownToday) return false;
    final previous = _lastKnownToday;
    _lastKnownToday = today;
    if (_dayOnly(_selectedCalendarDate) == previous) _selectedCalendarDate = today;
    _dayScheduleCache.clear();
    _todaySnapshot = null; // yesterday's payload (its "tomorrow" section, its timeline) is not today's
    _lastBackendSyncAt = null;
    _recalculateSchedule();
    notifyListeners();
    if (!_isDemoMode && isAuthenticated && _onboardingComplete) {
      unawaited(loadCalendarDay(_selectedCalendarDate, silent: true));
      unawaited(refreshTodayData(silent: true));
    } else if (_selectedDateSchedule != null) {
      unawaited(loadCalendarDay(_selectedCalendarDate, silent: true));
    }
    SmartReminderService.instance.onDateRollover(today, _tasks);
    return true;
  }

  /// A Today payload fetched before today began, for a different date: last night's, served from the offline cache.
  /// (A live answer is fetched now, so it is never "before today began" and is always accepted.)
  bool _isYesterdaysToday(TodayResponseModel m) {
    if (m.date.isEmpty) return false;
    final today = _dayOnly(_clockNow());
    final ymd = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return m.date != ymd && m.lastUpdatedAt.isBefore(today);
  }

  /// The Calendar is showing days: follow the minute clock from now on (once).
  void _ensureClockSubscription() {
    if (_clockSubscribed) return;
    _clockSubscribed = true;
    FlowClock().addListener(_onClockTick);
  }
  final Set<String> _completedAfterDeviationTaskIds = {};
  bool _onboardingComplete = false;
  /// Optimistic local quest bump, once per user completion (no network).
  VoidCallback? onTaskCompletedForFlow;

  /// The server's progression changed (completion confirmed, trophy claimed): re-read the Flow overview once.
  VoidCallback? onFlowNeedsRefresh;

  /// Fires once per user completion (never on un-complete, never on the backend echo), so Noya
  /// reacts exactly once. [lastOfDay] is true when nothing else is pending today.
  void Function(TaskItem task, {required bool lastOfDay})? onTaskCompletedForNoya;

  /// Whether any task owned by today is still open. Ownership matches the backend: the slot's day,
  /// else `plannedDate`; an undated task (not yet saved) counts as today. Never createdAt/completedAt.
  bool get hasPendingTasksToday {
    final now = FlowClock().now;
    return _tasks.any((t) {
      if (t.isCompleted) return false;
      final day = t.scheduledStart ?? t.plannedDate;
      return day == null || (day.year == now.year && day.month == now.month && day.day == now.day);
    });
  }
  final Map<String, Completer<TaskItem>> _pendingTaskCreations = {};

  /// Last failed background sync (e.g. a save that was rejected and reverted). UI shows it once.
  String? _lastSyncError;
  String? get lastSyncError => _lastSyncError;
  void clearSyncError() {
    if (_lastSyncError != null) {
      _lastSyncError = null;
      notifyListeners();
    }
  }

  DateTime? _lastResumeRefresh;

  /// The app was away (backgrounded, or closed for a long time and restored): a task slot may have ended since.
  /// What is "missed" and what is "next" is derived from the clock plus the stored slots (never persisted by
  /// the passage of time), so coming back re-reads the authoritative day and Today instead of trusting a
  /// snapshot taken before the app left. Silent: a cached day stays on screen while the fresh one loads.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_rollOverIfNewDay()) {
      _lastResumeRefresh = _clockNow();
      _lastClockTickAt = _clockNow();
      return;
    }
    if (_isDemoMode || !isAuthenticated || !_onboardingComplete) return;
    final now = _clockNow();
    final last = _lastResumeRefresh;
    if (last != null && now.difference(last) < const Duration(seconds: 20)) return;
    _lastResumeRefresh = now;
    _lastClockTickAt = _clockNow();
    unawaited(loadCalendarDay(_selectedCalendarDate, silent: true));
    unawaited(refreshTodayData());
  }

  /// Every minute: the Calendar re-derives missed/bypassed/NOW on its own (CalendarTab listens to FlowClock). The
  /// provider additionally re-reads the selected day from the server when a stop boundary was crossed or 5 minutes
  /// passed, so server-side changes (completions elsewhere, history, suggestions) show without a manual refresh.
  void _onClockTick() {
    final now = FlowClock().now;
    final previous = _lastClockTickAt ?? now;
    _lastClockTickAt = now;
    SmartReminderService.instance.checkDueReminders(now);
    if (_rollOverIfNewDay()) return; // a new day re-reads everything; no stop-boundary logic for the old one
    final day = _selectedDateSchedule;
    if (_isDemoMode || !isAuthenticated || day == null || _calendarRefreshInFlight) return;
    final today = DateTime(now.year, now.month, now.day);
    if (_selectedCalendarDate != today) return;
    bool crossed(DateTime? t) => t != null && t.isAfter(previous) && !t.isAfter(now);
    final boundary = [...day.timeline, ...day.unscheduledTasks].any((i) => crossed(i.startTime) || crossed(i.endTime));
    final last = _lastCalendarFetchAt;
    if (boundary || last == null || now.difference(last) >= const Duration(minutes: 5)) {
      unawaited(loadCalendarDay(_selectedCalendarDate, silent: true));
    }
  }

  /// One refresh after any change to a task: Today and the Calendar day re-read what the server stored.
  Future<void> _afterTaskMutation() async {
    _dayScheduleCache.clear();
    if (_isDemoMode || !isAuthenticated) {
      if (_selectedDateSchedule != null) await loadCalendarDay(_selectedCalendarDate, silent: true);
      return;
    }
    // The task list too: the server may have moved the task (a skip, a collateral move), and the app's own copy is what
    // later projections of the day are drawn from. Reads are numbered and unconfirmed edits laid back on top.
    await Future.wait<void>([
      refreshTodayData(),
      loadCalendarDay(_selectedCalendarDate, silent: true),
      loadUserTasks(),
    ]);
  }

  /// [day] without the stops of [ids] (history nodes too when [history]: a deleted task leaves no ghost, a moved one does).
  DayScheduleResponse _stripTasks(DayScheduleResponse day, Set<String> ids, {required bool history}) {
    List<ScheduleItem> keep(List<ScheduleItem> items) =>
        items.where((i) => !ids.contains(dayPathTaskKey(i))).toList();
    return day.withItems(
      timeline: keep(day.timeline),
      fixedCommitments: keep(day.fixedCommitments),
      completedTasks: keep(day.completedTasks),
      remainingTasks: keep(day.remainingTasks),
      unscheduledTasks: keep(day.unscheduledTasks),
      deviations: history ? keep(day.deviations) : null,
    );
  }

  /// [day] with task [id] drawn from the LIVE task list: a deleted / cancelled task leaves, a created or edited one
  /// takes the slot it has now, and one explicitly moved to another day leaves this day's live projection at once.
  /// A skip / defer ([_keptStopTaskIds]) is left exactly as the server drew it (its stop becomes history; only the
  /// server decides what the day keeps), and so is a finished one (completion is drawn onto the existing stop).
  /// History nodes are never touched, so a stop keeps its anchor.
  DayScheduleResponse _projectTask(DayScheduleResponse day, String id) {
    TaskItem? task;
    for (final t in _tasks) {
      if (t.id == id) task = t;
    }
    if (task == null || task.status == TaskStatus.cancelled) return _stripTasks(day, {id}, history: true);
    if (task.isCompleted) return day;
    final date = DateTime.tryParse(day.date);
    if (date == null) return day;
    final local = _buildLocalScheduleForDate(DateTime(date.year, date.month, date.day), allowCachedToday: false)
        .where((i) => i.taskId == id)
        .toList();
    if (local.isEmpty) return _keptStopTaskIds.contains(id) ? day : _stripTasks(day, {id}, history: false);
    final stripped = _stripTasks(day, {id}, history: false);
    return stripped.withItems(
      timeline: orderDayPathItems([...stripped.timeline, ...local.where((i) => !isUnscheduledItem(i))]),
      unscheduledTasks: [...stripped.unscheduledTasks, ...local.where(isUnscheduledItem)],
    );
  }

  /// What a server read may show: nothing the user just deleted, and every unsaved local change as it is now.
  DayScheduleResponse _reconcileDay(DayScheduleResponse day) {
    var out = day;
    if (_deletedTaskIds.isNotEmpty) out = _stripTasks(out, _deletedTaskIds, history: true);
    for (final id in _unsyncedTaskIds) {
      out = _projectTask(out, id);
    }
    return out;
  }

  /// Draws the live state of [ids] onto the selected day right now (the caller notifies).
  void _projectIntoSelectedDay(Iterable<String> ids) {
    var day = _selectedDateSchedule;
    if (day == null) return;
    for (final id in ids) {
      day = _projectTask(day!, id);
    }
    _selectedDateSchedule = day;
  }

  /// A task-list read with the unconfirmed edits laid back on top (see [_pendingCompletions]).
  List<TaskItem> _withPendingTaskEdits(List<TaskItem> remote) {
    if (_pendingCompletions.isEmpty && _pendingRemovals.isEmpty) return remote;
    return [
      for (final t in remote)
        if (!(_pendingRemovals[t.id]?.contains(_everyDay) ?? false))
          _pendingCompletions.contains(t.id) && !t.isCompleted
              ? t.copyWith(isCompleted: true, completedAt: t.completedAt ?? DateTime.now(), status: TaskStatus.completed)
              : t,
    ];
  }

  /// A day read with the unconfirmed removals (a delete, a move to another day) applied again: a read that was in
  /// flight when the user acted still lists the task.
  DayScheduleResponse _withPendingDayEdits(DayScheduleResponse day) {
    if (_pendingRemovals.isEmpty) return day;
    var out = day;
    _pendingRemovals.forEach((taskId, days) {
      final everywhere = days.contains(_everyDay);
      if (everywhere || days.contains(day.date)) out = out.withoutTask(taskId, includeHistory: everywhere);
    });
    return out;
  }

  /// The selected day without [taskId], shown at once (the server confirms and the day is re-read after).
  void _removeFromSelectedDay(String taskId, {required bool includeHistory}) {
    final day = _selectedDateSchedule;
    if (day == null) return;
    final next = day.withoutTask(taskId, includeHistory: includeHistory);
    _selectedDateSchedule = next;
    _dayScheduleCache[day.date] = next;
  }

  void _recordAnchors(String dateStr, DayScheduleResponse day) {
    if (!_anchorStore.isLoaded) return;
    final history = dayPathHistoryAnchors(day.deviations);
    final anchors = <String, DateTime?>{};
    for (final item in [...day.timeline, ...day.unscheduledTasks, ...day.deviations]) {
      if (item.taskId == null) continue;
      anchors.putIfAbsent(dayPathTaskKey(item), () => dayPathNaturalAnchor(item, history));
    }
    if (_anchorStore.record(dateStr, anchors)) unawaited(_anchorStore.save());
  }

  /// The user explicitly moved [taskId] (a new time/day): its stop may take its new place.
  void _forgetAnchor(String taskId) {
    if (_anchorStore.forgetTask(taskId)) unawaited(_anchorStore.save());
  }

  /// See [_scheduleWriteSeq]: true (and recorded) when the read holding [ticket] may write [_schedule].
  bool _claimScheduleWrite(int ticket) {
    if (ticket < _scheduleAppliedSeq) return false;
    _scheduleAppliedSeq = ticket;
    return true;
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    if (_clockSubscribed) FlowClock().removeListener(_onClockTick);
    busy.dispose();
    super.dispose();
  }

  AppStateProvider({ApiService? customApi, AuthUser? initialUser}) {
    apiService = customApi ?? ApiService();
    authService = AuthService(api: apiService);
    taskService = TaskService(api: apiService);
    readinessService = ReadinessService(api: apiService);
    scheduleService = ScheduleService(api: apiService);
    feedbackService = FeedbackService(api: apiService);
    calendarService = CalendarService(api: apiService);
    healthService = HealthService(api: apiService);
    todayService = TodayService(api: apiService);
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {} // no binding in some isolated tests

    // Check if session is already restored from Supabase client or provided explicitly
    _currentUser = initialUser ?? authService.currentUser;
    if (_currentUser != null) {
      _isDemoMode = false;
      _tasks = [];
      _schedule = [];
      _readiness = ReadinessModel.uncalibrated();
      // Started now; onUserAuthenticated (splash) reuses these instead of fetching the same data again.
      _launchLoad = Future.wait([loadUserTasks(), refreshTodayData()]);
    } else {
      _tasks = [];
      _schedule = [];
      _readiness = ReadinessModel.uncalibrated();
    }

    _loadOnboardingState();
    _reflectionsReady = _loadReflections();
    _routeStatesReady = _loadRouteStates();
    SmartReminderService.instance.taskListProvider = () => _tasks;
    SmartReminderService.instance.syncTasks(_tasks);
    _anchorStore.load().then((_) {
      final day = _selectedDateSchedule;
      if (day != null) _recordAnchors(day.date, day);
      notifyListeners();
    });
  }

  late final Future<void> _routeStatesReady;

  /// Completes once persisted route states (skipped/deviated/recovered) have loaded.
  Future<void> get routeStatesReady => _routeStatesReady;

  Future<void> _loadRouteStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final skipped = prefs.getStringList('flowstate_skipped_task_ids');
      final deferred = prefs.getStringList('flowstate_deferred_task_ids');
      final completedDev = prefs.getStringList('flowstate_completed_after_deviation_task_ids');
      final dates = prefs.getString('flowstate_skipped_task_dates');
      if (dates != null && dates.isNotEmpty) {
        try {
          (jsonDecode(dates) as Map<String, dynamic>).forEach((k, v) => _skipDates[k] = v.toString());
        } catch (_) {}
      }
      if (skipped != null && skipped.isNotEmpty) {
        // a skip saved before skips had a day is kept, but marks no day's stop (skippedTaskIdsOn needs its day)
        _skippedTaskIds.addAll(skipped);
      }
      if (deferred != null && deferred.isNotEmpty) {
        _deferredTaskIds.addAll(deferred);
      }
      if (completedDev != null && completedDev.isNotEmpty) {
        _completedAfterDeviationTaskIds.addAll(completedDev);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveRouteStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('flowstate_skipped_task_ids', _skippedTaskIds.toList());
      _skipDates.removeWhere((id, _) => !_skippedTaskIds.contains(id));
      await prefs.setString('flowstate_skipped_task_dates', jsonEncode(_skipDates));
      await prefs.setStringList('flowstate_deferred_task_ids', _deferredTaskIds.toList());
      await prefs.setStringList('flowstate_completed_after_deviation_task_ids', _completedAfterDeviationTaskIds.toList());
    } catch (_) {}
  }

  String get _reflectionScope => _currentUser?.id ?? 'local';

  /// Reflections recorded while the stored ones were still loading (they must survive the load).
  final Set<String> _reflectionsRecordedDuringLoad = {};

  Future<void> _loadReflections() async {
    final scope = _reflectionScope;
    _reflectionsRecordedDuringLoad.clear();
    final loaded = await _reflectionStore.load(scope);
    if (scope != _reflectionScope) return;
    final fresh = {
      for (final id in _reflectionsRecordedDuringLoad)
        if (_reflections[id] != null) id: _reflections[id]!,
    };
    _reflections
      ..clear()
      ..addAll(loaded)
      ..addAll(fresh);
    _reflectionsRecordedDuringLoad.clear();
    if (fresh.isNotEmpty) _reflectionsSaved = _reflectionStore.save(scope, _reflections.values);
    notifyListeners();
  }

  /// Completes once this user's on-device reflections have loaded.
  Future<void> get reflectionsReady => _reflectionsReady;

  /// Completes once the latest reflection has been written to the device.
  Future<void> get reflectionsSaved => _reflectionsSaved;

  /// All reflections recorded on this device, newest first.
  List<TaskReflection> get reflections =>
      _reflections.values.toList()..sort((a, b) => b.completedAt.compareTo(a.completedAt));

  /// The reflection for a task, accepting Calendar item ids ("sched-…", "comp-…").
  TaskReflection? reflectionFor(String id) {
    final direct = _reflections[id];
    if (direct != null) return direct;
    for (final prefix in const ['sched-', 'comp-']) {
      if (id.startsWith(prefix)) return _reflections[id.substring(prefix.length)];
    }
    return null;
  }


  // Getters
  PersonalData get personalData => _personalData;
  List<TaskItem> get tasks => List.unmodifiable(_tasks);
  ReadinessModel get readiness => _readiness;
  List<ScheduleItem> get schedule => List.unmodifiable(_schedule);
  DayScheduleResponse? get selectedDateSchedule => _selectedDateSchedule;
  bool get isLoadingCalendarDay => _isLoadingCalendarDay;
  DateTime get selectedCalendarDate => _selectedCalendarDate;
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
  bool get isAuthenticated =>
      (_currentUser != null && !_currentUser!.id.startsWith('guest_')) ||
      authService.isAuthenticated;

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
    // Remaining = what can still be done. A slot that ended unstarted is MISSED (same rule as the backend and the
    // Calendar): it leaves the remaining workload and is reported apart for history/analytics.
    final now = FlowClock().now;
    bool isMissed(TaskItem t) {
      final start = t.scheduledStart;
      if (start == null || t.isActive) return false;
      return slotHasEnded(t.scheduledEnd ?? start.add(Duration(minutes: t.durationMinutes)), now);
    }

    final open = _tasks.where((t) => !t.isCompleted && !t.isCommitment).toList();
    final missed = open.where(isMissed).toList();
    final totalMins = open.where((t) => !isMissed(t)).fold<int>(0, (sum, t) => sum + t.durationMinutes);
    final missedMins = missed.fold<int>(0, (sum, t) => sum + t.durationMinutes);
    final hours = totalMins ~/ 60;
    final mins = totalMins % 60;
    final formatted = hours > 0 ? '${hours}h ${mins}m planned' : '${mins}m planned';
    final overloaded = totalMins > 390;

    return WorkloadSummaryModel(
      plannedMinutes: totalMins,
      formattedWorkload: formatted,
      message: totalMins == 0 && missed.isNotEmpty
          ? "Nothing left that can still be done today. ${missed.length} missed task${missed.length == 1 ? '' : 's'}: redo or replan when you're ready."
          : totalMins == 0
              ? "Let's build your day."
              : (overloaded ? "You're trying to fit $formatted into 6h 30m." : "Your day looks manageable."),
      isOverloaded: overloaded,
      availableMinutes: 390,
      missedMinutes: missedMins,
      missedCount: missed.length,
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
    if (rec.deadlineLabel.isNotEmpty) reasons.add(rec.deadlineLabel);
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

  String? get preferredActiveTaskId {
    final day = _preferredActiveDate;
    if (_preferredActiveTaskId == null || day == null) return _preferredActiveTaskId;
    final now = _clockNow();
    return DateTime(now.year, now.month, now.day) == day ? _preferredActiveTaskId : null;
  }

  /// Tasks skipped ON [date] (a skip never marks the task's stop on other days).
  Set<String> skippedTaskIdsOn(DateTime date) {
    final day = DateFormat('yyyy-MM-dd').format(date);
    return {for (final id in _skippedTaskIds) if (_skipDates[id] == day) id};
  }

  /// Every still-skipped task and the day it was skipped on (History files an explicit skip under that day).
  Map<String, DateTime> get skippedOnByTask => {
        for (final id in _skippedTaskIds)
          if (DateTime.tryParse(_skipDates[id] ?? '') != null) id: DateTime.parse(_skipDates[id]!),
      };

  /// Tasks the user has completed in this session that the server may not have confirmed yet.
  Set<String> get locallyCompletedTaskIds => {for (final t in _tasks) if (t.isCompleted) t.id};

  /// The device ledger's stop anchors for [date] (see buildCanonicalDayStops).
  Map<String, DayPathAnchorHint> dayPathAnchorsFor(DateTime date) =>
      _anchorStore.forDay(DateFormat('yyyy-MM-dd').format(date));
  Set<String> get deferredTaskIds => Set.unmodifiable(_deferredTaskIds);
  Set<String> get skippedTaskIds => Set.unmodifiable(_skippedTaskIds);
  Set<String> get completedAfterDeviationTaskIds => Set.unmodifiable(_completedAfterDeviationTaskIds);

  /// Primary "RIGHT NOW" execution recommendation
  TaskItem? get recommendedTask {
    final now = FlowClock().now;
    final today = DateTime(now.year, now.month, now.day);

    // A slot whose time passed unstarted is MISSED: it stays in the timeline and is recovered through
    // Redo/Replan, but it never leads "do this now". Mirrors the backend's derived state.
    bool isMissedSlot(TaskItem t) {
      final start = t.scheduledStart;
      if (t.isCommitment || start == null || t.isActive) return false;
      final end = t.scheduledEnd ?? start.add(Duration(minutes: t.durationMinutes));
      return slotHasEnded(end, now);
    }

    bool isFutureSlot(TaskItem t) {
      final start = t.scheduledStart;
      return start != null && start.isAfter(now.add(const Duration(minutes: 15)));
    }

    bool isTaskForToday(TaskItem t) {
      if (t.isCommitment) return false; // a fixed block is never "do this now" / up next
      if (t.scheduledStart != null) {
        // a stored slot belongs to its own day: an earlier day's slot is history, a later one is not today's
        final sDate = DateTime(t.scheduledStart!.year, t.scheduledStart!.month, t.scheduledStart!.day);
        return sDate == today;
      }
      if (t.plannedDate != null) {
        final pDate = DateTime(t.plannedDate!.year, t.plannedDate!.month, t.plannedDate!.day);
        return !pDate.isAfter(today);
      }
      if (t.deadlineAt != null) {
        final dDate = DateTime(t.deadlineAt!.year, t.deadlineAt!.month, t.deadlineAt!.day);
        return !dDate.isAfter(today);
      }
      return true;
    }

    // 1. If user explicitly chose a task via "Do this now", prioritize it if pending and for today
    if (_preferredActiveTaskId != null) {
      final preferred = _tasks.where((t) => t.id == _preferredActiveTaskId && !t.isCompleted && isTaskForToday(t)).firstOrNull;
      if (preferred != null) return preferred;
      _preferredActiveTaskId = null;
    }

    // 2. If backend recommendation exists, is not completed locally, and is not deferred:
    final backendTask = _todaySnapshot?.currentRecommendation?.task;
    final isBackendTaskCompletedLocally = backendTask != null &&
        _tasks.any((t) => t.id == backendTask.id && t.isCompleted); // by id: another day's same-named task is another task
    if (backendTask != null && !backendTask.isCompleted && !isBackendTaskCompletedLocally && !_deferredTaskIds.contains(backendTask.id) && isTaskForToday(backendTask) && !isMissedSlot(backendTask)) {
      return backendTask;
    }

    // 3. Fallback: filter pending tasks for today excluding deferred tasks
    final pendingNonDeferred = _tasks
        .where((t) => !t.isCompleted && isTaskForToday(t) && !isMissedSlot(t) && !isFutureSlot(t) && !_deferredTaskIds.contains(t.id))
        .toList();
    if (pendingNonDeferred.isNotEmpty) {
      return pendingNonDeferred.firstWhere(
        (t) => t.difficulty == TaskDifficulty.high && t.isPriority,
        orElse: () => pendingNonDeferred.first,
      );
    }

    // 4. If all pending tasks are deferred, fallback to any pending task for today
    final anyPending = _tasks.where((t) => !t.isCompleted && isTaskForToday(t) && !isMissedSlot(t) && !isFutureSlot(t)).toList();
    if (anyPending.isEmpty) {
      // nothing actionable now: offer only the next upcoming slot, never a missed one
      final upcoming = _tasks.where((t) => !t.isCompleted && isTaskForToday(t) && !isMissedSlot(t)).toList()
        ..sort((a, b) => (a.scheduledStart ?? now).compareTo(b.scheduledStart ?? now));
      return upcoming.firstOrNull;
    }
    return anyPending.firstWhere(
      (t) => t.difficulty == TaskDifficulty.high && t.isPriority,
      orElse: () => anyPending.first,
    );
  }

  /// A commitment (a fixed block like going out) is not work: it can't be completed, skipped or started.
  bool _isCommitmentRef(String taskId) {
    final id = taskId.startsWith('sched-') ? taskId.substring(6) : taskId;
    return _tasks.any((t) => t.isCommitment && (t.id == id || t.id == taskId));
  }

  /// Sets a task as the user's preferred active recommendation (Do this now)
  void setPreferredActiveTask(String taskId) {
    if (_isCommitmentRef(taskId)) return;
    String cleanId = taskId;
    if (taskId.startsWith('sched-')) {
      final stripped = taskId.substring(6);
      if (_tasks.any((t) => t.id == stripped)) {
        cleanId = stripped;
      }
    }
    final byTitle = _tasks.where((t) => t.title.toLowerCase() == taskId.toLowerCase()).firstOrNull;
    if (byTitle != null) {
      cleanId = byTitle.id;
    }
    _preferredActiveTaskId = cleanId;
    final pickedOn = _clockNow();
    _preferredActiveDate = DateTime(pickedOn.year, pickedOn.month, pickedOn.day);
    _deferredTaskIds.remove(cleanId);
    _skippedTaskIds.remove(cleanId);

    // Identify which tasks were bypassed by this deviation (user chose C instead of B):
    final targetTask = _tasks.where((t) => t.id == cleanId).firstOrNull;
    if (targetTask != null && targetTask.scheduledStart != null) {
      for (final t in _tasks) {
        if (!t.isCompleted &&
            t.id != cleanId &&
            t.scheduledStart != null &&
            t.scheduledStart!.isBefore(targetTask.scheduledStart!)) {
          _skippedTaskIds.add(t.id);
          _skipDates[t.id] = DateFormat('yyyy-MM-dd').format(pickedOn);
        }
      }
    }

    _saveRouteStates();
    _dayScheduleCache.clear();
    notifyListeners();
    // the server moves the chosen task to now: re-read the day so the path shows it (its stop stays anchored)
    unawaited(recordOverride(chosenTaskId: cleanId).then((_) => _afterTaskMutation()));
  }

  /// The day a skip marks the task's stop on: the day the task is on (a skip made on tomorrow's task belongs to
  /// tomorrow, not today). A slot that is already in the past is shown on today (it carries over), so that skip is today's.
  DateTime _skipDayOf(String taskId) {
    final today = _dayOnly(_clockNow());
    final task = _tasks.where((t) => t.id == taskId).firstOrNull;
    final at = task?.scheduledStart ?? task?.plannedDate;
    if (at == null) return today;
    final day = _dayOnly(at);
    return day.isBefore(today) ? today : day;
  }

  /// Explicitly skips/defers ONE task, from any screen. The server keeps its slot as "skipped" history (its stop
  /// stays there on the day path) and moves the task to its next good window; works without a Today
  /// recommendation. Returns the server's message (null offline / in demo).
  Future<String?> skipTask(String taskId) async {
    if (_isCommitmentRef(taskId)) return null;
    String cleanId = taskId.startsWith('sched-') ? taskId.substring(6) : taskId;
    final byTitle = _tasks.where((t) => t.title.toLowerCase() == taskId.toLowerCase()).firstOrNull;
    if (byTitle != null) {
      cleanId = byTitle.id;
    }
    _skippedTaskIds.add(cleanId);
    SmartReminderService.instance.onTaskSkipped(cleanId);
    _skipDates[cleanId] = DateFormat('yyyy-MM-dd').format(_skipDayOf(cleanId));
    _deferredTaskIds.add(cleanId);
    if (_preferredActiveTaskId == cleanId) {
      _preferredActiveTaskId = null;
    }
    _saveRouteStates();
    _dayScheduleCache.clear();
    notifyListeners();
    if (_isDemoMode || !isAuthenticated) return null;
    String? message;
    try {
      final tz = await _localTimezone();
      final res = await apiService.post('/api/v1/today/skip/$cleanId', body: {if (tz != null) 'timezone': tz});
      if (res is Map<String, dynamic>) message = res['message'] as String?;
    } catch (e) {
      debugPrint('Skip not saved on the server: $e');
      _lastSyncError = "Couldn't save the skip. It will show here until you try again.";
    }
    await _afterTaskMutation();
    return message;
  }

  void clearPreferredActiveTask() {
    _preferredActiveTaskId = null;
    notifyListeners();
  }

  /// Reschedules a task to a user-chosen date and optional time.
  ///
  /// * With a time: the user fixed it => `scheduledStart/End` + `timeLocked = true`.
  /// * Date only: `plannedDate` is set and the old slot is CLEARED (explicit nulls are sent), so the
  ///   server can place it. `deadlineAt` is never touched (it used to be overwritten with
  ///   midnight of the target day, which inverted "not before" into "finish before").
  ///
  /// Returns true when the change was saved. On failure the local change is reverted and
  /// [lastSyncError] explains why — a failed save never looks like a success.
  Future<bool> rescheduleTask(
    String taskId, {
    required DateTime targetDate,
    TimeOfDay? targetTime,
    bool leaveDayAtOnce = true,
    bool keepStop = false, // a defer: the old stop stays until the server draws it as history
  }) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;

    final task = _tasks[index];
    final normalizedDate = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final now = FlowClock().now;
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    String deadlineStr;
    if (normalizedDate == today) {
      deadlineStr = 'Today';
    } else if (normalizedDate == tomorrow) {
      deadlineStr = 'Tomorrow';
    } else {
      deadlineStr = DateFormat('EEE, MMM d').format(normalizedDate);
    }

    DateTime? newScheduledStart;
    DateTime? newScheduledEnd;
    String? newScheduledTime;

    if (targetTime != null) {
      newScheduledStart = DateTime(
        normalizedDate.year,
        normalizedDate.month,
        normalizedDate.day,
        targetTime.hour,
        targetTime.minute,
      );
      newScheduledEnd = newScheduledStart.add(Duration(minutes: task.durationMinutes));
      newScheduledTime = DateFormat('h:mm a').format(newScheduledStart);
    }

    final updated = task.copyWith(
      deadline: deadlineStr,
      deadlineAt: task.deadlineAt ?? normalizedDate, // local only: the save below never sends it
      scheduledStart: newScheduledStart,
      clearScheduledStart: newScheduledStart == null,
      scheduledEnd: newScheduledEnd,
      clearScheduledEnd: newScheduledEnd == null,
      scheduledTime: newScheduledTime,
      clearScheduledTime: newScheduledTime == null,
      timeLocked: newScheduledStart != null,
      plannedDate: normalizedDate,
      clearPlannedDate: false,
      status: task.status == TaskStatus.completed ? task.status : TaskStatus.todo,
    );

    _tasks[index] = updated;
    SmartReminderService.instance.onTaskRescheduled(updated);
    _forgetAnchor(taskId); // an explicit new time/day: the stop takes its new place

    // Moved to another day: it leaves the day on screen now, not after the server answers. A read already in flight
    // still lists it, so the removal stays pending (and is re-applied to those reads) until the save is confirmed.
    final effectiveLeaveDayAtOnce = leaveDayAtOnce && !keepStop;
    final shownDay = DateFormat('yyyy-MM-dd').format(_selectedCalendarDate);
    final leavesShownDay = effectiveLeaveDayAtOnce &&
        !_isDemoMode &&
        isAuthenticated &&
        shownDay != DateFormat('yyyy-MM-dd').format(normalizedDate);
    if (leavesShownDay) {
      _pendingRemovals[taskId] = {shownDay};
      _dayScheduleCache.clear();
      _removeFromSelectedDay(taskId, includeHistory: false);
      notifyListeners();
    }

    if (_preferredActiveTaskId == taskId) {
      _preferredActiveTaskId = null;
    }

    // If rescheduled to another date or to a future time today, defer from immediate hero
    if (normalizedDate != today || (newScheduledStart != null && newScheduledStart.isAfter(now))) {
      _deferredTaskIds.add(taskId);
    } else {
      _deferredTaskIds.remove(taskId);
    }

    if (!_isDemoMode && isAuthenticated) {
      // The stop takes its new time on Calendar now; the server read after the save only confirms it.
      _unsyncedTaskIds.add(taskId);
      if (!effectiveLeaveDayAtOnce) _keptStopTaskIds.add(taskId);
      _dayScheduleCache.clear();
      _projectIntoSelectedDay([taskId]);
      notifyListeners();
      try {
        await taskService.patchTask(taskId, {
          'scheduled_start': newScheduledStart?.toUtc().toIso8601String(), // explicit null clears
          'scheduled_end': newScheduledEnd?.toUtc().toIso8601String(),
          'time_locked': newScheduledStart != null,
          'planned_date': DateFormat('yyyy-MM-dd').format(normalizedDate),
          if (task.status != TaskStatus.completed) 'status': TaskStatus.todo.value,
        });
      } catch (e) {
        debugPrint('Error updating rescheduled task on backend: $e');
        final i = _tasks.indexWhere((t) => t.id == taskId);
        if (i != -1) _tasks[i] = task; // revert: never show a time the server did not accept
        _deferredTaskIds.remove(taskId);
        _lastSyncError = "Couldn't save the new time for \u201c${task.title}\u201d. Nothing was changed.";
        _pendingRemovals.remove(taskId);
        _unsyncedTaskIds.remove(taskId);
        _keptStopTaskIds.remove(taskId);
        _projectIntoSelectedDay([taskId]);
        _dayScheduleCache.clear();
        _recalculateSchedule();
        notifyListeners();
        if (leavesShownDay) await loadCalendarDay(_selectedCalendarDate, silent: true); // the node comes back
        return false;
      }
    }

    await recordOverride(reason: 'reschedule');
    _pendingRemovals.remove(taskId); // the server has the move: the day read below is authoritative
    _dayScheduleCache.clear();
    _lastBackendSyncAt = null; // Force fresh schedule recalculation
    _recalculateSchedule();
    _recalculateReadiness();
    notifyListeners();

    await loadCalendarDay(_selectedCalendarDate, silent: true);
    _unsyncedTaskIds.remove(taskId);
    _keptStopTaskIds.remove(taskId);
    if (!_isDemoMode) {
      await refreshTodayData();
    }
    return true;
  }

  /// Defers a task to later / tomorrow so another task becomes the active recommendation
  Future<void> deferTaskToLater(String taskId, {DateTime? nextWindow}) async {
    final target = nextWindow ?? DateTime.now().add(const Duration(days: 1));
    final targetDate = DateTime(target.year, target.month, target.day);
    final targetTime = TimeOfDay(hour: target.hour, minute: target.minute);
    // "Later" is a deviation, not a move: the stop keeps its place on today's path as history.
    await rescheduleTask(taskId, targetDate: targetDate, targetTime: targetTime, leaveDayAtOnce: false);
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
      if (index == 2) {
        loadCalendarDay(_selectedCalendarDate, silent: true);
      }
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
      await prefs.setBool(userOnboardingKey(guest.id), !startWithOnboarding);
    } catch (_) {}
    notifyListeners();
  }

  /// Create local guest session with entered email when Supabase is offline
  Future<void> enterOfflineDemoUser(String email, {bool startWithOnboarding = true}) async {
    final cleanEmail = email.trim();
    final name = cleanEmail.contains('@') ? cleanEmail.split('@').first : 'Guest';
    final user = AuthUser(
      id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
      email: cleanEmail,
      name: name,
      onboardingCompleted: !startWithOnboarding,
    );
    _currentUser = user;
    _isDemoMode = false;
    _onboardingComplete = !startWithOnboarding;
    _currentNavIndex = 0;
    _tasks = [];
    _schedule = [];
    _readiness = ReadinessModel.uncalibrated();
    _todayNetworkState = TodayNetworkState.emptySuccess;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(userOnboardingKey(user.id), !startWithOnboarding);
    } catch (_) {}
    notifyListeners();
  }

  void setCurrentUserForTesting(AuthUser? user) {
    _currentUser = user;
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
    _preferredActiveTaskId = null;
    _deferredTaskIds.clear();
    _dayScheduleCache.clear();
    _selectedDateSchedule = null;
    _isLoadingCalendarDay = false;
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

  /// The offline/demo day render, exposed so tests can pin the derived state of each item.
  List<ScheduleItem> buildLocalScheduleForTesting(DateTime date) => _buildLocalScheduleForDate(date);

  void setTasksForTesting(List<TaskItem> tasks) {
    _tasks = List.from(tasks);
    _recalculateSchedule();
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
    if (_isCommitmentRef(taskId)) return;
    var index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1 && taskId.startsWith('sched-')) {
      final strippedId = taskId.substring(6);
      index = _tasks.indexWhere((t) => t.id == strippedId);
    }
    if (index == -1) {
      index = _tasks.indexWhere((t) => t.title.toLowerCase() == taskId.toLowerCase());
    }
    if (index != -1) {
      final task = _tasks[index];
      final willComplete = !task.isCompleted;
      _tasks[index] = task.copyWith(isCompleted: willComplete, completedAt: willComplete ? DateTime.now() : null);
      if (!willComplete) {
        _pendingCompletions.remove(task.id); // taken back: no unconfirmed completion to protect
        _completedAfterDeviationTaskIds.remove(task.id); // no longer done, so no longer "done late"
        SmartReminderService.instance.onTaskUpdated(_tasks[index], task);
      } else {
        SmartReminderService.instance.onTaskCompleted(task.id);
      }

      if (willComplete) {
        if (_preferredActiveTaskId == task.id || _preferredActiveTaskId == taskId) {
          _preferredActiveTaskId = null;
        }
        // If this task was skipped or deferred, mark it as completed after deviation (recovery)
        final wasSkipped = _skippedTaskIds.contains(task.id);
        final wasDeferred = _deferredTaskIds.contains(task.id);
        // A slot that ended before this completion was MISSED (derived from the clock, never stored): finishing it
        // now is a recovery too, so its stop rejoins the road marked as done late rather than as done on plan.
        final slotEnd = task.scheduledEnd ?? task.scheduledStart?.add(Duration(minutes: task.durationMinutes));
        final wasMissed = !task.isCommitment && slotHasEnded(slotEnd, _clockNow());
        if (wasMissed && !wasSkipped && !wasDeferred) {
          _completedAfterDeviationTaskIds.add(task.id);
          _saveRouteStates();
        }
        if (wasSkipped || wasDeferred) {
          _completedAfterDeviationTaskIds.add(task.id);
          _skippedTaskIds.remove(task.id);
          _deferredTaskIds.remove(task.id);
          _saveRouteStates();
        }
        // No made-up reflection here: ratings only ever come from the reflection sheet, and the server records
        // the real completion time itself.

        // Immediate optimistic quest update
        onTaskCompletedForFlow?.call();
        onTaskCompletedForNoya?.call(_tasks[index], lastOfDay: !hasPendingTasksToday);

        if (!_isDemoMode) {
          if (_pendingTaskCreations.containsKey(task.id)) {
            // Task creation is still in-flight; will be completed once created
            debugPrint('Task ${task.id} creation in-flight; backend completion queued.');
          } else {
            unawaited(_sendCompleteToBackend(task, wasSkipped: wasSkipped, wasDeferred: wasDeferred));
          }
        }
        _recalculateReadiness();
      }
      _dayScheduleCache.clear();
      _recalculateSchedule();
      // The Calendar draws the node done at once (locallyCompletedTaskIds); the authoritative day is re-read after
      // the server confirms (see _sendCompleteToBackend), never before, or the reload would show it open again.
      if (_selectedDateSchedule != null && (_isDemoMode || !willComplete)) {
        loadCalendarDay(_selectedCalendarDate, silent: true);
      }
      notifyListeners();
    }
  }

  /// Stores a completion the user just made. Until the server answers the completion is a pending edit: any read
  /// that was already in flight is re-checked against it. Confirmed: the day and Today are re-read once. Rejected:
  /// the task is put back as it was (never a "done" the server does not have) and the day is re-read.
  Future<void> _sendCompleteToBackend(TaskItem task, {bool wasSkipped = false, bool wasDeferred = false}) async {
    _pendingCompletions.add(task.id);
    try {
      await taskService.completeTask(task.id);
    } catch (e) {
      debugPrint('Error completing task on backend: $e');
      _pendingCompletions.remove(task.id);
      // Without an account (guest / offline) there is no server copy to agree with: the local completion stands.
      if (!isAuthenticated) return;
      final i = _tasks.indexWhere((t) => t.id == task.id);
      if (i != -1) _tasks[i] = task.isCompleted ? task.copyWith(isCompleted: false, status: TaskStatus.todo) : task;
      _completedAfterDeviationTaskIds.remove(task.id);
      if (wasSkipped) _skippedTaskIds.add(task.id);
      if (wasDeferred) _deferredTaskIds.add(task.id);
      unawaited(_saveRouteStates());
      _lastSyncError = "Couldn't save \u201c${task.title}\u201d as done. It was put back.";
      _recalculateReadiness();
      _recalculateSchedule();
      _dayScheduleCache.clear();
      notifyListeners();
      await _afterTaskMutation();
      return;
    }
    _pendingCompletions.remove(task.id);
    // Authoritative sync after backend confirms quest & task persistence (no second local bump)
    onFlowNeedsRefresh?.call();
    await _afterTaskMutation();
  }

  /// The trophy at the end of a finished day: Noya's XP, granted once per day by the server.
  ///
  /// Safe to call repeatedly: taps while a claim is in flight share that one request, a day already claimed in this
  /// session sends nothing, and the server itself grants a day's XP only once (a repeat reports `already_claimed`),
  /// so a restart or a second device can never claim twice either.
  Future<Map<String, dynamic>?> claimDayComplete(DateTime date) {
    if (_isDemoMode || !isAuthenticated) return Future.value(null);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    if (_claimedDays.contains(dateStr)) {
      return Future.value({'date': dateStr, 'claimed': true, 'already_claimed': true, 'xp_awarded': 0});
    }
    return _claimsInFlight[dateStr] ??= _claimDay(dateStr).whenComplete(() {
      // a block body: returning the removed future would make it wait on itself
      _claimsInFlight.remove(dateStr);
    });
  }

  Future<Map<String, dynamic>?> _claimDay(String dateStr) async {
    final tz = await _localTimezone();
    final res = await apiService.post('/api/v1/flow/day-complete/claim', body: {
      'date': dateStr,
      if (tz != null) 'timezone': tz,
    });
    _claimedDays.add(dateStr);
    final day = _selectedDateSchedule;
    if (day != null && day.date == dateStr) {
      _selectedDateSchedule = day.withDayComplete(day.dayComplete.copyWith(claimed: true));
      _dayScheduleCache[dateStr] = _selectedDateSchedule!;
    }
    notifyListeners();
    onFlowNeedsRefresh?.call(); // Flow/Noya progression re-reads its overview
    return res is Map<String, dynamic> ? res : null;
  }

  Future<TaskItem> addTask({
    required String title,
    required int durationMinutes,
    required TaskDifficulty difficulty,
    required String deadline,
    required String category,
    bool isPriority = false,
    TaskPriority? priority,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    DateTime? deadlineAt,
    String? scheduledTime,
    TaskType? taskType,
  }) async {
    final tempId = 'task-${DateTime.now().millisecondsSinceEpoch}';
    final newTask = TaskItem(
      id: tempId,
      title: title,
      durationMinutes: durationMinutes,
      difficulty: difficulty,
      deadline: deadline,
      category: category,
      isPriority: isPriority,
      priority: priority,
      prioritySource: priority != null ? 'explicit' : null,
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledEnd,
      deadlineAt: deadlineAt,
      scheduledTime: scheduledTime,
      taskType: taskType ?? TaskType.deepWork,
    );

    _tasks.insert(0, newTask);
    SmartReminderService.instance.onTaskAdded(newTask);
    _dayScheduleCache.clear();
    _recalculateReadiness();
    _recalculateSchedule();
    if (_isDemoMode) {
      if (_selectedDateSchedule != null) loadCalendarDay(_selectedCalendarDate, silent: true);
    } else {
      // The new stop is on Calendar now; the server read below only confirms it.
      _unsyncedTaskIds.add(tempId);
      _projectIntoSelectedDay([tempId]);
    }
    notifyListeners();

    if (!_isDemoMode) {
      final completer = Completer<TaskItem>();
      _pendingTaskCreations[tempId] = completer;

      try {
        final persisted = await taskService.createTask(newTask);
        final idx = _tasks.indexWhere((t) => t.id == tempId);
        if (idx != -1) {
          final wasCompleted = _tasks[idx].isCompleted;
          _tasks[idx] = persisted.copyWith(isCompleted: wasCompleted);
          if (persisted.id != tempId) {
            SmartReminderService.instance.cancelReminder(tempId);
            SmartReminderService.instance.onTaskAdded(_tasks[idx]);
          }
          if (wasCompleted) {
            unawaited(_sendCompleteToBackend(_tasks[idx]));
          }
          _dayScheduleCache.clear();
          // the temporary stop becomes the saved task's stop (same slot, real id)
          _unsyncedTaskIds
            ..remove(tempId)
            ..add(persisted.id);
          final day = _selectedDateSchedule;
          if (day != null) {
            _selectedDateSchedule = _projectTask(_stripTasks(day, {tempId}, history: true), persisted.id);
            unawaited(loadCalendarDay(_selectedCalendarDate, silent: true)
                .whenComplete(() => _unsyncedTaskIds.remove(persisted.id)));
          } else {
            _unsyncedTaskIds.remove(persisted.id);
          }
          notifyListeners();
        } else if (_deletedTaskIds.contains(tempId)) {
          _unsyncedTaskIds.remove(tempId);
        }
        completer.complete(persisted);
        _pendingTaskCreations.remove(tempId);
        return persisted;
      } catch (e) {
        debugPrint('Error creating task in backend: $e');
        completer.complete(newTask);
        _pendingTaskCreations.remove(tempId);
      }
    }

    return newTask;
  }

  void updateTask(TaskItem task) {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      final previous = _tasks[index];
      _tasks[index] = task;
      SmartReminderService.instance.onTaskUpdated(task, previous);
      if (previous.scheduledStart != task.scheduledStart || previous.plannedDate != task.plannedDate) {
        _forgetAnchor(task.id); // the user edited its time/day
      }
      _dayScheduleCache.clear();
      if (!_isDemoMode) {
        // Calendar shows the edit now; the server read after the save only confirms it.
        _unsyncedTaskIds.add(task.id);
        _projectIntoSelectedDay([task.id]);
        taskService.updateTask(task).then((saved) {
          // The server has the change now: re-read the day so Calendar shows what is stored, not a pre-save view.
          _dayScheduleCache.clear();
          if (_selectedDateSchedule != null) {
            unawaited(loadCalendarDay(_selectedCalendarDate, silent: true)
                .whenComplete(() => _unsyncedTaskIds.remove(task.id)));
          } else {
            _unsyncedTaskIds.remove(task.id);
          }
          return saved;
        }).catchError((Object e) {
          // A rejected save is reverted and reported, never silently kept.
          debugPrint('Error saving task ${task.id}: $e');
          final i = _tasks.indexWhere((t) => t.id == task.id);
          if (i != -1) {
            _tasks[i] = previous;
            SmartReminderService.instance.onTaskUpdated(previous, task);
          }
          _lastSyncError = "Couldn't save changes to \u201c${task.title}\u201d. They were reverted.";
          _dayScheduleCache.clear();
          _unsyncedTaskIds.remove(task.id);
          _projectIntoSelectedDay([task.id]);
          _recalculateSchedule();
          notifyListeners();
          return previous;
        });
      }
      _recalculateReadiness();
      _recalculateSchedule();
      // Demo mode has no server: re-read the local day now. Signed in, the day is re-read once, after the save.
      if (_isDemoMode && _selectedDateSchedule != null) {
        loadCalendarDay(_selectedCalendarDate, silent: true);
      }
      notifyListeners();
    }
  }

  /// Deletes a task. The node leaves Calendar at once and stays gone: a read that was already in flight is
  /// re-checked against the pending delete, and the day is re-read once the server has actually deleted it.
  void removeTask(String taskId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    final removed = index == -1 ? null : _tasks[index];
    if (index != -1) _tasks.removeAt(index);
    SmartReminderService.instance.onTaskDeleted(taskId);
    _forgetAnchor(taskId);
    _unsyncedTaskIds.remove(taskId);
    _dayScheduleCache.clear();
    _recalculateReadiness();
    _recalculateSchedule();
    if (_isDemoMode || !isAuthenticated) {
      // No account to confirm against (demo / guest): the local list is the truth, the server call is best-effort.
      if (!_isDemoMode) taskService.deleteTask(taskId).catchError((_) {});
      if (_selectedDateSchedule != null) loadCalendarDay(_selectedCalendarDate, silent: true);
      notifyListeners();
      return;
    }
    _pendingCompletions.remove(taskId);
    _pendingRemovals[taskId] = {_everyDay};
    _deletedTaskIds.add(taskId);
    _removeFromSelectedDay(taskId, includeHistory: true);
    notifyListeners();
    unawaited(_confirmTaskDelete(taskId, removed, index));
  }

  Future<void> _confirmTaskDelete(String taskId, TaskItem? removed, int index) async {
    final deleted = <String>{taskId};
    var serverOk = true;
    try {
      if (!_isDemoMode) {
        // Still being created: there is nothing under the temporary id; delete what the server stores for it.
        final creation = _pendingTaskCreations[taskId];
        var onServer = <String>[taskId];
        if (creation != null) {
          final persisted = await creation.future;
          onServer = persisted.id == taskId ? <String>[] : <String>[persisted.id];
          deleted.addAll(onServer);
          _deletedTaskIds.addAll(onServer);
          for (final sId in onServer) {
            _pendingRemovals[sId] = {_everyDay};
          }
          _tasks.removeWhere((t) => onServer.contains(t.id));
        }
        for (final id in onServer) {
          try {
            await taskService.deleteTask(id);
          } on ApiException catch (e) {
            if (e.statusCode != 404) rethrow; // already gone is as good as deleted
          }
        }
      }
    } catch (e) {
      serverOk = false;
      debugPrint('Error deleting task $taskId: $e');
    }

    _pendingRemovals.remove(taskId);
    for (final id in deleted) {
      _pendingRemovals.remove(id);
    }

    if (!serverOk && removed != null && !_tasks.any((t) => t.id == taskId)) {
      _tasks.insert(index.clamp(0, _tasks.length), removed);
      SmartReminderService.instance.onTaskAdded(removed);
      _lastSyncError = "Couldn't delete \u201c${removed.title}\u201d. It was put back.";
      _deletedTaskIds.removeAll(deleted);
      _dayScheduleCache.clear();
      _recalculateReadiness();
      _recalculateSchedule();
      _projectIntoSelectedDay([taskId]);
      notifyListeners();
    }

    try {
      await _afterTaskMutation();
    } finally {
      _deletedTaskIds.removeAll(deleted);
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

  /// Loads the authoritative schedule for a selected calendar date.
  /// Changing dates never displays stale data from the previous date.
  Future<void> loadCalendarDay(DateTime date, {bool silent = false}) async {
    _ensureClockSubscription();
    _calendarDayRequestId++;
    final requestId = _calendarDayRequestId;
    final normalizedDate = DateTime(date.year, date.month, date.day);
    _selectedCalendarDate = normalizedDate;
    final dateStr = DateFormat('yyyy-MM-dd').format(normalizedDate);
    final now = FlowClock().now;
    final today = DateTime(now.year, now.month, now.day);
    final isToday = normalizedDate == today;
    final isPast = normalizedDate.isBefore(today);

    // Instant restoration from cache if available (eliminates flicker/reload flash)
    if (_dayScheduleCache.containsKey(dateStr)) {
      _selectedDateSchedule = _withPendingDayEdits(_dayScheduleCache[dateStr]!);
      _isLoadingCalendarDay = false;
      notifyListeners();
    } else if (silent && _selectedDateSchedule != null && _selectedDateSchedule!.date == dateStr) {
      // a background refresh keeps the day on screen while the fresh copy loads
    } else {
      _selectedDateSchedule = null; // Clear immediately to avoid displaying stale data from previous date
      _isLoadingCalendarDay = true;
      notifyListeners();
    }

    if (_isDemoMode) {
      final localTimeline = _buildLocalScheduleForDate(normalizedDate);
      if (requestId == _calendarDayRequestId) {
        final localSchedule = DayScheduleResponse(
          date: dateStr,
          isToday: isToday,
          isPast: isPast,
          timeline: localTimeline,
          fixedCommitments: localTimeline.where((item) => item.isFixed).toList(),
          completedTasks: localTimeline.where((item) => item.isCompleted).toList(),
          remainingTasks: localTimeline.where((item) => !item.isCompleted && !item.isFixed).toList(),
          focusWindow: _readiness.focusWindowRange,
          totalPlannedMinutes: localTimeline.fold(0, (acc, item) => acc + item.durationMinutes),
        );
        _dayScheduleCache[dateStr] = localSchedule;
        _selectedDateSchedule = localSchedule;
        if (isToday) {
          _schedule = localTimeline.where((t) => !t.isCompleted).toList();
        }
        _isLoadingCalendarDay = false;
        notifyListeners();
      }
      return;
    }

    _calendarRefreshInFlight = true;
    final scheduleTicket = ++_scheduleWriteSeq;
    try {
      // Only a blocking load (nothing cached to show) is "thinking"; a background refresh stays silent.
      final blocking = _selectedDateSchedule == null;
      final fetched = blocking
          ? await busy.track(() => calendarService.getDaySchedule(dateStr), label: 'Loading your day')
          : await calendarService.getDaySchedule(dateStr);
      if (requestId == _calendarDayRequestId) {
        // The server's day, minus what was deleted here a moment ago and with unsaved local edits applied.
        final day = _reconcileDay(_withPendingDayEdits(fetched));
        _dayScheduleCache[dateStr] = day;
        _selectedDateSchedule = day;
        _lastCalendarFetchAt = FlowClock().now;
        _recordAnchors(dateStr, day);
        if (isToday && _claimScheduleWrite(scheduleTicket)) {
          _schedule = day.timeline.where((t) => !t.isCompleted).toList();
        }
        _isLoadingCalendarDay = false;
        notifyListeners();
      }
    } catch (_) {
      if (requestId == _calendarDayRequestId) {
        // Offline: the last day the server sent is better than a local rebuild (it has the history nodes)
        final previous = _selectedDateSchedule;
        if (previous != null && previous.date == dateStr) {
          _isLoadingCalendarDay = false;
          notifyListeners();
          return;
        }
        // Safe offline / local fallback
        final localTimeline = _buildLocalScheduleForDate(normalizedDate);
        final fallback = DayScheduleResponse(
          date: dateStr,
          isToday: isToday,
          isPast: isPast,
          timeline: localTimeline,
          fixedCommitments: localTimeline.where((item) => item.isFixed).toList(),
          completedTasks: localTimeline.where((item) => item.isCompleted).toList(),
          remainingTasks: localTimeline.where((item) => !item.isCompleted && !item.isFixed).toList(),
          focusWindow: _readiness.focusWindowRange,
          totalPlannedMinutes: localTimeline.fold(0, (acc, item) => acc + item.durationMinutes),
        );
        // Not cached: a fallback built from local tasks can lag the server, and a cached partial day would
        // keep showing it. The next load asks the server again.
        _selectedDateSchedule = fallback;
        _isLoadingCalendarDay = false;
        notifyListeners();
      }
    } finally {
      _calendarRefreshInFlight = false;
    }
  }

  /// Generates a dry-run Replan proposal for the specified date.
  /// Strictly DRY RUN: Never modifies _tasks or database.
  Future<ReplanResponse> replanDay({
    required DateTime date,
    required String message,
    Map<String, dynamic>? quickAdd,
    String? idempotencyKey,
  }) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    // The same request while it is still running shares one call (one model call, one possible Shield charge).
    return _flight.run('replan-$dateKey-$message-${quickAdd ?? ''}', () => _replanDay(
          date: date, message: message, quickAdd: quickAdd, idempotencyKey: idempotencyKey));
  }

  Future<ReplanResponse> _replanDay({
    required DateTime date,
    required String message,
    Map<String, dynamic>? quickAdd,
    String? idempotencyKey,
  }) {
    // Noya shows "thinking" from the moment the work starts until it settles (success, error or timeout).
    return busy.track(() async {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final now = FlowClock().now;
      final timezone = await _localTimezone();

      return await calendarService.replanDay(
        dateStr: dateStr,
        message: message,
        currentLocalTime: now,
        timezone: timezone,
        quickAdd: quickAdd,
        idempotencyKey: idempotencyKey,
      );
    }, label: 'Rearranging your day');
  }

  /// The device's IANA zone name (never an abbreviation like "IST"; null => the server uses the stored
  /// preference). Resolved once: it is a platform-channel call and cannot change within a session.
  String? _cachedTimezone;
  bool _timezoneResolved = false;
  Future<String?> _localTimezone() async {
    if (!_timezoneResolved) {
      _cachedTimezone = await TimezoneService.localIanaName();
      _timezoneResolved = true;
    }
    return _cachedTimezone;
  }

  /// Atomically applies a confirmed PlanDiff to the database.
  /// Refreshes Calendar date schedule, User Tasks, and Today page (including Up Next).
  Future<ApplyReplanResponse> applyReplan(PlanDiff diff) => _flight.run(
        'apply-replan',
        () => busy.track(() => _applyReplan(diff), label: 'Updating your plan'),
      );

  Future<ApplyReplanResponse> _applyReplan(PlanDiff diff) async {
    final tzName = await _localTimezone();
    final request = diff.toApplyRequest().withClock(FlowClock().now, timezoneName: tzName);

    if (_isDemoMode) {
      _applyPlanDiffLocally(diff);
      _dayScheduleCache.clear();
      await loadCalendarDay(_selectedCalendarDate, silent: true);
      _recalculateSchedule();
      SmartReminderService.instance.onReplanApplied(_tasks);
      notifyListeners();
      return ApplyReplanResponse(
        success: true,
        updatedCount: diff.movedTasks.length,
        createdCount: diff.newlyScheduledTasks.length,
        cancelledCount: diff.cancelledTasks.length,
        message: 'Successfully applied replan in demo mode.',
      );
    }

    try {
      final res = await calendarService.applyReplan(request);
      if (res.success) {
        final intents = (request.raw?['intents'] as Map?) ?? const {};
        // Skips/defers keep their stop (history) until the re-read draws it as such.
        final keptStops = <String>{
          for (final e in intents.entries)
            if (const {'skipped', 'deferred'}.contains(e.value)) e.key.toString(),
        };
        // Adopt exactly what the server stored before reloading everything else.
        for (final raw in res.persistedTasks) {
          final persisted = TaskItem.fromJson(raw);
          final i = _tasks.indexWhere((t) => t.id == persisted.id);
          if (i != -1) {
            _tasks[i] = persisted;
          } else if (persisted.status != TaskStatus.cancelled) {
            _tasks.insert(0, persisted);
          }
        }
        // An explicit move ("move gym to 8") gives the stop its new place; skips/defers keep it (history).
        intents.forEach((id, intent) {
          if (const {'rescheduled', 'preference_shift', 'delayed'}.contains(intent)) _forgetAnchor(id.toString());
        });
        // A "Do this now" pin on a task Replan just moved would keep showing its old slot as current.
        final movedIds = {for (final raw in res.persistedTasks) (raw['id'] ?? '').toString()};
        if (_preferredActiveTaskId != null && movedIds.contains(_preferredActiveTaskId)) {
          _preferredActiveTaskId = null;
        }
        // The new plan is on Calendar before the re-read: what Replan stored is drawn, what it cancelled is gone.
        final replanned = <String>{
          for (final raw in res.persistedTasks) (raw['id'] ?? '').toString(),
        }..remove('');
        final cancelled = {for (final c in diff.cancelledTasks) c.taskId};
        _tasks.removeWhere((t) => cancelled.contains(t.id));
        _unsyncedTaskIds.addAll(replanned);
        _keptStopTaskIds.addAll(keptStops.intersection(replanned));
        _dayScheduleCache.clear();
        final shown = _selectedDateSchedule;
        if (shown != null) {
          _selectedDateSchedule = _stripTasks(shown, cancelled, history: true);
          _projectIntoSelectedDay(replanned);
          notifyListeners();
        }
        // Authoritative Refresh Cycle:
        // 1. Calendar schedule for selected date
        // The three reads are independent: run them together instead of one after another.
        _dayScheduleCache.clear();
        await Future.wait<void>([
          loadCalendarDay(_selectedCalendarDate, silent: true), // 1. Calendar schedule for the selected date
          loadUserTasks(), // 2. User tasks from backend
          refreshTodayData(authoritative: true), // 3. Today (Up Next & Rhythm); never a stale cached snapshot
        ]);
        _unsyncedTaskIds.removeAll(replanned);
        _keptStopTaskIds.removeAll(replanned);
        // 4. Recalculate local schedule and readiness
        _recalculateSchedule();
        _recalculateReadiness();
        SmartReminderService.instance.onReplanApplied(_tasks);
        notifyListeners();
      }
      return res;
    } catch (e) {
      debugPrint('Failed to apply replan: $e');
      rethrow;
    }
  }

  void _applyPlanDiffLocally(PlanDiff diff) {
    for (final moved in diff.movedTasks) {
      final idx = _tasks.indexWhere((t) => t.id == moved.taskId);
      if (idx != -1) {
        final match = diff.afterSchedule.firstWhere(
          (item) => (item.taskId != null && item.taskId == moved.taskId) || item.title == moved.title,
          orElse: () => diff.afterSchedule.isNotEmpty
              ? diff.afterSchedule.first
              : ScheduleItem(
                  id: moved.taskId,
                  time: moved.newTime ?? '',
                  period: '',
                  title: moved.title,
                  type: 'Focus',
                  tagText: 'TASK',
                ),
        );
        _tasks[idx] = _tasks[idx].copyWith(
          scheduledStart: match.startTime,
          scheduledEnd: match.endTime,
        );
      }
    }
    for (final nt in diff.newlyScheduledTasks) {
      final match = diff.afterSchedule.firstWhere(
        (item) => (item.taskId != null && item.taskId == nt.taskId) || item.title == nt.title,
        orElse: () => diff.afterSchedule.isNotEmpty
            ? diff.afterSchedule.first
            : ScheduleItem(
                id: nt.taskId,
                time: nt.newTime ?? '',
                period: '',
                title: nt.title,
                type: 'Focus',
                tagText: 'TASK',
              ),
      );
      _tasks.add(TaskItem(
        id: nt.taskId.isNotEmpty ? nt.taskId : 'task-${DateTime.now().millisecondsSinceEpoch}',
        title: nt.title,
        durationMinutes: nt.durationMinutes,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
        scheduledStart: match.startTime,
        scheduledEnd: match.endTime,
      ));
    }
    for (final c in diff.cancelledTasks) {
      _tasks.removeWhere((t) => t.id == c.taskId);
    }
  }

  List<ScheduleItem> _buildLocalScheduleForDate(DateTime date, {bool allowCachedToday = true}) {
    final now = FlowClock().now;
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;

    // Filter tasks for this date strictly by scheduledStart (never fall back to midnight or deadline)
    final dateTasks = _tasks.where((t) {
      final sStart = t.scheduledStart;
      if (sStart == null) return false;
      return sStart.year == date.year &&
          sStart.month == date.month &&
          sStart.day == date.day;
    }).toList();

    // Open tasks planned for this day that have no slot are still the day's tasks: they get a node, never nothing.
    final unslotted = _tasks.where((t) {
      if (t.scheduledStart != null || t.isCompleted || t.status == TaskStatus.cancelled) return false;
      final p = t.plannedDate;
      if (p != null) return p.year == date.year && p.month == date.month && p.day == date.day;
      return isToday; // legacy undated rows belong to today
    }).toList();

    if (allowCachedToday && dateTasks.isEmpty && unslotted.isEmpty && isToday && _schedule.isNotEmpty) {
      return _schedule;
    }

    final startOfDay = DateTime(date.year, date.month, date.day);
    final unscheduledItems = unslotted.map((t) => ScheduleItem(
          id: 'sched-${t.id}',
          taskId: t.id,
          time: '--:--',
          period: '',
          title: t.title,
          type: t.taskType == TaskType.deepWork ? 'High Focus' : 'Task',
          tagText: 'UNSCHEDULED',
          durationMinutes: t.durationMinutes,
          isConflict: true,
          isCommitment: t.isCommitment,
          startTime: startOfDay,
          endTime: startOfDay.add(Duration(minutes: t.durationMinutes)),
        ));

    return [...dateTasks.map((t) {
      final sStart = t.scheduledStart!;
      // Mirrors the backend day render: a user-fixed time stays fixed in Calendar.
      final locked = t.timeLocked && !t.isCompleted;
      final isDeviated = (_skippedTaskIds.contains(t.id) || _deferredTaskIds.contains(t.id)) && !t.isCompleted;
      final isRecovered = _completedAfterDeviationTaskIds.contains(t.id) && t.isCompleted;
      final sEnd = t.scheduledEnd ?? sStart.add(Duration(minutes: t.durationMinutes));
      final derived = deriveSlotState(
        completed: t.isCompleted, cancelled: false, active: t.isActive,
        start: sStart, end: sEnd, now: now, bedtimeHours: _personalData.bedtimeHour,
        commitment: t.isCommitment,
      );
      final isMissed = derived == TaskState.missed;
      final isFailed = derived == TaskState.failed;
      return ScheduleItem(
        id: 'sched-${t.id}',
        taskId: t.id,
        time: DateFormat('h:mm').format(sStart),
        period: DateFormat('a').format(sStart),
        title: t.title,
        type: t.taskType == TaskType.deepWork ? 'High Focus' : 'Task',
        tagText: t.isCompleted
            ? (isRecovered ? 'RECOVERED' : 'COMPLETED')
            : isDeviated
                ? 'SKIPPED'
                : locked
                    ? 'FIXED'
                    : (t.taskType == TaskType.deepWork ? 'DEEP WORK' : 'TASK'),
        durationMinutes: t.durationMinutes,
        isCompleted: t.isCompleted,
        isFixed: locked,
        isMissed: isMissed,
        isSkipped: isDeviated,
        isCompletedAfterDeviation: isRecovered,
        isFailed: isFailed,
        isCommitment: t.isCommitment,
        state: derived.name,
        startTime: sStart,
        endTime: sEnd,
      );
    }), ...unscheduledItems];
  }

  void setActiveFocusTask(TaskItem? task) {
    _activeFocusTask = task;
    SmartReminderService.instance.activeFocusTaskId = task?.id;
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

  /// Per-second break progress. Only the break card listens to it: a whole-provider notify every second used
  /// to rebuild all five tabs for the duration of a break.
  final ValueNotifier<int> breakTick = ValueNotifier<int>(0);

  void updateBreakElapsed(int seconds) {
    _breakElapsedSeconds = seconds;
    breakTick.value = seconds;
  }

  void endBreakSession() {
    _isBreakActive = false;
    _breakElapsedSeconds = 0;
    notifyListeners();
  }

  /// Records post-task completion feedback into the Personal Learning Engine,
  /// persists behavioral observation to backend, and triggers real-time schedule & readiness adaptation.
  void recordTaskFeedback({
    required String taskId,
    required int actualMinutes,
    required int feeling,
    String? durationFeedback,
    String? blockerNote,
    int? energyScore,
    int? focusScore,
    int? difficultyScore,
    int? distractionScore,
    DateTime? completedAt,
    bool durationMeasured = false,
  }) {
    final focus = focusScore ?? (feeling >= 4 ? 5 : (feeling == 3 ? 4 : (feeling == 2 ? 3 : 1)));
    final energy = feeling >= 4 ? 'Energized' : (feeling == 3 ? 'Steady' : 'Drained');
    final at = completedAt ?? DateTime.now();

    // A duration is only a duration when something measured it (the Focus timer). Screens that have no timer pass the
    // planned length, which would make every estimate look perfect: store "unknown" (0) instead.
    final measuredMinutes = durationMeasured ? actualMinutes : 0;
    final log = FeedbackLog(
      taskId: taskId,
      completedAt: at,
      actualMinutes: measuredMinutes,
      perceivedFocusScore: focus,
      energyFeeling: energy,
      energyScore: energyScore,
      difficultyScore: difficultyScore ?? 3,
      distractionScore: distractionScore,
      notes: [
        if (durationFeedback != null) 'Duration: $durationFeedback',
        if (blockerNote != null) 'Blocker: $blockerNote',
      ].join('; '),
    );

    final reflected = _tasks.where((t) => t.id == taskId).firstOrNull;
    // What the server learns from: only values the user actually gave (energy/focus are shown to and confirmed by
    // the user in the sheet; untouched difficulty/distraction are null), and a duration only when it was measured.
    final notes = [
      'Feeling: ${TaskReflection.feelingLabel(feeling)}',
      if (durationFeedback != null) 'Duration: $durationFeedback',
      if (blockerNote != null) 'Blocker: $blockerNote',
    ].join('; ');
    final payload = <String, dynamic>{
      if (durationMeasured && actualMinutes > 0) 'actual_minutes': actualMinutes,
      if (focusScore != null) 'focus_score': focusScore.clamp(1, 5),
      if (energyScore != null) 'energy_score': energyScore.clamp(1, 5),
      if (difficultyScore != null) 'difficulty_score': difficultyScore.clamp(1, 5),
      if (distractionScore != null) 'distraction_score': distractionScore.clamp(1, 5),
      'notes': notes,
    };
    _reflections[taskId] = TaskReflection(
      taskId: taskId,
      title: reflected?.title ?? '',
      feeling: feeling,
      energy: energyScore ?? (feeling >= 4 ? 5 : (feeling == 3 ? 4 : (feeling == 2 ? 3 : 2))),
      focus: focus,
      difficulty: difficultyScore ?? 3,
      distraction: distractionScore ?? 1,
      completedAt: at,
      actualMinutes: measuredMinutes,
      plannedMinutes: reflected?.durationMinutes,
      plannedStart: reflected?.scheduledStart,
      durationFeedback: durationFeedback,
      note: blockerNote,
      pendingSync: (_isDemoMode || _currentUser == null) ? null : payload,
    );
    _reflectionsRecordedDuringLoad.add(taskId);
    _reflectionsSaved = _reflectionStore.save(_reflectionScope, _reflections.values);

    _learningEngine.recordSessionFeedback(log);
    _recalculateReadiness();
    _recalculateSchedule();
    notifyListeners();

    _syncReflection(taskId);
  }

  final Set<String> _reflectionSyncInFlight = {};

  /// Delivers one reflection's pending payload. Offline / server errors keep it queued for the next successful
  /// Today refresh; a task the server no longer has (404) or rejects (422) is dropped from the queue.
  Future<void> _syncReflection(String taskId) async {
    final r = _reflections[taskId];
    final body = r?.pendingSync;
    if (r == null || body == null || _isDemoMode || _currentUser == null) return;
    if (_pendingTaskCreations.containsKey(taskId) || !_reflectionSyncInFlight.add(taskId)) return;
    try {
      await apiService.post('/api/v1/tasks/$taskId/feedback', body: body);
      _markReflectionSynced(taskId);
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 422) _markReflectionSynced(taskId);
    } catch (_) {
      // stays queued
    } finally {
      _reflectionSyncInFlight.remove(taskId);
    }
  }

  void _markReflectionSynced(String taskId) {
    final r = _reflections[taskId];
    if (r == null || r.pendingSync == null) return;
    _reflections[taskId] = r.markSynced();
    _reflectionsSaved = _reflectionStore.save(_reflectionScope, _reflections.values);
  }

  /// Retries reflections that could not be delivered earlier (called after a successful Today refresh).
  void _flushPendingReflections() {
    for (final id in _reflections.values.where((r) => r.pendingSync != null).map((r) => r.taskId).toList()) {
      _syncReflection(id);
    }
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
    // If backend data is fresh, synchronize with local task completion status
    if (_isBackendDataFresh && _todaySnapshot != null) {
      final completedIds = _tasks.where((t) => t.isCompleted).map((t) => t.id).toSet();
      final completedTitles = _tasks.where((t) => t.isCompleted).map((t) => t.title.toLowerCase()).toSet();

      _schedule = _todaySnapshot!.upcomingTimeline.where((item) {
        final cleanId = item.id.startsWith('sched-') ? item.id.substring(6) : item.id;
        final isLocallyCompleted = completedIds.contains(item.id) ||
            completedIds.contains(cleanId) ||
            (item.taskId != null && completedIds.contains(item.taskId)) ||
            completedTitles.contains(item.title.toLowerCase());
        return !isLocallyCompleted && !item.isCompleted;
      }).toList();
      return;
    }
    _schedule = _schedulingEngine.generateOptimizedSchedule(
      tasks: _tasks,
      readiness: _readiness,
      profile: PlanningProfile.fromPersonalData(_personalData),
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
      final tz = await TimezoneService.localIanaName();
      final res = await apiService.post('/api/v1/today/override', body: {
        'decision_id': decisionId,
        if (tz != null) 'timezone': tz,
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

  /// Confirm a Build My Day plan.
  ///
  /// Backend mode: ONE atomic, idempotent request (same [planId] => same result, no duplicates).
  /// Local state is changed only AFTER the server confirms, using the rows the server stored.
  /// On failure this throws [PlanConfirmException]: nothing was saved, the preview must stay open,
  /// and a retry with the same [planId] is safe. Demo/offline-guest mode keeps the local-only path.
  Future<void> confirmCandidates(List<TaskItem> candidates, {String? planId}) =>
      _flight.run('confirm-${planId ?? 'plan'}', () => _confirmCandidates(candidates, planId: planId));

  Future<void> _confirmCandidates(List<TaskItem> candidates, {String? planId}) async {
    if (candidates.isEmpty) return;

    if (_isDemoMode || _currentUser == null) {
      final List<TaskItem> created = [];
      for (int i = 0; i < candidates.length; i++) {
        final temp = candidates[i].copyWith(id: 'task-${DateTime.now().millisecondsSinceEpoch}-$i');
        _tasks.insert(0, temp);
        created.add(temp);
      }
      _dayScheduleCache.clear();
      _recalculateReadiness();
      _recalculateSchedule();
      notifyListeners();
      return;
    }

    final tz = await TimezoneService.localIanaName();
    final id = planId ?? 'plan-${DateTime.now().microsecondsSinceEpoch}';
    final items = candidates.map(candidateToBatchItem).toList();

    Map<String, dynamic> res;
    try {
      res = await taskService.batchCreateAndSchedule(
        planId: id,
        items: items,
        timezone: tz,
        currentLocalTime: FlowClock().now,
      );
    } on ApiException catch (e) {
      final detail = e.data is Map<String, dynamic> ? (e.data as Map<String, dynamic>)['detail'] : null;
      if (e.statusCode == 422 && detail is Map<String, dynamic> && detail['errors'] is List) {
        final errors = (detail['errors'] as List)
            .whereType<Map<String, dynamic>>()
            .map(PlanConfirmError.fromJson)
            .toList();
        throw PlanConfirmException(
          errors.isNotEmpty ? errors.first.message : 'Some tasks need attention.',
          errors: errors,
          isValidation: true,
        );
      }
      throw PlanConfirmException(
        e.statusCode == null
            ? "Couldn't reach Flowstate. Your plan is still here \u2014 try again."
            : "Couldn't save your plan right now. Your plan is still here \u2014 try again.",
      );
    } catch (_) {
      throw const PlanConfirmException("Couldn't reach Flowstate. Your plan is still here \u2014 try again.");
    }

    for (final raw in (res['tasks'] as List? ?? []).whereType<Map<String, dynamic>>()) {
      final persisted = TaskItem.fromJson(raw);
      final i = _tasks.indexWhere((t) => t.id == persisted.id);
      if (i != -1) {
        _tasks[i] = persisted;
      } else {
        _tasks.insert(0, persisted);
      }
    }
    _dayScheduleCache.clear();
    _recalculateReadiness();
    _recalculateSchedule();
    notifyListeners();
    await refreshTodayData();
    if (_selectedDateSchedule != null) {
      await loadCalendarDay(_selectedCalendarDate, silent: true);
    }
  }

  /// Wire shape for one item of the confirm request. `scheduled_start` is a full instant (never a
  /// display string + today's date) and `time_locked` is true only for user-fixed times.
  static Map<String, dynamic> candidateToBatchItem(TaskItem t) {
    final start = t.scheduledStart;
    final end = start == null ? null : (t.scheduledEnd ?? start.add(Duration(minutes: t.durationMinutes)));
    return {
      'title': t.title,
      if (t.description != null) 'description': t.description,
      'category': t.category,
      'task_type': t.taskType.value,
      'difficulty': t.difficulty.name,
      'priority': t.effectivePriority.value,
      'estimated_minutes': t.durationMinutes,
      if (t.deadlineAt != null) 'deadline_at': t.deadlineAt!.toUtc().toIso8601String(),
      if (start != null) 'scheduled_start': start.toUtc().toIso8601String(),
      if (end != null) 'scheduled_end': end.toUtc().toIso8601String(),
      'source': t.source.value,
      'time_locked': start != null && t.timeLocked,
      if (t.isCommitment) 'is_commitment': true,
      if (t.plannedDate != null) 'planned_date': DateFormat('yyyy-MM-dd').format(t.plannedDate!),
      'client_ref': t.id,
      if (t.candidateId != null) 'candidate_id': t.candidateId,
      if (t.routineOverrideId != null && t.routineOverrideDate != null) ...{
        'routine_override_id': t.routineOverrideId,
        'routine_override_date': t.routineOverrideDate,
      },
      if (t.dependsOn.isNotEmpty) 'depends_on': t.dependsOn,
      if (t.prioritySource == 'explicit' || t.prioritySource == 'inferred') 'priority_source': t.prioritySource,
      if (t.durationSource != null) 'duration_source': t.durationSource,
      if (t.focusLevel != null) 'focus_level': t.focusLevel,
      if (t.focusSource != null) 'focus_source': t.focusSource,
      if (t.deadlineKind != null) 'deadline_kind': t.deadlineKind,
      if (t.preferredStart != null) 'preferred_start': t.preferredStart!.toUtc().toIso8601String(),
      if (t.preferredWindowStart != null) 'preferred_window_start': t.preferredWindowStart!.toUtc().toIso8601String(),
      if (t.preferredWindowEnd != null) 'preferred_window_end': t.preferredWindowEnd!.toUtc().toIso8601String(),
    };
  }

  static String userOnboardingKey(String userId) => 'flowstate_onboarding_complete_$userId';

  /// Persist onboarding completion status to SharedPreferences and backend.
  Future<void> markOnboardingComplete() async {
    await markOnboardingCompleteLocally();
    await _syncOnboardingCompleteToBackend();
  }

  /// The quick, local half: flips the flag and stores it, so the app can open Today right away.
  Future<void> markOnboardingCompleteLocally() async {
    _onboardingComplete = true;
    _currentNavIndex = 0;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flowstate_onboarding_complete', true);
      if (_currentUser != null) {
        await prefs.setBool(userOnboardingKey(_currentUser!.id), true);
      }
    } catch (_) {}
  }

  Future<void> _syncOnboardingCompleteToBackend() async {
    if (_currentUser == null) return;
    try {
      await apiService.post('/api/v1/auth/onboarding-complete');
    } catch (_) {}
  }

  // ── Questionnaire submit ────────────────────────────────────────────────────
  // The personalization write is CRITICAL (the schedule and readiness are built from it), so the questionnaire
  // awaits it. Everything after it (the "onboarding complete" flag, the first Today load) is not: it runs in the
  // background and can fail safely. A profile write that failed is stored and retried, never dropped.
  String _pendingProfileKey() => 'flowstate_onboarding_profile_pending_${_currentUser?.id ?? 'anonymous'}';

  /// Stores the questionnaire answers on the backend. Returns true when the backend has them; on failure the
  /// payload is kept for a retry (next background attempt or app start) and false is returned.
  Future<bool> submitOnboardingProfile(Map<String, dynamic> payload) {
    return busy.track(() async {
      try {
        await apiService.post('/api/v1/readiness/onboarding', body: payload);
        await _clearPendingOnboardingProfile();
        return true;
      } catch (e) {
        debugPrint('Onboarding profile write failed; will retry: $e');
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_pendingProfileKey(), jsonEncode(payload));
        } catch (_) {}
        return false;
      }
    }, label: 'Personalizing your plan');
  }

  Future<void> _clearPendingOnboardingProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingProfileKey());
    } catch (_) {}
  }

  /// Re-sends a questionnaire write that failed earlier. True when nothing is left pending.
  Future<bool> retryPendingOnboardingProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingProfileKey());
      if (raw == null) return true;
      await apiService.post('/api/v1/readiness/onboarding', body: Map<String, dynamic>.from(jsonDecode(raw) as Map));
      await prefs.remove(_pendingProfileKey());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Non-critical work after the questionnaire, off the critical path: re-send a failed profile write, tell the
  /// backend onboarding is complete, then load Today from the authoritative backend state (retrying once).
  /// Failure is safe: Today shows its normal retry state and the pending profile stays queued.
  Future<void> finishOnboardingInBackground({required bool profileSaved}) async {
    try {
      if (!profileSaved) await retryPendingOnboardingProfile();
      await _syncOnboardingCompleteToBackend();
    } catch (_) {}
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await refreshTodayData(authoritative: true);
        if (_todayNetworkState != TodayNetworkState.networkFailure &&
            _todayNetworkState != TodayNetworkState.serverError) {
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> _loadOnboardingState() async {
    if (_currentUser == null) {
      _onboardingComplete = false;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(userOnboardingKey(_currentUser!.id)) ?? _currentUser!.onboardingCompleted;
      if (done != _onboardingComplete) {
        _onboardingComplete = done;
        notifyListeners();
      }
      // A questionnaire write that failed last time is re-sent now (silently; it stays queued if this fails too).
      if (done && !_isDemoMode) unawaited(retryPendingOnboardingProfile());
    } catch (_) {}
  }

  /// [authoritative] true (after a write such as Replan Apply): never fall back to a cached snapshot, because
  /// that would show the pre-write schedule as if it were current. On failure the stale snapshot is dropped and
  /// Today is rebuilt from the already-adopted local tasks.
  Future<void> refreshTodayData({bool authoritative = false, bool silent = false}) async {
    if (!_isDemoMode && isAuthenticated) _ensureClockSubscription(); // midnight reaches Today even if Calendar was never opened
    // Only the newest Today read is applied, and its schedule only if no later Calendar read wrote one (see
    // _scheduleWriteSeq): an older answer arriving last can never put a stale, differently-shaped list back.
    final requestId = ++_todayRequestId;
    final scheduleTicket = ++_scheduleWriteSeq;
    // A refresh with Today already on screen is silent: the content stays put instead of flashing a skeleton
    // on every resume / edit / pull-to-refresh. Only the very first load shows the loading state.
    if (_todaySnapshot == null && !silent) {
      _isLoading = true;
      _todayNetworkState = TodayNetworkState.loading;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final today = await todayService.getTodayExperience(allowCachedFallback: !authoritative);
      if (requestId != _todayRequestId) return; // a newer Today read owns the state
      if (_isYesterdaysToday(today)) throw const ApiException('Cached Today is from an earlier day');
      _todaySnapshot = today;
      _lastUpdatedAt = today.lastUpdatedAt;
      _lastBackendSyncAt = DateTime.now();
      _readiness = today.readiness;
      if (_claimScheduleWrite(scheduleTicket)) _schedule = today.upcomingTimeline;
      if (today.readiness.focusWindowRange.contains('14:00') ||
          today.readiness.focusWindowRange.toLowerCase().contains('2:00 pm') ||
          today.readiness.focusWindowRange.toLowerCase().contains('afternoon')) {
        _personalData = _personalData.copyWith(focusPeak: 'Afternoon');
      }
      _isOffline = false;
      _isLoading = false;
      final hasTasks = _tasks.isNotEmpty || today.upcomingTimeline.isNotEmpty || today.currentRecommendation != null;
      _todayNetworkState = hasTasks ? TodayNetworkState.tasksSuccess : TodayNetworkState.emptySuccess;
      _errorMessage = null;
      notifyListeners();
      _flushPendingReflections();
    } catch (e) {
      if (requestId != _todayRequestId) return;
      if (authoritative) {
        _todaySnapshot = null;
        _lastBackendSyncAt = null;
        _isOffline = true;
        _isLoading = false;
        _recalculateReadiness();
        _recalculateSchedule();
        _todayNetworkState = _tasks.isNotEmpty ? TodayNetworkState.tasksSuccess : TodayNetworkState.emptySuccess;
        notifyListeners();
        return;
      }
      // Check for cached offline data
      var cached = await todayService.getCachedToday();
      if (requestId != _todayRequestId) return;
      if (cached != null && _isYesterdaysToday(cached)) cached = null; // never show last night's plan as today's
      if (cached != null) {
        _todaySnapshot = cached;
        _lastUpdatedAt = cached.lastUpdatedAt;
        _readiness = cached.readiness;
        if (_claimScheduleWrite(scheduleTicket)) _schedule = cached.upcomingTimeline;
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
  /// Tasks + Today already requested by the constructor for a restored session (consumed once).
  Future<void>? _launchLoad;

  /// [awaitData] false returns as soon as the identity and onboarding state are known (the splash can navigate);
  /// the user's data keeps loading in the background, in parallel.
  Future<void> onUserAuthenticated(AuthUser user, {bool awaitData = true}) async {
    final bool isSwitchingUser = _currentUser == null || _currentUser!.id != user.id || _isDemoMode;
    _currentUser = user;
    _isDemoMode = false;

    if (isSwitchingUser) {
      _claimedDays.clear();
      _pendingCompletions.clear();
      _pendingRemovals.clear();
      _reflections.clear();
      _reflectionsReady = _loadReflections();
      _tasks = [];
      _schedule = [];
      _dayScheduleCache.clear();
      _selectedDateSchedule = null;
      _isLoadingCalendarDay = false;
      _preferredActiveTaskId = null;
      _deferredTaskIds.clear();
      _readiness = ReadinessModel.uncalibrated();
      _todaySnapshot = null;
      _currentNavIndex = 0;
    }

    // Strict user-scoped onboarding verification:
    // If backend profile or user model indicates completion, or user-scoped SharedPreferences says so
    bool isCompleted = user.onboardingCompleted;
    if (!isCompleted) {
      try {
        final prefs = await SharedPreferences.getInstance();
        isCompleted = prefs.getBool(userOnboardingKey(user.id)) ?? false;
      } catch (_) {}
    }

    _onboardingComplete = isCompleted;
    if (isCompleted) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('flowstate_onboarding_complete', true);
        await prefs.setBool(userOnboardingKey(user.id), true);
      } catch (_) {}
    } else {
      // Brand new user: clear legacy global flag so it never leaks from prior sessions
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('flowstate_onboarding_complete');
      } catch (_) {}
    }
    notifyListeners();

    // Query backend single source of truth for onboarding/profile state
    try {
      final profile = await authService.fetchUserProfile();
      if (profile != null) {
        _currentUser = profile;
        if (profile.onboardingCompleted) {
          _onboardingComplete = true;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('flowstate_onboarding_complete', true);
            await prefs.setBool(userOnboardingKey(user.id), true);
          } catch (_) {}
        }
      }
    } catch (_) {}

    notifyListeners();

    // Only load personalized readiness profile and today data if onboarding is completed.
    // Everything below is independent: one parallel round instead of four sequential ones.
    if (_onboardingComplete) {
      final launch = isSwitchingUser ? null : _launchLoad;
      _launchLoad = null;
      final data = Future.wait([
        _loadReadinessProfile(),
        launch ?? Future.wait([loadUserTasks(), refreshTodayData()]),
        loadCalendarDay(_selectedCalendarDate, silent: true),
      ]);
      if (awaitData) await data;
    }
  }

  Future<void> _loadReadinessProfile() async {
    try {
      final res = await apiService.get('/api/v1/readiness/profile');
      if (res is Map<String, dynamic>) {
        final peakStart = res['preferred_peak_start'] as String? ?? '09:30';
        final peakHour = int.tryParse(peakStart.split(':')[0]) ?? 9;
        String peakLabel = 'Morning';
        if (peakHour >= 12 && peakHour < 17) {
          peakLabel = 'Afternoon';
        } else if (peakHour >= 17) {
          peakLabel = 'Evening';
        }
        _personalData = _personalData.copyWith(
          focusPeak: peakLabel,
          wakeTime: res['weekday_wake_time'] as String? ?? _personalData.wakeTime,
          bedtime: res['bedtime'] as String? ?? _personalData.bedtime,
        );
      }
    } catch (_) {}

    notifyListeners();
  }

  /// Fetches real tasks belonging exclusively to the authenticated user from the database.
  Future<void> loadUserTasks() async {
    final requestId = ++_tasksRequestId;
    try {
      final remoteTasks = await taskService.getTasks();
      // A newer read already landed: this one is older than what is on screen.
      if (requestId < _tasksAppliedId) return;
      _tasksAppliedId = requestId;
      _tasks = _withPendingTaskEdits(remoteTasks).where((t) => !_deletedTaskIds.contains(t.id)).toList();
      SmartReminderService.instance.syncTasks(_tasks);
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
    _claimedDays.clear();
    _pendingCompletions.clear();
    _pendingRemovals.clear();
    _currentUser = null;
    _tasks = [];
    _schedule = [];
    _todaySnapshot = null;
    _readiness = ReadinessModel.uncalibrated();
    _onboardingComplete = false;
    _currentNavIndex = 0;
    _preferredActiveTaskId = null;
    _deferredTaskIds.clear();
    _activeFocusTask = null;
    _personalData = MockData.initialPersonalData;
    _todayNetworkState = TodayNetworkState.emptySuccess;
    _errorMessage = null;
    _dayScheduleCache.clear();
    _deletedTaskIds.clear();
    _unsyncedTaskIds.clear();
    _selectedDateSchedule = null;
    _isLoadingCalendarDay = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('flowstate_onboarding_complete');
    } catch (_) {}
  }
}

