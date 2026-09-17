import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/category_chip.dart';
import '../components/task_card.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import '../utils/mock_data.dart';
import 'add_task_sheet.dart';
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

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);

    final highPriority = state.highPriorityTasks;
    final later = state.laterTasks;
    final completed = state.completedTasks;

    return Scaffold(
      backgroundColor: FlowColors.darkBackground,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 74.0), // Above bottom nav
        child: FloatingActionButton.extended(
          backgroundColor: FlowColors.cyan,
          foregroundColor: FlowColors.textInverse,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
          icon: const Icon(Icons.add_rounded, size: 22),
          label: Text(
            'Add Task',
            style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: () => _openAddTaskSheet(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
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
                        'You have ${state.tasks.where((t) => !t.isCompleted).length} tasks for today',
                        style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                      ),
                    ],
                  ),
                  // Tune / Filter Icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: FlowColors.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: FlowColors.darkBorder, width: 1.0),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.tune_rounded, size: 22),
                      color: FlowColors.textPrimary,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Filter options: Sort by energy requirement, deadline, difficulty.'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
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
              const SizedBox(height: 28),

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
                      onToggleComplete: () => state.toggleTaskCompletion(t.id),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WhatShouldIDoScreen(task: t),
                          ),
                        );
                      },
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
                      onToggleComplete: () => state.toggleTaskCompletion(t.id),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WhatShouldIDoScreen(task: t),
                          ),
                        );
                      },
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
                    )),
              ],

              // Safe clearance for bottom nav & FAB
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}
