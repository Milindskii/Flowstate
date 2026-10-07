import 'package:flowstate/models/calendar_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _diffJson({Map<String, dynamic>? applyRequest}) => {
      'plan_id': 'plan-1',
      'selected_date': '2026-10-05',
      'created_at': '2026-10-05T03:30:00Z',
      'before_schedule': [],
      'after_schedule': [],
      'moved_tasks': [
        {
          'task_id': 'gym',
          'title': 'Gym',
          'change_type': 'moved',
          'new_date': 'Tomorrow',
          'new_date_iso': '2026-10-06',
          'new_start': '2026-10-06T11:30:00Z',
          'new_end': '2026-10-06T12:30:00Z',
        }
      ],
      'newly_scheduled_tasks': [
        {
          'task_id': 'new-1',
          'title': 'Fix bug',
          'change_type': 'new',
          'new_time': '3:00 PM',
          'new_start': '2026-10-05T09:30:00Z',
          'new_end': '2026-10-05T11:30:00Z',
          'priority': 'urgent',
          'task_type': 'deep_work',
          'duration_minutes': 120,
        }
      ],
      'unchanged_tasks': [],
      'cancelled_tasks': [],
      'unscheduled_tasks': [],
      'skipped_immutable': [
        {'task_id': 'done', 'title': 'Done', 'change_type': 'protected'}
      ],
      'conflicts': [],
      'explanation': 'x',
      'timezone_used': 'Asia/Kolkata',
      if (applyRequest != null) 'apply_request': applyRequest,
    };

void main() {
  group('Replan apply request (findings 5 and 6)', () {
    final serverRequest = {
      'plan_id': 'plan-1',
      'selected_date': '2026-10-05',
      'task_updates': [
        {
          'task_id': 'gym',
          'scheduled_start': '2026-10-06T11:30:00Z',
          'scheduled_end': '2026-10-06T12:30:00Z',
          'expected_updated_at': '2026-10-05T03:00:00.123456Z',
          'user_override': false,
        },
        {
          // explicit null: "clear this task's slot" must survive the round trip
          'task_id': 'missed',
          'scheduled_start': null,
          'scheduled_end': null,
          'planned_date': '2026-10-05',
          'expected_updated_at': '2026-10-05T03:00:00Z',
        }
      ],
      'new_tasks': [
        {
          'title': 'Fix bug',
          'estimated_minutes': 120,
          'priority': 'urgent',
          'source': 'manual',
          'time_locked': true
        }
      ],
      'cancelled_task_ids': ['old'],
      'timezone': 'Asia/Kolkata',
    };

    test(
        'uses the server-authored apply_request verbatim (no title matching, no guessing)',
        () {
      final diff = PlanDiff.fromJson(_diffJson(applyRequest: serverRequest));
      final req = diff.toApplyRequest();
      final json = req.toJson();
      expect(
          json['task_updates'][0]['scheduled_start'], '2026-10-06T11:30:00Z');
      expect(json['task_updates'][0]['expected_updated_at'],
          '2026-10-05T03:00:00.123456Z');
      expect(json['new_tasks'][0]['priority'], 'urgent',
          reason: 'urgent priority must not be dropped');
      expect(json['new_tasks'][0]['source'], 'manual',
          reason: "'quick_add' is not a valid source and made apply 422");
      expect(json['cancelled_task_ids'], ['old']);
    });

    test('explicit nulls are preserved so a slot can be cleared', () {
      final json = PlanDiff.fromJson(_diffJson(applyRequest: serverRequest))
          .toApplyRequest()
          .toJson();
      final clear = (json['task_updates'] as List)[1] as Map;
      expect(clear.containsKey('scheduled_start'), isTrue);
      expect(clear['scheduled_start'], isNull);
      expect(clear['planned_date'], '2026-10-05');
    });

    test(
        'withClock adds the IANA zone and an aware UTC clock without touching the plan',
        () {
      final now = DateTime(2026, 10, 5, 9, 0);
      final json = PlanDiff.fromJson(_diffJson(applyRequest: serverRequest))
          .toApplyRequest()
          .withClock(now, timezoneName: 'Asia/Kolkata')
          .toJson();
      expect(json['timezone'], 'Asia/Kolkata');
      expect((json['current_local_time'] as String).endsWith('Z'), isTrue);
      expect(json['plan_id'], 'plan-1');
      expect((json['task_updates'] as List).length, 2);
    });

    test(
        'a "move to tomorrow" diff item carries real instants, not just a label',
        () {
      final diff = PlanDiff.fromJson(_diffJson(applyRequest: serverRequest));
      final moved = diff.movedTasks.single;
      expect(moved.newDate, 'Tomorrow');
      expect(moved.newDateIso, '2026-10-06');
      expect(moved.newStart, isNotNull);
      expect(moved.newStart!.toUtc(), DateTime.utc(2026, 10, 6, 11, 30));
      expect(
          moved.newEnd!.difference(moved.newStart!), const Duration(hours: 1));
    });

    test('protected (completed / in-progress) items are parsed for display',
        () {
      final diff = PlanDiff.fromJson(_diffJson(applyRequest: serverRequest));
      expect(diff.skippedImmutable.single.title, 'Done');
      expect(diff.timezoneUsed, 'Asia/Kolkata');
    });

    test(
        'offline fallback builder keeps urgent priority and uses a valid source',
        () {
      final diff = PlanDiff.fromJson(_diffJson()); // no server apply_request
      final json = diff.toApplyRequest().toJson();
      final created = (json['new_tasks'] as List).single as Map;
      expect(created['priority'], 'urgent');
      expect(created['source'], 'manual');
    });
  });
}
