import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/category_chip.dart';
import '../components/task_card.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';
import '../utils/mock_data.dart';
import 'add_task_sheet.dart';
import 'brain_dump_sheet.dart';
import 'task_feedback_sheet.dart';
import 'what_should_i_do_screen.dart';

/// Screen 5: Tasks Inbox
class TaskInboxTab extends StatelessWidget {
  const TaskInboxTab({super.key});

  void _openAddTaskSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddTaskSheet(),
    );
  }

  void _openBrainDumpSheet(BuildContext context) {
    showBrainDumpSheet(context);
  }

  void _openTaskDetail(BuildContext context, TaskItem t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => WhatShouldIDoScreen(task: t),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

    final allTasks = state.selectedCategory == 'All'
        ? state.tasks
        : state.tasks.where((t) => t.category == state.selectedCategory).toList();
    final highPriority = allTasks.where((t) => t.isPriority && !t.isCompleted).toList();
    final later = allTasks.where((t) => !t.isPriority && !t.isCompleted).toList();
    final completed = allTasks.where((t) => t.isCompleted).toList();

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 74.0), // Above bottom nav
        child: FloatingActionButton.extended(
          backgroundColor: accent,
          foregroundColor: FlowColors.textInverse,
          elevation: 3,
          shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
          icon: const Icon(Icons.add_rounded, size: 22),
          label: Text(
            'Add Task',
            style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: () {
            FlowHaptics.lightTap();
            _openAddTaskSheet(context);
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: FlowSpacing.pageMargin(context),
            vertical: 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tasks',
                        style: FlowTypography.headlineMedium().copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        allTasks.isEmpty
                            ? 'Your inbox is all clear'
                            : 'You have ${allTasks.where((t) => !t.isCompleted).length} tasks for today',
                        style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                      ),
                    ],
                  ),
                  // Brain Dump quick shortcut
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: FlowColors.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: FlowColors.darkBorder, width: 1.0),
                    ),
                    child: IconButton(
                      tooltip: 'Brain Dump',
                      icon: Icon(Icons.bolt_rounded, size: 22, color: accent),
                      onPressed: () => _openBrainDumpSheet(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Category Filter Horizontal Strip
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: MockData.categories.map((cat) {
                    return CategoryChip(
                      label: cat,
                      isSelected: state.selectedCategory == cat,
                      onTap: () => state.setSelectedCategory(cat),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),

              // Empty State or Task Sections
              if (allTasks.isEmpty) ...[
                _buildEmptyState(context, state, accent),
              ] else ...[

              // High Priority Section
              if (highPriority.isNotEmpty) ...[
                Text(
                  'High Priority',
                  style: FlowTypography.labelLarge(color: FlowColors.textSecondary).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                ...highPriority.map((t) => TaskCard(
                      task: t,
                      onToggleComplete: () {
                        final willComplete = !t.isCompleted;
                        state.toggleTaskCompletion(t.id);
                        if (willComplete) {
                          showTaskFeedbackSheet(
                            context,
                            taskId: t.id,
                            actualMinutes: t.durationMinutes,
                            onSubmit: (fb) {
                              state.recordTaskFeedback(
                                taskId: t.id,
                                actualMinutes: fb.actualMinutes,
                                feeling: fb.feeling,
                                durationFeedback: fb.durationFeedback,
                                blockerNote: fb.blockerNote,
                              );
                            },
                          );
                        }
                      },
                      onTap: () => _openTaskDetail(context, t),
                    )),
                const SizedBox(height: 16),
              ],

              // Later Today Section
              if (later.isNotEmpty) ...[
                Text(
                  'Later Today',
                  style: FlowTypography.labelLarge(color: FlowColors.textSecondary).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                ...later.map((t) => TaskCard(
                      task: t,
                      onToggleComplete: () {
                        final willComplete = !t.isCompleted;
                        state.toggleTaskCompletion(t.id);
                        if (willComplete) {
                          showTaskFeedbackSheet(
                            context,
                            taskId: t.id,
                            actualMinutes: t.durationMinutes,
                            onSubmit: (fb) {
                              state.recordTaskFeedback(
                                taskId: t.id,
                                actualMinutes: fb.actualMinutes,
                                feeling: fb.feeling,
                                durationFeedback: fb.durationFeedback,
                                blockerNote: fb.blockerNote,
                              );
                            },
                          );
                        }
                      },
                      onTap: () => _openTaskDetail(context, t),
                    )),
                const SizedBox(height: 16),
              ],

              // Completed Tasks Section
              if (completed.isNotEmpty) ...[
                Text(
                  'Completed (${completed.length})',
                  style: FlowTypography.labelLarge(color: FlowColors.mintLight).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                ...completed.map((t) => TaskCard(
                      task: t,
                      onToggleComplete: () => state.toggleTaskCompletion(t.id),
                      onTap: () => _openTaskDetail(context, t),
                    )),
              ],
            ], // closes else ...[

              // Safe clearance for bottom nav & FAB
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppStateProvider state, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardLargeRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: FlowColors.softShadow(context),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: FlowColors.surfaceElevated(context),
              shape: BoxShape.circle,
              border: Border.all(color: FlowColors.border(context)),
            ),
            child: Icon(
              Icons.checklist_rounded,
              color: accent,
              size: 26,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Your task inbox is clear',
            style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Capture assignments, projects, errands, or thoughts. Flowstate will organize and schedule them in your peak focus window.',
            style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                FlowHaptics.lightTap();
                _openAddTaskSheet(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: FlowColors.textInverse,
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  borderRadius: FlowRadii.buttonRadius,
                ),
              ),
              child: Text(
                'Add task',
                style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () {
                FlowHaptics.lightTap();
                _openBrainDumpSheet(context);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: FlowColors.textPrimaryOf(context),
                side: BorderSide(color: FlowColors.border(context)),
                shape: const RoundedRectangleBorder(
                  borderRadius: FlowRadii.buttonRadius,
                ),
              ),
              child: Text(
                'Brain dump a messy day',
                style: FlowTypography.labelMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
