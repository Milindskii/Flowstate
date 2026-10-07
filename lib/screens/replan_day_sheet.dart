import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../components/noya_companion_view.dart';
import '../components/noya_thinking.dart';
import '../components/plan_diff_view.dart';
import '../components/replan_new_task_sheet.dart';
import '../models/calendar_models.dart';
import '../models/schedule_item.dart';
import '../providers/app_state_provider.dart';
import '../services/api_service.dart';
import '../utils/friendly_error.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Opens the dedicated Replan My Day modal sheet.
void showReplanDaySheet(
  BuildContext context, {
  required DateTime selectedDate,
  DayScheduleResponse? currentSchedule,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => ReplanDaySheet(
      selectedDate: selectedDate,
      currentSchedule: currentSchedule,
    ),
  );
}

/// User-facing text for a failed Replan call (plain language only). Exposed for tests.
String replanFriendlyError(Object e) => friendlyErrorMessage(e, fallback: _replanFallback);

const String _replanFallback = "I couldn't build a new plan right now. Your message is still here, so you can try again.";

class _ChatMessage {
  final bool isUser;
  final String text;
  PlanDiff? proposal; // replaced when the user edits a new task in the preview
  final bool isError;
  final String? retryText; // the preserved request, resent by "Try again"
  final ReplanClarification? clarification; // Noya needs a detail: its options are shown under the question
  final DateTime timestamp;

  _ChatMessage({
    required this.isUser,
    required this.text,
    this.proposal,
    this.isError = false,
    this.retryText,
    this.clarification,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Dedicated contextual planning sheet for Replan My Day (Task 4: Dry Run Only).
class ReplanDaySheet extends StatefulWidget {
  final DateTime selectedDate;
  final DayScheduleResponse? currentSchedule;

  const ReplanDaySheet({
    super.key,
    required this.selectedDate,
    this.currentSchedule,
  });

  @override
  State<ReplanDaySheet> createState() => _ReplanDaySheetState();
}

class _ReplanDaySheetState extends State<ReplanDaySheet> with WidgetsBindingObserver {
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();

  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isApplying = false;
  bool _planExpanded = false;
  bool get _hasConversation => _messages.any((m) => m.isUser);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Seed initial assistant greeting
    _messages.add(
      _ChatMessage(
        isUser: false,
        text: "Tell me what changed with your day, or tap a quick action below.",
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textCtrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // The keyboard opened or closed: keep the latest message and the composer in view.
    if (MediaQuery.of(context).viewInsets.bottom > 0) _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _populateInput(String prefix) {
    FlowHaptics.lightTap();
    _textCtrl.text = prefix;
    _textCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _textCtrl.text.length),
    );
    _focusNode.requestFocus();
  }

  Future<void> _sendMessage(String text, {Map<String, dynamic>? quickAdd, String? display, _ChatMessage? retryOf}) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && quickAdd == null) || _isLoading) return;

    setState(() {
      if (retryOf != null) {
        _messages.remove(retryOf);
      } else {
        _messages.add(_ChatMessage(isUser: true, text: display ?? trimmed));
      }
      _isLoading = true;
    });
    _scrollToBottom();
    FlowHaptics.lightTap();

    try {
      final provider = Provider.of<AppStateProvider>(context, listen: false);
      final response = await provider.replanDay(
        date: widget.selectedDate,
        message: trimmed,
        quickAdd: quickAdd,
      );

      final diff = response.planDiff;
      final clarification = diff.clarification;
      String assistantMsg;
      if (clarification != null) {
        assistantMsg = clarification.question;
      } else if (diff.hasTrueConflict) {
        assistantMsg = 'Part of that clashes with a fixed time, so I worked around it:';
      } else if (diff.issues.any((i) => i.kind == 'ambiguous' || i.kind == 'not_found' || i.kind == 'unparsed')) {
        assistantMsg = "Here's what I could do — I need a little more detail on the rest:";
      } else if (diff.issues.any((i) => i.kind == 'capacity')) {
        assistantMsg = "Here's how I'd reshape the rest of your day. Not everything fit:";
      } else {
        assistantMsg = "Here's how I'd reshape the rest of your day:";
      }

      if (mounted) {
        // the draft is cleared only once the request succeeded, so a failure never loses the user's words
        if (_textCtrl.text.trim() == trimmed) _textCtrl.clear();
        setState(() {
          _isLoading = false;
          _messages.add(_ChatMessage(
            isUser: false,
            text: assistantMsg,
            proposal: clarification == null ? diff : null,
            clarification: clarification,
          ));
        });
        _scrollToBottom();
        FlowHaptics.success();
      }
    } catch (e) {
      if (mounted) {
        final errText = replanFriendlyError(e);
        setState(() {
          _isLoading = false;
          _messages.add(_ChatMessage(
            isUser: false,
            text: errText,
            isError: true,
            retryText: quickAdd == null ? trimmed : null,
          ));
        });
        _scrollToBottom();
        FlowHaptics.selection();
      }
    }
  }

  /// A tap on one of Noya's task-specific options: send it as the user's reply, or hand the half-written
  /// request ("move going out to ") to the composer so the user supplies the missing detail.
  void _chooseOption(ReplanClarificationOption option) {
    if (_isLoading) return;
    final message = option.message;
    if (message != null && message.isNotEmpty) {
      _sendMessage(message, display: option.label);
    } else if (option.prefill != null) {
      _populateInput(option.prefill!);
    }
  }

  Future<void> _openUrgentSheet() async {
    FlowHaptics.lightTap();
    final r = await ReplanNewTaskSheet.show(context);
    if (r == null || !mounted) return;
    final start = r.time == null
        ? null
        : '${r.time!.hour.toString().padLeft(2, '0')}:${r.time!.minute.toString().padLeft(2, '0')}';
    await _sendMessage(
      '',
      display: 'Urgent: ${r.title} · ${r.minutes} min${r.time == null ? '' : ' at ${r.time!.format(context)}'}',
      quickAdd: {'title': r.title, 'duration_minutes': r.minutes, if (start != null) 'start_time': start},
    );
  }

  Future<void> _editNewTask(_ChatMessage msg, TaskDiffItem item) async {
    final proposal = msg.proposal;
    final index = item.applyIndex;
    if (proposal == null || index == null) return;
    final startLocal = item.newStart;
    final r = await ReplanNewTaskSheet.show(
      context,
      editing: true,
      initialTitle: item.needsTitle ? '' : item.title,
      initialMinutes: item.durationMinutes,
      initialTime: startLocal == null ? null : TimeOfDay(hour: startLocal.hour, minute: startLocal.minute),
    );
    if (r == null || !mounted) return;
    DateTime? start;
    if (r.time != null) {
      final base = startLocal ?? DateTime.tryParse(proposal.selectedDate) ?? widget.selectedDate;
      final changed = startLocal == null || startLocal.hour != r.time!.hour || startLocal.minute != r.time!.minute;
      if (changed) start = DateTime(base.year, base.month, base.day, r.time!.hour, r.time!.minute);
    }
    setState(() {
      msg.proposal = proposal.withEditedNewTask(applyIndex: index, title: r.title, minutes: r.minutes, start: start);
    });
  }

  String _applyErrorText(Object e) {
    if (e is ApiException) {
      final detail = e.data is Map<String, dynamic> ? (e.data as Map<String, dynamic>)['detail'] : null;
      if (e.statusCode == 409) {
        final msg = detail is Map<String, dynamic> ? detail['message'] as String? : null;
        return (msg != null && isPlainSentence(msg))
            ? msg
            : 'Your schedule changed since this plan was made. Ask again to get a fresh plan.';
      }
      if (e.statusCode == 422 && detail is Map<String, dynamic> && detail['errors'] is List) {
        final errs = (detail['errors'] as List).whereType<Map<String, dynamic>>().toList();
        if (errs.isNotEmpty) {
          final code = errs.first['code'];
          if (code == 'start_in_past') return 'That plan would put something in the past. Ask again for a fresh plan.';
          if (code == 'overlap') return 'That plan would overlap another task. Ask again for a fresh plan.';
          if (code == 'after_deadline') return 'That plan would miss a deadline. Ask again for a fresh plan.';
        }
      }
    }
    const unchanged = "Couldn't apply that plan \u2014 your day is unchanged.";
    if (e is ApiException && (e.statusCode ?? 0) >= 500) return unchanged;
    return friendlyErrorMessage(e, fallback: unchanged);
  }

  Future<void> _handleApplyProposal(PlanDiff proposal) async {
    if (_isApplying) return;
    setState(() {
      _isApplying = true;
    });
    FlowHaptics.selection();

    try {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      final res = await appState.applyReplan(proposal);
      if (mounted) {
        FlowHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    res.message.isNotEmpty ? res.message : 'Schedule updated successfully!',
                    style: FlowTypography.bodyMedium(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: FlowColors.accentCyan,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        FlowHaptics.warning();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_applyErrorText(e), style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context))),
            backgroundColor: FlowColors.surfaceElevated(context),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.chip)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final planItems = widget.currentSchedule?.timeline ?? [];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: (MediaQuery.of(context).size.height * 0.90 - bottomInset).clamp(280.0, double.infinity),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FlowColors.border(context),
                    borderRadius: BorderRadius.circular(FlowRadii.pill),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    NoyaThinking(active: _isLoading || _isApplying, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Replan my day',
                            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('EEEE, MMMM d').format(widget.selectedDate),
                            style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: FlowColors.textSecondaryOf(context),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),
              Divider(height: 1, color: FlowColors.border(context)),

              // Scrollable Context + Chat History Area
              Flexible(
                child: ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    // 1. Current Plan Context (collapses to one line once the conversation starts)
                    _buildCurrentPlanContext(planItems),

                    const SizedBox(height: 16),

                    // 2. Quick Action Chips (only while there is nothing to react to yet)
                    if (!_hasConversation) ...[
                      _buildQuickActionChips(),
                      const SizedBox(height: 16),
                    ],

                    // 3. Conversation Messages
                    ..._messages.map((msg) => _buildMessageBubble(msg)),

                    // 4. Loading State
                    if (_isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const NoyaThinking(active: true, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Let me rearrange what's flexible...",
                                style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Bottom Input Bar
              _buildBottomInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentPlanContext(List<ScheduleItem> planItems) {
    final collapsed = _hasConversation && !_planExpanded && planItems.isNotEmpty;
    if (collapsed) {
      return InkWell(
        key: const Key('replan_plan_summary'),
        borderRadius: FlowRadii.cardRadius,
        onTap: () => setState(() => _planExpanded = true),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: FlowColors.surfaceElevated(context),
            borderRadius: FlowRadii.cardRadius,
            border: Border.all(color: FlowColors.border(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Your current plan \u00b7 ${planItems.length} task${planItems.length == 1 ? '' : 's'}',
                  style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.expand_more_rounded, color: FlowColors.textMutedOf(context)),
            ],
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your current plan',
                style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${planItems.length} task${planItems.length == 1 ? '' : 's'}',
                style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (planItems.isEmpty)
            Text(
              'No scheduled tasks for this day yet.',
              style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
            )
          else
            ...planItems.map((item) {
              final isFixed = item.isFixed || item.tagText == 'FIXED';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: Text(
                        '${item.time} ${item.period}'.trim(),
                        style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.title,
                        style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isFixed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: FlowColors.accentAmber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(FlowRadii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline_rounded, size: 11, color: FlowColors.accentAmber),
                            const SizedBox(width: 3),
                            Text(
                              'Fixed',
                              style: FlowTypography.labelSmall(color: FlowColors.accentAmber).copyWith(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildQuickActionChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What changed?',
          style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildChip("I'm running late", () => _sendMessage("I'm running 30 minutes late")),
              const SizedBox(width: 8),
              _buildChip("Urgent work arrived", _openUrgentSheet),
              const SizedBox(width: 8),
              _buildChip("Move something", () => _populateInput("Move ")),
              const SizedBox(width: 8),
              _buildChip("Cancel a task", () => _populateInput("Cancel ")),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String label, VoidCallback onTap, {Key? key}) {
    return InkWell(
      key: key,
      onTap: _isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(FlowRadii.pill),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FlowRadii.pill),
          border: Border.all(color: FlowColors.border(context)),
        ),
        child: Text(
          label,
          style: FlowTypography.labelSmall(
            color: _isLoading ? FlowColors.textMutedOf(context) : FlowColors.textSecondaryOf(context),
          ).copyWith(fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    final maxBubble = MediaQuery.of(context).size.width * 0.8;
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxBubble),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: FlowColors.accentCyan.withValues(alpha: 0.14),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
            border: Border.all(color: FlowColors.accentCyan.withValues(alpha: 0.28)),
          ),
          child: _CollapsibleText(
            key: const Key('replan_user_message'),
            text: msg.text,
            style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)),
          ),
        ),
      );
    }

    final bubbleBg = FlowColors.surfaceElevated(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 8),
                child: NoyaCompanionView(state: NoyaState.idle, size: 28),
              ),
              Flexible(
                child: Container(
                  key: msg.isError ? const Key('replan_error_bubble') : null,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: bubbleBg,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(color: FlowColors.border(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (msg.isError) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.info_outline_rounded, size: 16, color: FlowColors.warningOf(context)),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(msg.text, style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context))),
                          ),
                        ],
                      ),
                      if (msg.isError && msg.retryText != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const Key('replan_retry'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            ),
                            onPressed: _isLoading ? null : () => _sendMessage(msg.retryText!, retryOf: msg),
                            child: const Text('Try again'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (msg.clarification != null && msg.clarification!.options.isNotEmpty && identical(msg, _messages.last))
            Padding(
              key: const Key('replan_clarification_options'),
              padding: const EdgeInsets.only(left: 36, top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in msg.clarification!.options)
                    _buildChip(o.label, () => _chooseOption(o), key: Key('replan_option_${o.label}')),
                ],
              ),
            ),
          if (msg.proposal != null) ...[
            const SizedBox(height: 10),
            PlanDiffView(
              diff: msg.proposal!,
              isApplying: _isApplying,
              onEditNewTask: (t) => _editNewTask(msg, t),
              onApply: () => _handleApplyProposal(msg.proposal!),
              onAdjust: () {
                _focusNode.requestFocus();
              },
              onDiscard: () {
                // Dismissing a preview changes nothing; the conversation stays and Noya confirms it.
                setState(() {
                  msg.proposal = null;
                  _messages.add(_ChatMessage(
                    isUser: false,
                    text: 'No problem \u2014 your plan stays as it is. Tell me if you want to try something else.',
                  ));
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  /// The composer is an input CONTROL (a rounded rectangle with its own border and focus ring), deliberately not
  /// shaped like a message bubble. It grows from one line up to [_composerMaxLines], then scrolls inside itself,
  /// so it never takes over the screen. The send button is anchored inside it (48 dp target). While a request is
  /// running the field is read-only and visibly dimmed; the draft is only cleared after a successful send.
  static const int _composerMaxLines = 5;

  Widget _buildBottomInputBar() {
    final border = FlowColors.border(context);
    return Container(
      key: const Key('replan_composer_bar'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        border: Border(top: BorderSide(color: border)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4)),
        ],
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([_textCtrl, _focusNode]),
        builder: (context, _) {
          final busy = _isLoading;
          final canSend = _textCtrl.text.trim().isNotEmpty && !busy;
          final focused = _focusNode.hasFocus && !busy;
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: busy ? 0.6 : 1,
            child: Container(
              key: const Key('replan_composer_box'),
              constraints: const BoxConstraints(minHeight: 56),
              decoration: BoxDecoration(
                color: FlowColors.surfaceElevated(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: focused ? FlowColors.accentCyan : border, width: focused ? 1.5 : 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                      child: TextField(
                        controller: _textCtrl,
                        focusNode: _focusNode,
                        key: const Key('replan_composer'),
                        readOnly: busy,
                        minLines: 1,
                        maxLines: _composerMaxLines,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textCapitalization: TextCapitalization.sentences,
                        style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)),
                        decoration: InputDecoration(
                          hintText: busy ? 'Noya is working on it…' : 'Tell Noya what changed...',
                          hintStyle: FlowTypography.bodyMedium(color: FlowColors.textMutedOf(context)),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton.filled(
                        key: const Key('replan_send'),
                        tooltip: 'Send',
                        icon: busy
                            ? const SizedBox(
                                key: Key('replan_send_busy'),
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded, size: 20),
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          backgroundColor: (canSend || busy) ? FlowColors.accentCyan : FlowColors.surface(context),
                          disabledBackgroundColor: busy ? FlowColors.accentCyan : FlowColors.surface(context),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: busy ? Colors.white : FlowColors.textMutedOf(context),
                        ),
                        onPressed: canSend ? () => _sendMessage(_textCtrl.text) : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Long user messages stay readable: past a few lines they fold behind "Show more".
class _CollapsibleText extends StatefulWidget {
  final String text;
  final TextStyle style;
  static const int collapsedLines = 6;

  const _CollapsibleText({super.key, required this.text, required this.style});

  @override
  State<_CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<_CollapsibleText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        textDirection: Directionality.of(context),
        maxLines: _CollapsibleText.collapsedLines + 1,
      )..layout(maxWidth: constraints.maxWidth);
      final overflows = painter.didExceedMaxLines;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.text,
            style: widget.style,
            maxLines: (_expanded || !overflows) ? null : _CollapsibleText.collapsedLines,
            overflow: TextOverflow.fade,
          ),
          if (overflows)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(
                  _expanded ? 'Show less' : 'Show more',
                  style: widget.style.copyWith(fontWeight: FontWeight.w700, color: FlowColors.accentCyan),
                ),
              ),
            ),
        ],
      );
    });
  }
}
