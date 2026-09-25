import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/primary_button.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';

import 'package:intl/intl.dart';
import '../models/task_item.dart';
import '../models/schedule_item.dart';
import '../services/flow_clock.dart';

/// Screen 8: Calendar Tab with Focus Windows & "Optimize My Day" Engine Action
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  int _selectedDayIndex = 0; // Today by default

  List<String> get _days {
    final now = FlowClock().now;
    return List.generate(7, (index) {
      final day = now.add(Duration(days: index));
      final dayName = DateFormat('E').format(day);
      final dayNum = DateFormat('d').format(day);
      return '$dayName\n$dayNum';
    });
  }

  DateTime get _selectedDate {
    final now = FlowClock().now;
    return now.add(Duration(days: _selectedDayIndex));
  }


  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    final pageMargin = FlowSpacing.pageMargin(context);

    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: pageMargin, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Calendar',
                style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Energy-aligned schedule & focus blocks',
                style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 20),

              // Horizontal Date Strip
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_days.length, (index) {
                    final isSelected = _selectedDayIndex == index;
                    return Semantics(
                      button: true,
                      selected: isSelected,
                      label: 'Day ${_days[index].replaceAll('\n', ' ')}',
                      child: GestureDetector(
                        onTap: () {
                          FlowHaptics.selection();
                          setState(() => _selectedDayIndex = index);
                        },
                        child: Container(
                          width: 54,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? accent : FlowColors.surface(context),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected ? accent : FlowColors.border(context),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            _days[index],
                            textAlign: TextAlign.center,
                            style: FlowTypography.labelMedium(
                              color: isSelected ? FlowColors.textInverse : FlowColors.textPrimaryOf(context),
                            ).copyWith(
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 24),

              // Prominent "Optimize My Day" Action Button
              PrimaryButton(
                label: state.isOptimizing ? 'Optimizing with Rhythm Engine...' : 'Optimize My Day',
                icon: const Icon(Icons.auto_awesome_rounded, color: FlowColors.textInverse, size: 20),
                isLoading: state.isOptimizing,
                onPressed: () async {
                  await state.optimizeSchedule();
                  FlowHaptics.success();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Schedule recalibrated to align with your peak readiness window!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 24),

              // Highlighted Focus Window Block
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: FlowColors.surface(context),
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: FlowColors.softShadow(context),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.bolt_rounded, color: accent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Optimal Focus Window',
                            style: FlowTypography.titleMedium(color: accent).copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.readiness.focusWindowRange,
                            style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Calendar Scheduled Blocks
              Text(
                'Scheduled Timeline',
                style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),

              Builder(
                builder: (context) {
                  final dayTasks = _selectedDayIndex == 0
                      ? state.schedule
                      : state.tasks.where((t) {
                          final sStart = t.scheduledStart;
                          final dLine = t.deadlineAt;
                          final matchStart = sStart != null && sStart.year == _selectedDate.year && sStart.month == _selectedDate.month && sStart.day == _selectedDate.day;
                          final matchDline = dLine != null && dLine.year == _selectedDate.year && dLine.month == _selectedDate.month && dLine.day == _selectedDate.day;
                          return matchStart || matchDline;
                        }).map((t) {
                          final sStart = t.scheduledStart ?? t.deadlineAt ?? _selectedDate;
                          return ScheduleItem(
                            id: 'sched-${t.id}',
                            time: DateFormat('h:mm').format(sStart),
                            period: DateFormat('a').format(sStart),
                            title: t.title,
                            type: t.taskType == TaskType.deepWork ? 'High Focus' : 'Task',
                            tagText: t.taskType == TaskType.deepWork ? 'DEEP WORK' : 'TASK',
                            tagBg: FlowColors.tagMediumBg,
                            tagColor: FlowColors.tagMediumText,
                            durationMinutes: t.durationMinutes,
                          );
                        }).toList();

                  if (dayTasks.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                      decoration: BoxDecoration(
                        color: FlowColors.surface(context),
                        borderRadius: FlowRadii.cardRadius,
                        border: Border.all(color: FlowColors.border(context), width: 1.0),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.event_note_outlined, size: 36, color: FlowColors.textMutedOf(context)),
                          const SizedBox(height: 12),
                          Text(
                            'No scheduled events yet',
                            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Connect your calendar or calibrate your day to visualize focus blocks.',
                            style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () => state.optimizeSchedule(),
                            child: const Text('Calibrate focus blocks'),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: dayTasks.map((item) {
                      final isDeepWork = item.tagText == 'DEEP WORK';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: FlowColors.surface(context),
                          borderRadius: FlowRadii.cardRadius,
                          border: Border.all(
                            color: isDeepWork ? accent.withValues(alpha: 0.4) : FlowColors.border(context),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: FlowColors.softShadow(context),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.time,
                                  style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  item.period,
                                  style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)).copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${item.durationMinutes} min · ${item.type}',
                                    style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: isDeepWork ? accent.withValues(alpha: 0.15) : FlowColors.surfaceElevated(context),
                                borderRadius: BorderRadius.circular(FlowRadii.pill),
                              ),
                              child: Text(
                                item.tagText,
                                style: FlowTypography.labelSmall(color: isDeepWork ? accent : FlowColors.textSecondaryOf(context)).copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
