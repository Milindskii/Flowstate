import 'package:flowstate/engines/day_path_order.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/services/day_path_anchor_store.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _at(int h, [int m = 0]) => DateTime(2026, 10, 7, h, m);

ScheduleItem _live(String task, DateTime start) => ScheduleItem(
      id: 'sched-$task',
      taskId: task,
      time: '${start.hour}:00',
      period: 'AM',
      title: 'Task $task',
      type: 'Task',
      tagText: 'TASK',
      startTime: start,
    );

void main() {
  const day = '2026-10-07';

  test('the ledger still holds against server re-suggestions (first seen wins)', () {
    final store = DayPathAnchorStore();
    store.record(day, {'B': _at(9)});
    store.record(day, {'B': _at(13)});
    expect(store.forDay(day)['B']!.anchor, _at(9));
  });

  test('an authoritative time corrects a stale anchor and keeps its order', () {
    final store = DayPathAnchorStore();
    store.record(day, {'A': _at(8), 'B': _at(9)});
    final seq = store.forDay(day)['B']!.seq;
    expect(store.reconcile(day, {'B': _at(14)}), isTrue);
    expect(store.forDay(day)['B']!.anchor, _at(14));
    expect(store.forDay(day)['B']!.seq, seq);
    expect(store.forDay(day)['A']!.anchor, _at(8), reason: 'others are untouched');
    expect(store.reconcile(day, {'B': _at(14)}), isFalse, reason: 'already agrees');
    expect(store.reconcile(day, {'Z': _at(14)}), isFalse, reason: 'unknown tasks are not invented');
  });

  test('stops carry the time they were ordered by, so the route and the order always agree', () {
    final stops = buildCanonicalDayStops(
      live: [_live('A', _at(8)), _live('B', _at(13))],
      anchors: {'B': DayPathAnchorHint(anchor: _at(9))},
    );
    expect(stops.map((s) => s.taskId), ['A', 'B']);
    expect(stops[1].anchorStart, _at(9), reason: 'the ledger anchor, not the live 13:00 slot');
  });
}
