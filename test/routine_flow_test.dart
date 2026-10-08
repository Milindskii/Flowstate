import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/components/routine_confirm_sheet.dart';
import 'package:flowstate/models/ai_plan_models.dart';
import 'package:flowstate/models/routine.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';

Map<String, dynamic> _proposalJson({String kind = 'fixed', String recurrence = 'daily'}) => {
      'proposal_id': 'rp_1',
      'title': 'Gym',
      'kind': kind,
      'recurrence': recurrence,
      'start_hhmm': '16:00',
      'summary': 'Every day · 4:00 PM',
      'plan_dates': ['2026-10-05', '2026-10-06'],
      'horizon_days': 7,
    };

Widget _host(RoutineProposal p, ValueChanged<bool> onResult) => MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () async => onResult(await showRoutineConfirmSheet(ctx, p)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  test('plan response carries routine proposals and per-task overrides', () {
    final r = AIPlanResult.fromJson({
      'tasks': [
        {
          'title': 'Gym',
          'type': 'physical',
          'estimated_minutes': 60,
          'routine_override_id': 'r1',
          'routine_override_date': '2026-10-05',
        }
      ],
      'routine_proposals': [_proposalJson()],
    });
    expect(r.routineProposals, hasLength(1));
    expect(r.routineProposals.first.createsTasks, isTrue);
    expect(r.routineProposals.first.planDates, hasLength(2));
    final item = r.tasks.first.toTaskItem();
    expect(item.routineOverrideId, 'r1');
    expect(item.routineOverrideDate, '2026-10-05');
  });

  test('confirm request sends the one-day override so the routine day is replaced, not duplicated', () {
    const t = TaskItem(
      id: 'c1',
      title: 'Gym',
      durationMinutes: 60,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Fitness',
      routineOverrideId: 'r1',
      routineOverrideDate: '2026-10-05',
    );
    final wire = AppStateProvider.candidateToBatchItem(t);
    expect(wire['routine_override_id'], 'r1');
    expect(wire['routine_override_date'], '2026-10-05');
    final none = AppStateProvider.candidateToBatchItem(const TaskItem(
      id: 'c2',
      title: 'Read',
      durationMinutes: 30,
      difficulty: TaskDifficulty.light,
      deadline: 'Today',
      category: 'Study',
    ));
    expect(none.containsKey('routine_override_id'), isFalse);
  });

  test('sheet copy matches the confirmation wording', () {
    final p = RoutineProposal.fromJson(_proposalJson());
    expect(routineQuestion(p), 'Make Gym a daily routine?');
    expect(routineHorizonLine(p), 'Next 7 days will be planned.');
    final weekly = RoutineProposal.fromJson(_proposalJson(recurrence: 'weekly'));
    expect(routineQuestion(weekly), 'Make Gym a weekly routine?');
    final avoid = RoutineProposal.fromJson(_proposalJson(kind: 'avoid'));
    expect(avoid.createsTasks, isFalse);
  });

  testWidgets('Confirm returns true', (tester) async {
    bool? result;
    await tester.pumpWidget(_host(RoutineProposal.fromJson(_proposalJson()), (v) => result = v));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.text('Make Gym a daily routine?'), findsOneWidget);
    expect(find.text('Every day · 4:00 PM'), findsOneWidget);
    expect(find.text('Next 7 days will be planned.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('routine_confirm_button')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('Cancel returns false and saves nothing', (tester) async {
    bool? result;
    await tester.pumpWidget(_host(RoutineProposal.fromJson(_proposalJson()), (v) => result = v));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routine_cancel_button')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('dismissing the sheet counts as cancel', (tester) async {
    bool? result;
    await tester.pumpWidget(_host(RoutineProposal.fromJson(_proposalJson()), (v) => result = v));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // scrim
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('a double tap on Confirm answers once', (tester) async {
    var answers = 0;
    await tester.pumpWidget(_host(RoutineProposal.fromJson(_proposalJson()), (_) => answers++));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('routine_confirm_button'));
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(answers, 1);
  });
}
