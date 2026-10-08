import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_theme.dart';
import '../theme/flow_typography.dart';

/// Reusable Date and Time Picker row component with real calendar & clock dialogs.
/// Used by EditTaskSheet, BrainDumpSheet (Build My Day), and AddTaskSheet.
class TaskDateTimePickers extends StatelessWidget {
  final DateTime? selectedDate;
  final TimeOfDay? selectedTime;
  final ValueChanged<DateTime?> onDateChanged;
  final ValueChanged<TimeOfDay?> onTimeChanged;
  final String dateLabel;
  final String timeLabel;
  final Color? accentColor;
  final Key? dateButtonKey;
  final Key? timeButtonKey;
  final Key? clearDateKey;
  final Key? clearTimeKey;

  const TaskDateTimePickers({
    super.key,
    required this.selectedDate,
    required this.selectedTime,
    required this.onDateChanged,
    required this.onTimeChanged,
    this.dateLabel = 'DATE',
    this.timeLabel = 'TIME',
    this.accentColor,
    this.dateButtonKey = const Key('edit_task_date_button'),
    this.timeButtonKey = const Key('edit_task_time_button'),
    this.clearDateKey = const Key('edit_task_clear_date'),
    this.clearTimeKey = const Key('edit_task_clear_time'),
  });

  static String formatDateDisplay(DateTime? date) {
    if (date == null) return 'Pick date';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final comp = DateTime(date.year, date.month, date.day);
    if (comp == today) return 'Today';
    if (comp == today.add(const Duration(days: 1))) return 'Tomorrow';
    return DateFormat('EEE, MMM d').format(date);
  }

  static String formatTimeDisplay(TimeOfDay? time) {
    if (time == null) return 'Pick time';
    final dt = DateTime(2026, 1, 1, time.hour, time.minute);
    return DateFormat('h:mm a').format(dt);
  }

  static TimeOfDay? parseTimeString(String? str) {
    if (str == null || str.isEmpty || str == 'No fixed time' || str == 'Pick time') return null;
    try {
      final dt = DateFormat('h:mm a').parseLoose(str.trim());
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {
      try {
        final parts = str.trim().split(RegExp(r'[:\s]'));
        if (parts.length >= 2) {
          int h = int.parse(parts[0]);
          int m = int.parse(parts[1]);
          if (str.toUpperCase().contains('PM') && h < 12) h += 12;
          if (str.toUpperCase().contains('AM') && h == 12) h = 0;
          return TimeOfDay(hour: h, minute: m);
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<DateTime?> pickDate(
    BuildContext context, {
    DateTime? initialDate,
    Color? accentColor,
  }) async {
    FlowHaptics.lightTap();
    final now = DateTime.now();
    final init = initialDate ?? now;
    final first = init.isBefore(now.subtract(const Duration(days: 365)))
        ? init.subtract(const Duration(days: 30))
        : now.subtract(const Duration(days: 365));
    final last = init.isAfter(now.add(const Duration(days: 730)))
        ? init.add(const Duration(days: 365))
        : now.add(const Duration(days: 730));
    final themeColor = accentColor ?? FlowColors.mint;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
      helpText: 'Select Task Date',
      cancelText: 'Cancel',
      confirmText: 'Done',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: themeColor,
                    onPrimary: FlowColors.textInverse,
                    surface: FlowColors.surfaceElevatedDark,
                    onSurface: FlowColors.textPrimaryDark,
                  )
                : ColorScheme.light(
                    primary: themeColor,
                    onPrimary: FlowColors.textInverse,
                    surface: FlowColors.surfaceLight,
                    onSurface: FlowColors.textPrimaryLight,
                  ),
            datePickerTheme: FlowTheme.buildDatePickerTheme(isDark, themeColor),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  static Future<TimeOfDay?> pickTime(
    BuildContext context, {
    TimeOfDay? initialTime,
    Color? accentColor,
  }) async {
    FlowHaptics.lightTap();
    final themeColor = accentColor ?? FlowColors.mint;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showTimePicker(
      context: context,
      initialTime: initialTime ?? const TimeOfDay(hour: 10, minute: 0),
      helpText: 'Select Start Time',
      cancelText: 'Cancel',
      confirmText: 'Done',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: themeColor,
                    onPrimary: FlowColors.textInverse,
                    surface: FlowColors.surfaceElevatedDark,
                    onSurface: FlowColors.textPrimaryDark,
                  )
                : ColorScheme.light(
                    primary: themeColor,
                    onPrimary: FlowColors.textInverse,
                    surface: FlowColors.surfaceLight,
                    onSurface: FlowColors.textPrimaryLight,
                  ),
            timePickerTheme: FlowTheme.buildTimePickerTheme(isDark, themeColor),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeAccent = accentColor ?? FlowColors.mint;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // DATE BUTTON
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateLabel,
                style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                key: dateButtonKey,
                onTap: () async {
                  final picked = await pickDate(
                    context,
                    initialDate: selectedDate,
                    accentColor: activeAccent,
                  );
                  if (picked != null) {
                    onDateChanged(picked);
                  }
                },
                borderRadius: BorderRadius.circular(FlowRadii.button),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selectedDate != null
                        ? activeAccent.withValues(alpha: isDark ? 0.12 : 0.08)
                        : (isDark
                            ? FlowColors.surface(context)
                            : FlowColors.surfaceElevated(context)),
                    borderRadius: BorderRadius.circular(FlowRadii.button),
                    border: Border.all(
                      color: selectedDate != null
                          ? activeAccent.withValues(alpha: 0.7)
                          : FlowColors.border(context),
                      width: selectedDate != null ? 1.2 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: selectedDate != null
                              ? activeAccent.withValues(alpha: isDark ? 0.22 : 0.15)
                              : (isDark
                                  ? FlowColors.surfaceContainerDark
                                  : FlowColors.surfaceContainerLight),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.calendar_today_rounded,
                          size: 14,
                          color: selectedDate != null ? activeAccent : FlowColors.textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          formatDateDisplay(selectedDate),
                          style: FlowTypography.bodySmall(
                            color: selectedDate != null
                                ? FlowColors.textPrimaryOf(context)
                                : FlowColors.textMutedOf(context),
                          ).copyWith(
                            fontWeight: selectedDate != null ? FontWeight.w700 : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selectedDate != null)
                        GestureDetector(
                          key: clearDateKey,
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            FlowHaptics.lightTap();
                            onDateChanged(null);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: FlowColors.textMutedOf(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),

        // TIME BUTTON
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeLabel,
                style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                key: timeButtonKey,
                onTap: () async {
                  final picked = await pickTime(
                    context,
                    initialTime: selectedTime,
                    accentColor: activeAccent,
                  );
                  if (picked != null) {
                    onTimeChanged(picked);
                  }
                },
                borderRadius: BorderRadius.circular(FlowRadii.button),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selectedTime != null
                        ? activeAccent.withValues(alpha: isDark ? 0.12 : 0.08)
                        : (isDark
                            ? FlowColors.surface(context)
                            : FlowColors.surfaceElevated(context)),
                    borderRadius: BorderRadius.circular(FlowRadii.button),
                    border: Border.all(
                      color: selectedTime != null
                          ? activeAccent.withValues(alpha: 0.7)
                          : FlowColors.border(context),
                      width: selectedTime != null ? 1.2 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: selectedTime != null
                              ? activeAccent.withValues(alpha: isDark ? 0.22 : 0.15)
                              : (isDark
                                  ? FlowColors.surfaceContainerDark
                                  : FlowColors.surfaceContainerLight),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.access_time_rounded,
                          size: 15,
                          color: selectedTime != null ? activeAccent : FlowColors.textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          formatTimeDisplay(selectedTime),
                          style: FlowTypography.bodySmall(
                            color: selectedTime != null
                                ? FlowColors.textPrimaryOf(context)
                                : FlowColors.textMutedOf(context),
                          ).copyWith(
                            fontWeight: selectedTime != null ? FontWeight.w700 : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selectedTime != null)
                        GestureDetector(
                          key: clearTimeKey,
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            FlowHaptics.lightTap();
                            onTimeChanged(null);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: FlowColors.textMutedOf(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
