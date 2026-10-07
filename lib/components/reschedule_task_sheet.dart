import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';
import 'task_date_time_pickers.dart';

/// Premium, intentional bottom sheet for rescheduling a task.
/// Reuses [TaskDateTimePickers] to ensure complete visual and architectural consistency.
class RescheduleTaskSheet extends StatefulWidget {
  final TaskItem task;

  const RescheduleTaskSheet({
    super.key,
    required this.task,
  });

  static Future<void> show(BuildContext context, TaskItem task) {
    FlowHaptics.lightTap();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
      ),
      builder: (_) => RescheduleTaskSheet(task: task),
    );
  }

  @override
  State<RescheduleTaskSheet> createState() => _RescheduleTaskSheetState();
}

class _RescheduleTaskSheetState extends State<RescheduleTaskSheet> {
  late DateTime _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default date is today (or existing task date if in future)
    if (widget.task.scheduledStart != null) {
      _selectedDate = DateTime(
        widget.task.scheduledStart!.year,
        widget.task.scheduledStart!.month,
        widget.task.scheduledStart!.day,
      );
      _selectedTime = TimeOfDay(
        hour: widget.task.scheduledStart!.hour,
        minute: widget.task.scheduledStart!.minute,
      );
    } else if (widget.task.deadlineAt != null) {
      _selectedDate = DateTime(
        widget.task.deadlineAt!.year,
        widget.task.deadlineAt!.month,
        widget.task.deadlineAt!.day,
      );
      _selectedTime = TaskDateTimePickers.parseTimeString(widget.task.scheduledTime);
    } else {
      _selectedDate = DateTime(now.year, now.month, now.day);
      _selectedTime = TaskDateTimePickers.parseTimeString(widget.task.scheduledTime);
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  bool get _isTomorrow {
    final now = DateTime.now().add(const Duration(days: 1));
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  void _selectToday() {
    FlowHaptics.lightTap();
    final now = DateTime.now();
    setState(() {
      _selectedDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _selectTomorrow() {
    FlowHaptics.lightTap();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    setState(() {
      _selectedDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    });
  }

  void _selectNoFixedTime() {
    FlowHaptics.lightTap();
    setState(() {
      _selectedTime = null;
    });
  }

  Future<void> _handleConfirm() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    FlowHaptics.success();

    final state = Provider.of<AppStateProvider>(context, listen: false);

    final saved = await state.rescheduleTask(
      widget.task.id,
      targetDate: _selectedDate,
      targetTime: _selectedTime,
    );

    if (mounted) {
      Navigator.of(context).pop();

      if (!saved) {
        // The server did not accept the change and the app reverted it: say so instead of claiming success.
        final reason = state.lastSyncError ?? "Couldn't reschedule \u201c${widget.task.title}\u201d. Nothing was changed.";
        state.clearSyncError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reason),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final String dateLabel = _isToday
          ? 'today'
          : (_isTomorrow ? 'tomorrow' : DateFormat('EEE, MMM d').format(_selectedDate));
      final String timeLabel = _selectedTime != null
          ? ' at ${TaskDateTimePickers.formatTimeDisplay(_selectedTime)}'
          : '';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rescheduled "${widget.task.title}" to $dateLabel$timeLabel'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = FlowColors.accentCyan;

    return SafeArea(
      key: const Key('reschedule_task_sheet'),
      child: Padding(
        padding: EdgeInsets.only(
          left: FlowSpacing.pageMargin(context),
          right: FlowSpacing.pageMargin(context),
          top: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: FlowColors.border(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row: Title & Close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(FlowRadii.chip),
                      ),
                      child: const Icon(Icons.event_repeat_rounded, size: 18, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Reschedule Task',
                      style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  key: const Key('reschedule_close_button'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: FlowColors.textMutedOf(context),
                  splashRadius: 18,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Task Summary Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: FlowColors.surfaceElevated(context),
                borderRadius: FlowRadii.inputRadius,
                border: Border.all(color: FlowColors.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.task.title,
                    style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.task.durationMinutes} min · ${widget.task.difficulty.tagText} · Current: ${widget.task.deadline}',
                    style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Date Quick Selection Chips
            Text(
              'DATE',
              style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildQuickChip(
                  key: const Key('reschedule_chip_today'),
                  label: 'Today',
                  isSelected: _isToday,
                  accent: accent,
                  onTap: _selectToday,
                ),
                const SizedBox(width: 8),
                _buildQuickChip(
                  key: const Key('reschedule_chip_tomorrow'),
                  label: 'Tomorrow',
                  isSelected: _isTomorrow,
                  accent: accent,
                  onTap: _selectTomorrow,
                ),
                const SizedBox(width: 8),
                _buildQuickChip(
                  key: const Key('reschedule_chip_custom_date'),
                  label: !_isToday && !_isTomorrow
                      ? DateFormat('MMM d').format(_selectedDate)
                      : 'Pick Date',
                  isSelected: !_isToday && !_isTomorrow,
                  accent: accent,
                  onTap: () async {
                    final picked = await TaskDateTimePickers.pickDate(
                      context,
                      initialDate: _selectedDate,
                      accentColor: accent,
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Time Quick Selection Chips
            Text(
              'TIME',
              style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildQuickChip(
                  key: const Key('reschedule_chip_no_fixed_time'),
                  label: 'No fixed time',
                  isSelected: _selectedTime == null,
                  accent: accent,
                  onTap: _selectNoFixedTime,
                ),
                const SizedBox(width: 8),
                _buildQuickChip(
                  key: const Key('reschedule_chip_morning'),
                  label: '9:30 AM',
                  isSelected: _selectedTime?.hour == 9 && _selectedTime?.minute == 30,
                  accent: accent,
                  onTap: () {
                    FlowHaptics.lightTap();
                    setState(() => _selectedTime = const TimeOfDay(hour: 9, minute: 30));
                  },
                ),
                const SizedBox(width: 8),
                _buildQuickChip(
                  key: const Key('reschedule_chip_afternoon'),
                  label: '2:00 PM',
                  isSelected: _selectedTime?.hour == 14 && _selectedTime?.minute == 0,
                  accent: accent,
                  onTap: () {
                    FlowHaptics.lightTap();
                    setState(() => _selectedTime = const TimeOfDay(hour: 14, minute: 0));
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Shared TaskDateTimePickers Row (Reused from Build My Day / Edit Task)
            TaskDateTimePickers(
              selectedDate: _selectedDate,
              selectedTime: _selectedTime,
              dateLabel: 'CALENDAR DATE',
              timeLabel: 'CLOCK TIME',
              accentColor: accent,
              dateButtonKey: const Key('reschedule_date_picker_button'),
              timeButtonKey: const Key('reschedule_time_picker_button'),
              clearDateKey: const Key('reschedule_clear_date_button'),
              clearTimeKey: const Key('reschedule_clear_time_button'),
              onDateChanged: (newDate) {
                if (newDate != null) {
                  setState(() => _selectedDate = newDate);
                }
              },
              onTimeChanged: (newTime) {
                setState(() => _selectedTime = newTime);
              },
            ),
            const SizedBox(height: 24),

            // Actions: Cancel & Reschedule
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      key: const Key('reschedule_cancel_button'),
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: FlowColors.textSecondaryOf(context),
                        side: BorderSide(color: FlowColors.border(context)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(FlowRadii.button),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      key: const Key('reschedule_confirm_button'),
                      onPressed: _isSubmitting ? null : _handleConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: FlowColors.textInverse,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(FlowRadii.button),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Confirm Reschedule',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip({
    required Key key,
    required String label,
    required bool isSelected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final context = this.context;
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(FlowRadii.chip),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.15) : FlowColors.surfaceElevated(context),
          borderRadius: BorderRadius.circular(FlowRadii.chip),
          border: Border.all(
            color: isSelected ? accent : FlowColors.border(context),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: FlowTypography.labelMedium(
            color: isSelected ? accent : FlowColors.textSecondaryOf(context),
          ).copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
