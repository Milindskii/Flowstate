import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/plan_diff_view.dart';
import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/models/schedule_item.dart';

void main() {
  _notesTests();
  group('Task 5: PlanDiffView / Before → After Component Tests', () {
    late PlanDiff sampleDiff;

    setUp(() {
      sampleDiff = const PlanDiff(
        planId: 'diff-sample-1',
        selectedDate: '2026-10-02',
        explanation: 'Shifted flexible tasks around your 6:00 PM Dentist appointment.',
        conflicts: [
          'Direct conflict with fixed commitment: Dentist Appointment at 6:00 PM',
        ],
        issues: [
          ReplanIssue(kind: 'conflict', message: 'Direct conflict with fixed commitment: Dentist Appointment at 6:00 PM'),
        ],
        beforeSchedule: [
          ScheduleItem(
            id: 'b-1',
            time: '4:00',
            period: 'PM',
            title: 'Quarterly Report',
            type: 'deep_work',
            tagText: 'DEEP WORK',
          ),
          ScheduleItem(
            id: 'b-2',
            time: '5:00',
            period: 'PM',
            title: 'Gym Session',
            type: 'physical',
            tagText: 'PHYSICAL',
          ),
          ScheduleItem(
            id: 'b-3',
            time: '6:00',
            period: 'PM',
            title: 'Dentist Appointment',
            type: 'meeting',
            tagText: 'FIXED',
            isFixed: true,
          ),
        ],
        afterSchedule: [
          ScheduleItem(
            id: 'a-new',
            time: '4:00',
            period: 'PM',
            title: 'Urgent Client Work',
            type: 'deep_work',
            tagText: 'NEW',
          ),
          ScheduleItem(
            id: 'b-1',
            time: '5:00',
            period: 'PM',
            title: 'Quarterly Report',
            type: 'deep_work',
            tagText: 'DEEP WORK',
          ),
          ScheduleItem(
            id: 'b-3',
            time: '6:00',
            period: 'PM',
            title: 'Dentist Appointment',
            type: 'meeting',
            tagText: 'FIXED',
            isFixed: true,
          ),
          ScheduleItem(
            id: 'b-2',
            time: '7:30',
            period: 'PM',
            title: 'Gym Session',
            type: 'physical',
            tagText: 'PHYSICAL',
          ),
        ],
        newlyScheduledTasks: [
          TaskDiffItem(
            taskId: 't-urgent',
            title: 'Urgent Client Work',
            changeType: 'new',
            newTime: '4:00 PM',
            durationMinutes: 60,
          ),
        ],
        movedTasks: [
          TaskDiffItem(
            taskId: 't-report',
            title: 'Quarterly Report',
            changeType: 'moved',
            oldTime: '4:00 PM',
            newTime: '5:00 PM',
            durationMinutes: 60,
            reason: 'Shifted to make room for urgent work',
          ),
          TaskDiffItem(
            taskId: 't-gym',
            title: 'Gym Session',
            changeType: 'moved',
            oldTime: '5:00 PM',
            newTime: '7:30 PM',
            durationMinutes: 60,
            reason: 'Moved after dinner window',
          ),
        ],
        unchangedTasks: [
          TaskDiffItem(
            taskId: 't-dentist',
            title: 'Dentist Appointment',
            changeType: 'unchanged',
            oldTime: '6:00 PM',
            newTime: '6:00 PM',
            isFixed: true,
            durationMinutes: 45,
            reason: 'Fixed commitment',
          ),
        ],
        cancelledTasks: [
          TaskDiffItem(
            taskId: 't-read',
            title: 'Evening Reading',
            changeType: 'cancelled',
            oldTime: '9:00 PM',
            reason: 'Cancelled by user',
          ),
        ],
        unscheduledTasks: [
          TaskDiffItem(
            taskId: 't-errand',
            title: 'Grocery Run',
            changeType: 'unscheduled',
            reason: 'Could not fit before bedtime',
          ),
        ],
      );
    });

    testWidgets('1. Header renders the friendly title and a PREVIEW pill', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanDiffView(diff: sampleDiff),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PLAN PREVIEW'), findsOneWidget);
      expect(find.text("Here's how I'd reshape the rest of your day"), findsOneWidget);
      expect(find.text('PREVIEW'), findsOneWidget);
      expect(find.textContaining('DRY RUN'), findsNothing);
    });

    testWidgets('2. Metrics bar displays count badges for all categories', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanDiffView(diff: sampleDiff),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 Moved'), findsOneWidget);
      expect(find.text('1 New'), findsOneWidget);
      expect(find.text('1 Unchanged'), findsOneWidget);
      expect(find.text('1 Cancelled'), findsOneWidget);
      expect(find.text('1 Unscheduled'), findsOneWidget);
    });

    testWidgets('3. Renders conflict alert banner noting fixed appointments cannot be moved', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanDiffView(diff: sampleDiff),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clashes with a fixed time'), findsOneWidget);
      expect(find.textContaining('Dentist Appointment at 6:00 PM'), findsOneWidget);
      expect(find.textContaining('other fixed events are locked'), findsNothing);
    });

    testWidgets('4. What Changed view renders New, Moved, Fixed Unchanged, Cancelled, and Unscheduled cards with explicit explanations', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanDiffView(diff: sampleDiff),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // New Tasks
      expect(find.text('New Tasks'), findsOneWidget);
      expect(find.text('Urgent Client Work'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('NEW → 4:00 PM'), findsOneWidget);

      // Moved Tasks
      expect(find.text('Moved Tasks'), findsOneWidget);
      expect(find.text('Quarterly Report'), findsOneWidget);
      expect(find.text('4:00 PM → 5:00 PM'), findsOneWidget);
      expect(find.text('Gym Session'), findsOneWidget);
      expect(find.text('5:00 PM → 7:30 PM'), findsOneWidget);
      expect(find.text('MOVED'), findsNWidgets(2));

      // Fixed & Unchanged with explicit reassurance
      expect(find.text('Fixed & Unchanged Tasks'), findsOneWidget);
      expect(find.text('Dentist Appointment'), findsOneWidget);
      expect(find.text('6:00 PM → 6:00 PM'), findsOneWidget);
      expect(find.text('🔒 FIXED · UNCHANGED'), findsOneWidget);
      expect(find.text('Unchanged because it is a fixed commitment.'), findsOneWidget);

      // Cancelled Tasks
      expect(find.text('Cancelled Tasks'), findsOneWidget);
      expect(find.text('Evening Reading'), findsOneWidget);
      expect(find.text('CANCELLED'), findsOneWidget);

      // Unscheduled Tasks
      expect(find.text("DIDN'T FIT TODAY"), findsOneWidget);
      expect(find.text('Grocery Run'), findsOneWidget);
      expect(find.text('UNSCHEDULED'), findsOneWidget);
    });

    testWidgets('5. Before → After tab renders side-by-side comparison with fixed locks and new indicators', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanDiffView(diff: sampleDiff),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Before → After" tab
      expect(find.text('Before → After'), findsOneWidget);
      await tester.tap(find.text('Before → After'));
      await tester.pumpAndSettle();

      expect(find.text('BEFORE'), findsOneWidget);
      expect(find.text('AFTER (PROPOSED)'), findsOneWidget);

      // Verify lock icon is rendered for dentist in comparison
      expect(find.byIcon(Icons.lock_rounded), findsWidgets);
    });

    testWidgets('6. Action buttons render Apply Changes, Tell Noya what to change, Discard and trigger callbacks', (WidgetTester tester) async {
      bool applied = false;
      bool adjusted = false;
      bool discarded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanDiffView(
                diff: sampleDiff,
                onApply: () => applied = true,
                onAdjust: () => adjusted = true,
                onDiscard: () => discarded = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Apply Changes
      expect(find.text('Apply Changes'), findsOneWidget);
      await tester.ensureVisible(find.text('Apply Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Changes'));
      expect(applied, isTrue);

      // Tap Tell Noya what to change
      expect(find.text('Tell Noya what to change'), findsOneWidget);
      await tester.ensureVisible(find.text('Tell Noya what to change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tell Noya what to change'));
      expect(adjusted, isTrue);

      // Tap Discard
      expect(find.text('Keep current plan'), findsOneWidget);
      await tester.ensureVisible(find.text('Keep current plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep current plan'));
      expect(discarded, isTrue);
    });

    testWidgets('7. Disclaimer explicitly confirms changes are not applied to database', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanDiffView(diff: sampleDiff),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Preliminary proposal. Changes have not been applied to your database.'),
        findsOneWidget,
      );
    });
  });
}

void _notesTests() {
  Widget host(PlanDiff d) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PlanDiffView(diff: d))));

  group('Typed plan notes', () {
    testWidgets('capacity, protected and unclear notes are calm, never a fixed-time clash', (tester) async {
      const diff = PlanDiff(
        planId: 'p',
        selectedDate: '2026-10-05',
        conflicts: ['x', 'y', 'z'],
        issues: [
          ReplanIssue(kind: 'capacity', message: 'Not enough time for Essay.'),
          ReplanIssue(kind: 'protected', message: 'Going out is a fixed commitment, so I left it as it is.'),
          ReplanIssue(kind: 'unparsed', message: 'I did not catch the last part.'),
        ],
      );
      await tester.pumpWidget(host(diff));
      await tester.pumpAndSettle();
      expect(diff.hasTrueConflict, isFalse);
      expect(find.text('Clashes with a fixed time'), findsNothing);
      expect(find.text("Didn't fit today"), findsOneWidget);
      expect(find.text('Kept exactly as is'), findsOneWidget);
      expect(find.text('Need a bit more detail'), findsOneWidget);
    });
  });
}
