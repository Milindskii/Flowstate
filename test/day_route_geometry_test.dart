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

/// A bypassed stop (skipped / missed / failed) stays at its slot while the road swings past it and carries on.
void expectBypassed(DayRouteGeometry g, String id) {
  final s = g.stopById(id);
  expect(g.distanceToRoute(s.center), greaterThan(DayRouteGeometry.nodeRadius + 10), reason: '$id: the road never runs under the node');
  expect((g.routeXAt(s.center.dy) - s.center.dx).abs(), closeTo(DayRouteGeometry.detourDistance, 0.5), reason: '$id: it swings past');
}

/// Every stop except [bypassed] is on the road, and every stop is exactly where it is without any state.
void expectBendsOnlyAt(DayRouteGeometry g, DayRouteGeometry planned, Set<String> bypassed) {
  expect(g.layoutSignature, planned.layoutSignature);
  for (var i = 0; i < g.stops.length; i++) {
    final s = g.stops[i];
    expect(s.center, planned.stops[i].center, reason: '${s.id} keeps its timeline slot');
    if (bypassed.contains(s.id)) {
      expectBypassed(g, s.id);
    } else {
      expect(g.distanceToRoute(s.center), lessThan(0.5), reason: '${s.id} is on the route');
    }
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

  test('a skipped stop stays at its slot and the road swings around it, continuing to the next stop', () {
    final all = geo([item('a'), item('b'), item('c'), item('d')]);
    final g = geo([item('a'), item('b', skipped: true), item('c'), item('d')]);
    final a = g.stopById('a'), b = g.stopById('b'), c = g.stopById('c'), d = g.stopById('d');
    expect(b.role, StopRouteRole.skipped);
    expectBendsOnlyAt(g, all, {'b'});
    expect(g.sampleXs, isNot(all.sampleXs), reason: 'the route model is regenerated from the states');
    expect(allAre(between(g, a, b), RouteSegmentState.ahead), isTrue, reason: 'blue runs INTO the skipped stop');
    expect(allAre(between(g, b, c), RouteSegmentState.ahead), isTrue, reason: 'and on out of it');
    expect(allAre(between(g, c, d), RouteSegmentState.ahead), isTrue);
  });

  test('skipped between two done stops: the journey went past it, so the road into it is walked too', () {
    final g = geo([item('a', completed: true), item('b', skipped: true), item('c', completed: true), item('d')], now: 'd');
    final a = g.stopById('a'), b = g.stopById('b'), c = g.stopById('c'), d = g.stopById('d');
    expect(b.walked, isTrue, reason: 'c was done after it');
    expect(b.role, StopRouteRole.skipped, reason: 'but the node is still a skip, never a completion');
    expect(allAre(between(g, a, b), RouteSegmentState.traveled), isTrue);
    expect(allAre(between(g, b, c), RouteSegmentState.traveled), isTrue);
    expect(allAre(between(g, c, d), RouteSegmentState.traveled), isTrue);
    expectBendsOnlyAt(g, geo([item('a'), item('b'), item('c'), item('d')]), {'b'});
  });

  test('a deferred history node is a skipped node: the road goes around it', () {
    final g = geo([item('a'), item('h', deviation: 'deferred'), item('c')]);
    expect(g.stopById('h').role, StopRouteRole.skipped);
    expectBendsOnlyAt(g, geo([item('a'), item('h'), item('c')]), {'h'});
  });

  test('recovered right after its predecessor: the orange state follows the SAME winding route, no separate line', () {
    // A done, B done late (nothing finished after A): the traveller really went A -> B, so the road into B is orange.
    final g = geo([item('a', completed: true), item('b', completed: true, recovered: true), item('c'), item('d')], now: 'c');
    final a = g.stopById('a'), b = g.stopById('b'), c = g.stopById('c');
    expect(b.role, StopRouteRole.recovered);
    expect(b.detached, isFalse);
    expect(b.walked, isFalse, reason: 'recovered is not part of the normal walked route');
    expect(g.branches, isEmpty, reason: 'no second path: the orange state is on the one road');
    expectSameRoad(g, geo([item('a'), item('b'), item('c'), item('d')]));
    expect(allAre(between(g, a, b), RouteSegmentState.recovered), isTrue, reason: 'the way into B is orange');
    expect(allAre(between(g, b, c), RouteSegmentState.traveled), isTrue);
    // orange samples lie on the very polyline that green and blue ones do
    for (var i = 0; i < g.sampleYs.length; i++) {
      if (g.sampleStates[i] == RouteSegmentState.recovered) {
        expect(g.distanceToRoute(Offset(g.sampleXs[i], g.sampleYs[i])), lessThan(1e-6));
      }
    }
  });

  group('recovery starts from where the traveller actually was', () {
    // A -> B -> C -> D. B is missed; A, C and D are done; B is done last.
    final done = [
      item('a', completed: true),
      item('b', completed: true, recovered: true),
      item('c', completed: true),
      item('d', completed: true),
    ];
    final planned = geo([item('a'), item('b'), item('c'), item('d')]);

    test('B keeps its timeline slot, the road bends around it, and an orange branch runs D -> B (never A -> B)', () {
      final g = geo(done);
      final b = g.stopById('b');
      expect(b.role, StopRouteRole.recovered);
      expect(b.detached, isTrue);
      for (var i = 0; i < 4; i++) {
        expect(g.stops[i].center, planned.stops[i].center, reason: '${g.stops[i].id} keeps its slot');
      }
      expectBypassed(g, 'b');
      expect(g.branches, hasLength(1));
      final branch = g.branches.single;
      expect((branch.fromId, branch.toId), ('d', 'b'), reason: 'from the latest real position, not the chronological predecessor');
      expect(branch.points.first, g.stopById('d').center);
      expect(branch.points.last, b.center);
      // it runs back up the screen, through the time between D and B
      expect(branch.points.first.dy, greaterThan(branch.points.last.dy));
      // no orange stretch of the main road: the road did not go A -> B
      expect(g.sampleStates, isNot(contains(RouteSegmentState.recovered)));
      // the road still continues through C and D, and the stretch past B was already walked
      expect(g.distanceToRoute(g.stopById('c').center), lessThan(0.5));
      expect(g.distanceToRoute(g.stopById('d').center), lessThan(0.5));
      expect(g.sampleStates.where((s) => s == RouteSegmentState.traveled), isNotEmpty);
    });

    test('with completion times the origin is the stop completed right before B, whatever the plan order', () {
      final t0 = DateTime(2026, 10, 8, 9);
      final g = DayRouteGeometry.compute(done, null, w, completedAt: {
        'a': t0, 'c': t0.add(const Duration(hours: 1)), 'd': t0.add(const Duration(hours: 2)), 'b': t0.add(const Duration(hours: 3)),
      });
      expect(g.branches.single.fromId, 'd');
      // C finished AFTER B: the traveller was at A when B was done
      final g2 = DayRouteGeometry.compute(done, null, w, completedAt: {
        'a': t0, 'b': t0.add(const Duration(hours: 1)), 'c': t0.add(const Duration(hours: 2)), 'd': t0.add(const Duration(hours: 3)),
      });
      expect(g2.branches, isEmpty, reason: 'A -> B really happened: orange into B on the road');
      expect(g2.stopById('b').detached, isFalse);
      expect(allAre(between(g2, g2.stopById('a'), g2.stopById('b')), RouteSegmentState.recovered), isTrue);
    });

    test('a later recovery starts from the previous real position, even a recovered one', () {
      final items = [
        item('a', completed: true),
        item('b', completed: true, recovered: true),
        item('c', completed: true),
        item('d', completed: true, recovered: true),
        item('e', completed: true),
      ];
      final t0 = DateTime(2026, 10, 8, 9);
      final g = DayRouteGeometry.compute(items, null, w, completedAt: {
        'a': t0, 'c': t0.add(const Duration(hours: 1)), 'e': t0.add(const Duration(hours: 2)),
        'b': t0.add(const Duration(hours: 3)), 'd': t0.add(const Duration(hours: 4)),
      });
      expect([for (final b in g.branches) (b.fromId, b.toId)], [('e', 'b'), ('b', 'd')]);
    });

    test('undoing the recovery recomputes: B is missed again, bypassed, and the branch is gone', () {
      final recovered = geo(done);
      final undone = geo([item('a', completed: true), item('b', missed: true), item('c', completed: true), item('d', completed: true)]);
      expect(recovered.branches, hasLength(1));
      expect(undone.branches, isEmpty);
      expect(undone.stopById('b').role, StopRouteRole.bypassed);
      expect(undone.stopById('b').center, recovered.stopById('b').center);
      expect(undone.sameRoute(recovered), isFalse);
    });

    test('recovery with the traveller\'s latest position deleted or rescheduled away: recomputed from what is left', () {
      // D deleted: the latest real position is now C
      final g = geo([item('a', completed: true), item('b', completed: true, recovered: true), item('c', completed: true)]);
      expect(g.branches.single.fromId, 'c');
    });

    test('rejoins the route: the road past a recovered stop still reaches the future tasks', () {
      final g = geo([
        item('a', completed: true), item('b', completed: true, recovered: true), item('c', completed: true), item('d'), item('e'),
      ], now: 'd');
      expect(g.branches.single.fromId, 'c');
      expect(g.distanceToRoute(g.stopById('d').center), lessThan(0.5));
      expect(g.distanceToRoute(g.stopById('e').center), lessThan(0.5));
      expect(g.sampleYs.last, g.stopById('e').center.dy);
    });
  });

  test('a missed stop stays at its planned position; the road bends around it to the next stop', () {
    final all = geo([item('a'), item('m'), item('c')]);
    final g = geo([item('a'), item('m', missed: true), item('c')]);
    final m = g.stopById('m');
    expect(m.role, StopRouteRole.bypassed);
    expect(g.stops.map((s) => s.id).toList(), ['a', 'm', 'c'], reason: 'chronological order is preserved');
    expect(m.center, all.stopById('m').center, reason: 'the node does not move');
    expectBendsOnlyAt(g, all, {'m'});
  });

  test('failed is a red node the road goes around (red is reserved for true failure)', () {
    final g = geo([item('a'), item('f', failed: true), item('c')]);
    expect(g.stopById('f').role, StopRouteRole.failed);
    expectBendsOnlyAt(g, geo([item('a'), item('f'), item('c')]), {'f'});
  });

  test('a commitment is a normal stop on the route', () {
    final g = geo([item('a'), item('go', commitment: true), item('c')]);
    expect(g.stopById('go').role, StopRouteRole.onRoute);
  });

  test('skipping the first and the last stop still leaves one continuous road from the first to the last', () {
    final g = geo([item('a', skipped: true), item('b'), item('c', skipped: true)]);
    expectBendsOnlyAt(g, geo([item('a'), item('b'), item('c')]), {'a', 'c'});
    expect(g.sampleYs.first, g.stopById('a').center.dy);
    expect(g.sampleYs.last, g.stopById('c').center.dy);
  });

  test('every state at once: one continuous, gap-free route; only bypassed stops are skirted', () {
    final items = [
      item('a', completed: true),
      item('b', skipped: true),
      item('c', completed: true, recovered: true),
      item('d', missed: true),
      item('e', failed: true),
      item('f'),
    ];
    final g = geo(items, now: 'f');
    // C was reached from A (B was skipped, nothing finished after it), so C is not on the road from B: it is bypassed
    // and a branch carries the traveller from A to it.
    expectBendsOnlyAt(g, geo([for (final i in items) item(i.id)]), {'b', 'c', 'd', 'e'});
    expect([for (final b in g.branches) (b.fromId, b.toId)], [('a', 'c')]);
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

  test('skipping moves the road (not the stops); recovering keeps the line and changes colours', () {
    final base = geo([item('a'), item('b'), item('c'), item('d')]);
    final skipped = geo([item('a', completed: true), item('b', skipped: true), item('c'), item('d')]);
    final recovered = geo([item('a', completed: true), item('b', completed: true, recovered: true), item('c'), item('d')]);
    for (final other in [skipped, recovered]) {
      for (var i = 0; i < base.stops.length; i++) {
        expect(other.stops[i].center, base.stops[i].center);
        expect(other.stops[i].labelOnLeft, base.stops[i].labelOnLeft);
      }
      expect(base.sameRoute(other), isFalse);
    }
    expect(recovered.sampleXs, base.sampleXs, reason: 'a recovered stop is on the road: the line is identical');
    expect(skipped.sampleXs, isNot(base.sampleXs), reason: 'a skipped stop bends the line');
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
      // the road above may only ease its last bend toward the finish (one smooth curve), never visibly move
      for (var i = 0; i < plain.sampleXs.length - 1; i++) {
        expect(g.sampleXs[i], closeTo(plain.sampleXs[i], 2.0));
      }
    });

    test('a finish after skipped / recovered stops still follows the one road', () {
      final items = [item('a', completed: true), item('b', skipped: true), item('c', completed: true, recovered: true)];
      final g = geo(items, finish: true);
      expect(g.distanceToRoute(g.finish!.center), lessThan(0.5));
      for (final s in g.stops.where((s) => s.id != 'b' && s.id != 'c')) {
        expect(g.distanceToRoute(s.center), lessThan(0.5));
      }
      expectBypassed(g, 'b');
      expectBypassed(g, 'c'); // reached from A, not from the skipped B
      expect(g.branches.single.fromId, 'a');
    });
  });
}
