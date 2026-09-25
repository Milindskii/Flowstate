import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../components/ai_economy_sheets.dart';
import '../engines/scheduling_engine.dart';
import '../models/schedule_item.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ai_plan_service.dart';
import '../services/task_parse_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'parsed_plan_confirm_sheet.dart';

/// Bottom sheet for brain-dump task input and plan preview.
///
/// Local-First Pipeline:
/// 1. Natural user text entry (no voice / microphone in V1).
/// 2. If clear and unambiguous, immediately parses locally via deterministic rules (0 AI credits, 0 latency).
/// 3. If genuinely ambiguous or complex, attempts Gemini task structuring.
/// 4. If Gemini fails (offline, timeout, API limit), seamlessly falls back to local parser without blocking.
/// 5. Flowstate deterministic scheduler builds the plan.
/// 6. Shows Plan Preview with pinned [ Add & Schedule ] action.
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
  String? _errorMessage;
  String? _fallbackNotice;
  String? _planSource;

  bool _showPreview = false;
  List<TaskItem> _planCandidates = [];
  List<ScheduleItem> _scheduleItems = [];

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
        _showPreview = true;
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
        _showPreview = true;
        _isLoading = false;
      });
      FlowHaptics.selection();
    }
  }

  void _addAndSchedule() {
    FlowHaptics.success();
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    provider.confirmCandidates(_planCandidates);
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '${_planCandidates.length} task${_planCandidates.length == 1 ? '' : 's'} added to your day',
        style: FlowTypography.bodySmall(color: FlowColors.textPrimary),
      ),
      backgroundColor: FlowColors.darkCardElevated,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _editPlan() {
    FlowHaptics.selection();
    Navigator.of(context).pop();
    showParsedPlanConfirmSheet(context, candidates: _planCandidates);
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
            maxHeight: MediaQuery.of(context).size.height * 0.85,
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
              const SizedBox(height: 16),

              // Scrollable Content Area
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _showPreview ? _buildPlanPreviewContent(accent) : _buildInputContent(),
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

        // Text input container (Microphone completely removed for V1)
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
              sched = _scheduleItems.firstWhere((s) => s.id == 'sched-${task.id}');
            } catch (_) {}
            return _buildTaskPreviewCard(task, sched, accent);
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildTaskPreviewCard(TaskItem task, ScheduleItem? sched, Color accent) {
    String? timeDisplay = task.scheduledTime;
    if (timeDisplay == null && sched != null) {
      final s = sched.time;
      final p = sched.period;
      timeDisplay = '$s $p';
    }

    final isFixedTime = task.scheduledStart != null;
    final isPriorityInferred = task.ambiguities.contains('inferred_priority');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (timeDisplay != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isFixedTime
                    ? FlowColors.accentCyan.withValues(alpha: 0.14)
                    : FlowColors.darkCardElevated,
                borderRadius: FlowRadii.pillRadius,
                border: Border.all(
                  color: isFixedTime ? FlowColors.accentCyan.withValues(alpha: 0.25) : FlowColors.darkBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 12,
                    color: isFixedTime ? FlowColors.accentCyan : FlowColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      isFixedTime ? '$timeDisplay · Fixed time' : timeDisplay,
                      style: FlowTypography.labelSmall(
                        color: isFixedTime ? FlowColors.accentCyan : FlowColors.textSecondary,
                      ).copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            task.title,
            style: FlowTypography.bodyLarge().copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${task.category} · ${task.durationMinutes} min',
                style: FlowTypography.bodySmall(color: FlowColors.textSecondary),
              ),
              Text('•', style: FlowTypography.bodySmall(color: FlowColors.textMuted)),
              Text(
                '${_capitalize(task.priority.value)} priority${isPriorityInferred ? ' (Inferred)' : ''}',
                style: FlowTypography.bodySmall(
                  color: isPriorityInferred ? FlowColors.warning : FlowColors.textSecondary,
                ).copyWith(fontWeight: isPriorityInferred ? FontWeight.w600 : FontWeight.normal),
              ),
              if (task.deadline.isNotEmpty && task.deadline != 'Today') ...[
                Text('•', style: FlowTypography.bodySmall(color: FlowColors.textMuted)),
                Text(
                  'Due ${task.deadline}',
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondary),
                ),
              ],
            ],
          ),
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
      child: _showPreview
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('edit_button'),
                    onPressed: _editPlan,
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
                    onPressed: _addAndSchedule,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: FlowColors.textInverse,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Add & Schedule',
                      style: FlowTypography.labelLarge(color: FlowColors.textInverse)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            )
          : SizedBox(
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
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
