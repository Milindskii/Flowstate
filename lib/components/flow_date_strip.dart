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

  const FlowDateStrip({
    super.key,
    required this.days,
    required this.selected,
    required this.today,
    required this.onSelect,
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
  ///
  /// Layout is only valid until the scroll position moves: `jumpTo` marks the strip for a new layout, and a render
  /// box that needs layout has no trustworthy size or position. So the first-show jump is its own step, and the
  /// visibility check runs on the next frame, against boxes that have been laid out again.
  void _revealSelected(Duration duration) {
    if (!mounted) return;
    if (duration == Duration.zero && _alignTodayOnFirstShow()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _keepSelectedVisible(Duration.zero));
      return;
    }
    _keepSelectedVisible(duration);
  }

  /// A laid-out render box, or null when there is none yet (not built, detached, or not laid out).
  static RenderBox? _laidOut(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// First show: today sits second from the left — one day of history in view, the days ahead filling the rest, and
  /// earlier history a scroll back. Returns true when it moved the strip (the caller must wait for a new layout).
  bool _alignTodayOnFirstShow() {
    final chipContext = _selectedChipKey.currentContext;
    final anchor = _laidOut(_todayChipKey.currentContext ?? chipContext);
    final scrollable = chipContext == null ? null : Scrollable.maybeOf(chipContext);
    final scrollBox = _laidOut(scrollable?.context);
    if (anchor == null || scrollBox == null || scrollable == null) return false;
    final position = scrollable.position;
    final anchorLeft = anchor.localToGlobal(Offset.zero, ancestor: scrollBox).dx;
    final target = (position.pixels + anchorLeft - anchor.size.width).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return false;
    position.jumpTo(target);
    return true;
  }

  void _keepSelectedVisible(Duration duration) {
    if (!mounted) return;
    final chipContext = _selectedChipKey.currentContext;
    final chipBox = _laidOut(chipContext);
    final scrollBox = _laidOut(chipContext == null ? null : Scrollable.maybeOf(chipContext)?.context);
    if (chipContext == null || chipBox == null || scrollBox == null) return;

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

    final Key chipKey;
    final String accessibilityLabel;
    if (isYesterday) {
      chipKey = const Key('calendar_day_chip_yesterday');
      accessibilityLabel = 'Yesterday ${DateFormat('MMMM d').format(day)}';
    } else if (isToday) {
      chipKey = const Key('calendar_day_chip_today');
      accessibilityLabel = 'Today ${DateFormat('MMMM d').format(day)}';
    } else if (isTomorrow) {
      chipKey = const Key('calendar_day_chip_tomorrow');
      accessibilityLabel = 'Tomorrow ${DateFormat('MMMM d').format(day)}';
    } else {
      chipKey = Key('calendar_day_chip_${DateFormat('yyyy-MM-dd').format(day)}');
      accessibilityLabel = DateFormat('EEEE MMMM d').format(day);
    }

    void select() {
      FlowHaptics.selection();
      widget.onSelect(day);
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
                child: AnimatedContainer(
                  duration: FlowMotion.responsiveDuration(context, FlowMotion.microDuration),
                  curve: FlowMotion.easeOut,
                  constraints: const BoxConstraints(minWidth: 46),
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
                  decoration: BoxDecoration(
                    color: isSelected ? accent : FlowColors.surface(context),
                    borderRadius: FlowRadii.chipRadius,
                    border: Border.all(color: isSelected ? accent : FlowColors.border(context), width: 1.0),
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
                      Container(
                        key: isToday ? const Key('calendar_today_marker') : null,
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isToday ? (isSelected ? FlowColors.textInverse : accent) : Colors.transparent,
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
