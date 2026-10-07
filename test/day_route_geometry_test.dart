import 'package:flowstate/components/day_path/day_route_geometry.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleItem item(
  String id, {
  bool completed = false,
  bool skipped = false,
  bool recovered = false,
  bool failed = false,
  bool missed = false,
  bool commitment = false,
  String? deviation,
  int at = 0,
  String? state,
}) =>
    ScheduleItem(
      id: id,
      time: '9:00',
      period: 'AM',
      title: 'Task $id',
      type: 'Task',
      tagText: 'TASK',
      isCompleted: completed,
      isSkipped: skipped,
      isCompletedAfterDeviation: recovered,
      isFailed: failed,
      isMissed: missed,
      isCommitment: commitment,
      deviation: deviation,
      state: state,
      startTime: DateTime(2026, 10, 7, 9).add(Duration(minutes: at)),
    );

const w = 360.0;

DayRouteGeometry geo(List<ScheduleItem> items, {String? now, bool finish = false}) =>
    DayRouteGeometry.compute(items, now, w, finish: finish);

/// The state of every sample strictly between [a] and [b] ([a] is the earlier stop: higher on the screen, smaller y):
/// the one stretch of road between two neighbouring stops.
List<RouteSegmentState> between(DayRouteGeometry g, StopGeometry a, StopGeometry b) => [
      for (var i = 0; i < g.sampleYs.length; i++)
        if (g.sampleYs[i] > a.center.dy && g.sampleYs[i] < b.center.dy) g.sampleStates[i]
    ];

bool allAre(List<RouteSegmentState> states, RouteSegmentState s) => states.isNotEmpty && states.every((x) => x == s);

void main() {
  final four = [item('a', at: 0), item('b', at: 60), item('c', at: 120), item('d', at: 180)];

  test('A. planned: stops run chronologically from the top down, all on one blue road', () {
    final g = geo(four);
    for (var i = 0; i + 1 < g.stops.length; i++) {
      expect(g.stops[i].center.dy, lessThan(g.stops[i + 1].center.dy));
    }
    expect(g.stops.every((s) => s.role == StopRouteRole.onRoute && !s.deviated), isTrue);
    expect(g.sampleStates.every((s) => s == RouteSegmentState.ahead), isTrue);
    expect(g.detours, isEmpty);
    for (final s in g.stops) {
      expect(g.distanceToRoute(s.center), lessThan(0.5));
    }
  });

  test('A. the route is centred in the viewport and stays inside it, deviations included', () {
    final items = [for (var i = 0; i < 8; i++) item('t$i', at: i * 45, skipped: i.isOdd)];
    final g = geo(items);
    expect(g.sampleXs.every((x) => x > 20 && x < w - 20), isTrue);
    for (final d in g.detours) {
      expect(d.points.every((p) => p.dx >= 0 && p.dx <= w), isTrue);
    }
  });

  test('A. the room between stops follows the time between them (a longer gap = a longer road)', () {
    final tight = geo([item('a', at: 0), item('b', at: 0)]);
    final wide = geo([item('a', at: 0), item('b', at: 240)]);
    final gapTight = tight.stops[1].center.dy - tight.stops[0].center.dy;
    final gapWide = wide.stops[1].center.dy - wide.stops[0].center.dy;
    expect(gapTight, DayRouteGeometry.minSpacing);
    expect(gapWide, greaterThan(gapTight));
    expect(gapWide, lessThanOrEqualTo(DayRouteGeometry.maxSpacing));
  });

  test('B. completed stops turn the walked stretch green; the road ahead stays blue', () {
    final g = geo([item('a', completed: true, at: 0), item('b', completed: true, at: 60), item('c', at: 120), item('d', at: 180)], now: 'c');
    final a = g.stopById('a'), b = g.stopById('b'), c = g.stopById('c'), d = g.stopById('d');
    expect(allAre(between(g, a, b), RouteSegmentState.traveled), isTrue);
    expect(allAre(between(g, b, c), RouteSegmentState.traveled), isTrue, reason: 'the stretch into NOW is walked');
    expect(allAre(between(g, c, d), RouteSegmentState.ahead), isTrue, reason: 'beyond NOW is still ahead');
  });

  test('C. skipped: the node stays at its slot, the road swings out beside it and carries on to the next stop', () {
    final planned = geo(four);
    final g = geo([item('a', at: 0), item('b', at: 60, skipped: true), item('c', at: 120), item('d', at: 180)]);
    final b = g.stopById('b');
    expect(b.role, StopRouteRole.skipped);
    expect(b.center, planned.stopById('b').center, reason: 'the node keeps its planned place');
    expect(b.deviated, isTrue);
    expect(g.distanceToRoute(b.center), closeTo(DayRouteGeometry.bypassOffset, 1.5), reason: 'the road passes BESIDE the node');
    expect(g.distanceToRoute(b.center), greaterThan(DayRouteGeometry.nodeRadius + DayRouteGeometry.nearHalfWidth));
    // the road is still one continuous line through the other stops, and on to the next one
    for (final id in ['a', 'c', 'd']) {
      expect(g.distanceToRoute(g.stopById(id).center), lessThan(0.5), reason: '$id stays on the road');
    }
    for (var i = 0; i + 1 < g.sampleYs.length; i++) {
      expect(g.sampleYs[i + 1] - g.sampleYs[i], lessThanOrEqualTo(DayRouteGeometry.sampleStep + 0.01), reason: 'no gap');
    }
    expect(g.sameRoute(planned), isFalse, reason: 'the skip is visible in the route');
    expect(g.detours, isEmpty, reason: 'no orange until it is recovered');
  });

  test('C. the road swings out on the side away from the label', () {
    final g = geo([item('a', at: 0, skipped: true), item('b', at: 60, skipped: true), item('c', at: 120, skipped: true)]);
    for (final s in g.stops) {
      expect(s.routeX > s.center.dx, s.labelOnLeft, reason: '${s.id}: label on the left means the road passes on the right');
    }
  });

  test('C. missed (slot ended) and failed stops are bypassed the same way; a deferred history node is a skip', () {
    final g = geo([item('a', at: 0), item('m', at: 60, missed: true), item('f', at: 120, failed: true), item('h', at: 180, deviation: 'deferred')]);
    expect(g.stopById('m').role, StopRouteRole.bypassed);
    expect(g.stopById('f').role, StopRouteRole.failed);
    expect(g.stopById('h').role, StopRouteRole.skipped);
    for (final id in ['m', 'f', 'h']) {
      expect(g.stopById(id).deviated, isTrue);
    }
  });

  test('a commitment is a normal stop on the route', () {
    final g = geo([item('a'), item('go', commitment: true, missed: true), item('c')]);
    expect(g.stopById('go').role, StopRouteRole.onRoute);
    expect(g.stopById('go').deviated, isFalse);
  });

  test('D. recovering: an orange way back leaves the road at the next point, goes up to the node and rejoins below it', () {
    final g = geo([item('a', at: 0), item('b', at: 60, state: 'recovering'), item('c', at: 120), item('d', at: 180)]);
    final b = g.stopById('b'), c = g.stopById('c');
    expect(b.role, StopRouteRole.recovering);
    expect(b.deviated, isTrue);
    expect(g.detours, hasLength(1));
    final d = g.detours.single;
    expect(d.stopId, 'b');
    expect((d.points.first - Offset(c.routeX, c.center.dy)).distance, lessThan(0.5), reason: 'it leaves the road at the next stop');
    expect((d.points.last - b.center).distance, lessThan(0.5), reason: 'and arrives at the skipped node');
    expect(d.points.first.dy, greaterThan(d.points.last.dy), reason: 'it travels BACK up the day');
    expect(allAre(between(g, b, c), RouteSegmentState.recovered), isTrue, reason: 'the road home from the node is orange');
    expect(allAre(between(g, c, g.stopById('d')), RouteSegmentState.ahead), isTrue);
  });

  test('D. recovered (done after a skip): the deviation stays in the route, the node is done', () {
    final g = geo([item('a', completed: true, at: 0), item('b', completed: true, recovered: true, at: 60), item('c', completed: true, at: 120), item('d', at: 180)], now: 'd');
    final b = g.stopById('b');
    expect(b.role, StopRouteRole.recovered);
    expect(b.walked, isFalse, reason: 'recovered is not part of the normal walked route');
    expect(b.deviated, isTrue, reason: 'completing it does not pretend the deviation never happened');
    expect(g.detours.map((d) => d.stopId), ['b']);
    expect(allAre(between(g, b, g.stopById('c')), RouteSegmentState.recovered), isTrue);
    expect(allAre(between(g, g.stopById('c'), g.stopById('d')), RouteSegmentState.traveled), isTrue);
  });

  test('D. recovering -> recovered keeps the same geometry (only the node changes)', () {
    final doing = geo([item('a', at: 0), item('b', at: 60, state: 'recovering'), item('c', at: 120)]);
    final done = geo([item('a', at: 0), item('b', at: 60, completed: true, recovered: true), item('c', at: 120)]);
    expect(done.sampleXs, doing.sampleXs);
    expect(done.detours.single.points, doing.detours.single.points);
  });

  test('D. a recovered LAST stop still loops back to its node', () {
    final g = geo([item('a', at: 0), item('b', at: 60, completed: true, recovered: true)]);
    expect(g.detours, hasLength(1));
    expect((g.detours.single.points.last - g.stopById('b').center).distance, lessThan(0.5));
  });

  test('E. rescheduling a task changes the route: its stop, the gaps around it and the bend all move', () {
    final before = geo([item('a', at: 0), item('b', at: 30), item('c', at: 240)]);
    final after = geo([item('a', at: 0), item('b', at: 200), item('c', at: 240)]);
    expect(after.stopById('b').center, isNot(before.stopById('b').center));
    expect(after.stopById('b').center.dy, isNot(before.stopById('b').center.dy));
    expect(after.sameRoute(before), isFalse);
    expect(after.stopById('a').center, before.stopById('a').center, reason: 'untouched stops stay');
  });

  test('E. moving a task past another reorders the stops on the road', () {
    final g = geo([item('a', at: 0), item('c', at: 60), item('b', at: 120)]);
    expect(g.stops.map((s) => s.id), ['a', 'c', 'b']);
  });

  test('F. deleting a stop closes the road around the remaining stops', () {
    final all = geo(four);
    final three = geo([four[0], four[2], four[3]]);
    expect(three.stops.map((s) => s.id), ['a', 'c', 'd']);
    expect(three.height, lessThan(all.height));
    for (final s in three.stops) {
      expect(three.distanceToRoute(s.center), lessThan(0.5));
    }
  });

  test('F. deleting a recovered stop removes its orange way back too', () {
    final withB = geo([item('a', at: 0), item('b', at: 60, completed: true, recovered: true), item('c', at: 120)]);
    final without = geo([item('a', at: 0), item('c', at: 120)]);
    expect(withB.detours, hasLength(1));
    expect(without.detours, isEmpty);
  });

  test('skipping the first and the last stop still leaves one continuous road', () {
    final g = geo([item('a', at: 0, skipped: true), item('b', at: 60), item('c', at: 120, skipped: true)]);
    expect(g.sampleYs.first, g.stopById('a').center.dy);
    expect(g.sampleYs.last, g.stopById('c').center.dy);
    for (var i = 0; i + 1 < g.sampleYs.length; i++) {
      expect(g.sampleYs[i + 1] - g.sampleYs[i], lessThanOrEqualTo(DayRouteGeometry.sampleStep + 0.01));
    }
  });

  test('every state at once: one continuous, gap-free route and a detour for the recovered stop', () {
    final items = [
      item('a', completed: true, at: 0),
      item('b', skipped: true, at: 40),
      item('c', completed: true, recovered: true, at: 80),
      item('d', missed: true, at: 120),
      item('e', failed: true, at: 160),
      item('f', at: 200),
    ];
    final g = geo(items, now: 'f');
    expect(g.detours.map((d) => d.stopId), ['c']);
    for (var i = 0; i + 1 < g.sampleYs.length; i++) {
      expect(g.sampleYs[i + 1] - g.sampleYs[i], lessThanOrEqualTo(DayRouteGeometry.sampleStep + 0.01), reason: 'no gap');
    }
  });

  test('labels sit opposite the bend of the road', () {
    final g = geo([for (var i = 0; i < 8; i++) item('t$i', at: i * 30)]);
    for (final s in g.stops) {
      if ((s.center.dx - w / 2).abs() > 10) {
        expect(s.labelOnLeft, s.center.dx > w / 2);
      }
    }
  });

  test('every stop is drawn at the same size and the road keeps one width', () {
    final g = geo([for (var i = 0; i < 6; i++) item('t$i')]);
    expect(g.stops.every((s) => s.scale == g.stops.first.scale), isTrue);
    expect(g.halfWidthAt(10), g.halfWidthAt(g.height - 10));
  });

  test('the road begins at the first stop and ends at the last stop', () {
    for (final n in [2, 4, 6, 9]) {
      final g = geo([for (var i = 0; i < n; i++) item('t$i', at: i * 50)]);
      expect(g.sampleYs.first, closeTo(g.stops.first.center.dy, 0.01));
      expect(g.sampleYs.last, closeTo(g.stops.last.center.dy, 0.01));
      expect(g.tailStart, g.sampleYs.length);
    }
  });

  test('stops have room: at least 130 logical px apart, and all fit inside the scrollable height', () {
    for (final n in [2, 4, 6, 8, 12]) {
      final g = geo([for (var i = 0; i < n; i++) item('t$i', at: i * 20)]);
      for (var i = 0; i + 1 < n; i++) {
        expect(g.stops[i + 1].center.dy - g.stops[i].center.dy, greaterThanOrEqualTo(130));
      }
      expect(g.stops.every((s) => s.center.dy > 0 && s.center.dy < g.height), isTrue);
    }
  });

  group('morphing between two routes', () {
    test('lerp at 1 is the new route and at 0 starts from the old one, with the new stops', () {
      final a = geo([item('a', at: 0), item('b', at: 30), item('c', at: 240)]);
      final b = geo([item('a', at: 0), item('b', at: 200), item('c', at: 240)]);
      expect(identical(DayRouteGeometry.lerp(a, b, 1), b), isTrue);
      final start = DayRouteGeometry.lerp(a, b, 0);
      expect(start.stops.map((s) => s.id), b.stops.map((s) => s.id));
      expect(start.stopById('b').center.dy, closeTo(a.stopById('b').center.dy, 0.01));
      final mid = DayRouteGeometry.lerp(a, b, 0.5);
      final y0 = a.stopById('b').center.dy, y1 = b.stopById('b').center.dy;
      expect(mid.stopById('b').center.dy, closeTo((y0 + y1) / 2, 0.01));
      expect(mid.sampleXs.length, b.sampleXs.length);
    });

    test('a deleted stop: the road resamples smoothly onto the shorter route', () {
      final a = geo(four);
      final b = geo([four[0], four[2], four[3]]);
      final mid = DayRouteGeometry.lerp(a, b, 0.5);
      expect(mid.stops.length, 3);
      expect(mid.height, closeTo((a.height + b.height) / 2, 0.01));
      expect(mid.sampleYs.first, closeTo((a.sampleYs.first + b.sampleYs.first) / 2, 0.01));
    });

    test('a new orange detour draws in, a removed one draws out', () {
      final plain = geo([item('a', at: 0), item('b', at: 60, skipped: true), item('c', at: 120)]);
      final recovered = geo([item('a', at: 0), item('b', at: 60, state: 'recovering'), item('c', at: 120)]);
      final drawIn = DayRouteGeometry.lerp(plain, recovered, 0.4);
      expect(drawIn.detours.single.reveal, closeTo(0.4, 1e-9));
      final drawOut = DayRouteGeometry.lerp(recovered, plain, 0.4);
      expect(drawOut.detours.single.reveal, closeTo(0.6, 1e-9));
    });

    test('a different width never morphs', () {
      final a = DayRouteGeometry.compute(four, null, 360);
      final b = DayRouteGeometry.compute(four, null, 400);
      expect(identical(DayRouteGeometry.lerp(a, b, 0.5), b), isTrue);
    });
  });

  group('the finish (Trophy) at the end of the road', () {
    test('without a finish there is none', () {
      expect(geo([item('a'), item('b')]).finish, isNull);
    });

    test('a finish sits below the last stop on the same road, which is green into it', () {
      final plain = geo([item('a', completed: true), item('b', completed: true)]);
      final g = geo([item('a', completed: true), item('b', completed: true)], finish: true);
      final end = g.finish!;
      expect(g.stops.length, 2, reason: 'the finish is not a task stop');
      expect(end.center.dy, greaterThan(g.stops.last.center.dy));
      expect(end.center.dy - g.stops.last.center.dy, DayRouteGeometry.defaultSpacing);
      expect(g.distanceToRoute(end.center), lessThan(0.5));
      expect(g.sampleYs.last, closeTo(end.center.dy, 0.01), reason: 'the road ends at the finish');
      expect(allAre(between(g, g.stops.last, end), RouteSegmentState.traveled), isTrue);
      expect(g.height, greaterThan(plain.height));
      for (var i = 0; i < plain.stops.length; i++) {
        expect(g.stops[i].center, plain.stops[i].center, reason: 'adding the finish moves no stop');
      }
    });

    test('a finish after skipped / recovered stops still follows the one road', () {
      final items = [item('a', completed: true, at: 0), item('b', skipped: true, at: 60), item('c', completed: true, recovered: true, at: 120)];
      final g = geo(items, finish: true);
      expect(g.distanceToRoute(g.finish!.center), lessThan(0.5));
      expect(g.detours.map((d) => d.stopId), ['c']);
      expect((g.detours.single.points.first - Offset(g.finish!.routeX, g.finish!.center.dy)).distance, lessThan(0.5));
    });
  });
}
