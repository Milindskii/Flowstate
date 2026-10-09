import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../components/ai_economy_sheets.dart';
import '../core/config/brain_dump_limit.dart';
import '../components/companion/noya_reaction_controller.dart';
import '../components/noya_companion_view.dart';
import '../components/noya_failure_state.dart';
import '../components/noya_motion_view.dart';
import '../components/noya_shield_gate.dart';
import '../components/shield_popups.dart';
import '../components/noya_notice.dart';
import '../components/routine_confirm_sheet.dart';
import '../components/task_date_time_pickers.dart';
import '../engines/plan_candidates.dart';
import '../engines/scheduling_engine.dart';
import '../models/ai_plan_models.dart';
import '../models/routine.dart';
import '../models/schedule_item.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/flow_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ai_plan_service.dart';
import '../services/plan_confirm_exception.dart';
import '../services/routine_service.dart';
import '../services/task_parse_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import '../utils/commitment_window.dart';
import '../utils/word_count.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'flow_screen.dart';
import 'pro_subscription_screen.dart';
import '../utils/friendly_error.dart';

enum _BrainDumpViewMode { input, preview, edit }

/// Bottom sheet for brain-dump task input, structured plan preview, and task editing.
///
/// Local-First Pipeline:
/// 1. Natural user text entry (no microphone in V1).
/// 2. If clear and unambiguous, immediately parses locally via deterministic rules (0 AI credits, 0 latency).
/// 3. If genuinely ambiguous or complex, attempts Gemini task structuring.
/// 4. If Gemini fails (offline, timeout, API limit), Noya's failure card offers "Try again" or "Plan it myself"
/// (the local parser runs only when the user chooses it, never silently).
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
  String? _aiFailureCode;

  /// Why the last edit was refused (a paste that did not fit); cleared by the next edit.
  String? _limitNote;

  int get _maxWords => _usageStatus?.maxInputWords ?? kDefaultBrainDumpMaxWords;
  int get _wordCount => countWords(_ctrl.text);
  int get _overBy => (_wordCount - _maxWords).clamp(0, 1 << 30);
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
      if (!mounted) return;
      // Every edit: the word counter is live. An edit clears the note about the previous refused paste.
      setState(() {
        _isValid = _ctrl.text.trim().isNotEmpty;
        _limitNote = null;
      });
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
      if (mounted && status != null) {
        setState(() => _usageStatus = status);
        _publishShieldBalance(status);
      }
    } catch (_) {}
  }

  /// Every Shield pill in the app shows the balance the server just reported here (never a local count).
  void _publishShieldBalance(AIUsageStatus? status) {
    if (status == null || !mounted) return;
    try {
      Provider.of<FlowProvider>(context, listen: false).applyServerShieldBalance(status.shieldsAvailable);
    } catch (_) {}
  }

  bool get _hasFlowLayer {
    try {
      Provider.of<FlowProvider>(context, listen: false);
      return true;
    } catch (_) {
      return false;
    }
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
    if (_overBy > 0) return; // the button is disabled too; the counter says how much to trim
    if (_viewMode != _BrainDumpViewMode.input) return; // a late second tap on a plan that already landed: never a second plan
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
      _aiFailureCode = null;
      _isAiPlan = false;
    });

    // Newly created accounts receive at least one complimentary AI task-planning use.
    // If the account has complimentary AI planning available, route to AI planning.
    // Otherwise, call Gemini only if the input requires AI enrichment.
    // AI planning needs an account: a signed-out (guest/demo) user is never sent to AI.
    // If their text needs AI they get a sign-in prompt; otherwise the local planner handles simple lists.
    final signedIn =
        Provider.of<AppStateProvider>(context, listen: false).isAuthenticated;
    final requiresAi = TaskParseService.requiresAiEnrichment(rawText);

    if (requiresAi && !signedIn) {
      _showAiFailure('auth_required');
      return;
    }

    if (!signedIn) {
      _proceedLocalParsing(rawText, 'Planned by Flowstate');
      return;
    }

    // Authenticated user:
    // If complimentary AI is available, Pro is active, shields are available, OR the input is a
    // conversational brain dump requiring AI, route to the backend AI planning pipeline.
    // The deterministic parser is NEVER used as a silent substitute for conversational dumps.
    // The account's allowance is the SERVER's to say: ask again if the first read did not land. An unknown status is
    // never treated as "free plan available": plain input then takes the deterministic planner (no AI, no Shields).
    if (!requiresAi && _usageStatus == null) {
      await _fetchUsageStatus();
      if (!mounted) return;
    }
    final canUseLocalDirectly = !requiresAi &&
        (_usageStatus == null || !_usageStatus!.freeUseAvailable) &&
        !(_usageStatus?.isPro ?? false);

    if (canUseLocalDirectly) {
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

      // The Shield decision is made here, BEFORE any AI request. The price is on screen above the button
      // ("AI planning · 1 Shield"), so pressing it is the consent: no second sheet. The server re-checks everything.
      final usageStatus = await aiService.getUsageStatus();
      if (usageStatus == null) {
        // The server could not be asked: nothing is assumed about the balance and nothing is charged.
        await aiService.reportFailure(requestId, 'client_error', 'usage status unavailable');
        _showAiFailure('offline');
        return;
      }
      if (mounted) setState(() => _usageStatus = usageStatus);
      _publishShieldBalance(usageStatus);
      bool consumeShield = false;

      if (!usageStatus.isPro && !usageStatus.freeUseAvailable) {
        if (!usageStatus.canAffordShieldPlan) {
          _showAiFailure('insufficient_shields');
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

      if (result.tasks.isEmpty && result.routineProposals.isEmpty) {
        _showAiFailure('empty');
        return;
      }
      if (result.schedulingError != null) {
        _showAiFailure('scheduling_failed');
        return;
      }

      _afterPlanCharged(result);

      // Routines found in the dump are applied only after the user confirms each one. Cancel saves nothing.
      final savedRoutines = await _confirmRoutines(result.routineProposals, provider);
      if (!mounted) return;
      if (result.tasks.isEmpty) {
        // Nothing else to plan: the routine was the whole request.
        setState(() => _isLoading = false);
        if (savedRoutines > 0) {
          Navigator.of(context).pop();
        } else {
          _showAiFailure('empty');
        }
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
      if (e.code == 'input_too_long') {
        // The user can fix this right now: say so next to the field instead of showing a failure card.
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = plainOr(e.message, 'That is a bit long for one plan. Please shorten it and try again.');
          _viewMode = _BrainDumpViewMode.input;
        });
        return;
      }
      if (e.code == 'insufficient_shields') await _fetchUsageStatus(); // the gate shows the server's current balance
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

  /// The plan came back: show the balance the server now reports and, when a Shield paid for it, say so once and small.
  void _afterPlanCharged(AIPlanResult result) {
    final usage = result.usage;
    if (usage != null && mounted) setState(() => _usageStatus = usage);
    _publishShieldBalance(usage);
    if (!result.shieldConsumed) return;
    final cost = usage?.shieldCost ?? AIUsageStatus.defaultShieldCost;
    NoyaNoticeCenter.instance.success('$cost Shield${cost == 1 ? '' : 's'} used.', title: 'Plan ready');
    try {
      // the Flow Hub shows the same balance: bring it up to date now instead of at its next open
      unawaited(Provider.of<FlowProvider>(context, listen: false).loadOverview());
    } catch (_) {}
  }

  /// Asks the user about each detected routine. Returns how many were saved.
  Future<int> _confirmRoutines(List<RoutineProposal> proposals, AppStateProvider provider) async {
    var saved = 0;
    for (final proposal in proposals) {
      if (!mounted) return saved;
      final ok = await showRoutineConfirmSheet(context, proposal);
      if (!ok || !mounted) continue;
      try {
        // Stable per proposal: a retry or double tap can never create the routine twice.
        await RoutineService(api: provider.apiService)
            .confirm(proposal, idempotencyKey: 'rp-${proposal.proposalId}', now: DateTime.now());
        saved++;
        NoyaNoticeCenter.instance.show(NoyaNotice(
            NoticeKind.success, '${proposal.title} will be planned around. ${proposal.summary}',
            title: 'Routine saved'));
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Couldn't save ${proposal.title} as a routine. Please try again."),
          ));
        }
      }
    }
    if (saved > 0) await provider.refreshTodayData();
    return saved;
  }

  void _showAiFailure(String code) {
    if (!mounted) return;
    setState(() {
      _aiFailureCode = code;
      _isLoading = false;
      _viewMode = _BrainDumpViewMode.input;
    });
  }

  Future<void> _retryWithAi() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _isLoading) return;
    setState(() {
      _isLoading = true;
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

  /// "Earn a Shield": Noya's Shield popup (rewarded ads, the pack, or the Flow Hub where streaks, quests and the free
  /// refill live). Everything opens ON TOP of this sheet, so the dump is still here afterwards, and the balance is read
  /// again from the server.
  Future<void> _earnShield() async {
    if (!_hasFlowLayer) return _visitThenRecheck(const FlowScreen());
    await ShieldWalletPopup.show(context, onFlowHub: () => _visitThenRecheck(const FlowScreen()));
    if (mounted) await _recheckShields();
  }

  /// "Get Pro": the Pro page only shows the plans; nothing is bought or unlocked from here.
  Future<void> _getPro() => _visitThenRecheck(const ProSubscriptionScreen());

  Future<void> _visitThenRecheck(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    await _recheckShields();
  }

  Future<void> _recheckShields() async {
    await _fetchUsageStatus();
    final status = _usageStatus;
    if (!mounted || status == null) return;
    if (_aiFailureCode == 'insufficient_shields' && (status.isPro || status.canAffordShieldPlan)) {
      setState(() => _aiFailureCode = null); // a Shield arrived (or Pro): Noya is awake again
    }
  }

  void _useBasicPlanner() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
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
        _confirmError = plainOr(e.message, 'This plan needs another look. Please review it and try again.');
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

    // The app-wide Noya feedback channel (deduplicated, compact), not a one-off snack bar.
    NoyaNoticeCenter.instance.success(
        '${finalizedTasks.length} task${finalizedTasks.length == 1 ? '' : 's'} added to your day',
        title: 'Plan created!');
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

  /// What Noya says while napping. Running out of Shields and a technical failure are DIFFERENT stories and never
  /// share words: only the first one may say "out of Shields", only the second says nothing was charged.
  String _napLine(String code, String name) {
    final isPro = _usageStatus?.isPro ?? false;
    final safe = isPro ? 'Your tasks are safe.' : 'Your tasks are safe and your Shield was not charged.';
    switch (code) {
      case 'auth_required':
        return 'Sign in to let $name organize your day with AI.';
      case 'insufficient_shields':
        return "You're out of Shields.";
      case 'quota_exhausted':
        return "AI planning isn't available right now. $name can still build a basic plan.";
      case 'privacy_declined':
        return isPro ? 'Nothing was sent.' : 'Nothing was sent and no Shield was used.';
      case 'empty':
        return isPro
            ? "$name couldn't find any tasks in that."
            : "$name couldn't find any tasks in that. No Shield was used.";
      case 'scheduling_failed':
        return isPro
            ? "$name couldn't fit these into your day."
            : "$name couldn't fit these into your day. No Shield was used.";
      case 'rate_limited':
        return "That's a lot of planning in a short time. Please try again in a little while.";
      case 'pro_cap_day':
        return "You've reached today's AI planning limit. It resets tomorrow.";
      case 'pro_cap_month':
        return "You've reached this month's AI planning limit.";
      case 'offline':
        return isPro
            ? "$name couldn't reach Flowstate. Check your connection."
            : "$name couldn't reach Flowstate. Check your connection. No Shield was used.";
      default:
        return 'AI is temporarily unavailable. $safe';
    }
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
    } else if (_aiFailureCode != null && _viewMode == _BrainDumpViewMode.input) {
      phase = 'asleep';
      // The card under the header says WHY (out of Shields / AI unavailable / ...); the header only says Noya rests.
      noyaTitle = '$name is resting';
      noyaMessage = _aiFailureCode == 'auth_required'
          ? 'Sign in to let $name organize your day with AI.'
          : 'Your text is safe.';
      noyaState = NoyaState.sleepy;
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
      noyaMessage = 'Your text is safe.';
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
          // lands, sleeps peacefully when AI is resting, and recovers calmly when a save fails.
          NoyaMotionView(
            mood: (phase == 'thinking' || phase == 'saving')
                ? NoyaMood.thinking
                : (phase == 'asleep' ? NoyaMood.asleep : NoyaMood.rest),
            pose: noyaState,
            size: noyaSize,
            reactions: _noyaReactions,
            showAmbientGlow: !hasKeyboard && phase != 'asleep',
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

  /// The cost of Noya's AI planning, said plainly BEFORE the button is pressed: one label, one sentence, the balance.
  Widget _buildAiAndShieldsBanner() {
    final status = _usageStatus;
    final isPro = status?.isPro ?? false;
    final freeAvailable = status?.freeUseAvailable ?? false;
    final shields = status?.shieldsAvailable ?? 0;
    final cost = status?.shieldCost ?? AIUsageStatus.defaultShieldCost;
    final shieldWord = cost == 1 ? 'Shield' : 'Shields';

    final String label;
    final String body;
    if (status == null) {
      label = '✨ AI planning';
      body = 'Checking your Shields…';
    } else if (isPro) {
      label = '✨ AI planning · Pro';
      body = 'Noya will turn your brain dump into a plan. No Shields needed with Pro.';
    } else if (freeAvailable) {
      label = '✨ AI planning · included';
      body = 'Noya will turn your brain dump into a plan. This one needs no Shield.';
    } else {
      label = '✨ AI planning · $cost $shieldWord';
      body = 'Use $cost $shieldWord and Noya will turn your brain dump into a plan.';
    }

    return Container(
      key: const Key('ai_cost_banner'),
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
                label,
                key: const Key('ai_cost_label'),
                style: FlowTypography.labelMedium(color: FlowColors.accentCyan)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              if (isPro)
                _bannerBadge(Icons.bolt_rounded, 'Pro', FlowColors.accentMint)
              else if (status != null)
                _bannerBadge(Icons.shield_outlined, '$shields ${shields == 1 ? 'Shield' : 'Shields'} left',
                    FlowColors.accentCyan),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            key: const Key('ai_cost_body'),
            style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))
                .copyWith(fontSize: 12, height: 1.35),
          ),
          if (status != null && !isPro && !freeAvailable && !status.canAffordShieldPlan) ...[
            const SizedBox(height: 6),
            Text(
              "You're out of Shields. You can earn one in Flow Hub, or plan it yourself.",
              key: const Key('ai_cost_empty_hint'),
              style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(fontSize: 10.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bannerBadge(IconData icon, String text, Color color) {
    return Container(
      key: const Key('ai_shield_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: FlowTypography.labelSmall(color: color).copyWith(fontWeight: FontWeight.w600, fontSize: 11)),
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
        if (_aiFailureCode != null) ...[
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
            inputFormatters: [
              WordLimitFormatter(
                maxWords: _maxWords,
                maxChars: _maxWords * kBrainDumpCharsPerWord,
                onRejected: (over) => WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _limitNote = over == 1 && _wordCount < _maxWords
                      ? "That's too much text for one plan."
                      : 'That paste would go $over ${over == 1 ? 'word' : 'words'} over the limit.');
                }),
              ),
            ],
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

        const SizedBox(height: 8),
        _buildWordCounterRow(),
        const SizedBox(height: 16),
      ],
    );
  }

  /// One quiet line under the field: why the last action was refused on the left, `247 / 450 words` on the right.
  Widget _buildWordCounterRow() {
    final over = _overBy;
    final message = over > 0
        ? 'Trim $over ${over == 1 ? 'word' : 'words'} to continue'
        : (_limitNote ?? _errorMessage);
    final nearLimit = _wordCount >= (_maxWords * 0.9).ceil();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: message == null
              ? const SizedBox.shrink()
              : Text(message, style: FlowTypography.bodySmall(color: FlowColors.warning)),
        ),
        const SizedBox(width: 12),
        Text(
          '$_wordCount / $_maxWords words',
          key: const Key('brain_dump_word_counter'),
          style: FlowTypography.bodySmall(
              color: nearLimit ? FlowColors.warning : FlowColors.textMutedOf(context)),
        ),
      ],
    );
  }

  Widget _buildAiFailureCard() {
    final code = _aiFailureCode;
    final isAuth = code == 'auth_required';

    if (code == 'insufficient_shields') {
      final status = _usageStatus;
      if (status != null) {
        // Noya is napping because the Shields ran out: balance, next free Shield, how to earn one, Pro, and the manual
        // planner one tap away. (A provider failure is a different card below and never says this.)
        return NoyaShieldGate(
          status: status,
          onEarn: _earnShield,
          onPro: _getPro,
          onManual: _useBasicPlanner,
        );
      }
    }

    String title = "Noya's taking a little nap";
    String body = _napLine(code ?? '', 'Noya');
    if (isAuth) {
      title = 'Sign in to use AI planning';
      body = 'Sign in to let Noya organize your day with AI. Your text is safe.';
    } else if (code == 'insufficient_shields') {
      // the balance could not be read, so nothing is claimed about it
      body = "Noya couldn't check your Shields just now. You can still plan it yourself.";
    }

    return NoyaFailureState(
      key: const Key('ai_failure_card'),
      compact: true,
      title: title,
      body: body,
      onRetry: isAuth ? _signInForAi : _retryWithAi,
      retryLabel: isAuth ? 'Sign in' : 'Try again',
      retryKey: isAuth
          ? const Key('sign_in_for_ai_button')
          : const Key('retry_ai_button'),
      onAlternative: _useBasicPlanner,
      alternativeLabel: 'Plan it myself',
      alternativeKey: const Key('use_basic_planner_button'),
      isLoading: _isLoading,
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

  /// A 44x44 icon-only control for the plan cards (Edit, Delete): the same size and look, so they line up.
  Widget _cardIconButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: Icon(icon, size: 20, color: FlowColors.textMutedOf(context))),
          ),
        ),
      ),
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
            crossAxisAlignment: CrossAxisAlignment.center,
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
              // Two matching icon buttons, one row, one size: Edit, then the dustbin at the far right.
              _cardIconButton(
                key: Key('preview_edit_${task.id}'),
                icon: Icons.edit_outlined,
                label: 'Edit task',
                onTap: () => _openEditMode(index),
              ),
              _cardIconButton(
                key: Key('preview_remove_${task.id}'),
                icon: Icons.delete_outline_rounded,
                label: 'Delete task',
                onTap: () => _removeCandidate(index),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // TYPE · DURATION
          Text(
            '${task.taskType.label} · ${task.isDurationExplicit ? '${task.durationMinutes} min' : 'Estimated ${task.durationMinutes} min'}',
            style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),

          // THE DECISION: when it is planned (or recommended), as one line, with at most one small badge.
          // "Show the decision, hide the machinery": the reasoning is one tap away (below).
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                isFixedTime ? 'Scheduled: ' : 'Recommended: ',
                style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))
                    .copyWith(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Text(
                task.recommendedSlotDisplay ??
                    (isFixedTime ? timeDisplay! : (task.unscheduledReason != null ? 'Not scheduled' : 'Upcoming')),
                key: Key('preview_time_${task.id}'),
                style: FlowTypography.bodySmall(color: isFixedTime ? FlowColors.accentCyan : FlowColors.accentMint)
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              if (_cardBadge(task, isFixedTime: isFixedTime, isExplicit: isExplicit, isInferred: isInferred, accent: accent)
                  case final badge?)
                badge,
            ],
          ),

          if (_confirmErrors[task.id] != null) ...[
            const SizedBox(height: 6),
            Text(
              _confirmErrors[task.id]!,
              style: FlowTypography.bodySmall(color: FlowColors.warning).copyWith(fontWeight: FontWeight.w600),
            ),
          ],

          // DETAILS (collapsed): the scheduling reason, priority and deadline, only when the user asks.
          if (_hasCardDetails(task, isExplicit: isExplicit, isInferred: isInferred, isFixedTime: isFixedTime))
            _CardDetails(
              key: Key('preview_details_${task.id}'),
              lines: [
                if (task.schedulingExplanation != null && task.schedulingExplanation!.isNotEmpty)
                  task.schedulingExplanation!,
                if (task.priority != null && (isExplicit || isInferred))
                  isExplicit
                      ? '${_capitalize(task.priority!.value)} priority'
                      : 'Suggested priority: ${_capitalize(task.priority!.value)}',
                if (task.focusLevel == 'high') 'Needs high focus',
                if (task.deadline.isNotEmpty && task.deadline != 'Today') 'Due ${task.deadline}',
              ],
            ),
        ],
      ),
    );
  }

  bool _hasCardDetails(TaskItem task, {required bool isExplicit, required bool isInferred, required bool isFixedTime}) =>
      (task.schedulingExplanation?.isNotEmpty ?? false) ||
      (task.priority != null && (isExplicit || isInferred)) ||
      task.focusLevel == 'high' ||
      (task.deadline.isNotEmpty && task.deadline != 'Today');

  /// The one small state badge a card may show: Fixed time beats a suggested priority.
  Widget? _cardBadge(TaskItem task,
      {required bool isFixedTime, required bool isExplicit, required bool isInferred, required Color accent}) {
    String? label;
    Color color = FlowColors.accentCyan;
    if (isFixedTime) {
      label = 'Fixed time';
    } else if (isInferred && task.priority != null) {
      label = 'Suggested ${_capitalize(task.priority!.value)}';
      color = FlowColors.warning;
    }
    if (label == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: FlowRadii.pillRadius),
      child: Text(label,
          style: FlowTypography.labelSmall(color: color).copyWith(fontSize: 10.5, fontWeight: FontWeight.w700)),
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
                TaskType.personal,
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
              onPressed: _isValid && _overBy == 0 && !_isLoading ? _buildPlan : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isValid && _overBy == 0 ? accent : FlowColors.border(context),
                foregroundColor: _isValid && _overBy == 0
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


/// "Why this time": the reasoning behind a plan card, collapsed until asked for.
class _CardDetails extends StatefulWidget {
  final List<String> lines;
  const _CardDetails({super.key, required this.lines});

  @override
  State<_CardDetails> createState() => _CardDetailsState();
}

class _CardDetailsState extends State<_CardDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final muted = FlowColors.textMutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: FlowRadii.pillRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Why this time', style: FlowTypography.labelSmall(color: muted).copyWith(fontWeight: FontWeight.w700)),
                Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: muted),
              ],
            ),
          ),
        ),
        if (_open)
          for (final line in widget.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line,
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(fontSize: 11.5, height: 1.3)),
            ),
      ],
    );
  }
}
