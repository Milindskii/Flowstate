import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_motion.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';

/// Full-month day picker for the Calendar, opened from the header's calendar button.
///
/// Same visual language as [FlowDateStrip]: surface chips with a hairline border, the accent fill for the
/// selected day and the accent dot for today. A small dot under a day marks one that has tasks the app already
/// has in memory (no extra request is made to draw the month).
///
/// Returns the chosen day through [Navigator.pop], or null when dismissed.
Future<DateTime?> showFlowMonthPicker(
  BuildContext context, {
  required DateTime selected,
  required DateTime today,
  Set<DateTime> daysWithTasks = const {},
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
    ),
    builder: (_) => FlowMonthPicker(selected: selected, today: today, daysWithTasks: daysWithTasks),
  );
}

class FlowMonthPicker extends StatefulWidget {
  final DateTime selected;
  final DateTime today;
  final Set<DateTime> daysWithTasks;

  /// How far the month can be paged either way.
  static const int monthRange = 24;

  const FlowMonthPicker({
    super.key,
    required this.selected,
    required this.today,
    this.daysWithTasks = const {},
  });

  @override
  State<FlowMonthPicker> createState() => _FlowMonthPickerState();
}

class _FlowMonthPickerState extends State<FlowMonthPicker> {
  late DateTime _month; // first day of the shown month
  late DateTime _picked;
  bool _forward = true;

  DateTime get _todayMonth => DateTime(widget.today.year, widget.today.month);

  @override
  void initState() {
    super.initState();
    _picked = _day(widget.selected);
    _month = DateTime(_picked.year, _picked.month);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  int _offsetOf(DateTime month) => (month.year - _todayMonth.year) * 12 + month.month - _todayMonth.month;

  bool get _canBack => _offsetOf(_month) > -FlowMonthPicker.monthRange;
  bool get _canForward => _offsetOf(_month) < FlowMonthPicker.monthRange;

  void _page(int delta) {
    FlowHaptics.selection();
    setState(() {
      _forward = delta > 0;
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  void _goToday() {
    FlowHaptics.selection();
    setState(() {
      _forward = !_todayMonth.isBefore(_month);
      _month = _todayMonth;
      _picked = _day(widget.today);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final margin = FlowSpacing.pageMargin(context);
    final picked = _picked;
    final hasTasks = widget.daysWithTasks.contains(picked);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(margin, 10, margin, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: FlowColors.border(context), borderRadius: FlowRadii.pillRadius),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_month),
                    key: const Key('month_picker_title'),
                    style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_month != _todayMonth || picked != _day(widget.today))
                  TextButton(
                    key: const Key('month_picker_today'),
                    onPressed: _goToday,
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      minimumSize: const Size(48, 44),
                      textStyle: FlowTypography.labelMedium().copyWith(fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Today'),
                  ),
                _NavButton(
                  key: const Key('month_picker_prev'),
                  icon: Icons.chevron_left_rounded,
                  label: 'Previous month',
                  onTap: _canBack ? () => _page(-1) : null,
                ),
                _NavButton(
                  key: const Key('month_picker_next'),
                  icon: Icons.chevron_right_rounded,
                  label: 'Next month',
                  onTap: _canForward ? () => _page(1) : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: Row(
                children: [
                  for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                    Expanded(
                      child: Center(
                        child: Text(d, style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context))),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: FlowMotion.responsiveDuration(context, FlowMotion.screenDuration),
              switchInCurve: FlowMotion.easeOut,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: Offset(_forward ? 0.06 : -0.06, 0), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: _MonthGrid(
                key: ValueKey<DateTime>(_month),
                month: _month,
                today: _day(widget.today),
                picked: picked,
                daysWithTasks: widget.daysWithTasks,
                onPick: (d) {
                  FlowHaptics.selection();
                  setState(() => _picked = d);
                },
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${DateFormat('EEEE, MMMM d').format(picked)}${hasTasks ? ' · has tasks' : ''}',
              key: const Key('month_picker_summary'),
              style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: FlowSpacing.buttonHeight,
              child: FilledButton(
                key: const Key('month_picker_go'),
                onPressed: () {
                  FlowHaptics.lightTap();
                  Navigator.of(context).pop(picked);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: FlowColors.textInverse,
                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                  textStyle: FlowTypography.buttonPrimary(),
                ),
                child: const Text('Go to day'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _NavButton({super.key, required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(icon, color: onTap == null ? FlowColors.textMutedOf(context) : FlowColors.textPrimaryOf(context)),
      );
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final DateTime picked;
  final Set<DateTime> daysWithTasks;
  final ValueChanged<DateTime> onPick;

  const _MonthGrid({
    super.key,
    required this.month,
    required this.today,
    required this.picked,
    required this.daysWithTasks,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday-first
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return Column(
      children: [
        for (var row = 0; row < cells.length ~/ 7; row++)
          Row(
            children: [
              for (final day in cells.sublist(row * 7, row * 7 + 7))
                Expanded(
                  child: day == null
                      ? const SizedBox(height: 48)
                      : _DayCell(
                          day: day,
                          isToday: day == today,
                          isPicked: day == picked,
                          isPast: day.isBefore(today),
                          hasTasks: daysWithTasks.contains(day),
                          onTap: () => onPick(day),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final bool isPicked;
  final bool isPast;
  final bool hasTasks;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isPicked,
    required this.isPast,
    required this.hasTasks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final fg = isPicked
        ? FlowColors.textInverse
        : (isPast ? FlowColors.textMutedOf(context) : FlowColors.textPrimaryOf(context));
    final dot = isPicked ? FlowColors.textInverse : (isToday ? accent : FlowColors.textMutedOf(context));
    return Semantics(
      button: true,
      selected: isPicked,
      label: '${isToday ? 'Today, ' : ''}${DateFormat('EEEE MMMM d').format(day)}${hasTasks ? ', has tasks' : ''}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        key: Key('month_day_${DateFormat('yyyy-MM-dd').format(day)}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: FlowMotion.responsiveDuration(context, FlowMotion.microDuration),
              curve: FlowMotion.easeOut,
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isPicked ? accent : Colors.transparent,
                borderRadius: FlowRadii.chipRadius,
                border: Border.all(
                  color: isPicked ? accent : (isToday ? accent.withValues(alpha: 0.6) : Colors.transparent),
                  width: 1.2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: FlowTypography.labelLarge(color: fg).copyWith(
                      fontWeight: isPicked || isToday ? FontWeight.w700 : FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasTasks ? dot : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
