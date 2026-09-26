import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../components/ai_economy_sheets.dart';
import '../components/companion/companion_graphic.dart';
import '../components/companion/flow_companion_animation_controller.dart';
import '../engines/scheduling_engine.dart';
import '../models/schedule_item.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/flow_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ai_plan_service.dart';
import '../services/task_parse_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

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
void showBrainDumpSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.darkSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _BrainDumpSheet(),
  );
}

class _BrainDumpSheet extends StatefulWidget {
  const _BrainDumpSheet();
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
  String? _planSource;

  _BrainDumpViewMode _viewMode = _BrainDumpViewMode.input;
  List<TaskItem> _planCandidates = [];
  List<ScheduleItem> _scheduleItems = [];

  // Edit State
  int _editingIndex = 0;
  final _editTitleCtrl = TextEditingController();
  TaskType _editType = TaskType.deepWork;
  int _editDuration = 45;
  TaskPriority _editPriority = TaskPriority.medium;
  String _editPrioritySource = 'unspecified';
  String _editDeadline = 'Today';
  String? _editFixedTime;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final v = _ctrl.text.trim().isNotEmpty;
      if (v != _isValid) setState(() => _isValid = v);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _editTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _buildPlan() async {
    final rawText = _ctrl.text.trim();
    if (rawText.isEmpty || _isLoading) {
      if (rawText.isEmpty) {
        setState(() => _errorMessage = 'Tell me at least one thing you need to get done.');
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _fallbackNotice = null;
    });

    final provider = Provider.of<AppStateProvider>(context, listen: false);

    // Rule: Gemini is an enhancement layer, NOT a dependency.
    // If input is clear and deterministic rules handle it safely, DO NOT call Gemini.
    final needsAi = TaskParseService.requiresAiEnrichment(rawText);

    if (!needsAi) {
      _proceedLocalParsing(rawText, 'Planned by Flowstate');
      return;
    }

    // Input is genuinely ambiguous or complex -> attempt Gemini enhancement
    try {
      final acceptedPrivacy = await checkAndShowGeminiPrivacyDisclosure(context);
      if (!acceptedPrivacy) {
        // User declined privacy disclosure -> fall back to local parser seamlessly
        _proceedLocalParsing(rawText, 'Planned by Flowstate');
        return;
      }

      final aiService = AIPlanService(api: provider.apiService);
      final usageStatus = await aiService.getUsageStatus();
      bool consumeShield = false;

      if (!usageStatus.isPro && !usageStatus.freeUseAvailable) {
        if (usageStatus.shieldsAvailable > 0) {
          if (!mounted) return;
          final confirmedShield = await showShieldConfirmationSheet(
            context,
            shieldsAvailable: usageStatus.shieldsAvailable,
            freeRemaining: 0,
          );
          if (!confirmedShield) {
            // User declined shield -> fall back to local parser without charge
            _proceedLocalParsing(rawText, 'Planned by Flowstate');
            return;
          }
          consumeShield = true;
        } else {
          // No shields / quota exhausted -> fall back to local parser
          _proceedLocalParsing(rawText, 'Planned by Flowstate');
          return;
        }
      }

      final result = await aiService.generatePlan(
        rawText: rawText,
        consumeShield: consumeShield,
      );

      if (!mounted) return;

      if (result.tasks.isEmpty) {
        _proceedLocalParsing(rawText, 'Planned by Flowstate');
        return;
      }

      final candidates = result.tasks.map((t) => t.toTaskItem()).toList();
      final schedule = const SchedulingEngine().generateOptimizedSchedule(
        tasks: candidates,
        readiness: provider.readiness,
      );

      setState(() {
        _planCandidates = candidates;
        _scheduleItems = schedule;
        _planSource = 'Enhanced with AI';
        _viewMode = _BrainDumpViewMode.preview;
        _isLoading = false;
      });
      FlowHaptics.selection();
    } catch (_) {
      // Offline / network failure / server unavailable -> SEAMLESS FALLBACK
      // Do NOT show blocking error. Never lose user text.
      if (!mounted) return;
      _proceedLocalParsing(
        rawText,
        'Planned by Flowstate',
        notice: "AI planning isn't available right now, so Flowstate used its built-in planner.",
      );
    }
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
    final schedule = const SchedulingEngine().generateOptimizedSchedule(
      tasks: localTasks,
      readiness: provider.readiness,
    );

    if (mounted) {
      setState(() {
        _planCandidates = localTasks;
        _scheduleItems = schedule;
        _planSource = source;
        _fallbackNotice = notice;
        _viewMode = _BrainDumpViewMode.preview;
        _isLoading = false;
      });
      FlowHaptics.selection();
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
      _editPriority = task.priority;
      _editPrioritySource = task.prioritySource ?? (task.isPriorityExplicit ? 'explicit' : 'unspecified');
      _editDeadline = task.deadline;
      _editFixedTime = task.scheduledTime;
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
      _editPriority = task.priority;
      _editPrioritySource = task.prioritySource ?? (task.isPriorityExplicit ? 'explicit' : 'unspecified');
      _editDeadline = task.deadline;
      _editFixedTime = task.scheduledTime;
    });
  }

  void _syncCurrentEditToCandidate() {
    if (_editingIndex < 0 || _editingIndex >= _planCandidates.length) return;
    final task = _planCandidates[_editingIndex];
    final title = _editTitleCtrl.text.trim().isNotEmpty ? _editTitleCtrl.text.trim() : task.title;
    final cleanAmbiguities = List<String>.from(task.ambiguities);
    if (_editPrioritySource == 'explicit') {
      cleanAmbiguities.remove('priority_unspecified');
      cleanAmbiguities.remove('inferred_priority');
    }

    _planCandidates[_editingIndex] = task.copyWith(
      title: title,
      taskType: _editType,
      durationMinutes: _editDuration,
      priority: _editPriority,
      prioritySource: _editPrioritySource,
      deadline: _editDeadline,
      scheduledTime: _editFixedTime,
      ambiguities: cleanAmbiguities,
    );
  }

  void _saveEdit() {
    FlowHaptics.success();
    _syncCurrentEditToCandidate();

    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final schedule = const SchedulingEngine().generateOptimizedSchedule(
      tasks: _planCandidates,
      readiness: provider.readiness,
    );

    setState(() {
      _scheduleItems = schedule;
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
    setState(() => _isSubmitting = true);
    FlowHaptics.success();

    final provider = Provider.of<AppStateProvider>(context, listen: false);

    final finalizedTasks = _planCandidates.map((task) {
      ScheduleItem? sched;
      try {
        sched = _scheduleItems.firstWhere((s) => s.id == 'sched-${task.id}' || s.title == task.title);
      } catch (_) {}

      final prio = (task.prioritySource == 'unspecified' || task.ambiguities.contains('priority_unspecified'))
          ? TaskPriority.medium
          : task.priority;
      final cleanAmbiguities = List<String>.from(task.ambiguities)
        ..remove('priority_unspecified')
        ..remove('inferred_priority')
        ..remove('needs_confirmation');

      DateTime? start = task.scheduledStart;
      String? timeStr = task.scheduledTime;
      if (start == null && sched != null) {
        try {
          final parts = sched.time.split(':');
          if (parts.length >= 2) {
            int hour = int.parse(parts[0]);
            final minute = int.parse(parts[1]);
            if (sched.period.toUpperCase() == 'PM' && hour < 12) hour += 12;
            if (sched.period.toUpperCase() == 'AM' && hour == 12) hour = 0;
            final now = DateTime.now();
            start = DateTime(now.year, now.month, now.day, hour, minute);
          }
        } catch (_) {}
        timeStr = '${sched.time} ${sched.period}';
      }

      return task.copyWith(
        priority: prio,
        scheduledStart: start,
        scheduledTime: timeStr,
        ambiguities: cleanAmbiguities,
      );
    }).toList();

    provider.confirmCandidates(finalizedTasks);
    if (!mounted) return;
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '${finalizedTasks.length} task${finalizedTasks.length == 1 ? '' : 's'} added to your day',
        style: FlowTypography.bodySmall(color: FlowColors.textPrimary),
      ),
      backgroundColor: FlowColors.darkCardElevated,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
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
                  decoration: const BoxDecoration(
                    color: FlowColors.darkBorder,
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
                    _BrainDumpViewMode.preview => _buildPlanPreviewContent(accent),
                    _BrainDumpViewMode.edit => _buildEditContent(accent),
                  },
                ),
              ),

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
    final species = companion?.species ?? 'fox';
    final name = companion?.name ?? 'Noya';

    String noyaMessage;
    if (_isLoading) {
      noyaMessage = '$name is structuring your plan...';
    } else if (_viewMode == _BrainDumpViewMode.preview) {
      noyaMessage = '$name arranged your focus flow.';
    } else if (_viewMode == _BrainDumpViewMode.edit) {
      noyaMessage = 'Fine-tune with $name.';
    } else {
      noyaMessage = '$name is ready to organize your day.';
    }

    return Container(
      key: const Key('noya_companion_header'),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FlowColors.darkCardElevated,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.darkBorder),
      ),
      child: Row(
        children: [
          CompanionGraphic(
            species: species,
            size: 26,
            state: _isLoading ? CompanionAnimState.focusing : CompanionAnimState.idle,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: FlowTypography.labelMedium().copyWith(
                    fontWeight: FontWeight.w700,
                    color: FlowColors.textPrimary,
                  ),
                ),
                Text(
                  noyaMessage,
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondary).copyWith(
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What else is on your plate?',
          style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Just write it out.',
          style: FlowTypography.bodySmall(color: FlowColors.textMuted),
        ),
        const SizedBox(height: 16),

        // Text input container
        Container(
          decoration: BoxDecoration(
            color: FlowColors.darkCard,
            borderRadius: FlowRadii.cardRadius,
            border: Border.all(
              color: _errorMessage != null ? FlowColors.warning : FlowColors.darkBorder,
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
              hintText: 'e.g. Finish Python lab tomorrow, study arrays, call the dentist at 4, gym at 6...',
              hintStyle: FlowTypography.bodySmall(color: FlowColors.textMuted),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_planSource == 'Enhanced with AI' ? accent : FlowColors.accentMint)
                      .withValues(alpha: 0.14),
                  borderRadius: FlowRadii.pillRadius,
                ),
                child: Text(
                  _planSource ?? 'Planned by Flowstate',
                  overflow: TextOverflow.ellipsis,
                  style: FlowTypography.labelSmall(
                    color: _planSource == 'Enhanced with AI' ? accent : FlowColors.accentMint,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Here is your optimized execution schedule.',
          style: FlowTypography.bodySmall(color: FlowColors.textMuted),
        ),

        if (_fallbackNotice != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FlowColors.darkCardElevated,
              borderRadius: FlowRadii.cardRadius,
              border: Border.all(color: FlowColors.darkBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: FlowColors.accentMint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _fallbackNotice!,
                    style: FlowTypography.bodySmall(color: FlowColors.textSecondary).copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Scheduled task cards
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _planCandidates.length,
          itemBuilder: (ctx, i) {
            final task = _planCandidates[i];
            ScheduleItem? sched;
            try {
              sched = _scheduleItems.firstWhere((s) => s.id == 'sched-${task.id}' || s.title == task.title);
            } catch (_) {}
            return _buildTaskPreviewCard(task, sched, accent, i);
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildTaskPreviewCard(TaskItem task, ScheduleItem? sched, Color accent, int index) {
    String? timeDisplay = task.scheduledTime;
    if (timeDisplay == null && sched != null) {
      final s = sched.time;
      final p = sched.period;
      timeDisplay = '$s $p';
    }

    final isFixedTime = task.scheduledStart != null;
    final isExplicit = task.isPriorityExplicit;
    final isInferred = task.isPriorityInferred;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(
          color: isInferred ? FlowColors.warning.withValues(alpha: 0.35) : FlowColors.darkBorder,
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
                    color: FlowColors.textPrimary,
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
                      const Icon(Icons.edit_outlined, size: 14, color: FlowColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        'Edit',
                        style: FlowTypography.labelSmall(color: FlowColors.textMuted).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // TYPE · DURATION
          Text(
            '${task.taskType.label} · ${task.durationMinutes} min',
            style: FlowTypography.bodySmall(color: FlowColors.textSecondary).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),

          // PRIORITY
          if (isExplicit)
            Text(
              '${_capitalize(task.priority.value)} priority',
              style: FlowTypography.bodySmall(color: FlowColors.textSecondary),
            )
          else if (isInferred)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: FlowColors.warning.withValues(alpha: 0.12),
                borderRadius: FlowRadii.pillRadius,
              ),
              child: Text(
                'Suggested priority: ${_capitalize(task.priority.value)}',
                style: FlowTypography.bodySmall(color: FlowColors.warning).copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            )
          else
            Text(
              'Priority not specified',
              style: FlowTypography.bodySmall(color: FlowColors.textMuted).copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          const SizedBox(height: 4),

          // TIME / DEADLINE
          if (timeDisplay != null)
            Text(
              isFixedTime ? '$timeDisplay · Fixed time' : timeDisplay,
              style: FlowTypography.bodySmall(
                color: isFixedTime ? FlowColors.accentCyan : FlowColors.textSecondary,
              ).copyWith(
                fontWeight: isFixedTime ? FontWeight.w600 : FontWeight.normal,
              ),
            )
          else if (task.deadline.isNotEmpty && task.deadline != 'Today')
            Text(
              task.deadline,
              style: FlowTypography.bodySmall(color: FlowColors.textSecondary),
            ),
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
                style: FlowTypography.labelSmall(color: FlowColors.textMuted),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? accent.withValues(alpha: 0.15) : FlowColors.darkCard,
                        borderRadius: FlowRadii.pillRadius,
                        border: Border.all(
                          color: isSelected ? accent : FlowColors.darkBorder,
                        ),
                      ),
                      child: Text(
                        _planCandidates[i].title,
                        style: FlowTypography.labelSmall(
                          color: isSelected ? accent : FlowColors.textSecondary,
                        ).copyWith(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Title
          Text('TASK TITLE', style: FlowTypography.labelSmall(color: FlowColors.textMuted).copyWith(letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: FlowColors.darkCard,
              borderRadius: FlowRadii.cardRadius,
              border: Border.all(color: FlowColors.darkBorder),
            ),
            child: TextField(
              key: const Key('edit_task_title_field'),
              controller: _editTitleCtrl,
              style: FlowTypography.bodyMedium(),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Type
          Text('TASK TYPE', style: FlowTypography.labelSmall(color: FlowColors.textMuted).copyWith(letterSpacing: 0.5)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? accent.withValues(alpha: 0.15) : FlowColors.darkCard,
                    borderRadius: FlowRadii.pillRadius,
                    border: Border.all(color: isSel ? accent : FlowColors.darkBorder),
                  ),
                  child: Text(
                    t.label,
                    style: FlowTypography.labelSmall(
                      color: isSel ? accent : FlowColors.textSecondary,
                    ).copyWith(fontWeight: isSel ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Estimated Duration
          Text('ESTIMATED DURATION', style: FlowTypography.labelSmall(color: FlowColors.textMuted).copyWith(letterSpacing: 0.5)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? accent.withValues(alpha: 0.15) : FlowColors.darkCard,
                    borderRadius: FlowRadii.pillRadius,
                    border: Border.all(color: isSel ? accent : FlowColors.darkBorder),
                  ),
                  child: Text(
                    '$m min',
                    style: FlowTypography.labelSmall(
                      color: isSel ? accent : FlowColors.textSecondary,
                    ).copyWith(fontWeight: isSel ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Priority
          Text('PRIORITY', style: FlowTypography.labelSmall(color: FlowColors.textMuted).copyWith(letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              (label: 'Unspecified', prio: TaskPriority.medium, source: 'unspecified'),
              (label: 'Low', prio: TaskPriority.low, source: 'explicit'),
              (label: 'Medium', prio: TaskPriority.medium, source: 'explicit'),
              (label: 'High', prio: TaskPriority.high, source: 'explicit'),
              (label: 'Urgent', prio: TaskPriority.urgent, source: 'explicit'),
            ].map((item) {
              final isSel = item.source == 'unspecified'
                  ? _editPrioritySource == 'unspecified'
                  : (_editPriority == item.prio && _editPrioritySource == 'explicit');
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? accent.withValues(alpha: 0.15) : FlowColors.darkCard,
                    borderRadius: FlowRadii.pillRadius,
                    border: Border.all(color: isSel ? accent : FlowColors.darkBorder),
                  ),
                  child: Text(
                    item.label,
                    style: FlowTypography.labelSmall(
                      color: isSel ? accent : FlowColors.textSecondary,
                    ).copyWith(fontWeight: isSel ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Deadline
          Text('DEADLINE', style: FlowTypography.labelSmall(color: FlowColors.textMuted).copyWith(letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: ['Today', 'Tomorrow', 'Friday', 'Next week'].map((d) {
              final isSel = _editDeadline == d;
              return GestureDetector(
                key: Key('deadline_chip_${d.toLowerCase()}'),
                onTap: () {
                  FlowHaptics.selection();
                  setState(() => _editDeadline = d);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? accent.withValues(alpha: 0.15) : FlowColors.darkCard,
                    borderRadius: FlowRadii.pillRadius,
                    border: Border.all(color: isSel ? accent : FlowColors.darkBorder),
                  ),
                  child: Text(
                    d,
                    style: FlowTypography.labelSmall(
                      color: isSel ? accent : FlowColors.textSecondary,
                    ).copyWith(fontWeight: isSel ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Fixed Time
          Text('FIXED TIME', style: FlowTypography.labelSmall(color: FlowColors.textMuted).copyWith(letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [null, '9:00 AM', '2:00 PM', '5:00 PM', '6:00 PM'].map((t) {
              final isSel = _editFixedTime == t;
              return GestureDetector(
                key: Key('time_chip_${t == null ? 'none' : t.replaceAll(' ', '_').replaceAll(':', '')}'),
                onTap: () {
                  FlowHaptics.selection();
                  setState(() => _editFixedTime = t);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? accent.withValues(alpha: 0.15) : FlowColors.darkCard,
                    borderRadius: FlowRadii.pillRadius,
                    border: Border.all(color: isSel ? accent : FlowColors.darkBorder),
                  ),
                  child: Text(
                    t ?? 'No fixed time',
                    style: FlowTypography.labelSmall(
                      color: isSel ? accent : FlowColors.textSecondary,
                    ).copyWith(fontWeight: isSel ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPinnedBottomCTA(Color accent) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth < 360 ? 16.0 : 24.0;

    return Container(
      decoration: const BoxDecoration(
        color: FlowColors.darkSurface,
        border: Border(top: BorderSide(color: FlowColors.darkBorder, width: 0.8)),
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
                backgroundColor: _isValid ? accent : FlowColors.darkBorder,
                foregroundColor: _isValid ? FlowColors.textInverse : FlowColors.textMuted,
                elevation: 0,
                shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
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
                        color: _isValid ? FlowColors.textInverse : FlowColors.textMuted,
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
                    foregroundColor: FlowColors.textPrimary,
                    side: const BorderSide(color: FlowColors.darkBorder),
                    shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Edit',
                    style: FlowTypography.labelLarge(color: FlowColors.textPrimary)
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
                    shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
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
                          style: FlowTypography.labelLarge(color: FlowColors.textInverse)
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
                    foregroundColor: FlowColors.textPrimary,
                    side: const BorderSide(color: FlowColors.darkBorder),
                    shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Cancel',
                    style: FlowTypography.labelLarge(color: FlowColors.textPrimary)
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
                    shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Save changes',
                    style: FlowTypography.labelLarge(color: FlowColors.textInverse)
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
