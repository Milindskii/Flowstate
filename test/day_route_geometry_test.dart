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

DayRouteGeometry geo(List<ScheduleItem> items, {String? now}) => DayRouteGeometry.compute(items, now, w);

/// Samples strictly between [a] and [b] ([a] is the earlier stop: higher on the screen, smaller y).
Iterable<bool> travelledBetween(DayRouteGeometry g, StopGeometry a, StopGeometry b) sync* {
  for (var i = 0; i < g.sampleYs.length; i++) {
    final y = g.sampleYs[i];
    if (y > a.center.dy && y < b.center.dy) yield g.sampleTraveled[i];
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
    expect(g.stops.every((s) => s.onRoute), isTrue);
    expect(g.sampleTraveled.any((t) => t), isFalse);
    for (final s in g.stops) {
      expect(g.distanceToRoute(s.center), lessThan(0.5));
    }
  });

  test('completed stops turn the walked stretch green; the road ahead stays blue', () {
    final g = geo([item('a', completed: true), item('b', completed: true), item('c'), item('d')], now: 'c');
    final a = g.stopById('a'), b = g.stopById('b'), c = g.stopById('c'), d = g.stopById('d');
    expect(travelledBetween(g, a, b).every((t) => t), isTrue);
    expect(travelledBetween(g, b, c).every((t) => t), isTrue, reason: 'the stretch into NOW is walked');
    expect(travelledBetween(g, c, d).every((t) => !t), isTrue, reason: 'beyond NOW is still ahead');
  });

  test('a skipped stop is bypassed: the blue route physically bends around it and never passes through', () {
    final all = geo([item('a'), item('b'), item('c'), item('d')]);
    final g = geo([item('a'), item('b', skipped: true), item('c'), item('d')]);
    final b = g.stopById('b');
    expect(b.role, StopRouteRole.skipped);
    expect(g.distanceToRoute(b.center), greaterThanOrEqualTo(DayRouteGeometry.bypassClearance - 3));
    expect(all.distanceToRoute(all.stopById('b').center), lessThan(0.5), reason: 'before the skip the route went through B');
    // the route still reaches its neighbours
    for (final id in ['a', 'c', 'd']) {
      expect(g.distanceToRoute(g.stopById(id).center), lessThan(0.5));
    }
    // the bend is real geometry: the route differs from the unskipped one near B
    final y = b.center.dy;
    expect((g.routeXAt(y) - all.routeXAt(y)).abs(), greaterThan(1));
    expect(g.spurs.map((s) => s.stopId), contains('b'));
  });

  test('a deferred history node bypasses like a skip', () {
    final g = geo([item('a'), item('h', deviation: 'deferred'), item('c')]);
    expect(g.stopById('h').role, StopRouteRole.skipped);
    expect(g.distanceToRoute(g.stopById('h').center), greaterThanOrEqualTo(DayRouteGeometry.bypassClearance - 3));
  });

  test('a recovered stop keeps its history: route still bends around it and an orange detour runs through it', () {
    final g = geo([item('a', completed: true), item('b', completed: true, recovered: true), item('c', completed: true), item('d')], now: 'd');
    final b = g.stopById('b');
    expect(b.role, StopRouteRole.recovered);
    expect(b.walked, isFalse, reason: 'recovered is not part of the normal walked route');
    expect(g.distanceToRoute(b.center), greaterThanOrEqualTo(DayRouteGeometry.bypassClearance - 3));
    expect(g.detours.length, 1);
    final d = g.detours.single;
    expect(d.stopId, 'b');
    expect(d.points.any((p) => (p - b.center).distance < 1), isTrue, reason: 'the detour passes through the node');
    expect(d.points.first.dy, lessThan(b.center.dy), reason: 'it leaves the previous stop (above) ...');
    expect(d.points.last.dy, greaterThan(b.center.dy), reason: '... and rejoins at the next stop (below)');
  });

  test('a missed stop stays at its planned position; the route moves past it on its own (bypassed, not a skip)', () {
    final all = geo([item('a'), item('m'), item('c')]);
    final g = geo([item('a'), item('m', missed: true), item('c')]);
    final m = g.stopById('m');
    expect(m.role, StopRouteRole.bypassed);
    expect(g.distanceToRoute(m.center), greaterThanOrEqualTo(DayRouteGeometry.bypassClearance - 3));
    expect(g.stops.map((s) => s.id).toList(), ['a', 'm', 'c'], reason: 'chronological order is preserved');
    expect(m.center, all.stopById('m').center, reason: 'the node does not move');
    for (final id in ['a', 'c']) {
      expect(g.distanceToRoute(g.stopById(id).center), lessThan(0.5), reason: 'the route still reaches its neighbours');
    }
  });

  test('failed bypasses the route (red is reserved for true failure)', () {
    final g = geo([item('a'), item('f', failed: true), item('c')]);
    expect(g.stopById('f').role, StopRouteRole.failed);
    expect(g.distanceToRoute(g.stopById('f').center), greaterThanOrEqualTo(DayRouteGeometry.bypassClearance - 3));
  });

  test('a commitment is a normal stop on the route', () {
    final g = geo([item('a'), item('go', commitment: true), item('c')]);
    expect(g.stopById('go').role, StopRouteRole.onRoute);
  });

  test('skipping the first and the last stop still yields a route that clears them', () {
    final g = geo([item('a', skipped: true), item('b'), item('c', skipped: true)]);
    for (final id in ['a', 'c']) {
      expect(g.distanceToRoute(g.stopById(id).center), greaterThanOrEqualTo(DayRouteGeometry.bypassClearance - 3));
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

  test('skipping or recovering a stop never moves any stop: same stops, different road', () {
    final base = geo([item('a'), item('b'), item('c'), item('d')]);
    final skipped = geo([item('a', completed: true), item('b', skipped: true), item('c'), item('d')]);
    final recovered = geo([item('a', completed: true), item('b', completed: true, recovered: true), item('c'), item('d')]);
    for (final other in [skipped, recovered]) {
      for (var i = 0; i < base.stops.length; i++) {
        expect(other.stops[i].center, base.stops[i].center);
        if (other.stops[i].onRoute) expect(other.stops[i].labelOnLeft, base.stops[i].labelOnLeft);
      }
    }
    expect(base.sameRoute(skipped), isFalse); // the road did change
    expect(recovered.detours, isNotEmpty);
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
}
