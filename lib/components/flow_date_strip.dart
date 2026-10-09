import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_motion.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Horizontal day picker for Calendar (spec B2.1, §8.3).
///
/// Chips show the weekday over the day number. Today keeps a small accent dot in every
/// selection state, a month abbreviation sits above the first chip of each month, and the
/// selected chip scrolls fully into view whenever the selection changes.
class FlowDateStrip extends StatefulWidget {
  final List<DateTime> days;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;
  final Set<DateTime> daysWithTasks;
  final ValueChanged<DateTime>? onCustomizeDate;

  const FlowDateStrip({
    super.key,
    required this.days,
    required this.selected,
    required this.today,
    required this.onSelect,
    this.daysWithTasks = const {},
    this.onCustomizeDate,
  });

  @override
  State<FlowDateStrip> createState() => _FlowDateStripState();
}

class _FlowDateStripState extends State<FlowDateStrip> {
  final GlobalKey _selectedChipKey = GlobalKey();
  final GlobalKey _todayChipKey = GlobalKey();

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected(Duration.zero));
  }

  @override
  void didUpdateWidget(FlowDateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDay(oldWidget.selected, widget.selected)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected(FlowMotion.screenDuration));
    }
  }

  /// Scrolls only as far as needed to show the whole selected chip.
  void _revealSelected(Duration duration) {
    if (!mounted) return;
    final chipContext = _selectedChipKey.currentContext;
    if (chipContext == null) return;
    final chipBox = chipContext.findRenderObject() as RenderBox?;
    final scrollBox = Scrollable.maybeOf(chipContext)?.context.findRenderObject() as RenderBox?;
    if (chipBox == null || scrollBox == null || !chipBox.hasSize || !scrollBox.hasSize) return;

    if (duration == Duration.zero) {
      // First show: today sits second from the left — one day of history in view, the days
      // ahead filling the rest, and earlier history a scroll back.
      final anchor = (_todayChipKey.currentContext ?? chipContext).findRenderObject() as RenderBox?;
      if (anchor != null && anchor.hasSize) {
        final position = Scrollable.of(chipContext).position;
        final anchorLeft = anchor.localToGlobal(Offset.zero, ancestor: scrollBox).dx;
        position.jumpTo((position.pixels + anchorLeft - anchor.size.width).clamp(position.minScrollExtent, position.maxScrollExtent));
      }
    }

    final left = chipBox.localToGlobal(Offset.zero, ancestor: scrollBox).dx;
    final right = left + chipBox.size.width;
    final ScrollPositionAlignmentPolicy policy;
    if (left < 0) {
      policy = ScrollPositionAlignmentPolicy.keepVisibleAtStart;
    } else if (right > scrollBox.size.width) {
      policy = ScrollPositionAlignmentPolicy.keepVisibleAtEnd;
    } else {
      return;
    }
    Scrollable.ensureVisible(
      chipContext,
      duration: FlowMotion.responsiveDuration(context, duration),
      curve: FlowMotion.easeOut,
      alignmentPolicy: policy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < days.length; i++) _buildDay(context, days[i], showMonth: i == 0 || days[i].month != days[i - 1].month),
        ],
      ),
    );
  }

  Widget _buildDay(BuildContext context, DateTime day, {required bool showMonth}) {
    final accent = Theme.of(context).colorScheme.primary;
    final today = widget.today;
    final isSelected = _sameDay(day, widget.selected);
    final isToday = _sameDay(day, today);
    final isYesterday = _sameDay(day, today.subtract(const Duration(days: 1)));
    final isTomorrow = _sameDay(day, today.add(const Duration(days: 1)));

    final hasTasks = widget.daysWithTasks.any((d) => _sameDay(d, day));

    final Key chipKey;
    final String accessibilityLabel;
    final taskSuffix = hasTasks ? ', has tasks' : '';
    if (isYesterday) {
      chipKey = const Key('calendar_day_chip_yesterday');
      accessibilityLabel = 'Yesterday ${DateFormat('MMMM d').format(day)}$taskSuffix';
    } else if (isToday) {
      chipKey = const Key('calendar_day_chip_today');
      accessibilityLabel = 'Today ${DateFormat('MMMM d').format(day)}$taskSuffix';
    } else if (isTomorrow) {
      chipKey = const Key('calendar_day_chip_tomorrow');
      accessibilityLabel = 'Tomorrow ${DateFormat('MMMM d').format(day)}$taskSuffix';
    } else {
      chipKey = Key('calendar_day_chip_${DateFormat('yyyy-MM-dd').format(day)}');
      accessibilityLabel = '${DateFormat('EEEE MMMM d').format(day)}$taskSuffix';
    }

    void select() {
      FlowHaptics.selection();
      if (isSelected && widget.onCustomizeDate != null) {
        widget.onCustomizeDate!(day);
      } else {
        widget.onSelect(day);
      }
    }

    void customize() {
      FlowHaptics.lightTap();
      if (widget.onCustomizeDate != null) {
        widget.onCustomizeDate!(day);
      } else {
        widget.onSelect(day);
      }
    }

    final foreground = isSelected ? FlowColors.textInverse : FlowColors.textPrimaryOf(context);
    final monthStyle = FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(fontWeight: FontWeight.w700);

    return KeyedSubtree(
      key: isToday ? _todayChipKey : null,
      child: Padding(
        key: isSelected ? _selectedChipKey : null,
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Every day reserves the label line so chips stay aligned.
            ExcludeSemantics(
              child: showMonth
                  ? Text(
                      DateFormat('MMM').format(day),
                      key: Key('calendar_month_label_${DateFormat('yyyy-MM').format(day)}'),
                      style: monthStyle,
                    )
                  : Text(' ', style: monthStyle),
            ),
            const SizedBox(height: 4),
            Semantics(
              button: true,
              selected: isSelected,
              label: accessibilityLabel,
              onTap: select,
              excludeSemantics: true,
              child: GestureDetector(
                key: chipKey,
                onTap: select,
                onLongPress: customize,
                child: AnimatedContainer(
                  duration: FlowMotion.responsiveDuration(context, FlowMotion.microDuration),
                  curve: FlowMotion.easeOut,
                  constraints: const BoxConstraints(minWidth: 46),
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
                  decoration: BoxDecoration(
                    color: isSelected ? accent : FlowColors.surface(context),
                    borderRadius: FlowRadii.chipRadius,
                    border: Border.all(
                      color: isSelected
                          ? accent
                          : (isToday ? accent.withValues(alpha: 0.55) : FlowColors.border(context)),
                      width: isToday && !isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('E').format(day),
                        style: FlowTypography.labelSmall(
                          color: isSelected ? FlowColors.textInverse : FlowColors.textSecondaryOf(context),
                        ).copyWith(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: FlowTypography.titleSmall(color: foreground).copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Dot button showing that there is task in this date, with customization on click
                      Semantics(
                        button: true,
                        label: hasTasks ? 'Tasks on ${DateFormat('MMMM d').format(day)}' : null,
                        child: GestureDetector(
                          key: Key('calendar_dot_button_${DateFormat('yyyy-MM-dd').format(day)}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: customize,
                          child: Container(
                            key: isToday ? const Key('calendar_today_marker') : null,
                            width: 14,
                            height: 9,
                            alignment: Alignment.center,
                            child: AnimatedContainer(
                              duration: FlowMotion.responsiveDuration(context, FlowMotion.microDuration),
                              curve: FlowMotion.easeOut,
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hasTasks
                                    ? (isSelected ? FlowColors.textInverse : accent)
                                    : (isToday && widget.daysWithTasks.isEmpty
                                        ? (isSelected ? FlowColors.textInverse : accent)
                                        : Colors.transparent),
                                border: isToday && !hasTasks && widget.daysWithTasks.isNotEmpty
                                    ? Border.all(
                                        color: isSelected
                                            ? FlowColors.textInverse.withValues(alpha: 0.8)
                                            : accent.withValues(alpha: 0.7),
                                        width: 1.2,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
