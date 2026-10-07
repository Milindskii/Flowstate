import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import '../models/calendar_models.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'primary_button.dart';

enum PlanDiffViewTab {
  whatChanged,
  beforeAfter,
}

/// Rich, visual Plan Diff component comparing Before vs After schedules.
/// Visual Plan Diff component comparing Before vs After schedules.
class PlanDiffView extends StatefulWidget {
  final PlanDiff diff;
  final VoidCallback? onApply;
  final VoidCallback? onAdjust;
  final VoidCallback? onDiscard;
  /// Opens the editor for a NEW task in this proposal (rename, duration, time) before Apply.
  final void Function(TaskDiffItem task)? onEditNewTask;
  final bool isApplying;

  const PlanDiffView({
    super.key,
    required this.diff,
    this.onApply,
    this.onAdjust,
    this.onDiscard,
    this.onEditNewTask,
    this.isApplying = false,
  });

  @override
  State<PlanDiffView> createState() => _PlanDiffViewState();
}

class _PlanDiffViewState extends State<PlanDiffView> {
  PlanDiffViewTab _currentTab = PlanDiffViewTab.whatChanged;

  @override
  Widget build(BuildContext context) {
    final diff = widget.diff;
    final hasConflicts = diff.hasTrueConflict;
    final alertColor = FlowColors.errorOf(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(
          color: hasConflicts
              ? alertColor.withValues(alpha: 0.5)
              : FlowColors.accentCyan.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: hasConflicts
                ? alertColor.withValues(alpha: 0.08)
                : FlowColors.accentCyan.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Header Row: Title + "DRY RUN ONLY" Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: hasConflicts ? alertColor : FlowColors.accentCyan,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PLAN PREVIEW',
                            style: FlowTypography.labelSmall(
                              color: hasConflicts ? alertColor : FlowColors.accentCyan,
                            ).copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              fontSize: 9.5,
                            ),
                          ),
                          Text(
                            "Here's how I'd reshape the rest of your day",
                            style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: FlowColors.surfaceElevated(context),
                  borderRadius: BorderRadius.circular(FlowRadii.pill),
                  border: Border.all(color: FlowColors.border(context)),
                ),
                child: Text(
                  'PREVIEW',
                  style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 2. Metrics Bar: Count badges
          _buildMetricsBar(diff),

          // 3. Typed notes: only a true clash is red; capacity, protected and unclear notes are calm
          ..._buildIssueNotes(diff),

          // 4. Scheduler Explanation Callout
          if (diff.summaryText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: FlowColors.surfaceElevated(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: FlowColors.border(context).withValues(alpha: 0.6)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: FlowColors.accentCyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      diff.summaryText,
                      style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // 5. Segmented Tab Selector: "What Changed" vs "Before → After"
          _buildTabSelector(),

          const SizedBox(height: 14),

          // 6. Active Content: List View OR Timeline Comparison
          if (_currentTab == PlanDiffViewTab.whatChanged)
            _buildWhatChangedList(diff)
          else
            _buildBeforeAfterComparison(diff),

          const SizedBox(height: 16),
          Divider(height: 1, color: FlowColors.border(context)),
          const SizedBox(height: 14),

          // 7. Action Buttons (Task 5: Prepares actions without modifying DB)
          _buildActionButtons(context),

          const SizedBox(height: 8),

          // 8. Dry-Run Safety Notice
          Center(
            child: Text(
              'Preliminary proposal. Changes have not been applied to your database.',
              style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)).copyWith(
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsBar(PlanDiff diff) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (diff.movedTasks.isNotEmpty)
            _buildMetricPill(
              '${diff.movedTasks.length} Moved',
              FlowColors.accentCyan,
              FlowColors.accentCyan.withValues(alpha: 0.12),
            ),
          if (diff.newlyScheduledTasks.isNotEmpty) ...[
            const SizedBox(width: 6),
            _buildMetricPill(
              '${diff.newlyScheduledTasks.length} New',
              const Color(0xFF10B981),
              const Color(0xFF10B981).withValues(alpha: 0.12),
            ),
          ],
          if (diff.unchangedTasks.isNotEmpty) ...[
            const SizedBox(width: 6),
            _buildMetricPill(
              '${diff.unchangedTasks.length} Unchanged',
              FlowColors.accentAmber,
              FlowColors.accentAmber.withValues(alpha: 0.12),
            ),
          ],
          if (diff.cancelledTasks.isNotEmpty) ...[
            const SizedBox(width: 6),
            _buildMetricPill(
              '${diff.cancelledTasks.length} Cancelled',
              const Color(0xFFEF4444),
              const Color(0xFFEF4444).withValues(alpha: 0.12),
            ),
          ],
          if (diff.unscheduledTasks.isNotEmpty) ...[
            const SizedBox(width: 6),
            _buildMetricPill(
              '${diff.unscheduledTasks.length} Unscheduled',
              Colors.orange,
              Colors.orange.withValues(alpha: 0.12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricPill(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FlowRadii.pill),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: FlowTypography.labelSmall(color: fg).copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
        ),
      ),
    );
  }

  /// Groups the plan's notes by kind. Capacity notes are skipped when the same tasks are already listed in
  /// the "Didn't fit today" section, so nothing is said twice.
  List<Widget> _buildIssueNotes(PlanDiff diff) {
    final capacityListed = diff.unscheduledTasks.isNotEmpty;
    final groups = <(Set<String>, String, IconData, Color)>[
      ({'conflict'}, 'Clashes with a fixed time', Icons.event_busy_rounded, FlowColors.errorOf(context)),
      ({'capacity'}, "Didn't fit today", Icons.hourglass_bottom_rounded, FlowColors.warningOf(context)),
      ({'protected'}, 'Kept exactly as is', Icons.lock_outline_rounded, FlowColors.textSecondaryOf(context)),
      ({'ambiguous', 'not_found', 'unparsed'}, 'Need a bit more detail', Icons.help_outline_rounded, FlowColors.accentCyan),
      ({'past', 'note'}, 'Good to know', Icons.info_outline_rounded, FlowColors.textSecondaryOf(context)),
    ];
    final out = <Widget>[];
    for (final g in groups) {
      if (g.$1.contains('capacity') && capacityListed) continue;
      final items = diff.issuesOfKind(g.$1);
      if (items.isEmpty) continue;
      out.add(const SizedBox(height: 10));
      out.add(_IssueGroupCard(
        key: Key('replan_issue_${g.$1.first}'),
        title: g.$2,
        icon: g.$3,
        color: g.$4,
        messages: items.map((i) => i.message).toList(),
      ));
    }
    return out;
  }

  Widget _buildTabSelector() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: BorderRadius.circular(FlowRadii.pill),
        border: Border.all(color: FlowColors.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'What Changed',
              icon: Icons.list_alt_rounded,
              isSelected: _currentTab == PlanDiffViewTab.whatChanged,
              onTap: () {
                FlowHaptics.lightTap();
                setState(() => _currentTab = PlanDiffViewTab.whatChanged);
              },
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'Before → After',
              icon: Icons.compare_arrows_rounded,
              isSelected: _currentTab == PlanDiffViewTab.beforeAfter,
              onTap: () {
                FlowHaptics.lightTap();
                setState(() => _currentTab = PlanDiffViewTab.beforeAfter);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FlowRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? FlowColors.surface(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(FlowRadii.pill),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: FlowColors.softShadow(context),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? FlowColors.textPrimaryOf(context) : FlowColors.textMutedOf(context),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                title,
                style: FlowTypography.labelSmall(
                  color: isSelected ? FlowColors.textPrimaryOf(context) : FlowColors.textMutedOf(context),
                ).copyWith(
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhatChangedList(PlanDiff diff) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Newly Scheduled Tasks
        if (diff.newlyScheduledTasks.isNotEmpty) ...[
          _buildSectionHeader('New Tasks', const Color(0xFF10B981)),
          ...diff.newlyScheduledTasks.map((t) => _buildDiffItemCard(
                title: t.title,
                timeChange: 'NEW → ${t.newTime ?? 'Scheduled'}',
                badgeText: 'NEW',
                badgeColor: const Color(0xFF10B981),
                badgeBg: const Color(0xFF10B981).withValues(alpha: 0.12),
                icon: Icons.add_circle_outline_rounded,
                subtext: t.needsTitle
                    ? 'Name this task before applying'
                    : '${t.durationMinutes} min · Added to day',
                onEdit: widget.onEditNewTask == null ? null : () => widget.onEditNewTask!(t),
                editKey: Key('edit_new_task_${t.applyIndex ?? t.taskId}'),
              )),
          const SizedBox(height: 10),
        ],

        // 2. Moved Tasks
        if (diff.movedTasks.isNotEmpty) ...[
          _buildSectionHeader('Moved Tasks', FlowColors.accentCyan),
          ...diff.movedTasks.map((t) => _buildDiffItemCard(
                title: t.title,
                timeChange: t.changeLabel,
                badgeText: 'MOVED',
                badgeColor: FlowColors.accentCyan,
                badgeBg: FlowColors.accentCyan.withValues(alpha: 0.12),
                icon: Icons.sync_alt_rounded,
                subtext: t.reason ?? 'Shifted to accommodate schedule change',
              )),
          const SizedBox(height: 10),
        ],

        // 3. Fixed & Unchanged Tasks
        if (diff.unchangedTasks.isNotEmpty) ...[
          _buildSectionHeader('Fixed & Unchanged Tasks', FlowColors.accentAmber),
          ...diff.unchangedTasks.map((t) {
            final isFixed = t.isFixed || t.isCommitment;
            return _buildDiffItemCard(
              title: t.title,
              timeChange: t.changeLabel,
              badgeText: isFixed ? '🔒 FIXED · UNCHANGED' : 'UNCHANGED',
              badgeColor: FlowColors.accentAmber,
              badgeBg: FlowColors.accentAmber.withValues(alpha: 0.12),
              icon: isFixed ? Icons.lock_rounded : Icons.check_circle_outline_rounded,
              subtext: isFixed
                  ? 'Unchanged because it is a fixed commitment.'
                  : 'Time remains optimal without adjustments.',
            );
          }),
          const SizedBox(height: 10),
        ],

        // 4. Cancelled Tasks
        if (diff.cancelledTasks.isNotEmpty) ...[
          _buildSectionHeader('Cancelled Tasks', const Color(0xFFEF4444)),
          ...diff.cancelledTasks.map((t) => _buildDiffItemCard(
                title: t.title,
                timeChange: '${t.oldTime ?? '--'} → CANCELLED',
                badgeText: 'CANCELLED',
                badgeColor: const Color(0xFFEF4444),
                badgeBg: const Color(0xFFEF4444).withValues(alpha: 0.12),
                icon: Icons.remove_circle_outline_rounded,
                subtext: t.reason ?? 'Removed from today\'s schedule',
                isCancelled: true,
              )),
          const SizedBox(height: 10),
        ],

        // 5. Unscheduled Tasks
        if (diff.unscheduledTasks.isNotEmpty) ...[
          _buildSectionHeader("DIDN'T FIT TODAY", Colors.orange),
          ...diff.unscheduledTasks.map((t) => _buildDiffItemCard(
                title: t.title,
                // A roll-over is only a PROPOSAL: it is applied only if the user confirms the plan.
                timeChange: t.suggestionStart != null
                    ? 'Proposed: ${DateFormat('EEE, MMM d · h:mm a').format(t.suggestionStart!)}'
                    : 'Could not fit today',
                badgeText: 'UNSCHEDULED',
                badgeColor: Colors.orange,
                badgeBg: Colors.orange.withValues(alpha: 0.12),
                icon: Icons.warning_amber_rounded,
                subtext: t.reason ?? 'There was not enough free time before bedtime',
              )),
        ],

        // 6. Protected (completed / in progress): shown so the user can see they were left alone
        if (diff.skippedImmutable.isNotEmpty) ...[
          _buildSectionHeader('KEPT EXACTLY AS IS', Colors.blueGrey),
          ...diff.skippedImmutable.map((t) => _buildDiffItemCard(
                title: t.title,
                timeChange: t.oldTimeRange ?? t.oldTime ?? '',
                badgeText: 'PROTECTED',
                badgeColor: Colors.blueGrey,
                badgeBg: Colors.blueGrey.withValues(alpha: 0.12),
                icon: Icons.lock_outline_rounded,
                subtext: t.reason ?? 'Not changed',
              )),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        title,
        style: FlowTypography.labelSmall(color: color).copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildDiffItemCard({
    required String title,
    required String timeChange,
    required String badgeText,
    required Color badgeColor,
    required Color badgeBg,
    required IconData icon,
    required String subtext,
    bool isCancelled = false,
    VoidCallback? onEdit,
    Key? editKey,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: badgeColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: isCancelled ? TextDecoration.lineThrough : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onEdit != null)
                      InkWell(
                        key: editKey,
                        onTap: onEdit,
                        borderRadius: BorderRadius.circular(FlowRadii.pill),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.edit_rounded, size: 16, color: FlowColors.accentCyan),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(FlowRadii.pill),
                      ),
                      child: Text(
                        badgeText,
                        style: FlowTypography.labelSmall(color: badgeColor).copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  timeChange,
                  style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtext,
                  style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)).copyWith(
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeforeAfterComparison(PlanDiff diff) {
    final beforeList = diff.beforeSchedule;
    final afterList = diff.afterSchedule;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FlowColors.surfaceElevated(context),
            borderRadius: FlowRadii.cardRadius,
            border: Border.all(color: FlowColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Column Headers (Desktop/tablet/normal mobile)
              if (!isNarrow) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'BEFORE',
                        style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: FlowColors.textMutedOf(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AFTER (PROPOSED)',
                        style: FlowTypography.labelSmall(color: FlowColors.accentCyan).copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(height: 1, color: FlowColors.border(context)),
                const SizedBox(height: 8),
              ],

              // Side-by-side or paired comparison
              if (beforeList.isEmpty && afterList.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No events in timeline',
                      style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
                    ),
                  ),
                )
              else ...[
                ...List.generate(
                  beforeList.length > afterList.length ? beforeList.length : afterList.length,
                  (index) {
                    final beforeItem = index < beforeList.length ? beforeList[index] : null;
                    final afterItem = index < afterList.length ? afterList[index] : null;

                    if (isNarrow) {
                      // Narrow Phone Stacked View
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: FlowColors.surface(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: FlowColors.border(context).withValues(alpha: 0.6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'BEFORE: ',
                                  style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9.5,
                                  ),
                                ),
                                Expanded(
                                  child: beforeItem == null
                                      ? Text('—', style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)))
                                      : _buildTimelineCell(
                                          time: '${beforeItem.time} ${beforeItem.period}',
                                          title: beforeItem.title,
                                          isFixed: beforeItem.isFixed,
                                          isCompleted: beforeItem.isCompleted,
                                          color: FlowColors.textSecondaryOf(context),
                                        ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Icon(Icons.arrow_downward_rounded, size: 12, color: FlowColors.textMutedOf(context)),
                            ),
                            Row(
                              children: [
                                Text(
                                  'AFTER: ',
                                  style: FlowTypography.labelSmall(color: FlowColors.accentCyan).copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9.5,
                                  ),
                                ),
                                Expanded(
                                  child: afterItem == null
                                      ? Text('—', style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)))
                                      : _buildTimelineCell(
                                          time: '${afterItem.time} ${afterItem.period}',
                                          title: afterItem.title,
                                          isFixed: afterItem.isFixed,
                                          isCompleted: afterItem.isCompleted,
                                          isNew: !beforeList.any((b) => b.id == afterItem.id || b.title == afterItem.title),
                                          color: afterItem.isFixed ? FlowColors.accentAmber : FlowColors.accentCyan,
                                        ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }

                    // Standard Side-by-Side View
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Before column
                          Expanded(
                            child: beforeItem == null
                                ? Text('—', style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)))
                                : _buildTimelineCell(
                                    time: '${beforeItem.time} ${beforeItem.period}',
                                    title: beforeItem.title,
                                    isFixed: beforeItem.isFixed,
                                    isCompleted: beforeItem.isCompleted,
                                    color: FlowColors.textSecondaryOf(context),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.arrow_forward_rounded, size: 12, color: FlowColors.textMutedOf(context)),
                          ),
                          // After column
                          Expanded(
                            child: afterItem == null
                                ? Text('—', style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)))
                                : _buildTimelineCell(
                                    time: '${afterItem.time} ${afterItem.period}',
                                    title: afterItem.title,
                                    isFixed: afterItem.isFixed,
                                    isCompleted: afterItem.isCompleted,
                                    isNew: !beforeList.any((b) => b.id == afterItem.id || b.title == afterItem.title),
                                    color: afterItem.isFixed
                                        ? FlowColors.accentAmber
                                        : FlowColors.accentCyan,
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimelineCell({
    required String time,
    required String title,
    required Color color,
    bool isFixed = false,
    bool isCompleted = false,
    bool isNew = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              time,
              style: FlowTypography.labelSmall(color: color).copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (isFixed) ...[
              const SizedBox(width: 4),
              const Icon(Icons.lock_rounded, size: 10, color: FlowColors.accentAmber),
            ],
            if (isNew) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'NEW',
                  style: FlowTypography.labelSmall(color: const Color(0xFF10B981)).copyWith(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        Text(
          title,
          style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context)).copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 11,
            decoration: isCompleted ? TextDecoration.lineThrough : null,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // Primary CTA: Apply Changes (Dominant)
            PrimaryButton(
              label: widget.isApplying
                  ? 'Applying Schedule...'
                  : widget.diff.hasUnnamedNewTask
                      ? 'Name the new task to apply'
                      : 'Apply Changes',
              icon: widget.isApplying
                  ? null
                  : const Icon(Icons.check_rounded, color: FlowColors.textInverse, size: 18),
              isLoading: widget.isApplying,
              onPressed: widget.isApplying || widget.diff.hasUnnamedNewTask
                  ? null
                  : () {
                      FlowHaptics.selection();
                      if (widget.onApply != null) {
                        widget.onApply!();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Proposal confirmed. Applying changes...'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
            ),
            const SizedBox(height: 10),
            // Secondary: a conversational nudge to keep talking with Noya (tonal, not an outlined form button)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton.icon(
                key: const Key('plan_diff_adjust_button'),
                onPressed: widget.isApplying
                    ? null
                    : () {
                        FlowHaptics.lightTap();
                        widget.onAdjust?.call();
                      },
                style: TextButton.styleFrom(
                  foregroundColor: FlowColors.accentCyan,
                  backgroundColor: FlowColors.accentCyan.withValues(alpha: 0.10),
                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: Text(
                  'Tell Noya what to change',
                  style: FlowTypography.labelLarge(color: FlowColors.accentCyan).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 2),
            // Tertiary: a calm dismissal, nothing destructive about it
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                key: const Key('plan_diff_keep_button'),
                onPressed: widget.isApplying
                    ? null
                    : () {
                        FlowHaptics.lightTap();
                        widget.onDiscard?.call();
                      },
                child: Text(
                  'Keep current plan',
                  style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A compact, tinted note card: one icon + title, then plain-language bullets.
class _IssueGroupCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> messages;

  const _IssueGroupCard({super.key, required this.title, required this.icon, required this.color, required this.messages});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(FlowRadii.chip),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: FlowTypography.labelMedium(color: color).copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final m in messages)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 2),
              child: Text(m, style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(height: 1.35)),
            ),
        ],
      ),
    );
  }
}
