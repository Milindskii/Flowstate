import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/plan_diff_view.dart';
import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/screens/replan_day_sheet.dart';
import 'package:flowstate/services/api_service.dart';

PlanDiff _diff({bool needsTitle = false}) {
  return PlanDiff.fromJson({
    'plan_id': 'p1',
    'selected_date': '2026-10-05',
    'before_schedule': [],
    'after_schedule': [
      {
        'id': 'new-1', 'task_id': 'new-1', 'time': '3:00', 'period': 'PM', 'title': needsTitle ? 'Urgent work' : 'Finish API',
        'type': 'deep_work', 'tag_text': 'DEEP WORK', 'duration_minutes': 60,
        'start_time': '2026-10-05T15:00:00+05:30', 'end_time': '2026-10-05T16:00:00+05:30',
      }
    ],
    'newly_scheduled_tasks': [
      {
        'task_id': 'new-1', 'title': needsTitle ? 'Urgent work' : 'Finish API', 'change_type': 'new',
        'new_time': '3:00 PM', 'duration_minutes': 60, 'apply_index': 0, 'needs_title': needsTitle,
        'new_start': '2026-10-05T15:00:00+05:30', 'new_end': '2026-10-05T16:00:00+05:30',
      }
    ],
    'apply_request': {
      'plan_id': 'p1',
      'selected_date': '2026-10-05',
      'task_updates': [],
      'new_tasks': [
        {
          'title': needsTitle ? 'Urgent work' : 'Finish API', 'estimated_minutes': 60, 'task_type': 'deep_work',
          'priority': 'urgent', 'scheduled_start': '2026-10-05T09:30:00+00:00', 'scheduled_end': '2026-10-05T10:30:00+00:00',
        }
      ],
    },
  });
}

void main() {
  test('editing a new task patches the preview AND the apply payload', () {
    final edited = _diff().withEditedNewTask(applyIndex: 0, title: '  Renamed review ', minutes: 45);
    final item = edited.newlyScheduledTasks.single;
    expect(item.title, 'Renamed review');
    expect(item.durationMinutes, 45);
    expect(edited.afterSchedule.single.title, 'Renamed review');
    expect(edited.afterSchedule.single.durationMinutes, 45);
    final nt = (edited.toApplyRequest().toJson()['new_tasks'] as List).single as Map;
    expect(nt['title'], 'Renamed review');
    expect(nt['estimated_minutes'], 45);
    // end follows the new duration from the unchanged start
    final s = DateTime.parse(nt['scheduled_start'] as String);
    final e = DateTime.parse(nt['scheduled_end'] as String);
    expect(e.difference(s).inMinutes, 45);
  });

  test('choosing a new time moves the slot and locks it as chosen', () {
    final t = DateTime(2026, 10, 5, 17, 30);
    final edited = _diff().withEditedNewTask(applyIndex: 0, title: 'Finish API', minutes: 60, start: t);
    final nt = (edited.toApplyRequest().toJson()['new_tasks'] as List).single as Map;
    expect(DateTime.parse(nt['scheduled_start'] as String).toLocal(), t);
    expect(nt['time_locked'], true);
    expect(edited.newlyScheduledTasks.single.newStart, t);
  });

  test('an unnamed new task blocks Apply until it is named', () {
    final d = _diff(needsTitle: true);
    expect(d.hasUnnamedNewTask, true);
    final named = d.withEditedNewTask(applyIndex: 0, title: 'Fix login bug', minutes: 60);
    expect(named.hasUnnamedNewTask, false);
  });

  testWidgets('new task card shows an Edit action and Apply is disabled while unnamed', (tester) async {
    TaskDiffItem? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PlanDiffView(diff: _diff(needsTitle: true), onEditNewTask: (t) => tapped = t),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('edit_new_task_0')));
    expect(tapped?.applyIndex, 0);
    expect(find.text('Name the new task to apply'), findsOneWidget);
  });

  test('errors are shown in plain language, never raw backend text', () {
    const raw = ApiException(
      "{code: invalid_replan_request, errors: [{field: user_message, code: unrecognized_instruction}]}",
      statusCode: 422,
      data: {
        'detail': {
          'code': 'invalid_replan_request',
          'errors': [
            {'field': 'user_message', 'code': 'unrecognized_instruction', 'message': 'invalid_replan_request'}
          ]
        }
      },
    );
    final text = _ReplanErr.of(raw);
    for (final bad in ['code:', 'field:', 'invalid_', '{', 'HTTP', 'Gemini']) {
      expect(text.contains(bad), false, reason: text);
    }
    expect(_ReplanErr.of(const ApiException('Gemini model overloaded', statusCode: 503)).toLowerCase().contains('gemini'), false);
  });
}

class _ReplanErr {
  static String of(Object e) => replanFriendlyError(e);
}
