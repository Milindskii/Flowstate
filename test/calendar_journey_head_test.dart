import 'package:flowstate/components/day_path/day_route_geometry.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// The journey head: after an old stop is recovered, the road ahead starts from IT (the traveller's real position),
/// while every stop keeps its place on the timeline.

ScheduleItem item(
  String id, {
  bool completed = false,
  bool recovered = false,
  bool missed = false,
  bool skipped = false,
  String? deviation,
}) =>
    ScheduleItem(
      id: id,
      time: '9:00',
      period: 'AM',
      title: 'Task $id',
      type: 'Task',
      tagText: 'TASK',
      isCompleted: completed,
      isCompletedAfterDeviation: recovered,
      isMissed: missed,
      isSkipped: skipped,
      deviation: deviation,
    );

const w = 360.0;
final ids = ['A', 'B', 'C', 'D', 'E', 'F'];
DateTime at(int h) => DateTime(2026, 10, 9, h);

/// A B C D E F. [done] maps a finished stop to the hour it was finished; [recovered] are stops done after a miss.
DayRouteGeometry day(
  Map<String, int> done, {
  Set<String> recovered = const {},
  Set<String> missed = const {'B'},
  bool finish = false,
}) {
  final items = [
    for (final id in ids)
      item(id,
          completed: done.containsKey(id),
          recovered: recovered.contains(id),
          missed: !done.containsKey(id) && missed.contains(id)),
  ];
  return DayRouteGeometry.compute(items, null, w, finish: finish, completedAt: {for (final e in done.entries) e.key: at(e.value)});
}

bool hiddenBetween(DayRouteGeometry g, String a, String b) {
  final from = g.stopById(a).center.dy;
  final to = g.stopById(b).center.dy;
  final states = [
    for (var i = 0; i < g.sampleYs.length; i++)
      if (g.sampleYs[i] > from && g.sampleYs[i] < to) g.sampleStates[i]
  ];
  return states.isNotEmpty && states.every((x) => x == RouteSegmentState.hidden);
}

RecoveryBranch? branch(DayRouteGeometry g, String from, String to) {
  for (final b in g.branches) {
    if (b.fromId == from && b.toId == to) return b;
  }
  return null;
}

void main() {
  test('before the recovery: B is missed, the head is D and the road simply goes on from D', () {
    final g = day({'A': 9, 'C': 10, 'D': 11});
    expect(g.branches, isEmpty);
    expect(g.sampleStates, isNot(contains(RouteSegmentState.hidden)));
  });

  test('A, C, D done, B recovered: orange D -> B, and the road ahead starts at B, not at D', () {
    final before = day({'A': 9, 'C': 10, 'D': 11});
    final g = day({'A': 9, 'C': 10, 'D': 11, 'B': 12}, recovered: {'B'});

    expect(branch(g, 'D', 'B')?.state, RouteSegmentState.recovered, reason: 'the way back is orange');
    expect(g.stopById('B').center, before.stopById('B').center, reason: 'B keeps its place on the timeline');
    for (final id in ids) {
      expect(g.stopById(id).center, before.stopById(id).center, reason: '$id never moves');
    }

    final forward = branch(g, 'B', 'E');
    expect(forward, isNotNull, reason: 'the next stop is reached from B');
    expect(forward!.state, RouteSegmentState.ahead);
    expect(forward.points.first, g.stopById('B').center);
    expect(hiddenBetween(g, 'D', 'E'), isTrue, reason: 'no road leaves D any more');
    expect(g.branches.where((b) => b.fromId == 'A' || b.fromId == 'C'), isEmpty, reason: 'nothing starts from A or C');
    expect(g.branches.where((b) => b.fromId == 'D' && b.toId != 'B'), isEmpty);
    expect(g.branches.where((b) => b.toId == 'E'), hasLength(1), reason: 'one road into E, never a duplicate');
    expect(g.branches, hasLength(2));
    // the rest of the road is untouched
    expect(hiddenBetween(g, 'A', 'B'), isFalse);
    expect(hiddenBetween(g, 'E', 'F'), isFalse);
  });

  test('the branches are the same kind of road as the main road: continuous, ending exactly at their nodes', () {
    final g = day({'A': 9, 'C': 10, 'D': 11, 'B': 12}, recovered: {'B'});
    for (final b in g.branches) {
      expect(b.points.length, greaterThan(2));
      expect(b.points.first, g.stopById(b.fromId).center);
      for (var i = 0; i + 1 < b.points.length; i++) {
        expect((b.points[i + 1] - b.points[i]).distance, lessThan(DayRouteGeometry.sampleStep + 8), reason: 'no jumps');
      }
    }
    expect(g.branches.map((b) => b.state), containsAll([RouteSegmentState.recovered, RouteSegmentState.ahead]));
  });

  test('completing the next stop after the recovery: the road into it comes from B, still one road', () {
    final g = day({'A': 9, 'C': 10, 'D': 11, 'B': 12, 'E': 13}, recovered: {'B'});
    final fromB = branch(g, 'B', 'E');
    expect(fromB, isNotNull);
    expect(fromB!.state, RouteSegmentState.traveled);
    expect(hiddenBetween(g, 'D', 'E'), isTrue);
    expect(g.branches.where((b) => b.toId == 'E'), hasLength(1));
    expect(branch(g, 'D', 'E'), isNull);
    expect(hiddenBetween(g, 'E', 'F'), isFalse, reason: 'the head is now E: F continues from E on the plain road');
    expect(g.branches.where((b) => b.fromId == 'E'), isEmpty);
    expect(g.stopById('E').center, day({'A': 9}).stopById('E').center);
  });

  test('undoing the recovery brings the plain road back, exactly as before', () {
    final before = day({'A': 9, 'C': 10, 'D': 11});
    final recovered = day({'A': 9, 'C': 10, 'D': 11, 'B': 12}, recovered: {'B'});
    final undone = day({'A': 9, 'C': 10, 'D': 11});
    expect(recovered.sameRoute(before), isFalse);
    expect(undone.sameRoute(before), isTrue);
    expect(undone.branches, isEmpty);
    expect(undone.sampleStates, isNot(contains(RouteSegmentState.hidden)));
  });

  test('normal completion in order never hides or branches anything', () {
    final g = day({'A': 9, 'B': 10, 'C': 11}, missed: {});
    expect(g.branches, isEmpty);
    expect(g.sampleStates, isNot(contains(RouteSegmentState.hidden)));
  });

  test('a skipped stop is not a recovery: the road bends around it and goes on from the last finished stop', () {
    final items = [
      item('A', completed: true),
      item('B', skipped: true, deviation: 'skipped'),
      item('C', completed: true),
      item('D'),
    ];
    final g = DayRouteGeometry.compute(items, null, w, completedAt: {'A': at(9), 'C': at(10)});
    expect(g.branches, isEmpty);
    expect(g.sampleStates, isNot(contains(RouteSegmentState.hidden)));
  });

  test('several out-of-order recoveries: each new head starts the road ahead', () {
    // A and D finished, then B recovered, then C recovered: the head is C.
    final g = day({'A': 9, 'D': 10, 'B': 11, 'C': 12}, recovered: {'B', 'C'}, missed: {});
    final plain = day({});
    expect(branch(g, 'D', 'B')?.state, RouteSegmentState.recovered);
    expect(branch(g, 'C', 'E')?.state, RouteSegmentState.ahead, reason: 'E follows from the head C');
    expect(hiddenBetween(g, 'D', 'E'), isTrue);
    expect(g.branches.where((b) => b.toId == 'E'), hasLength(1));
    for (final id in ids) {
      expect(g.stopById(id).center, plain.stopById(id).center, reason: '$id stays on its timeline slot');
    }
  });

  test('when the day is complete the road to the Trophy leaves the head too', () {
    final done = {'A': 9, 'C': 10, 'D': 11, 'E': 12, 'F': 13, 'B': 14};
    final g = day(done, recovered: {'B'}, finish: true);
    final toFinish = branch(g, 'B', DayRouteGeometry.finishId);
    expect(toFinish, isNotNull);
    expect(toFinish!.state, RouteSegmentState.traveled);
  });
}
