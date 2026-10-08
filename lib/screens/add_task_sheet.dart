import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../components/primary_button.dart';
import '../components/task_date_time_pickers.dart';
import '../components/task_interactive_controls.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';
import '../services/smart_reminder_service.dart';
import 'brain_dump_sheet.dart';

/// Add Task Modal with real calendar date & clock time selection,
/// energy & schedule attributes, and AI assist integration.
class AddTaskSheet extends StatefulWidget {
  final DateTime? initialDate;

  const AddTaskSheet({super.key, this.initialDate});

  @override
  State<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<AddTaskSheet> {
  final TextEditingController _titleController = TextEditingController();

  int _selectedDuration = 60;
  TaskDifficulty _selectedDifficulty = TaskDifficulty.high;
  TaskPriority _selectedPriority = TaskPriority.medium;
  String _selectedDeadline = 'Due Tomorrow';
  String _selectedCategory = 'Work';
  bool _isPriority = false;
  bool _isSubmitting = false;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    SmartReminderService.instance.isCreatingTask = true;
    _selectedDate = widget.initialDate;
    if (_selectedDate != null) {
      _selectedDeadline = TaskDateTimePickers.formatDateDisplay(_selectedDate);
    }
  }

  // Auto-inferred suggestion as user types
  void _onTitleChanged(String val) {
    setState(() {
      final lower = val.toLowerCase();
      if (lower.contains('gym') ||
          lower.contains('run') ||
          lower.contains('workout')) {
        _selectedDifficulty = TaskDifficulty.physical;
        _selectedDuration = 60;
        _selectedCategory = 'Fitness';
      } else if (lower.contains('mail') ||
          lower.contains('call') ||
          lower.contains('clean')) {
        _selectedDifficulty = TaskDifficulty.light;
        _selectedDuration = 30;
        _selectedCategory = 'Personal';
      } else if (lower.contains('exam') ||
          lower.contains('study') ||
          lower.contains('revision')) {
        _selectedDifficulty = TaskDifficulty.medium;
        _selectedDuration = 45;
        _selectedCategory = 'Study';
      } else {
        _selectedDifficulty = TaskDifficulty.high;
        _selectedDuration = 60;
        _selectedCategory = 'Work';
      }
    });
  }

  TaskType _mapDifficultyToType(TaskDifficulty difficulty) {
    switch (difficulty) {
      case TaskDifficulty.high:
        return TaskType.deepWork;
      case TaskDifficulty.medium:
        return TaskType.study;
      case TaskDifficulty.light:
        return TaskType.shallowWork;
      case TaskDifficulty.physical:
        return TaskType.physical;
    }
  }

  DateTime _getToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _getTomorrow() {
    return _getToday().add(const Duration(days: 1));
  }

  DateTime _getThisFriday() {
    final today = _getToday();
    final daysUntilFriday = (DateTime.friday - today.weekday + 7) % 7;
    return today
        .add(Duration(days: daysUntilFriday == 0 ? 7 : daysUntilFriday));
  }

  DateTime _getNextMonday() {
    final today = _getToday();
    final daysUntilMonday = (DateTime.monday - today.weekday + 7) % 7;
    return today
        .add(Duration(days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _saveTask() async {
    if (_isSubmitting) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _isSubmitting = true);
    FlowHaptics.selection();

    DateTime? scheduledStart;
    DateTime? scheduledEnd;
    String? scheduledTimeStr;

    if (_selectedDate != null && _selectedTime != null) {
      scheduledStart = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      scheduledEnd = scheduledStart.add(Duration(minutes: _selectedDuration));
      scheduledTimeStr = DateFormat('h:mm a').format(scheduledStart);
    } else if (_selectedDate != null) {
      // Date selected without specific clock time
      scheduledStart = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
      );
    } else if (_selectedTime != null) {
      // Time selected without date defaults to today
      final today = _getToday();
      scheduledStart = DateTime(
        today.year,
        today.month,
        today.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      scheduledEnd = scheduledStart.add(Duration(minutes: _selectedDuration));
      scheduledTimeStr = DateFormat('h:mm a').format(scheduledStart);
    }

    String deadlineStr = _selectedDeadline;
    if (_selectedDate != null) {
      deadlineStr = TaskDateTimePickers.formatDateDisplay(_selectedDate);
    }

    final provider = Provider.of<AppStateProvider>(context, listen: false);
    await provider.addTask(
      title: title,
      durationMinutes: _selectedDuration,
      difficulty: _selectedDifficulty,
      deadline: deadlineStr,
      category: _selectedCategory,
      isPriority: _isPriority,
      priority: _selectedPriority,
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledEnd,
      deadlineAt: _selectedDate,
      scheduledTime: scheduledTimeStr,
      taskType: _mapDifficultyToType(_selectedDifficulty),
    );

    provider.optimizeSchedule();

    if (mounted) {
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task "$title" created.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    SmartReminderService.instance.isCreatingTask = false;
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(FlowRadii.cardLarge)),
        border: Border(
          top: BorderSide(color: FlowColors.border(context), width: 1.0),
        ),
      ),
      padding: EdgeInsets.only(
        left: FlowSpacing.pageMargin(context),
        right: FlowSpacing.pageMargin(context),
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: FlowColors.border(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Header with Title & Close (X) button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Add Task',
                        style: FlowTypography.titleMedium(
                                color: FlowColors.textPrimaryOf(context))
                            .copyWith(
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

                  // Task Title Input Field
                  TextField(
                    controller: _titleController,
                    autofocus: true,
                    style: FlowTypography.titleMedium(
                        color: FlowColors.textPrimaryOf(context)),
                    onChanged: _onTitleChanged,
                    decoration: InputDecoration(
                      hintText: 'What needs to get done?',
                      hintStyle: FlowTypography.bodyLarge(
                          color: FlowColors.textMutedOf(context)),
                      prefixIcon: const Icon(Icons.bolt_rounded,
                          color: FlowColors.accentCyan),
                      filled: true,
                      fillColor: FlowColors.surface(context),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(FlowRadii.inputField),
                        borderSide:
                            BorderSide(color: FlowColors.border(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(FlowRadii.inputField),
                        borderSide:
                            BorderSide(color: FlowColors.border(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(FlowRadii.inputField),
                        borderSide: const BorderSide(
                            color: FlowColors.accentCyan, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Build with AI: a quiet secondary enhancement under the title
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      key: const Key('add_task_build_with_ai_button'),
                      borderRadius: BorderRadius.circular(FlowRadii.chip),
                      onTap: () {
                        final currentText = _titleController.text.trim();
                        Navigator.pop(context);
                        showBrainDumpSheet(
                          context,
                          initialText:
                              currentText.isNotEmpty ? currentText : null,
                        );
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              Text(
                                '✨ Build with AI',
                                style: FlowTypography.labelMedium(
                                        color: FlowColors.accentCyan)
                                    .copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Describe what you need to get done in your own words',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: FlowTypography.bodySmall(
                                      color: FlowColors.textMutedOf(context)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Date & Time Selection (Task 1: Shared picker implementation reuse)
                  TaskDateTimePickers(
                    selectedDate: _selectedDate,
                    selectedTime: _selectedTime,
                    accentColor: FlowColors.accentCyan,
                    dateButtonKey: const Key('add_task_date_button'),
                    timeButtonKey: const Key('add_task_time_button'),
                    clearDateKey: const Key('add_task_clear_date'),
                    clearTimeKey: const Key('add_task_clear_time'),
                    onDateChanged: (d) {
                      setState(() {
                        _selectedDate = d;
                        if (d != null) {
                          _selectedDeadline =
                              TaskDateTimePickers.formatDateDisplay(d);
                        }
                      });
                    },
                    onTimeChanged: (t) {
                      setState(() {
                        _selectedTime = t;
                      });
                    },
                  ),
                  const SizedBox(height: 8),

                  // Quick Date Presets Row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildDatePresetChip(
                          key: const Key('add_task_preset_today'),
                          label: 'Today',
                          targetDate: _getToday(),
                        ),
                        _buildDatePresetChip(
                          key: const Key('add_task_preset_tomorrow'),
                          label: 'Tomorrow',
                          targetDate: _getTomorrow(),
                        ),
                        _buildDatePresetChip(
                          key: const Key('add_task_preset_friday'),
                          label: 'Due Friday',
                          targetDate: _getThisFriday(),
                        ),
                        _buildDatePresetChip(
                          key: const Key('add_task_preset_next_week'),
                          label: 'Next Week',
                          targetDate: _getNextMonday(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Duration Slider & Snapping Selector
                  DurationSliderSelector(
                    durationMinutes: _selectedDuration,
                    accentColor: FlowColors.accentCyan,
                    onChanged: (mins) =>
                        setState(() => _selectedDuration = mins),
                  ),
                  const SizedBox(height: 10),

                  // Focus Requirement Stepped Selector
                  FocusRequirementSelector(
                    selectedDifficulty: _selectedDifficulty,
                    accentColor: FlowColors.accentCyan,
                    onChanged: (diff) =>
                        setState(() => _selectedDifficulty = diff),
                  ),
                  const SizedBox(height: 14),

                  // Priority Selector (Low, Medium, High, Urgent)
                  PrioritySelector(
                    priority: _selectedPriority,
                    onChanged: (p) {
                      setState(() {
                        _selectedPriority = p;
                        _isPriority =
                            p == TaskPriority.high || p == TaskPriority.urgent;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          // Pinned so it stays reachable with the keyboard open
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              key: const Key('add_task_submit_button'),
              label: 'Add & Schedule',
              isLoading: _isSubmitting,
              onPressed: _isSubmitting ? null : _saveTask,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePresetChip({
    required Key key,
    required String label,
    required DateTime targetDate,
  }) {
    final isSelected = _isSameDay(_selectedDate, targetDate);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      key: key,
      margin: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: FlowRadii.pillRadius,
        onTap: () {
          FlowHaptics.selection();
          setState(() {
            if (isSelected) {
              _selectedDate = null;
              _selectedDeadline = '';
            } else {
              _selectedDate = targetDate;
              _selectedDeadline = label;
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 38),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? FlowColors.accentCyan.withValues(alpha: isDark ? 0.22 : 0.12)
                : (isDark
                    ? FlowColors.surfaceContainerDark
                    : FlowColors.surfaceContainerLight),
            borderRadius: FlowRadii.pillRadius,
            border: Border.all(
              color: isSelected
                  ? FlowColors.accentCyan
                  : FlowColors.border(context),
              width: isSelected ? 1.4 : 0.8,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: FlowColors.accentCyan.withValues(alpha: isDark ? 0.28 : 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                const Icon(
                  Icons.check_rounded,
                  size: 13,
                  color: FlowColors.accentCyan,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: FlowTypography.labelSmall(
                  color: isSelected
                      ? FlowColors.accentCyan
                      : FlowColors.textSecondaryOf(context),
                ).copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
