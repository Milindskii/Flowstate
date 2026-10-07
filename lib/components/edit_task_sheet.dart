import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import '../utils/commitment_window.dart';
import 'task_date_time_pickers.dart';
import 'task_interactive_controls.dart';

/// Modal sheet for editing task details, including date, time, duration, and priority.
class EditTaskSheet extends StatefulWidget {
  final TaskItem task;

  const EditTaskSheet({super.key, required this.task});

  static Future<void> show(BuildContext context, TaskItem task) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
      ),
      builder: (_) => EditTaskSheet(task: task),
    );
  }

  @override
  State<EditTaskSheet> createState() => _EditTaskSheetState();
}

class _EditTaskSheetState extends State<EditTaskSheet> {
  late TextEditingController _titleController;
  late TextEditingController _deadlineController;
  late TaskType _selectedType;
  late int _durationMinutes;
  late bool _isPriority;
  late TaskPriority _selectedPriority;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  TimeOfDay? _endTime;
  bool _isSaving = false;
  String? _commitmentError;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task.title);
    _deadlineController = TextEditingController(text: task.deadline);
    _selectedType = task.taskType;
    _durationMinutes = task.durationMinutes > 0 ? task.durationMinutes : 25;
    _isPriority = task.isPriority;
    _selectedPriority = task.priority ?? (task.isPriority ? TaskPriority.high : TaskPriority.medium);

    if (task.isCommitment && task.scheduledEnd != null) {
      _endTime = TimeOfDay(hour: task.scheduledEnd!.hour, minute: task.scheduledEnd!.minute);
    }

    if (task.scheduledStart != null) {
      _selectedDate = DateTime(
        task.scheduledStart!.year,
        task.scheduledStart!.month,
        task.scheduledStart!.day,
      );
      _selectedTime = TimeOfDay(
        hour: task.scheduledStart!.hour,
        minute: task.scheduledStart!.minute,
      );
    } else if (task.deadlineAt != null) {
      _selectedDate = task.deadlineAt;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _deadlineController.dispose();
    super.dispose();
  }

  Future<void> _saveCommitment() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _selectedDate == null || _selectedTime == null || _endTime == null) {
      setState(() => _commitmentError = 'Add a title, a date, and both start and end times.');
      return;
    }
    final d = _selectedDate!;
    final start = DateTime(d.year, d.month, d.day, _selectedTime!.hour, _selectedTime!.minute);
    final end = commitmentEnd(d, _selectedTime!, _endTime!);
    if (end.difference(start) > maxCommitmentSpan) {
      setState(() => _commitmentError = 'That would run for more than 12 hours. Check the end time.');
      return;
    }
    setState(() => _isSaving = true);
    FlowHaptics.selection();
    final updated = widget.task.copyWith(
      title: title,
      scheduledStart: start,
      scheduledEnd: end,
      durationMinutes: end.difference(start).inMinutes,
      scheduledTime: DateFormat('h:mm a').format(start),
      timeLocked: true,
      isCommitment: true,
    );
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    appState.updateTask(updated);
    if (!appState.isDemoMode) {
      appState.refreshTodayData().catchError((_) {});
    }
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${updated.title}" updated.'),
          duration: const Duration(seconds: 2),
          backgroundColor: FlowColors.surfaceElevated(context),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildCommitmentBody(BuildContext context) {
    final muted = FlowColors.textMutedOf(context);
    final label = FlowTypography.labelSmall(color: muted).copyWith(letterSpacing: 0.5, fontWeight: FontWeight.w700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lock_rounded, size: 16, color: FlowColors.textSecondaryOf(context)),
            const SizedBox(width: 6),
            Text(
              'Fixed commitment',
              key: const Key('commitment_badge'),
              style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Protected time — Flowstate plans your work around it.', style: FlowTypography.bodySmall(color: muted)),
        const SizedBox(height: 16),
        Text('TITLE', style: label),
        const SizedBox(height: 4),
        _titleField(context),
        const SizedBox(height: 12),
        TaskDateTimePickers(
          selectedDate: _selectedDate,
          selectedTime: _selectedTime,
          timeLabel: 'STARTS',
          onDateChanged: (d) => setState(() {
            _selectedDate = d;
            _commitmentError = null;
          }),
          onTimeChanged: (t) => setState(() {
            _selectedTime = t;
            _commitmentError = null;
          }),
        ),
        const SizedBox(height: 12),
        Text('ENDS', style: label),
        const SizedBox(height: 4),
        InkWell(
          key: const Key('commitment_end_time_button'),
          borderRadius: BorderRadius.circular(FlowRadii.inputField),
          onTap: () async {
            final t = await TaskDateTimePickers.pickTime(context, initialTime: _endTime ?? _selectedTime);
            if (t != null) {
              setState(() {
                _endTime = t;
                _commitmentError = null;
              });
            }
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
                Icon(Icons.schedule_rounded, size: 18, color: muted),
                const SizedBox(width: 8),
                Text(
                  TaskDateTimePickers.formatTimeDisplay(_endTime),
                  style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)),
                ),
              ],
            ),
          ),
        ),
        if (_selectedDate != null && _selectedTime != null && _endTime != null &&
            commitmentEnd(_selectedDate!, _selectedTime!, _endTime!).day != _selectedDate!.day) ...[
          const SizedBox(height: 6),
          Text('Ends the next day', key: const Key('commitment_next_day_hint'), style: FlowTypography.bodySmall(color: muted)),
        ],
        if (_commitmentError != null) ...[
          const SizedBox(height: 8),
          Text(
            _commitmentError!,
            key: const Key('commitment_error'),
            style: FlowTypography.bodySmall(color: FlowColors.warningOf(context)),
          ),
        ],
        const SizedBox(height: 24),
        _saveButton(onPressed: _isSaving ? null : _saveCommitment),
        const SizedBox(height: 10),
        _deleteButton(context, 'Remove commitment'),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _titleField(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: FlowColors.surfaceElevated(context),
          borderRadius: BorderRadius.circular(FlowRadii.inputField),
          border: Border.all(color: FlowColors.border(context)),
        ),
        child: TextField(
          controller: _titleController,
          style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            hintText: 'What needs to be done?',
          ),
        ),
      );

  Widget _saveButton({required VoidCallback? onPressed}) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: FlowColors.mint,
            foregroundColor: FlowColors.textInverse,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
          ),
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('Save Changes', style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w700)),
        ),
      );

  Widget _deleteButton(BuildContext context, String text) => Center(
        child: TextButton.icon(
          onPressed: _isSaving ? null : () => _confirmAndDelete(context),
          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: FlowColors.error),
          label: Text(text, style: FlowTypography.labelMedium(color: FlowColors.error).copyWith(fontWeight: FontWeight.w600)),
        ),
      );

  Future<void> _saveChanges() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _isSaving = true);
    FlowHaptics.selection();

    DateTime? newScheduledStart;
    DateTime? newScheduledEnd;
    if (_selectedDate != null && _selectedTime != null) {
      newScheduledStart = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      newScheduledEnd = newScheduledStart.add(Duration(minutes: _durationMinutes));
    }

    final updated = widget.task.copyWith(
      title: title,
      durationMinutes: _durationMinutes,
      taskType: _selectedType,
      difficulty: _mapTypeToDifficulty(_selectedType),
      isPriority: _isPriority,
      priority: _selectedPriority,
      prioritySource: 'explicit',
      deadline: _deadlineController.text.trim(),
      // The picked date is the day the task is planned for, NOT a deadline: writing it into deadlineAt
      // (midnight of that day) made every slot on that day "after the deadline".
      scheduledStart: newScheduledStart,
      scheduledEnd: newScheduledEnd,
      clearScheduledStart: newScheduledStart == null,
      clearScheduledEnd: newScheduledStart == null,
      scheduledTime: newScheduledStart != null ? DateFormat('h:mm a').format(newScheduledStart) : '',
      // Choosing a clock time here is the user fixing it (lock source L3).
      timeLocked: newScheduledStart != null,
      plannedDate: newScheduledStart == null ? _selectedDate : null,
      clearPlannedDate: newScheduledStart != null || _selectedDate == null,
    );

    final appState = Provider.of<AppStateProvider>(context, listen: false);
    appState.updateTask(updated);
    if (!appState.isDemoMode) {
      appState.refreshTodayData().catchError((_) {});
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task "${updated.title}" updated.'),
          duration: const Duration(seconds: 2),
          backgroundColor: FlowColors.surfaceElevated(context),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  TaskDifficulty _mapTypeToDifficulty(TaskType type) {
    switch (type) {
      case TaskType.deepWork:
        return TaskDifficulty.high;
      case TaskType.study:
        return TaskDifficulty.medium;
      case TaskType.physical:
        return TaskDifficulty.physical;
      case TaskType.admin:
      case TaskType.shallowWork:
      case TaskType.meeting:
      case TaskType.personal:
      case TaskType.creative:
        return TaskDifficulty.light;
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Title & Close (X) button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.task.isCommitment ? 'Edit Commitment' : 'Edit Task',
                    style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                      fontWeight: FontWeight.w700,
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
              const SizedBox(height: 4),
              if (widget.task.isCommitment)
                _buildCommitmentBody(context)
              else ...[
              // Title Field
              Text(
                'TASK TITLE',
                style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                decoration: BoxDecoration(
                  color: FlowColors.surfaceElevated(context),
                  borderRadius: BorderRadius.circular(FlowRadii.inputField),
                  border: Border.all(color: FlowColors.border(context)),
                ),
                child: TextField(
                  controller: _titleController,
                  style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    hintText: 'What needs to be done?',
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Date & Time Controls
              TaskDateTimePickers(
                selectedDate: _selectedDate,
                selectedTime: _selectedTime,
                onDateChanged: (d) => setState(() => _selectedDate = d),
                onTimeChanged: (t) => setState(() => _selectedTime = t),
              ),
              const SizedBox(height: 6),

              // Focus Requirement Stepped Selector
              FocusRequirementSelector(
                selectedDifficulty: _mapTypeToDifficulty(_selectedType),
                onChanged: (diff) {
                  setState(() {
                    switch (diff) {
                      case TaskDifficulty.high:
                        _selectedType = TaskType.deepWork;
                        break;
                      case TaskDifficulty.medium:
                        _selectedType = TaskType.study;
                        break;
                      case TaskDifficulty.light:
                        _selectedType = TaskType.shallowWork;
                        break;
                      case TaskDifficulty.physical:
                        _selectedType = TaskType.physical;
                        break;
                    }
                  });
                },
              ),
              const SizedBox(height: 6),

              // Duration Slider & Snapping Selector
              DurationSliderSelector(
                durationMinutes: _durationMinutes,
                onChanged: (mins) => setState(() => _durationMinutes = mins),
              ),
              const SizedBox(height: 6),

              // Priority Selector
              PrioritySelector(
                priority: _selectedPriority,
                onChanged: (p) {
                  setState(() {
                    _selectedPriority = p;
                    _isPriority = p == TaskPriority.high || p == TaskPriority.urgent;
                  });
                },
              ),
              const SizedBox(height: 24),

              // Save Changes Action Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _saveChanges,
                  style: FilledButton.styleFrom(
                    backgroundColor: FlowColors.mint,
                    foregroundColor: FlowColors.textInverse,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FlowRadii.button),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Save Changes',
                          style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),

              // Delete Task Destructive Action
              Center(
                child: TextButton.icon(
                  onPressed: _isSaving ? null : () => _confirmAndDelete(context),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: FlowColors.error),
                  label: Text(
                    'Delete Task',
                    style: FlowTypography.labelMedium(color: FlowColors.error).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _confirmAndDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: FlowColors.surfaceElevated(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.cardLarge)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: FlowColors.error, size: 24),
            const SizedBox(width: 8),
            Text(
              widget.task.isCommitment ? 'Remove commitment?' : 'Delete Task?',
              style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${widget.task.title}"? This action cannot be undone.',
          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(
              'Cancel',
              style: FlowTypography.labelLarge(color: FlowColors.textSecondaryOf(context)),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              Navigator.of(context).pop();
              FlowHaptics.selection();
              final appState = Provider.of<AppStateProvider>(context, listen: false);
              appState.removeTask(widget.task.id);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Task "${widget.task.title}" deleted.'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: FlowColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
