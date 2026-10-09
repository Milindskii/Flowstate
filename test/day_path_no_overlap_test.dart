import 'dart:math' as math;
import 'dart:ui';

import 'package:flowstate/components/day_path/day_route_geometry.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nothing on the day path ever overlaps: no label on a road or branch, no branch on the road, on another branch or on
/// a stop it does not start or end at, the road never under a stop it goes around, and Noya only where she fits.
/// Swept over many generated days (every mix of done / skipped / missed / recovered, in any completion order) at the
/// narrowest to widest phone widths.

ScheduleItem _item(String id, {bool done = false, bool recovered = false, bool missed = false, bool skipped = false}) =>
    ScheduleItem(
      id: id, time: '9:00', period: 'AM', title: 'Task $id', type: 'Task', tagText: 'TASK',
      isCompleted: done, isCompletedAfterDeviation: recovered, isMissed: missed, isSkipped: skipped,
      deviation: skipped ? 'skipped' : null,
    );

double _segDist(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  final t = len2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

double _lineDist(Offset p, List<Offset> line) {
  var best = double.infinity;
  for (var i = 0; i + 1 < line.length; i++) {
    best = math.min(best, _segDist(p, line[i], line[i + 1]));
  }
  return best;
}

void _expectNoOverlap(DayRouteGeometry g, String day) {
  const bed = DayRouteGeometry.nearHalfWidth;
  final runs = g.visibleRuns(g.sampleXs);
  final lines = <List<Offset>>[...runs, for (final b in g.branches) b.points];
  final nodes = <String, Offset>{for (final s in g.stops) s.id: s.center, if (g.finish != null) g.finish!.id: g.finish!.center};

  // labels: clear of every bed, on screen, and off their own node
  for (final s in [...g.stops, if (g.finish != null) g.finish!]) {
    final slot = s.label!;
    final rect = Rect.fromLTRB(slot.left, s.center.dy - DayRouteGeometry.labelHalfHeight, slot.right,
        s.center.dy + DayRouteGeometry.labelHalfHeight);
    expect(slot.left, greaterThanOrEqualTo(DayRouteGeometry.labelMargin - 0.01), reason: '$day ${s.id} label on screen');
    expect(slot.right, lessThanOrEqualTo(g.width - DayRouteGeometry.labelMargin + 0.01), reason: '$day ${s.id}');
    if (slot.width > 0) {
      for (final line in lines) {
        for (var i = 0; i + 1 < line.length; i++) {
          final a = line[i];
          final b = line[i + 1];
          if (math.max(a.dy, b.dy) < rect.top || math.min(a.dy, b.dy) > rect.bottom) continue;
          for (var j = 0; j <= 4; j++) {
            final p = Offset.lerp(a, b, j / 4)!;
            if (p.dy < rect.top || p.dy > rect.bottom) continue;
            final dx = p.dx < rect.left ? rect.left - p.dx : (p.dx > rect.right ? p.dx - rect.right : 0.0);
            expect(dx, greaterThanOrEqualTo(bed - 0.01), reason: '$day ${s.id}: label $slot touches a line at $p');
          }
        }
      }
      for (final o in g.stops) {
        final box = Rect.fromCircle(center: o.center, radius: DayRouteGeometry.nodeRadius);
        expect(box.overlaps(rect) && slot.width > 0 && o.id != s.id ? box.intersect(rect).width > 0.5 : false, isFalse,
            reason: '$day ${s.id}: label on node ${o.id}');
      }
      final own = Rect.fromCircle(center: s.center, radius: DayRouteGeometry.nodeRadius);
      expect(own.intersect(rect).width > 0.5 && own.overlaps(rect), isFalse, reason: '$day ${s.id}: label on its node');
    }
    // Noya, where she is allowed to appear, touches nothing
    if (s.companionFits) {
      final box = DayRouteGeometry.companionBox(s.center, labelOnLeft: slot.onLeft);
      expect(DayRouteGeometry.boxClear(box, lines, g.width), isTrue, reason: '$day ${s.id}: Noya on a line');
      expect(box.overlaps(rect) && box.intersect(rect).width > 0.5, isFalse, reason: '$day ${s.id}: Noya on the label');
    }
  }

  // the road never runs under a stop it bends around
  for (final s in g.stops.where(DayRouteGeometry.isBypassed)) {
    for (final run in runs) {
      expect(_lineDist(s.center, run), greaterThanOrEqualTo(DayRouteGeometry.nodeRadius + bed - 0.5),
          reason: '$day ${s.id}: the road runs under a stop it goes around');
    }
  }

  // branches: clear of the road, of each other and of stops they do not touch (away from their own ends)
  for (final b in g.branches) {
    final ends = [nodes[b.fromId]!, nodes[b.toId]!];
    bool nearEnd(Offset p, [List<Offset> more = const []]) =>
        [...ends, ...more].any((e) => (p - e).distance < DayRouteGeometry.nodeRadius + DayRouteGeometry.laneGap);
    // a stop on the far side of the road from the branch's lane is a junction: within its turn the branch crosses the
    // road once (level, straight across); nowhere else may it touch the road
    final junctions = b.junctions;
    for (final (stop, _) in junctions) {
      expect(ends, contains(stop), reason: '$day ${b.fromId}->${b.toId}: a junction is only ever at its own stop');
    }
    for (final p in b.points) {
      if (nearEnd(p)) continue;
      final atJunction = junctions.any((j) => (p - j.$1).distance < j.$2);
      for (final run in runs) {
        if (atJunction) continue;
        expect(_lineDist(p, run), greaterThanOrEqualTo(bed * 2 - 0.5), reason: '$day ${b.fromId}->${b.toId} on the road at $p');
      }
      for (final s in g.stops) {
        if (s.id == b.fromId || s.id == b.toId) continue;
        expect((p - s.center).distance, greaterThanOrEqualTo(DayRouteGeometry.nodeRadius + bed - 0.5),
            reason: '$day ${b.fromId}->${b.toId} runs over stop ${s.id}');
      }
      for (final o in g.branches) {
        if (identical(o, b)) continue;
        if (nearEnd(p, [nodes[o.fromId]!, nodes[o.toId]!])) continue;
        expect(_lineDist(p, o.points), greaterThanOrEqualTo(bed * 2 - 0.5),
            reason: '$day ${b.fromId}->${b.toId} on ${o.fromId}->${o.toId} at $p');
      }
    }
  }
}

void main() {
  const ids = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

  test('the auto-skip day: A done, C done, B skipped between them', () {
    for (final w in [320.0, 360.0, 412.0]) {
      final g = DayRouteGeometry.compute(
          [for (final id in ids.take(6)) _item(id, done: id == 'A' || id == 'C', skipped: id == 'B')], 'D', w,
          completedAt: {'A': DateTime(2026, 10, 9, 9), 'C': DateTime(2026, 10, 9, 10)});
      _expectNoOverlap(g, 'auto-skip @$w');
      expect(g.stopById('B').role, StopRouteRole.skipped);
    }
  });

  test('going back: A, C, D done, then the skipped B, then on (way back orange, both branches clear)', () {
    for (final w in [320.0, 360.0, 412.0]) {
      final g = DayRouteGeometry.compute(
          [for (final id in ids.take(6)) _item(id, done: 'ABCD'.contains(id), recovered: id == 'B')], null, w,
          completedAt: {
            'A': DateTime(2026, 10, 9, 9), 'C': DateTime(2026, 10, 9, 10),
            'D': DateTime(2026, 10, 9, 11), 'B': DateTime(2026, 10, 9, 12),
          });
      _expectNoOverlap(g, 'going back @$w');
      final back = g.branches.firstWhere((b) => b.toId == 'B');
      expect(back.fromId, 'D');
      expect(back.state, RouteSegmentState.recovered, reason: 'the way back to an old stop is orange');
      expect(g.branches.where((b) => b.fromId == 'B'), isNotEmpty, reason: 'the journey goes on from B');
    }
  });

  test('every generated day, at every phone width, has nothing overlapping', () {
    final rnd = math.Random(7);
    for (var run = 0; run < 300; run++) {
      final n = 3 + rnd.nextInt(6);
      final states = <String, int>{}; // 0 open, 1 done, 2 skipped, 3 missed, 4 recovered
      for (final id in ids.take(n)) {
        states[id] = rnd.nextInt(5);
      }
      final done = [for (final e in states.entries) if (e.value == 1 || e.value == 4) e.key]..shuffle(rnd);
      final at = {for (var i = 0; i < done.length; i++) done[i]: DateTime(2026, 10, 9, 8 + i)};
      final items = [
        for (final e in states.entries)
          _item(e.key, done: e.value == 1 || e.value == 4, recovered: e.value == 4, skipped: e.value == 2, missed: e.value == 3),
      ];
      final open = [for (final e in states.entries) if (e.value == 0) e.key];
      for (final w in [320.0, 360.0, 412.0]) {
        final g = DayRouteGeometry.compute(items, open.isEmpty ? null : open.first, w,
            finish: open.isEmpty && rnd.nextBool(), completedAt: at);
        _expectNoOverlap(g, 'day $run $states order $done @$w');
      }
    }
  });
}
