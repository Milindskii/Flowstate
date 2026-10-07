import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../components/ai_economy_sheets.dart';
import '../components/companion/noya_reaction_controller.dart';
import '../components/noya_companion_view.dart';
import '../components/noya_motion_view.dart';
import '../components/task_date_time_pickers.dart';
import '../engines/plan_candidates.dart';
import '../engines/scheduling_engine.dart';
import '../models/ai_plan_models.dart';
import '../models/schedule_item.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/flow_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ai_plan_service.dart';
import '../services/plan_confirm_exception.dart';
import '../services/task_parse_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import '../utils/commitment_window.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import '../services/auth_service.dart';
import 'auth_screen.dart';

enum _BrainDumpViewMode { input, preview, edit }

/// Bottom sheet for brain-dump task input, structured plan preview, and task editing.
///
/// Local-First Pipeline:
/// 1. Natural user text entry (no microphone in V1).
/// 2. If clear and unambiguous, immediately parses locally via deterministic rules (0 AI credits, 0 latency).
/// 3. If genuinely ambiguous or complex, attempts Gemini task structuring.
/// 4. If Gemini fails (offline, timeout, API limit), seamlessly falls back to local parser without blocking.
/// 5. Flowstate deterministic scheduler builds the plan.
/// 6. Shows Plan Preview with Noya companion header and pinned [ Add & Schedule ] action.
/// 7. Editing allows fine-tuning structured candidates without losing data or returning to raw input.
void showBrainDumpSheet(BuildContext context, {String? initialText}) {
  final appState = Provider.of<AppStateProvider>(context, listen: false);

  // If Supabase has an active session, ensure appState is synced and continue
  try {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null && !session.isExpired && !appState.isAuthenticated) {
      appState.onUserAuthenticated(AuthUser.fromSupabase(session.user));
    }
  } catch (_) {}

  // If still not authenticated and not in guest/demo mode, prompt for auth
  if (!appState.isAuthenticated &&
      !appState.isDemoMode &&
      (appState.currentUser == null ||
          !appState.currentUser!.id.startsWith('guest_'))) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthScreen(
          returnToBuildMyDay: true,
          onAuthenticated: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                showBrainDumpSheet(context, initialText: initialText);
              }
            });
          },
        ),
      ),
    );
    return;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _BrainDumpSheet(initialText: initialText),
  );
}

class _BrainDumpSheet extends StatefulWidget {
  final String? initialText;
  const _BrainDumpSheet({this.initialText});
  @override
  State<_BrainDumpSheet> createState() => _BrainDumpSheetState();
}

class _BrainDumpSheetState extends State<_BrainDumpSheet> {
  final _ctrl = TextEditingController();
  bool _isValid = false;
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _fallbackNotice;
  // Confirm state: the plan id is stable across retries (the server is idempotent per plan).
  String? _planId;
  String? _confirmError;
  Map<String, String> _confirmErrors = {};
  String? _planSource;
  AIUsageStatus? _usageStatus;
  // AI planning: one stable request id per brain dump ("Retry with AI" reuses it, so the server
  // charges at most once). A failure is shown with an explicit choice; never a silent local plan.
  String? _requestId;
  String? _aiFailureMessage;
  String? _aiFailureCode;
  bool _isAiPlan = false;

  /// The last candidate removed from the preview and the plan as it was, for Undo (nothing was saved yet).
  TaskItem? _lastRemoved;
  List<TaskItem>? _beforeRemoval;
  List<ScheduleItem>? _scheduleBeforeRemoval;

  _BrainDumpViewMode _viewMode = _BrainDumpViewMode.input;
  List<TaskItem> _planCandidates = [];
  List<ScheduleItem> _scheduleItems = [];

  // Edit State
  int _editingIndex = 0;
  final _editTitleCtrl = TextEditingController();
  TaskType _editType = TaskType.deepWork;
  int _editDuration = 45;
  TimeOfDay?
      _editEndTime; // commitments only: the window's end (may be past midnight)

  /// A commitment ("Going out 6:30–8:30") is a time block, edited as one: no task type, priority or deadline.
  bool get _editingCommitment =>
      _editingIndex >= 0 &&
      _editingIndex < _planCandidates.length &&
      _planCandidates[_editingIndex].isCommitment;
  TaskPriority _editPriority = TaskPriority.medium;
  String _editPrioritySource = 'unspecified';
  DateTime? _editSelectedDate;
  TimeOfDay? _editSelectedTime;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _ctrl.text = widget.initialText!;
      _isValid = true;
    }
    _ctrl.addListener(() {
      final v = _ctrl.text.trim().isNotEmpty;
      if (v != _isValid) setState(() => _isValid = v);
    });
    _fetchUsageStatus();
  }

  Future<void> _fetchUsageStatus() async {
    try {
      final provider = Provider.of<AppStateProvider>(context, listen: false);
      // AI usage belongs to an account: nothing to ask when signed out
      if (!provider.isAuthenticated) return;
      final aiService = AIPlanService(api: provider.apiService);
      final status = await aiService.getUsageStatus();
      if (mounted) {
        setState(() => _usageStatus = status);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _editTitleCtrl.dispose();
    _noyaReactions.dispose();
    super.dispose();
  }

  // Noya's reactions in this sheet: planReady when a plan lands, recover when a save fails.
  // DateTime.now (what FlowClock().now returns) so the sheet never spins up FlowClock's minute
  // timer just to time-stamp a reaction.
  final NoyaReactionController _noyaReactions =
      NoyaReactionController(clock: DateTime.now);
  String? _noyaPhase;

  void _noteNoyaPhase(String phase) {
    if (phase == _noyaPhase) return;
    final previous = _noyaPhase;
    _noyaPhase = phase;
    if (previous == null) return;
    NoyaReaction? reaction;
    // A fast local plan can go straight from input to ready without a thinking frame.
    if (phase == 'ready' && (previous == 'thinking' || previous == 'input')) {
      reaction = NoyaReaction.planReady;
    }
    if (phase == 'recover') reaction = NoyaReaction.recover;
    if (reaction == null) return;
    final r = reaction;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _noyaReactions.react(r);
    });
  }

  Future<void> _buildPlan() async {
    final rawText = _ctrl.text.trim();
    if (rawText.isEmpty || _isLoading) {
      if (rawText.isEmpty) {
        setState(() =>
            _errorMessage = 'Tell me at least one thing you need to get done.');
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _fallbackNotice = null;
      _planId = null;
      _confirmError = null;
      _confirmErrors = {};
      _aiFailureMessage = null;
      _aiFailureCode = null;
      _isAiPlan = false;
    });

    // Newly created accounts receive at least one complimentary AI task-planning use.
    // If the account has complimentary AI planning available, route to AI planning.
    // Otherwise, call Gemini only if the input requires AI enrichment.
    // AI planning needs an account: a signed-out (guest/demo) user is never sent to AI, and never sees a
    // provider error. If their text needs AI they get a sign-in prompt; otherwise the local planner handles it.
    final signedIn =
        Provider.of<AppStateProvider>(context, listen: false).isAuthenticated;
    final hasComplimentaryUse =
        signedIn && (_usageStatus?.freeUseAvailable ?? true);
    final needsAi =
        hasComplimentaryUse || TaskParseService.requiresAiEnrichment(rawText);

    if (needsAi && !signedIn) {
      _showAiFailure('auth_required');
      return;
    }

    if (!needsAi) {
      _proceedLocalParsing(rawText, 'Planned by Flowstate');
      return;
    }

    _requestId = 'bmd-${DateTime.now().microsecondsSinceEpoch}';
    await _runAiPlan(rawText);
  }

  /// The input needs AI. Any failure ends in [_showAiFailure] (the dump stays in the editor and the
  /// user chooses Retry with AI or Use basic planner); it never silently becomes a local plan.
  Future<void> _runAiPlan(String rawText) async {
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final aiService = AIPlanService(api: provider.apiService);
    final requestId =
        _requestId ??= 'bmd-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final acceptedPrivacy =
          await checkAndShowGeminiPrivacyDisclosure(context);
      if (!acceptedPrivacy) {
        await aiService.reportFailure(requestId, 'privacy_declined');
        _showAiFailure('privacy_declined');
        return;
      }

      // The Shield decision is made here, BEFORE any AI request: no free allowance left means either a confirmed
      // Shield payment or no AI call at all. The server re-checks everything; this only avoids a pointless call.
      final usageStatus = await aiService.getUsageStatus();
      bool consumeShield = false;

      if (!usageStatus.isPro && !usageStatus.freeUseAvailable) {
        if (!usageStatus.canAffordShieldPlan) {
          _showAiFailure('insufficient_shields');
          return;
        }
        if (!mounted) return;
        final confirmedShield = await showShieldConfirmationSheet(
          context,
          shieldsAvailable: usageStatus.shieldsAvailable,
          shieldCost: usageStatus.shieldCost,
        );
        if (!confirmedShield) {
          _showAiFailure('shield_declined');
          return;
        }
        consumeShield = true;
      }

      final result = await aiService.generatePlan(
        rawText: rawText,
        consumeShield: consumeShield,
        requestId: requestId,
      );

      if (!mounted) return;

      if (result.tasks.isEmpty) {
        _showAiFailure('empty');
        return;
      }
      if (result.schedulingError != null) {
        _showAiFailure('scheduling_failed');
        return;
      }

      // The backend already scheduled these: render its slots as they are (no client re-scheduling).
      final candidates = result.tasks.map((t) => t.toTaskItem()).toList();
      setState(() {
        _planCandidates = candidates;
        _scheduleItems = const [];
        _planSource = 'Enhanced with AI';
        _isAiPlan = true;
        _lastRemoved = null;
        _beforeRemoval = null;
        _viewMode = _BrainDumpViewMode.preview;
        _isLoading = false;
      });
      FlowHaptics.selection();
    } on AIPlanFailure catch (e) {
      _showAiFailure(e.code);
    } on AIEconomyException catch (e) {
      _showAiFailure(
          e.code == 'RATE_LIMITED' ? 'rate_limited' : 'quota_exhausted');
    } catch (e) {
      // Unexpected client-side failure: record it (best effort) and show the neutral generic message.
      await aiService.reportFailure(
          requestId, 'unknown', e.runtimeType.toString());
      _showAiFailure('unknown');
    }
  }

  // User-facing reasons use neutral Flowstate wording only: never the AI provider, a model, a quota/config detail,
  // an HTTP status, or an internal term. offline/server_error are Flowstate connectivity, not the AI.
  static const _busy = 'Flowstate AI is busy right now. Try again in a moment.';
  static const _unavailable =
      'Flowstate AI is temporarily unavailable. Try again later.';
  static const Map<String, String> _aiFailureReasons = {
    'offline':
        "Flowstate couldn't connect. Check your connection and try again.",
    'server_error':
        'Flowstate is having trouble right now. Try again in a moment.',
    'gemini_error': _unavailable,
    'provider_unavailable': _busy,
    'ai_busy': _busy,
    'provider_quota': 'Flowstate AI is at capacity right now. Try again later.',
    'model_not_found': _unavailable,
    'provider_auth': _unavailable,
    'timeout': 'Flowstate AI took too long to answer.',
    'network': 'Flowstate AI is unreachable right now. Try again shortly.',
    'malformed': "Flowstate AI's answer couldn't be read.",
    'empty': "Flowstate AI didn't find any tasks in your text.",
    'scheduling_failed': "the tasks couldn't be fitted into your schedule.",
    'quota_exhausted': "you've used your free AI plan.",
    'insufficient_shields':
        "you don't have enough Shields for another AI plan. Keep your streak going to earn more.",
    'shield_declined': 'no Shields were used.',
    'privacy_declined': 'you chose not to send this to Flowstate AI.',
    'rate_limited':
        "you've reached the planning limit for now. Try again later.",
    'request_in_progress':
        'Flowstate is still working on your last plan. One moment.',
    'another_request_in_flight':
        'Flowstate is still working on your last plan. One moment.',
    'pro_cap_day': "you've reached today's fair-use limit for AI planning.",
    'pro_cap_month':
        "you've reached this month's fair-use limit for AI planning.",
  };

  void _showAiFailure(String code) {
    if (!mounted) return;
    setState(() {
      _aiFailureCode = code;
      _aiFailureMessage = code == 'auth_required'
          ? 'Sign in to use AI planning'
          : code == 'shield_declined'
              ? 'No Shields were used.'
              : code == 'insufficient_shields'
                  ? "AI planning isn't available: ${_aiFailureReasons[code]}"
                  : 'AI planning failed: ${_aiFailureReasons[code] ?? "something went wrong. Please try again."}';
      _isLoading = false;
      _viewMode = _BrainDumpViewMode.input;
    });
  }

  Future<void> _retryWithAi() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _isLoading) return;
    setState(() {
      _isLoading = true;
      _aiFailureMessage = null;
      _aiFailureCode = null;
    });
    await _runAiPlan(text);
  }

  /// Closes the sheet, signs the user in, then reopens Build My Day with the same text.
  void _signInForAi() {
    final text = _ctrl.text;
    final navigator = Navigator.of(context);
    final host = navigator.context;
    navigator.pop();
    navigator.push(MaterialPageRoute(
      builder: (_) => AuthScreen(
        returnToBuildMyDay: true,
        onAuthenticated: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (host.mounted) showBrainDumpSheet(host, initialText: text);
          });
        },
      ),
    ));
  }

  void _useBasicPlanner() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _aiFailureMessage = null;
      _aiFailureCode = null;
    });
    // Local rules only: no AI call, no usage check, nothing charged.
    _proceedLocalParsing(text, 'Basic plan (not AI)',
        notice: 'Built without AI. No AI credits were used.');
  }

  void _proceedLocalParsing(String text, String source, {String? notice}) {
    final localTasks = TaskParseService.deterministicFallbackParse(text);
    if (localTasks.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Tell me at least one thing you need to get done.';
        });
      }
      return;
    }

    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final enrichedTasks = const SchedulingEngine().enrichTasksWithOptimalSlots(
      localTasks,
      existingTasks: provider.tasks,
    );
    final schedule = const SchedulingEngine().generateOptimizedSchedule(
      tasks: enrichedTasks,
      readiness: provider.readiness,
    );

    if (mounted) {
      setState(() {
        _planCandidates = enrichedTasks;
        _scheduleItems = schedule;
        _lastRemoved = null;
        _beforeRemoval = null;
        _planSource = source;
        _fallbackNotice = notice;
        _viewMode = _BrainDumpViewMode.preview;
        _isLoading = false;
      });
      FlowHaptics.selection();
    }
  }

  void _initDateAndTimeFromTask(TaskItem task) {
    _editEndTime = task.isCommitment && task.scheduledEnd != null
        ? TimeOfDay(
            hour: task.scheduledEnd!.hour, minute: task.scheduledEnd!.minute)
        : null;
    if (task.scheduledStart != null) {
      _editSelectedDate = DateTime(
        task.scheduledStart!.year,
        task.scheduledStart!.month,
        task.scheduledStart!.day,
      );
      _editSelectedTime = TimeOfDay(
        hour: task.scheduledStart!.hour,
        minute: task.scheduledStart!.minute,
      );
    } else {
      if (task.deadlineAt != null) {
        _editSelectedDate = DateTime(
          task.deadlineAt!.year,
          task.deadlineAt!.month,
          task.deadlineAt!.day,
        );
      } else if (task.deadline.isNotEmpty) {
        final lower = task.deadline.toLowerCase();
        final now = DateTime.now();
        if (lower == 'today') {
          _editSelectedDate = DateTime(now.year, now.month, now.day);
        } else if (lower == 'tomorrow') {
          _editSelectedDate = DateTime(now.year, now.month, now.day)
              .add(const Duration(days: 1));
        } else {
          _editSelectedDate = null;
        }
      } else {
        _editSelectedDate = null;
      }

      if (task.scheduledTime != null && task.scheduledTime!.isNotEmpty) {
        _editSelectedTime =
            TaskDateTimePickers.parseTimeString(task.scheduledTime);
      } else {
        _editSelectedTime = null;
      }
    }
  }

  void _openEditMode([int index = 0]) {
    FlowHaptics.selection();
    if (_planCandidates.isEmpty) return;
    final idx = index.clamp(0, _planCandidates.length - 1);
    final task = _planCandidates[idx];

    setState(() {
      _editingIndex = idx;
      _editTitleCtrl.text = task.title;
      _editType = task.taskType;
      _editDuration = task.durationMinutes;
      _editPriority = task.priority ?? TaskPriority.medium;
      _editPrioritySource = task.prioritySource ??
          (task.isPriorityExplicit ? 'explicit' : 'unspecified');
      _initDateAndTimeFromTask(task);
      _viewMode = _BrainDumpViewMode.edit;
    });
  }

  void _selectTaskToEdit(int idx) {
    if (idx < 0 || idx >= _planCandidates.length) return;
    FlowHaptics.selection();
    _syncCurrentEditToCandidate();
    final task = _planCandidates[idx];
    setState(() {
      _editingIndex = idx;
      _editTitleCtrl.text = task.title;
      _editType = task.taskType;
      _editDuration = task.durationMinutes;
      _editPriority = task.priority ?? TaskPriority.medium;
      _editPrioritySource = task.prioritySource ??
          (task.isPriorityExplicit ? 'explicit' : 'unspecified');
      _initDateAndTimeFromTask(task);
    });
  }

  void _syncCurrentEditToCandidate() {
    if (_editingIndex < 0 || _editingIndex >= _planCandidates.length) return;
    final task = _planCandidates[_editingIndex];
    final title = _editTitleCtrl.text.trim().isNotEmpty
        ? _editTitleCtrl.text.trim()
        : task.title;
    final cleanAmbiguities = List<String>.from(task.ambiguities);
    if (_editPrioritySource == 'explicit') {
      cleanAmbiguities.remove('priority_unspecified');
      cleanAmbiguities.remove('inferred_priority');
    }

    DateTime? newScheduledStart;
    DateTime? newScheduledEnd;
    String? newScheduledTime;

    if (_editSelectedTime != null) {
      final baseDate = _editSelectedDate ?? DateTime.now();
      newScheduledStart = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        _editSelectedTime!.hour,
        _editSelectedTime!.minute,
      );
      newScheduledEnd = newScheduledStart.add(Duration(minutes: _editDuration));
      final dt = DateTime(
          2026, 1, 1, _editSelectedTime!.hour, _editSelectedTime!.minute);
      newScheduledTime = DateFormat('h:mm a').format(dt);
    }

    if (task.isCommitment) {
      // Commitment semantics: the window is start..end (the end may be on the next day), there is no deadline,
      // and task type / priority are left exactly as they were.
      final day = _editSelectedDate ??
          newScheduledStart ??
          task.scheduledStart ??
          DateTime.now();
      final start = newScheduledStart ?? task.scheduledStart;
      final startClock = _editSelectedTime ??
          (start == null
              ? null
              : TimeOfDay(hour: start.hour, minute: start.minute));
      final endClock = _editEndTime ??
          (task.scheduledEnd == null
              ? null
              : TimeOfDay(
                  hour: task.scheduledEnd!.hour,
                  minute: task.scheduledEnd!.minute));
      DateTime? winStart = start;
      DateTime? winEnd = task.scheduledEnd;
      if (startClock != null) {
        winStart = DateTime(
            day.year, day.month, day.day, startClock.hour, startClock.minute);
        winEnd = endClock != null
            ? commitmentEnd(day, startClock, endClock)
            : winStart.add(Duration(minutes: task.durationMinutes));
      }
      _planCandidates[_editingIndex] = task.copyWith(
        title: title,
        scheduledStart: winStart,
        scheduledEnd: winEnd,
        scheduledTime:
            winStart == null ? null : DateFormat('h:mm a').format(winStart),
        durationMinutes: (winStart != null && winEnd != null)
            ? winEnd.difference(winStart).inMinutes
            : task.durationMinutes,
        clearDeadlineAt: true,
        timeLocked: true,
        isCommitment: true,
      );
      return;
    }

    String deadlineStr;
    DateTime? deadlineAt;
    if (_editSelectedDate != null) {
      deadlineAt = DateTime(
        _editSelectedDate!.year,
        _editSelectedDate!.month,
        _editSelectedDate!.day,
        23,
        59,
        59,
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final comp = DateTime(_editSelectedDate!.year, _editSelectedDate!.month,
          _editSelectedDate!.day);
      if (comp == today) {
        deadlineStr = 'Today';
      } else if (comp == today.add(const Duration(days: 1))) {
        deadlineStr = 'Tomorrow';
      } else {
        deadlineStr = DateFormat('EEE, MMM d').format(_editSelectedDate!);
      }
    } else {
      deadlineStr = 'Today';
      deadlineAt = null;
    }

    _planCandidates[_editingIndex] = applyPreviewEdit(
        task,
        task.copyWith(
          title: title,
          taskType: _editType,
          durationMinutes: _editDuration,
          priority: _editPriority,
          prioritySource: _editPrioritySource,
          deadline: deadlineStr,
          deadlineAt: deadlineAt,
          scheduledStart: newScheduledStart,
          scheduledEnd: newScheduledEnd,
          scheduledTime: newScheduledTime,
          ambiguities: cleanAmbiguities,
        ));
  }

  void _saveEdit() {
    FlowHaptics.success();
    _syncCurrentEditToCandidate();

    if (_isAiPlan) {
      // AI plans keep the backend's slots; the server re-validates everything on confirm.
      setState(() => _viewMode = _BrainDumpViewMode.preview);
      return;
    }
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final enriched = const SchedulingEngine().enrichTasksWithOptimalSlots(
      _planCandidates,
      existingTasks: provider.tasks,
    );
    final schedule = const SchedulingEngine().generateOptimizedSchedule(
      tasks: enriched,
      readiness: provider.readiness,
    );

    setState(() {
      _planCandidates = enriched;
      _scheduleItems = schedule;
      _viewMode = _BrainDumpViewMode.preview;
    });
  }

  /// Drops one proposed task from the plan. It is never saved; tasks that followed it now follow what it followed.
  void _removeCandidate(int index) {
    if (index < 0 || index >= _planCandidates.length) return;
    FlowHaptics.selection();
    final removed = _planCandidates[index];
    final before = List<TaskItem>.from(_planCandidates);
    final scheduleBefore = List<ScheduleItem>.from(_scheduleItems);
    final remaining = removeCandidateWithDeps(_planCandidates, removed.id);

    var candidates = remaining;
    var schedule = _scheduleItems.where((s) => s.id != 'sched-${removed.id}' && s.taskId != removed.id).toList();
    if (!_isAiPlan && remaining.isNotEmpty) {
      // the local plan is re-scheduled like after an edit (the AI plan is re-planned by the server on confirm)
      final provider = Provider.of<AppStateProvider>(context, listen: false);
      candidates = const SchedulingEngine().enrichTasksWithOptimalSlots(remaining, existingTasks: provider.tasks);
      schedule = const SchedulingEngine().generateOptimizedSchedule(tasks: candidates, readiness: provider.readiness);
    }

    setState(() {
      _planCandidates = candidates;
      _scheduleItems = schedule;
      _lastRemoved = removed;
      _beforeRemoval = before;
      _scheduleBeforeRemoval = scheduleBefore;
      if (candidates.isEmpty) _viewMode = _BrainDumpViewMode.input; // the text is still in the editor
    });
  }

  void _undoRemove() {
    final before = _beforeRemoval;
    if (before == null) return;
    FlowHaptics.lightTap();
    setState(() {
      _planCandidates = before;
      _scheduleItems = _scheduleBeforeRemoval ?? _scheduleItems;
      _lastRemoved = null;
      _beforeRemoval = null;
      _scheduleBeforeRemoval = null;
      _viewMode = _BrainDumpViewMode.preview;
    });
  }

  void _cancelEdit() {
    FlowHaptics.lightTap();
    setState(() {
      _viewMode = _BrainDumpViewMode.preview;
    });
  }

  Future<void> _addAndSchedule() async {
    if (_isSubmitting || _planCandidates.isEmpty) return;
    setState(() {
      _isSubmitting = true;
      _confirmError = null;
      _confirmErrors = {};
    });
    FlowHaptics.success();

    final provider = Provider.of<AppStateProvider>(context, listen: false);

    // A candidate keeps the FULL instant it was given (server slot or the user's edit). We never
    // rebuild a start time from a display string + today's date: that silently moved "tomorrow"
    // tasks to today. Candidates without a start are sent without one and the server places them.
    final finalizedTasks = _planCandidates.map((task) {
      final prio = (task.prioritySource == 'unspecified' ||
              task.ambiguities.contains('priority_unspecified'))
          ? TaskPriority.medium
          : task.priority;
      final cleanAmbiguities = List<String>.from(task.ambiguities)
        ..remove('priority_unspecified')
        ..remove('inferred_priority')
        ..remove('needs_confirmation');
      return task.copyWith(priority: prio, ambiguities: cleanAmbiguities);
    }).toList();

    _planId ??= 'plan-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await provider.confirmCandidates(finalizedTasks, planId: _planId);
    } on PlanConfirmException catch (e) {
      // Nothing was saved. Keep the preview open, show the server's message, and let the user fix it.
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _confirmError = e.message;
        _confirmErrors = {
          for (final er in e.errors)
            if (er.clientRef != null) er.clientRef!: er.message,
        };
      });
      FlowHaptics.selection();
      final firstBad =
          _planCandidates.indexWhere((t) => _confirmErrors.containsKey(t.id));
      if (e.isValidation &&
          firstBad != -1 &&
          e.errors.any((er) => er.needsNewTime)) {
        _openEditMode(firstBad);
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '${finalizedTasks.length} task${finalizedTasks.length == 1 ? '' : 's'} added to your day',
        style:
            FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context)),
      ),
      backgroundColor: FlowColors.surfaceElevated(context),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Widget _buildConfirmErrorBanner() {
    return Container(
      key: const Key('confirm_error_banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlowColors.warning.withValues(alpha: 0.12),
        borderRadius: FlowRadii.buttonRadius,
        border: Border.all(color: FlowColors.warning.withValues(alpha: 0.5)),
      ),
      child: Text(
        _confirmError!,
        style:
            FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context))
                .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FlowColors.border(context),
                    borderRadius: FlowRadii.pillRadius,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Canonical Noya Companion Header (Always visible throughout all states)
              _buildNoyaCompanionHeader(),
              const SizedBox(height: 10),

              // Scrollable Content Area
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: switch (_viewMode) {
                    _BrainDumpViewMode.input => _buildInputContent(),
                    _BrainDumpViewMode.preview =>
                      _buildPlanPreviewContent(accent),
                    _BrainDumpViewMode.edit => _buildEditContent(accent),
                  },
                ),
              ),

              if (_confirmError != null &&
                  _viewMode != _BrainDumpViewMode.input)
                _buildConfirmErrorBanner(),

              // Pinned Bottom CTA Section (Never pushed off screen)
              _buildPinnedBottomCTA(accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoyaCompanionHeader() {
    FlowProvider? flowProvider;
    try {
      flowProvider = Provider.of<FlowProvider>(context, listen: true);
    } catch (_) {}

    final companion = flowProvider?.companion;
    final name = companion?.name ?? 'Noya';

    String noyaTitle;
    String noyaMessage;
    NoyaState noyaState;
    String phase;

    if (_isLoading) {
      phase = 'thinking';
      noyaTitle = '$name is thinking...';
      noyaMessage = 'Structuring tasks & finding where each fits';
      noyaState = NoyaState.thinking;
    } else if (_isSubmitting) {
      phase = 'saving';
      noyaTitle = '$name is saving your plan...';
      noyaMessage = 'Putting each task on your calendar';
      noyaState = NoyaState.thinking;
    } else if (_confirmError != null && _viewMode != _BrainDumpViewMode.input) {
      phase = 'recover';
      noyaTitle = 'Your plan is safe with $name';
      noyaMessage =
          "It didn't save yet. Nothing is lost — try again when you're ready.";
      noyaState = NoyaState.encouraging;
    } else if (_viewMode == _BrainDumpViewMode.preview) {
      phase = 'ready';
      noyaTitle = '$name organized your plan';
      noyaMessage = 'Tap any task card to edit or reschedule';
      noyaState = NoyaState.proud;
    } else if (_viewMode == _BrainDumpViewMode.edit) {
      phase = 'edit';
      noyaTitle = 'Fine-tune with $name';
      noyaMessage = '$name will adapt the schedule to your edits';
      noyaState = NoyaState.focusing;
    } else if (_aiFailureCode != null && _aiFailureCode != 'auth_required') {
      // AI could not run (no Shields, declined, provider trouble): Noya rests, the text stays, nothing is lost.
      phase = 'rest';
      noyaTitle = '$name is resting';
      noyaMessage = _aiFailureCode == 'insufficient_shields' ||
              _aiFailureCode == 'quota_exhausted'
          ? "AI planning isn't available right now. $name can still build a basic plan."
          : "$name couldn't plan this one with AI. Your text is safe.";
      noyaState = NoyaState.sleepy;
    } else {
      phase = 'input';
      noyaTitle = 'Build My Day with $name';
      noyaMessage =
          'Tell Flowstate everything you need to do, and it figures out when each thing fits.';
      noyaState = _isValid ? NoyaState.encouraging : NoyaState.idle;
    }

    _noteNoyaPhase(phase);

    final hasKeyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    final noyaSize = hasKeyboard ? 40.0 : 72.0;
    final verticalPad = hasKeyboard ? 6.0 : 10.0;

    return Container(
      key: const Key('noya_companion_header'),
      margin:
          EdgeInsets.symmetric(horizontal: 24, vertical: hasKeyboard ? 2 : 4),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPad),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Living Noya: thinks while planning or saving (bounded loop), hops when the plan
          // lands, and recovers calmly when a save fails.
          NoyaMotionView(
            mood: (phase == 'thinking' || phase == 'saving')
                ? NoyaMood.thinking
                : NoyaMood.rest,
            pose: noyaState,
            size: noyaSize,
            reactions: _noyaReactions,
            showAmbientGlow: !hasKeyboard,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  noyaTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FlowTypography.labelLarge(
                          color: FlowColors.textPrimaryOf(context))
                      .copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  noyaMessage,
                  maxLines: hasKeyboard ? 2 : null,
                  overflow: hasKeyboard ? TextOverflow.ellipsis : null,
                  style: FlowTypography.bodySmall(
                          color: FlowColors.textSecondaryOf(context))
                      .copyWith(
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiAndShieldsBanner() {
    final status = _usageStatus;
    final isPro = status?.isPro ?? false;
    final freeAvailable = status?.freeUseAvailable ?? true;
    final shields = status?.shieldsAvailable ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FlowColors.surfaceContainer(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                '✨ AI planning',
                style: FlowTypography.labelMedium(color: FlowColors.accentCyan)
                    .copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (isPro)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: FlowColors.accentMint.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_rounded,
                          size: 13, color: FlowColors.accentMint),
                      const SizedBox(width: 4),
                      Text(
                        'Pro Unlimited',
                        style: FlowTypography.labelSmall(
                                color: FlowColors.accentMint)
                            .copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    // Shields badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: FlowColors.accentCyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                FlowColors.accentCyan.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_outlined,
                              size: 13, color: FlowColors.accentCyan),
                          const SizedBox(width: 4),
                          Text(
                            status != null
                                ? '$shields Shield${shields == 1 ? '' : 's'}'
                                : '... Shields',
                            style: FlowTypography.labelSmall(
                                    color: FlowColors.accentCyan)
                                .copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Free planning badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (freeAvailable
                                ? FlowColors.accentMint
                                : FlowColors.textMutedOf(context))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status != null
                            ? (freeAvailable
                                ? '1 free plan available'
                                : 'Free plan used')
                            : 'Checking...',
                        style: FlowTypography.labelSmall(
                          color: freeAvailable
                              ? FlowColors.accentMint
                              : FlowColors.textMutedOf(context),
                        ).copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Flowstate understands messy brain dumps and turns them into separate tasks, then finds where they fit in your day. You remain in complete control to edit or reschedule.',
            style: FlowTypography.bodySmall(
                    color: FlowColors.textSecondaryOf(context))
                .copyWith(
              fontSize: 11,
              height: 1.35,
            ),
          ),
          if (status != null && !isPro && !freeAvailable) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 12, color: FlowColors.accentCyan),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    status.canAffordShieldPlan
                        ? 'Free plan used. Next AI plan uses ${status.shieldCost} Shields, and Noya asks first.'
                        : 'Free plan used. An AI plan needs ${status.shieldCost} Shields; you have $shields.',
                    style: FlowTypography.labelSmall(
                            color: FlowColors.textMutedOf(context))
                        .copyWith(
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAiAndShieldsBanner(),
        Text(
          'What else is on your plate?',
          style: FlowTypography.titleMedium()
              .copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Just write it out.',
          style:
              FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
        ),
        const SizedBox(height: 16),
        // Shown above the editor so the choice is visible without scrolling past the dump.
        if (_aiFailureMessage != null) ...[
          _buildAiFailureCard(),
          const SizedBox(height: 12),
        ],

        // Text input container
        Container(
          decoration: BoxDecoration(
            color: FlowColors.surfaceContainer(context),
            borderRadius: FlowRadii.cardRadius,
            border: Border.all(
              color: _errorMessage != null
                  ? FlowColors.warning
                  : FlowColors.border(context),
            ),
          ),
          child: TextField(
            key: const Key('brain_dump_text_field'),
            controller: _ctrl,
            autofocus: true,
            maxLines: 5,
            minLines: 3,
            style: FlowTypography.bodyMedium(),
            decoration: InputDecoration(
              hintText:
                  'e.g. Finish Python lab tomorrow, study arrays, call the dentist at 4, gym at 6...',
              hintStyle: FlowTypography.bodySmall(
                  color: FlowColors.textMutedOf(context)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: FlowTypography.bodySmall(color: FlowColors.warning),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAiFailureCard() {
    return Container(
      key: const Key('ai_failure_card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlowColors.warning.withValues(alpha: 0.10),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _aiFailureMessage!,
            style: FlowTypography.bodySmall(
                    color: FlowColors.textPrimaryOf(context))
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _aiFailureCode == 'auth_required'
                ? 'Your text is still here. Nothing was sent.'
                : 'Your text is still here. Nothing was charged.',
            style:
                FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))
                    .copyWith(fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_aiFailureCode == 'auth_required')
                FilledButton(
                  key: const Key('sign_in_for_ai_button'),
                  onPressed: _isLoading ? null : _signInForAi,
                  child: const Text('Sign in'),
                )
              else if (_aiFailureCode != 'insufficient_shields')
                OutlinedButton(
                  key: const Key('retry_ai_button'),
                  onPressed: _isLoading ? null : _retryWithAi,
                  child: const Text('Retry with AI'),
                ),
              TextButton(
                key: const Key('use_basic_planner_button'),
                onPressed: _isLoading ? null : _useBasicPlanner,
                child: const Text('Use basic planner'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanPreviewContent(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'YOUR PLAN',
                style: FlowTypography.titleMedium().copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_planSource == 'Enhanced with AI'
                          ? accent
                          : FlowColors.accentMint)
                      .withValues(alpha: 0.14),
                  borderRadius: FlowRadii.pillRadius,
                ),
                child: Text(
                  _planSource ?? 'Planned by Flowstate',
                  overflow: TextOverflow.ellipsis,
                  style: FlowTypography.labelSmall(
                    color: _planSource == 'Enhanced with AI'
                        ? accent
                        : FlowColors.accentMint,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Here is your optimized execution schedule.',
          style:
              FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
        ),

        if (_fallbackNotice != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FlowColors.surfaceElevated(context),
              borderRadius: FlowRadii.cardRadius,
              border: Border.all(color: FlowColors.border(context)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: FlowColors.accentMint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _fallbackNotice!,
                    style: FlowTypography.bodySmall(
                            color: FlowColors.textSecondaryOf(context))
                        .copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        if (_lastRemoved != null)
          Padding(
            key: const Key('preview_removed_banner'),
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Removed \u201c${_lastRemoved!.title}\u201d from this plan.',
                    style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                  ),
                ),
                TextButton(
                  key: const Key('preview_undo_remove'),
                  onPressed: _undoRemove,
                  child: const Text('Undo'),
                ),
              ],
            ),
          ),

        // Scheduled task cards
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _planCandidates.length,
          itemBuilder: (ctx, i) {
            final task = _planCandidates[i];
            ScheduleItem? sched;
            try {
              sched = _scheduleItems.firstWhere(
                  (s) => s.id == 'sched-${task.id}' || s.title == task.title);
            } catch (_) {}
            return _buildTaskPreviewCard(task, sched, accent, i);
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildTaskPreviewCard(
      TaskItem task, ScheduleItem? sched, Color accent, int index) {
    String? timeDisplay = task.scheduledTime;
    if (timeDisplay == null && sched != null) {
      final s = sched.time;
      final p = sched.period;
      timeDisplay = '$s $p';
    }

    // Fixed = the user (or the server, from the user's own words) fixed this time. A recommended slot is not fixed.
    final isFixedTime = task.scheduledStart != null && task.timeLocked;
    final isExplicit = task.isPriorityExplicit;
    final isInferred = task.isPriorityInferred;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(
          color: isInferred
              ? FlowColors.warning.withValues(alpha: 0.35)
              : FlowColors.border(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TASK (Title)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: FlowTypography.titleSmall().copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: FlowColors.textPrimaryOf(context),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _openEditMode(index),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined,
                          size: 14, color: FlowColors.textMutedOf(context)),
                      const SizedBox(width: 4),
                      Text(
                        'Edit',
                        style: FlowTypography.labelSmall(
                                color: FlowColors.textMutedOf(context))
                            .copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Remove from this proposed plan (not saved yet, so no confirmation is needed; Undo is offered)
              Semantics(
                button: true,
                label: 'Remove ${task.title} from the plan',
                child: InkWell(
                  key: Key('preview_remove_${task.id}'),
                  borderRadius: FlowRadii.pillRadius,
                  onTap: () => _removeCandidate(index),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close_rounded, size: 16, color: FlowColors.textMutedOf(context)),
                          const SizedBox(width: 2),
                          Text(
                            'Remove',
                            style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context))
                                .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // TYPE · DURATION
          Text(
            '${task.taskType.label} · ${task.isDurationExplicit ? '${task.durationMinutes} min' : 'Estimated ${task.durationMinutes} min'}',
            style: FlowTypography.bodySmall(
                    color: FlowColors.textSecondaryOf(context))
                .copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),

          // PRIORITY (shown only when there is a real value; a missing one is never rendered as text)
          if (isExplicit && task.priority != null)
            Text(
              '${_capitalize(task.priority!.value)} priority',
              style: FlowTypography.bodySmall(
                  color: FlowColors.textSecondaryOf(context)),
            )
          else if (isInferred && task.priority != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: FlowColors.warning.withValues(alpha: 0.12),
                borderRadius: FlowRadii.pillRadius,
              ),
              child: Text(
                'Suggested: ${_capitalize(task.priority!.value)}',
                style: FlowTypography.bodySmall(color: FlowColors.warning)
                    .copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
          if (task.focusLevel == 'high') ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: FlowRadii.pillRadius,
              ),
              child: Text(
                'High focus',
                style: FlowTypography.bodySmall(color: accent)
                    .copyWith(fontWeight: FontWeight.w600, fontSize: 11),
              ),
            ),
          ],
          const SizedBox(height: 4),

          // TIME / DEADLINE (Only explicit user constraint)
          if (isFixedTime)
            Text(
              '$timeDisplay · Fixed time',
              style: FlowTypography.bodySmall(
                color: FlowColors.accentCyan,
              ).copyWith(
                fontWeight: FontWeight.w600,
              ),
            )
          else if (task.deadline.isNotEmpty && task.deadline != 'Today')
            Text(
              'Due ${task.deadline}',
              style: FlowTypography.bodySmall(
                  color: FlowColors.textSecondaryOf(context)),
            ),

          if (_confirmErrors[task.id] != null) ...[
            const SizedBox(height: 6),
            Text(
              _confirmErrors[task.id]!,
              style: FlowTypography.bodySmall(color: FlowColors.warning)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ],

          // RECOMMENDED TIME
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                isFixedTime ? 'Scheduled: ' : 'Recommended: ',
                style: FlowTypography.bodySmall(
                        color: FlowColors.textMutedOf(context))
                    .copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              Text(
                task.recommendedSlotDisplay ??
                    (isFixedTime
                        ? timeDisplay!
                        : (task.unscheduledReason != null
                            ? 'Not scheduled'
                            : 'Upcoming')),
                style: FlowTypography.bodySmall(
                  color: isFixedTime
                      ? FlowColors.accentCyan
                      : FlowColors.accentMint,
                ).copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              if (isFixedTime)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FlowColors.accentCyan.withValues(alpha: 0.15),
                    borderRadius: FlowRadii.pillRadius,
                  ),
                  child: Text(
                    'Fixed',
                    style:
                        FlowTypography.labelSmall(color: FlowColors.accentCyan)
                            .copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),

          // WHY / EXPLANATION
          if (task.schedulingExplanation != null &&
              task.schedulingExplanation!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: FlowColors.surfaceContainer(context),
                borderRadius: FlowRadii.cardRadius,
                border: Border.all(
                    color: FlowColors.border(context).withValues(alpha: 0.6)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Why: ',
                    style: FlowTypography.labelSmall(
                            color: FlowColors.textMutedOf(context))
                        .copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      task.schedulingExplanation!,
                      style: FlowTypography.bodySmall(
                              color: FlowColors.textSecondaryOf(context))
                          .copyWith(
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditContent(Color accent) {
    if (_planCandidates.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      key: const Key('structured_task_editor'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'EDIT GENERATED TASK',
                style: FlowTypography.titleSmall().copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '${_editingIndex + 1} of ${_planCandidates.length}',
                style: FlowTypography.labelSmall(
                    color: FlowColors.textMutedOf(context)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Task Selector tabs if multiple tasks
          if (_planCandidates.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_planCandidates.length, (i) {
                  final isSelected = i == _editingIndex;
                  return GestureDetector(
                    onTap: () => _selectTaskToEdit(i),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent.withValues(alpha: 0.15)
                            : FlowColors.surfaceElevated(context),
                        borderRadius: FlowRadii.pillRadius,
                        border: Border.all(
                          color:
                              isSelected ? accent : FlowColors.border(context),
                        ),
                      ),
                      child: Text(
                        _planCandidates[i].title,
                        style: FlowTypography.labelSmall(
                          color: isSelected
                              ? accent
                              : FlowColors.textSecondaryOf(context),
                        ).copyWith(
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Title
          Text('TASK TITLE',
              style: FlowTypography.labelSmall(
                      color: FlowColors.textMutedOf(context))
                  .copyWith(letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: FlowColors.surfaceElevated(context),
              borderRadius: FlowRadii.cardRadius,
              border: Border.all(color: FlowColors.border(context)),
            ),
            child: TextField(
              key: const Key('edit_task_title_field'),
              controller: _editTitleCtrl,
              style: FlowTypography.bodyMedium(),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),

          if (_editingCommitment) ...[
            Row(
              children: [
                Icon(Icons.lock_rounded,
                    size: 16, color: FlowColors.textSecondaryOf(context)),
                const SizedBox(width: 6),
                Text(
                  'Fixed commitment',
                  key: const Key('edit_commitment_badge'),
                  style: FlowTypography.labelMedium(
                          color: FlowColors.textSecondaryOf(context))
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Protected time — Flowstate plans your work around it.',
                style: FlowTypography.bodySmall(
                    color: FlowColors.textMutedOf(context))),
            const SizedBox(height: 14),
          ],

          if (!_editingCommitment) ...[
            // Type
            Text('TASK TYPE',
                style: FlowTypography.labelSmall(
                        color: FlowColors.textMutedOf(context))
                    .copyWith(letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                TaskType.deepWork,
                TaskType.study,
                TaskType.physical,
                TaskType.admin,
                TaskType.meeting,
                TaskType.creative,
              ].map((t) {
                final isSel = _editType == t;
                return GestureDetector(
                  key: Key('type_chip_${t.value}'),
                  onTap: () {
                    FlowHaptics.selection();
                    setState(() => _editType = t);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSel
                          ? accent.withValues(alpha: 0.15)
                          : FlowColors.surfaceElevated(context),
                      borderRadius: FlowRadii.pillRadius,
                      border: Border.all(
                          color: isSel ? accent : FlowColors.border(context)),
                    ),
                    child: Text(
                      t.label,
                      style: FlowTypography.labelSmall(
                        color: isSel
                            ? accent
                            : FlowColors.textSecondaryOf(context),
                      ).copyWith(
                          fontWeight:
                              isSel ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Estimated Duration
            Text('ESTIMATED DURATION',
                style: FlowTypography.labelSmall(
                        color: FlowColors.textMutedOf(context))
                    .copyWith(letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [15, 30, 45, 60, 90, 120].map((m) {
                final isSel = _editDuration == m;
                return GestureDetector(
                  key: Key('duration_chip_$m'),
                  onTap: () {
                    FlowHaptics.selection();
                    setState(() => _editDuration = m);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSel
                          ? accent.withValues(alpha: 0.15)
                          : FlowColors.surfaceElevated(context),
                      borderRadius: FlowRadii.pillRadius,
                      border: Border.all(
                          color: isSel ? accent : FlowColors.border(context)),
                    ),
                    child: Text(
                      '$m min',
                      style: FlowTypography.labelSmall(
                        color: isSel
                            ? accent
                            : FlowColors.textSecondaryOf(context),
                      ).copyWith(
                          fontWeight:
                              isSel ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Priority
            Text('PRIORITY',
                style: FlowTypography.labelSmall(
                        color: FlowColors.textMutedOf(context))
                    .copyWith(letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                (
                  label: 'Unspecified',
                  prio: TaskPriority.medium,
                  source: 'unspecified'
                ),
                (label: 'Low', prio: TaskPriority.low, source: 'explicit'),
                (
                  label: 'Medium',
                  prio: TaskPriority.medium,
                  source: 'explicit'
                ),
                (label: 'High', prio: TaskPriority.high, source: 'explicit'),
                (
                  label: 'Urgent',
                  prio: TaskPriority.urgent,
                  source: 'explicit'
                ),
              ].map((item) {
                final isSel = item.source == 'unspecified'
                    ? _editPrioritySource == 'unspecified'
                    : (_editPriority == item.prio &&
                        _editPrioritySource == 'explicit');
                return GestureDetector(
                  key: Key('priority_chip_${item.label.toLowerCase()}'),
                  onTap: () {
                    FlowHaptics.selection();
                    setState(() {
                      _editPriority = item.prio;
                      _editPrioritySource = item.source;
                    });
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSel
                          ? accent.withValues(alpha: 0.15)
                          : FlowColors.surfaceElevated(context),
                      borderRadius: FlowRadii.pillRadius,
                      border: Border.all(
                          color: isSel ? accent : FlowColors.border(context)),
                    ),
                    child: Text(
                      item.label,
                      style: FlowTypography.labelSmall(
                        color: isSel
                            ? accent
                            : FlowColors.textSecondaryOf(context),
                      ).copyWith(
                          fontWeight:
                              isSel ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
          ],

          // Date & Time Controls (Real Calendar & Clock Pickers)
          TaskDateTimePickers(
            selectedDate: _editSelectedDate,
            selectedTime: _editSelectedTime,
            dateLabel: _editingCommitment ? 'DATE' : 'DEADLINE / DATE',
            timeLabel: _editingCommitment ? 'STARTS' : 'FIXED TIME',
            accentColor: accent,
            dateButtonKey: const Key('edit_plan_task_date_button'),
            timeButtonKey: const Key('edit_plan_task_time_button'),
            clearDateKey: const Key('edit_plan_task_clear_date'),
            clearTimeKey: const Key('edit_plan_task_clear_time'),
            onDateChanged: (d) => setState(() => _editSelectedDate = d),
            onTimeChanged: (t) => setState(() => _editSelectedTime = t),
          ),
          if (_editingCommitment) ...[
            const SizedBox(height: 12),
            Text('ENDS',
                style: FlowTypography.labelSmall(
                        color: FlowColors.textMutedOf(context))
                    .copyWith(letterSpacing: 0.5)),
            const SizedBox(height: 6),
            InkWell(
              key: const Key('edit_commitment_end_time_button'),
              borderRadius: BorderRadius.circular(FlowRadii.inputField),
              onTap: () async {
                final t = await TaskDateTimePickers.pickTime(context,
                    initialTime: _editEndTime ?? _editSelectedTime);
                if (t != null) setState(() => _editEndTime = t);
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: FlowColors.surfaceElevated(context),
                  borderRadius: BorderRadius.circular(FlowRadii.inputField),
                  border: Border.all(color: FlowColors.border(context)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 18, color: FlowColors.textMutedOf(context)),
                    const SizedBox(width: 8),
                    Text(
                      TaskDateTimePickers.formatTimeDisplay(_editEndTime),
                      style: FlowTypography.bodyMedium(
                          color: FlowColors.textPrimaryOf(context)),
                    ),
                  ],
                ),
              ),
            ),
            if (_editSelectedTime != null &&
                _editEndTime != null &&
                !(_editEndTime!.hour * 60 + _editEndTime!.minute >
                    _editSelectedTime!.hour * 60 +
                        _editSelectedTime!.minute)) ...[
              const SizedBox(height: 6),
              Text('Ends the next day',
                  key: const Key('edit_commitment_next_day_hint'),
                  style: FlowTypography.bodySmall(
                      color: FlowColors.textMutedOf(context))),
            ],
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPinnedBottomCTA(Color accent) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth < 360 ? 16.0 : 24.0;

    return Container(
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        border: Border(
            top: BorderSide(color: FlowColors.border(context), width: 0.8)),
      ),
      padding: EdgeInsets.fromLTRB(horizontalPad, 14, horizontalPad, 16),
      child: switch (_viewMode) {
        _BrainDumpViewMode.input => SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              key: const Key('brain_dump_build_button'),
              onPressed: _isValid && !_isLoading ? _buildPlan : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isValid ? accent : FlowColors.border(context),
                foregroundColor: _isValid
                    ? FlowColors.textInverse
                    : FlowColors.textMutedOf(context),
                elevation: 0,
                shape: const RoundedRectangleBorder(
                    borderRadius: FlowRadii.buttonRadius),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: FlowColors.textInverse,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Build my day',
                      style: FlowTypography.labelLarge(
                        color: _isValid
                            ? FlowColors.textInverse
                            : FlowColors.textMutedOf(context),
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        _BrainDumpViewMode.preview => Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('edit_button'),
                  onPressed: () => _openEditMode(0),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FlowColors.textPrimaryOf(context),
                    side: BorderSide(color: FlowColors.border(context)),
                    shape: const RoundedRectangleBorder(
                        borderRadius: FlowRadii.buttonRadius),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Edit',
                    style: FlowTypography.labelLarge(
                            color: FlowColors.textPrimaryOf(context))
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  key: const Key('add_and_schedule_button'),
                  onPressed: _isSubmitting ? null : _addAndSchedule,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: FlowColors.textInverse,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(
                        borderRadius: FlowRadii.buttonRadius),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: FlowColors.textInverse,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Add & Schedule',
                          style: FlowTypography.labelLarge(
                                  color: FlowColors.textInverse)
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        _BrainDumpViewMode.edit => Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('edit_cancel_button'),
                  onPressed: _cancelEdit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FlowColors.textPrimaryOf(context),
                    side: BorderSide(color: FlowColors.border(context)),
                    shape: const RoundedRectangleBorder(
                        borderRadius: FlowRadii.buttonRadius),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Cancel',
                    style: FlowTypography.labelLarge(
                            color: FlowColors.textPrimaryOf(context))
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  key: const Key('save_changes_button'),
                  onPressed: _saveEdit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: FlowColors.textInverse,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(
                        borderRadius: FlowRadii.buttonRadius),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Save changes',
                    style:
                        FlowTypography.labelLarge(color: FlowColors.textInverse)
                            .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
      },
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
