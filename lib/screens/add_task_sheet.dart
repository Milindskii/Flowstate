import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';
import '../components/primary_button.dart';
import '../components/secondary_button.dart';

/// Screen 6: Add Task Modal with AI Inferred Attributes
class AddTaskSheet extends StatefulWidget {
  const AddTaskSheet({super.key});

  @override
  State<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<AddTaskSheet> {
  final TextEditingController _titleController = TextEditingController();

  int _selectedDuration = 90;
  TaskDifficulty _selectedDifficulty = TaskDifficulty.high;
  String _selectedDeadline = 'Due Tomorrow';
  String _selectedCategory = 'College';
  bool _isPriority = true;

  // Auto-inferred suggestion as user types
  void _onTitleChanged(String val) {
    setState(() {
      final lower = val.toLowerCase();
      if (lower.contains('gym') || lower.contains('run') || lower.contains('workout')) {
        _selectedDifficulty = TaskDifficulty.physical;
        _selectedDuration = 60;
        _selectedCategory = 'Fitness';
      } else if (lower.contains('mail') || lower.contains('call') || lower.contains('clean')) {
        _selectedDifficulty = TaskDifficulty.light;
        _selectedDuration = 30;
        _selectedCategory = 'Personal';
      } else if (lower.contains('exam') || lower.contains('study') || lower.contains('revision')) {
        _selectedDifficulty = TaskDifficulty.medium;
        _selectedDuration = 45;
        _selectedCategory = 'Study';
      } else {
        _selectedDifficulty = TaskDifficulty.high;
        _selectedDuration = 90;
        _selectedCategory = 'Work';
      }
    });
  }

  void _saveTask({bool autoSchedule = false}) {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final provider = Provider.of<AppStateProvider>(context, listen: false);
    provider.addTask(
      title: title,
      durationMinutes: _selectedDuration,
      difficulty: _selectedDifficulty,
      deadline: _selectedDeadline,
      category: _selectedCategory,
      isPriority: _isPriority,
    );

    if (autoSchedule) {
      provider.optimizeSchedule();
    }

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          autoSchedule
              ? 'Task added and placed in your peak focus window!'
              : 'Task saved to inbox.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
        border: Border(
          top: BorderSide(color: FlowColors.darkBorder, width: 1.0),
        ),
      ),
      padding: EdgeInsets.only(
        left: FlowSpacing.pageMargin(context),
        right: FlowSpacing.pageMargin(context),
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
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
                  color: FlowColors.darkBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Add Task',
              style: FlowTypography.headlineMedium().copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),

            // Large Title Input Field
            TextField(
              controller: _titleController,
              autofocus: true,
              style: FlowTypography.titleMedium(),
              onChanged: _onTitleChanged,
              decoration: const InputDecoration(
                hintText: 'What needs to get done?',
                prefixIcon: Icon(Icons.bolt_rounded, color: FlowColors.cyanLight),
              ),
            ),
            const SizedBox(height: 20),

            // AI dynamic tags header
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: FlowColors.cyanLight, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Energy & Schedule Attributes',
                  style: FlowTypography.labelMedium(color: FlowColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Duration Selector
            Text('Estimated Duration', style: FlowTypography.labelSmall(color: FlowColors.textMuted)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [30, 45, 60, 90, 120].map((mins) {
                  final isSelected = _selectedDuration == mins;
                  return _buildSelectablePill(
                    label: '$mins min',
                    isSelected: isSelected,
                    onTap: () => setState(() => _selectedDuration = mins),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Difficulty / Focus Requirement
            Text('Focus Requirement', style: FlowTypography.labelSmall(color: FlowColors.textMuted)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: TaskDifficulty.values.map((diff) {
                  final isSelected = _selectedDifficulty == diff;
                  return _buildSelectablePill(
                    label: diff.label,
                    isSelected: isSelected,
                    onTap: () => setState(() => _selectedDifficulty = diff),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Deadline
            Text('Deadline', style: FlowTypography.labelSmall(color: FlowColors.textMuted)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Due Today', 'Due Tomorrow', 'Due Friday', 'Next Week'].map((d) {
                  final isSelected = _selectedDeadline == d;
                  return _buildSelectablePill(
                    label: d,
                    isSelected: isSelected,
                    onTap: () => setState(() => _selectedDeadline = d),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Priority Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('High Priority Task', style: FlowTypography.bodyLarge()),
                Switch.adaptive(
                  value: _isPriority,
                  activeThumbColor: FlowColors.cyanLight,
                  onChanged: (val) => setState(() => _isPriority = val),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Buttons: Add Task & Add & Schedule
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Add Task',
                    onPressed: () => _saveTask(autoSchedule: false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: 'Add & Schedule',
                    onPressed: () => _saveTask(autoSchedule: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectablePill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: FlowRadii.pillRadius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? FlowColors.cyan : FlowColors.darkSurface,
            borderRadius: FlowRadii.pillRadius,
            border: Border.all(
              color: isSelected ? FlowColors.cyan : FlowColors.darkBorder,
              width: 1.0,
            ),
          ),
          child: Text(
            label,
            style: FlowTypography.labelSmall(
              color: isSelected ? FlowColors.textInverse : FlowColors.textPrimary,
            ).copyWith(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
