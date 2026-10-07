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

/// The road is the same line: every stop sits on it, and its shape does not depend on any stop's state.
void expectSameRoad(DayRouteGeometry g, DayRouteGeometry reference) {
  expect(g.layoutSignature, reference.layoutSignature);
  expect(g.sampleYs, reference.sampleYs);
  expect(g.sampleXs, reference.sampleXs);
  for (final s in g.stops) {
    expect(g.distanceToRoute(s.center), lessThan(0.5), reason: '${s.id} is on the route');
  }
}

void main() {
  test('stops run chronologically from the top (first task) down to the bottom (last task)', () {
    final g = geo([item('a'), item('b'), item('c')]);
    expect(g.stops[0].center.dy, lessThan(g.stops[1].center.dy));
    expect(g.stops[1].center.dy, lessThan(g.stops[2].center.dy));
    expect(g.stops.first.scale, 1.0);
    expect(g.stops.last.scale, closeTo(DayRouteGeometry.farScale, 1e-9));
  });

  test('the route is centred in the viewport and stays inside it', () {
    final g = geo([for (var i = 0; i < 8; i++) item('t$i')]);
    for (final s in g.stops) {
      expect((s.center.dx - w / 2).abs(), lessThanOrEqualTo(w * 0.23 + 1));
    }
    expect(g.sampleXs.every((x) => x > 20 && x < w - 20), isTrue);
  });

  test('all-future: one blue route through every stop', () {
    final g = geo([item('a'), item('b'), item('c')]);
    expect(g.stops.every((s) => s.role == StopRouteRole.onRoute), isTrue);
    expect(g.sampleStates.every((s) => s == RouteSegmentState.ahead), isTrue);
    for (final s in g.stops) {
      expect(g.distanceToRoute(s.center), lessThan(0.5));
    }
  });

  test('completed stops turn the walked stretch green; the road ahead stays blue', () {
    final g = geo([item('a', completed: true), item('b', completed: true), item('c'), item('d')], now: 'c');
    final a = g.stopById('a'), b = g.stopById('b'), c = g.stopById('c'), d = g.stopById('d');
    expect(allAre(between(g, a, b), RouteSegmentState.traveled), isTrue);
    expect(allAre(between(g, b, c), RouteSegmentState.traveled), isTrue, reason: 'the stretch into NOW is walked');
    expect(allAre(between(g, c, d), RouteSegmentState.ahead), isTrue, reason: 'beyond NOW is still ahead');
  });

  test('a skipped stop changes its node only: the road is the same line and stays blue through it', () {
    final all = geo([item('a'), item('b'), item('c'), item('d')]);
    final g = geo([item('a'), item('b', skipped: true), item('c'), item('d')]);
    final a = g.stopById('a'), b = g.stopById('b'), c = g.stopById('c'), d = g.stopById('d');
    expect(b.role, StopRouteRole.skipped);
    expectSameRoad(g, all);
    expect(allAre(between(g, a, b), RouteSegmentState.ahead), isTrue, reason: 'blue runs INTO the skipped stop');
    expect(allAre(between(g, b, c), RouteSegmentState.ahead), isTrue, reason: 'and on out of it');
    expect(allAre(between(g, c, d), RouteSegmentState.ahead), isTrue);
  });

  test('skipped between two done stops: blue into it (it was not walked), green after it', () {
    final g = geo([item('a', completed: true), item('b', skipped: true), item('c', completed: true), item('d')], now: 'd');
    final a = g.stopById('a'), b = g.stopById('b'), c = g.stopById('c'), d = g.stopById('d');
    expect(allAre(between(g, a, b), RouteSegmentState.ahead), isTrue);
    expect(allAre(between(g, b, c), RouteSegmentState.traveled), isTrue);
    expect(allAre(between(g, c, d), RouteSegmentState.traveled), isTrue);
    expectSameRoad(g, geo([item('a'), item('b'), item('c'), item('d')]));
  });

  test('a deferred history node is a skipped node on the same road', () {
    final g = geo([item('a'), item('h', deviation: 'deferred'), item('c')]);
    expect(g.stopById('h').role, StopRouteRole.skipped);
    expectSameRoad(g, geo([item('a'), item('h'), item('c')]));
  });

  test('a recovered stop: the orange state follows the SAME winding route, no separate line', () {
    final g = geo([item('a', completed: true), item('b', completed: true, recovered: true), item('c', completed: true), item('d')], now: 'd');
    final a = g.stopById('a'), b = g.stopById('b'), c = g.stopById('c'), d = g.stopById('d');
    expect(b.role, StopRouteRole.recovered);
    expect(b.walked, isFalse, reason: 'recovered is not part of the normal walked route');
    expectSameRoad(g, geo([item('a'), item('b'), item('c'), item('d')]));
    expect(allAre(between(g, a, b), RouteSegmentState.recovered), isTrue, reason: 'the way into B is orange');
    expect(allAre(between(g, b, c), RouteSegmentState.traveled), isTrue);
    expect(allAre(between(g, c, d), RouteSegmentState.traveled), isTrue);
    // orange samples lie on the very polyline that green and blue ones do
    for (var i = 0; i < g.sampleYs.length; i++) {
      if (g.sampleStates[i] == RouteSegmentState.recovered) {
        expect(g.distanceToRoute(Offset(g.sampleXs[i], g.sampleYs[i])), lessThan(1e-6));
      }
    }
  });

  test('A recovered, B normal, C normal: only the stretch into A changes colour', () {
    final g = geo([item('a', completed: true), item('b', completed: true, recovered: true), item('c'), item('d')], now: 'c');
    final states = g.sampleStates.toSet();
    expect(states, containsAll([RouteSegmentState.traveled, RouteSegmentState.recovered, RouteSegmentState.ahead]));
  });

  test('a missed stop stays at its planned position and on the road; only its node says it was missed', () {
    final all = geo([item('a'), item('m'), item('c')]);
    final g = geo([item('a'), item('m', missed: true), item('c')]);
    final m = g.stopById('m');
    expect(m.role, StopRouteRole.bypassed);
    expect(g.stops.map((s) => s.id).toList(), ['a', 'm', 'c'], reason: 'chronological order is preserved');
    expect(m.center, all.stopById('m').center, reason: 'the node does not move');
    expectSameRoad(g, all);
  });

  test('failed is a red node on the same road (red is reserved for true failure)', () {
    final g = geo([item('a'), item('f', failed: true), item('c')]);
    expect(g.stopById('f').role, StopRouteRole.failed);
    expectSameRoad(g, geo([item('a'), item('f'), item('c')]));
  });

  test('a commitment is a normal stop on the route', () {
    final g = geo([item('a'), item('go', commitment: true), item('c')]);
    expect(g.stopById('go').role, StopRouteRole.onRoute);
  });

  test('skipping the first and the last stop still leaves one continuous road through them', () {
    final g = geo([item('a', skipped: true), item('b'), item('c', skipped: true)]);
    expectSameRoad(g, geo([item('a'), item('b'), item('c')]));
    expect(g.sampleYs.first, g.stopById('a').center.dy);
    expect(g.sampleYs.last, g.stopById('c').center.dy);
  });

  test('every state at once: one continuous, gap-free route through all stops', () {
    final items = [
      item('a', completed: true),
      item('b', skipped: true),
      item('c', completed: true, recovered: true),
      item('d', missed: true),
      item('e', failed: true),
      item('f'),
    ];
    final g = geo(items, now: 'f');
    expectSameRoad(g, geo([for (final i in items) item(i.id)]));
    for (var i = 0; i + 1 < g.sampleYs.length; i++) {
      expect(g.sampleYs[i + 1] - g.sampleYs[i], lessThanOrEqualTo(DayRouteGeometry.sampleStep + 0.01), reason: 'no gap');
    }
  });

  test('deleting a stop recomputes the road around the remaining stops', () {
    final four = geo([item('a'), item('b'), item('c'), item('d')]);
    final three = geo([item('a'), item('c'), item('d')]);
    expect(three.stops.map((s) => s.id), ['a', 'c', 'd']);
    expect(three.height, lessThan(four.height));
    for (final s in three.stops) {
      expect(three.distanceToRoute(s.center), lessThan(0.5));
    }
  });

  test('labels sit opposite the bend of the road', () {
    final g = geo([for (var i = 0; i < 8; i++) item('t$i')]);
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

  test('geometries with the same stops share a signature so the route can morph', () {
    final a = geo([item('a'), item('b'), item('c'), item('d')]);
    final b = geo([item('a'), item('b', skipped: true), item('c'), item('d')]);
    expect(a.layoutSignature, b.layoutSignature);
    expect(a.sampleXs.length, b.sampleXs.length);
  });

  test('skipping or recovering a stop never moves any stop or the road: same stops, same line, new colours', () {
    final base = geo([item('a'), item('b'), item('c'), item('d')]);
    final skipped = geo([item('a', completed: true), item('b', skipped: true), item('c'), item('d')]);
    final recovered = geo([item('a', completed: true), item('b', completed: true, recovered: true), item('c'), item('d')]);
    for (final other in [skipped, recovered]) {
      for (var i = 0; i < base.stops.length; i++) {
        expect(other.stops[i].center, base.stops[i].center);
        expect(other.stops[i].labelOnLeft, base.stops[i].labelOnLeft);
      }
      expect(other.sampleXs, base.sampleXs, reason: 'the line itself is identical');
      expect(base.sameRoute(other), isFalse, reason: 'only the colours / node state differ');
    }
  });

  test('the road begins at the first stop and ends at the last stop', () {
    for (final n in [2, 4, 6, 9]) {
      final g = geo([for (var i = 0; i < n; i++) item('t$i')]);
      expect(g.sampleYs.first, closeTo(g.stops.first.center.dy, 0.01));
      expect(g.sampleYs.last, closeTo(g.stops.last.center.dy, 0.01));
      expect(g.tailStart, g.sampleYs.length);
    }
  });

  test('stops have room: at least 130 logical px apart, and all fit inside the scrollable height', () {
    for (final n in [2, 4, 6, 8, 12]) {
      final g = geo([for (var i = 0; i < n; i++) item('t$i')]);
      for (var i = 0; i + 1 < n; i++) {
        expect(g.stops[i + 1].center.dy - g.stops[i].center.dy, greaterThanOrEqualTo(130));
      }
      expect(g.stops.every((s) => s.center.dy > 0 && s.center.dy < g.height), isTrue);
    }
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
      expect(end.center.dy - g.stops.last.center.dy, DayRouteGeometry.farSpacing);
      expect(g.distanceToRoute(end.center), lessThan(0.5));
      expect(g.sampleYs.last, closeTo(end.center.dy, 0.01), reason: 'the road ends at the finish');
      expect(allAre(between(g, g.stops.last, end), RouteSegmentState.traveled), isTrue);
      expect(g.height, greaterThan(plain.height));
      for (var i = 0; i < plain.stops.length; i++) {
        expect(g.stops[i].center, plain.stops[i].center, reason: 'adding the finish moves no stop');
      }
      expect(g.sampleXs.sublist(0, plain.sampleXs.length - 1), plain.sampleXs.sublist(0, plain.sampleXs.length - 1));
    });

    test('a finish after skipped / recovered stops still follows the one road', () {
      final items = [item('a', completed: true), item('b', skipped: true), item('c', completed: true, recovered: true)];
      final g = geo(items, finish: true);
      expect(g.distanceToRoute(g.finish!.center), lessThan(0.5));
      for (final s in g.stops) {
        expect(g.distanceToRoute(s.center), lessThan(0.5));
      }
    });
  });
}
