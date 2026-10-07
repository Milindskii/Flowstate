import 'dart:math' as math;
import 'dart:ui';

import '../../models/schedule_item.dart';

/// What state a stop's NODE is in. It only chooses how the node is drawn and how the road leading to it is
/// coloured: it never decides whether the stop is on the route. Every stop is on the one canonical route.
enum StopRouteRole {
  /// Planned, active, completed or a commitment: nothing special to show.
  onRoute,

  /// Skipped or deferred: a yellow node. The road still runs through it, unchanged.
  skipped,

  /// Unfinished past the sleep boundary: a red node (true failure only).
  failed,

  /// The slot ended and the task was not done (derived from the clock, never a user "skip"): a muted node.
  bypassed,

  /// Skipped/deferred earlier and being done now: an orange return path loops back to the node.
  recovering,

  /// Skipped/deferred earlier and completed since: a done node ringed in orange. The orange return path stays: the
  /// deviation really happened and the route keeps saying so.
  recovered,
}

/// How one stretch of the route is coloured. The route's shape is the same whatever these are.
enum RouteSegmentState {
  /// The road ahead (blue).
  ahead,

  /// Already walked (green).
  traveled,

  /// The way back from a recovered stop to the main timeline (orange).
  recovered,
}

class StopGeometry {
  final String id;
  final int index;
  final Offset center;

  /// 0 at the first stop (top, earliest) to 1 at the last (bottom, latest): how far through the day it is.
  final double depth;

  /// Scale of the node ([DayRouteGeometry.farScale] is 1: every stop is drawn at the same size).
  final double scale;

  /// The label sits opposite the bend of the road.
  final bool labelOnLeft;
  final StopRouteRole role;

  /// Where the main road passes this stop: through the node, or beside it when the road deviated around it.
  final double routeX;

  /// The timeline position this stop was laid out from (null when it has no slot).
  final DateTime? at;

  /// True when the traveller has been here: completed on the normal route, or NOW.
  final bool walked;

  const StopGeometry({
    required this.id,
    required this.index,
    required this.center,
    required this.depth,
    required this.scale,
    required this.labelOnLeft,
    required this.role,
    required this.routeX,
    this.at,
    required this.walked,
  });

  /// True when the main road does not run through this node.
  bool get deviated => (routeX - center.dx).abs() > 0.01;

  StopGeometry lerpTo(StopGeometry o, double t) => StopGeometry(
        id: o.id,
        index: o.index,
        center: Offset.lerp(center, o.center, t)!,
        depth: o.depth,
        scale: o.scale,
        labelOnLeft: o.labelOnLeft,
        role: o.role,
        routeX: lerpDouble(routeX, o.routeX, t)!,
        at: o.at,
        walked: o.walked,
      );
}

/// The orange way back: it leaves the main road, travels back up to a skipped stop and rejoins the road below it.
/// [reveal] (0..1) draws it in (or out) while the route morphs.
class RouteDetour {
  final String stopId;
  final List<Offset> points;
  final double reveal;
  const RouteDetour({required this.stopId, required this.points, this.reveal = 1});

  RouteDetour withReveal(double r) => RouteDetour(stopId: stopId, points: points, reveal: r);
}

/// The single source of truth for the Day Path route: a visual journey through the day's timeline that shows both
/// the PLAN and how the user actually moved against it.
///
/// Route model (identity is stable, geometry is not: a stop keeps its id while its place and the road around it
/// legitimately change):
///
///   A. planned      The road runs through every stop in timeline order. A stop's place is derived from its timeline
///                   position: vertical spacing grows with the time gap to the previous stop (never less than a
///                   comfortable minimum) and the bend of the road is phased by the time of day. Blue ahead.
///   B. completed    Same place, same road; the stretch walked up to it is green.
///   C. skipped      The node stays visible at its planned slot, but the road no longer runs through it: it swings out
///      (also        beside the node and carries on to the next stop. The same goes for a slot that ended unfinished
///      bypassed,    (bypassed) and a failed stop.
///      failed)
///   D. recovered    A skipped stop that is being done (recovering) or was done (recovered): the main road keeps its
///                   deviation around the node, and an orange return path leaves the road at the next point, travels
///                   back up to the node and rejoins the road. Completing it recolours the node, never the history.
///   E. rescheduled  A new timeline position moves the stop; the whole route is recomputed. Consumers morph between
///                   the old and the new geometry with [lerp].
///   F. deleted      The stop leaves the list; the road closes around the remaining stops.
///
/// Two geometries can always be morphed: [lerp] resamples the old road onto the new one by progress along the day.
class DayRouteGeometry {
  static const double padBottom = 72;
  static const double padTop = 64;

  /// Vertical room between two stops: [minSpacing] plus [pxPerMinute] for every minute of gap, up to [maxSpacing].
  static const double minSpacing = 132;
  static const double maxSpacing = 196;
  static const double pxPerMinute = 0.4;

  /// Spacing used when a stop has no slot to measure a gap from.
  static const double defaultSpacing = 148;
  static const double farScale = 1.0;
  static const double sampleStep = 4;

  /// How far beside a skipped node the road passes, and how far out the orange return path bulges.
  static const double bypassOffset = 46;
  static const double detourBulge = 82;
  static const int detourSamples = 28;

  /// Visible node radius used for clearance (a stop's tap target is larger).
  static const double nodeRadius = 19;

  /// Half-width of the road bed at the foreground and in the distance.
  static const double nearHalfWidth = 12;
  static const double farHalfWidth = 12;

  /// The id of the finish (Trophy) point at the end of the route, when there is one.
  static const String finishId = 'path_finish';

  final double width;
  final double height;
  final List<StopGeometry> stops;

  /// The end of the road after the last stop (the day's Trophy), or null. It is not one of [stops].
  final StopGeometry? finish;

  /// Route samples, top to bottom (y increasing).
  final List<double> sampleYs;
  final List<double> sampleXs;

  /// The colour state of each sample's segment: the stretch that ARRIVES at the sample from the one above it.
  final List<RouteSegmentState> sampleStates;

  /// Index of the first sample past the last stop (always the sample count: the road ends at the last point).
  final int tailStart;

  /// The orange return paths of recovering / recovered stops.
  final List<RouteDetour> detours;

  const DayRouteGeometry({
    required this.width,
    required this.height,
    required this.stops,
    this.finish,
    required this.sampleYs,
    required this.sampleXs,
    required this.sampleStates,
    required this.tailStart,
    this.detours = const [],
  });

  bool get hasRoute => sampleYs.isNotEmpty;

  /// Two geometries with the same signature have the same stops, so they describe the same day.
  String get layoutSignature => '${width.round()}|${stops.map((s) => s.id).join(',')}${finish == null ? '' : '|finish'}';

  /// True when [other] would draw the same route (same samples, colours, node states and detours).
  bool sameRoute(DayRouteGeometry other) {
    if (layoutSignature != other.layoutSignature ||
        sampleXs.length != other.sampleXs.length ||
        detours.length != other.detours.length ||
        tailStart != other.tailStart) {
      return false;
    }
    if ((height - other.height).abs() > 0.01) return false;
    for (var i = 0; i < sampleXs.length; i++) {
      if ((sampleXs[i] - other.sampleXs[i]).abs() > 0.01 ||
          (sampleYs[i] - other.sampleYs[i]).abs() > 0.01 ||
          sampleStates[i] != other.sampleStates[i]) {
        return false;
      }
    }
    for (var i = 0; i < stops.length; i++) {
      if (stops[i].role != other.stops[i].role || (stops[i].center - other.stops[i].center).distance > 0.01) return false;
    }
    for (var i = 0; i < detours.length; i++) {
      if (detours[i].stopId != other.detours[i].stopId || (detours[i].points.last - other.detours[i].points.last).distance > 0.01) {
        return false;
      }
    }
    return true;
  }

  double halfWidthAt(double y) {
    final depth = height <= 0 ? 0.0 : (y / height).clamp(0.0, 1.0);
    return nearHalfWidth + (farHalfWidth - nearHalfWidth) * depth;
  }

  /// The route's x at [y] (linear between samples); the nearest end sample outside the route.
  double routeXAt(double y) {
    if (!hasRoute) return width / 2;
    if (y <= sampleYs.first) return sampleXs.first;
    if (y >= sampleYs.last) return sampleXs.last;
    var lo = 0;
    var hi = sampleYs.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (sampleYs[mid] <= y) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final y0 = sampleYs[lo];
    final y1 = sampleYs[hi];
    final t = y0 == y1 ? 0.0 : (y - y0) / (y1 - y0);
    return sampleXs[lo] + (sampleXs[hi] - sampleXs[lo]) * t;
  }

  /// Shortest distance from [p] to the main route polyline.
  double distanceToRoute(Offset p) {
    var best = double.infinity;
    for (var i = 0; i + 1 < sampleYs.length; i++) {
      final a = Offset(sampleXs[i], sampleYs[i]);
      final b = Offset(sampleXs[i + 1], sampleYs[i + 1]);
      final ab = b - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      final t = len2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
      best = math.min(best, (p - (a + ab * t)).distance);
    }
    return best;
  }

  StopGeometry stopById(String id) => stops.firstWhere((s) => s.id == id);

  RouteDetour? detourFor(String stopId) {
    for (final d in detours) {
      if (d.stopId == stopId) return d;
    }
    return null;
  }

  /// The geometry [t] of the way from [a] to [b]. The road is resampled by progress down the day, so old and new may
  /// have different stops, spacings and sample counts; stops that exist in both slide, a detour that is new draws
  /// in and one that is gone draws out. [t] >= 1 is exactly [b].
  static DayRouteGeometry lerp(DayRouteGeometry a, DayRouteGeometry b, double t) {
    if (t >= 1 || !a.hasRoute || !b.hasRoute || a.width != b.width) return b;
    final aFirst = a.sampleYs.first;
    final aSpan = a.sampleYs.last - aFirst;
    final bFirst = b.sampleYs.first;
    final bSpan = b.sampleYs.last - bFirst;
    final ys = <double>[];
    final xs = <double>[];
    for (var i = 0; i < b.sampleYs.length; i++) {
      final u = bSpan <= 0 ? 0.0 : (b.sampleYs[i] - bFirst) / bSpan;
      final ay = aFirst + aSpan * u;
      ys.add(lerpDouble(ay, b.sampleYs[i], t)!);
      xs.add(lerpDouble(a.routeXAt(ay), b.sampleXs[i], t)!);
    }
    final before = {for (final s in a.stops) s.id: s};
    StopGeometry slide(StopGeometry s) => before[s.id]?.lerpTo(s, t) ?? s;
    final aFinish = a.finish;
    final bFinish = b.finish;

    final detours = <RouteDetour>[];
    for (final d in b.detours) {
      final old = a.detourFor(d.stopId);
      if (old == null) {
        detours.add(d.withReveal(t));
      } else {
        detours.add(RouteDetour(
          stopId: d.stopId,
          points: [for (var k = 0; k < d.points.length; k++) Offset.lerp(old.points[k], d.points[k], t)!],
        ));
      }
    }
    for (final d in a.detours) {
      if (b.detourFor(d.stopId) == null) detours.add(d.withReveal(1 - t));
    }

    return DayRouteGeometry(
      width: b.width,
      height: lerpDouble(a.height, b.height, t)!,
      stops: [for (final s in b.stops) slide(s)],
      finish: bFinish == null ? null : (aFinish == null ? bFinish : aFinish.lerpTo(bFinish, t)),
      sampleYs: ys,
      sampleXs: xs,
      sampleStates: b.sampleStates,
      tailStart: b.tailStart,
      detours: detours,
    );
  }

  static StopRouteRole roleOf(ScheduleItem item) {
    if (item.isCompleted) return item.isCompletedAfterDeviation ? StopRouteRole.recovered : StopRouteRole.onRoute;
    if (item.state == 'recovering') return StopRouteRole.recovering;
    if (item.isSkipped || item.deviation == 'skipped' || item.deviation == 'deferred') return StopRouteRole.skipped;
    if (item.isFailed) return StopRouteRole.failed;
    // Time alone moves the route past a task whose slot ended unfinished. Commitments are protected: their time
    // passing is not a miss, so the route keeps running through them.
    if (item.isMissed && !item.isCommitment) return StopRouteRole.bypassed;
    return StopRouteRole.onRoute;
  }

  /// True for the stops the main road swings around instead of running through.
  static bool deviatesRoad(StopRouteRole role) => role != StopRouteRole.onRoute;

  static double _smooth(double u) => u * u * (3 - 2 * u);

  /// The timeline position a stop is laid out from.
  static DateTime? timelineAt(ScheduleItem item) => item.tagText == 'UNSCHEDULED' ? null : (item.anchorStart ?? item.startTime);

  /// The colour of the road arriving at [s] from [previous].
  static RouteSegmentState _stateInto(StopGeometry s, StopGeometry? previous, {required bool isFinish}) {
    // the way back from a recovering / recovered stop to the road is orange
    if (previous != null && (previous.role == StopRouteRole.recovered || previous.role == StopRouteRole.recovering)) {
      return RouteSegmentState.recovered;
    }
    if (isFinish) return RouteSegmentState.traveled; // the finish only exists once the day is done
    return s.walked ? RouteSegmentState.traveled : RouteSegmentState.ahead;
  }

  /// [finish] adds the end of the road after the last stop: the day's Trophy sits there, on the same route.
  static DayRouteGeometry compute(List<ScheduleItem> items, String? nowItemId, double width, {bool finish = false}) {
    final n = items.length;
    if (n == 0) {
      return DayRouteGeometry(
          width: width, height: 0, stops: const [], sampleYs: const [], sampleXs: const [], sampleStates: const [], tailStart: 0);
    }
    final points = n + (finish ? 1 : 0);
    final times = [for (final item in items) timelineAt(item)];

    // Vertical layout: the first (earliest) stop at the TOP, the last at the bottom. The room between two stops
    // follows the time between them, so moving a task in time moves the road.
    double spacingAfter(int i) {
      if (i + 1 >= n) return defaultSpacing; // to the finish
      final a = times[i];
      final b = times[i + 1];
      if (a == null || b == null) return defaultSpacing;
      final gap = math.max(0, b.difference(a).inMinutes);
      return (minSpacing + gap * pxPerMinute).clamp(minSpacing, maxSpacing).toDouble();
    }

    final ys = <double>[];
    var fromTop = padTop;
    for (var i = 0; i < points; i++) {
      ys.add(fromTop);
      if (i < points - 1) fromTop += spacingAfter(i);
    }
    final height = fromTop + padBottom;

    final amp = math.min(width * 0.18, 72.0);
    StopGeometry place(int i, String id, StopRouteRole role, bool walked, DateTime? at) {
      // depth is measured over the task stops only: adding the finish after the last one moves no stop
      final depth = (n > 1 ? i / (n - 1) : i.toDouble()).clamp(0.0, 1.0);
      final minuteOfDay = at == null ? 0 : at.hour * 60 + at.minute;
      final bend = math.sin(1.05 * i + 0.5 + 1.1 * minuteOfDay / 1440);
      final x = width / 2 + amp * (1 - 0.22 * depth) * bend;
      final leftOfCentre = (x - width / 2).abs() < 10 ? i.isOdd : x >= width / 2;
      // the road swings out on the side away from the label
      final side = leftOfCentre ? 1.0 : -1.0;
      final routeX = deviatesRoad(role) ? (x + side * bypassOffset).clamp(28.0, width - 28).toDouble() : x;
      return StopGeometry(
        id: id,
        index: i,
        center: Offset(x, ys[i]),
        depth: depth,
        scale: 1 - (1 - farScale) * depth,
        labelOnLeft: leftOfCentre,
        role: role,
        routeX: routeX,
        at: at,
        walked: walked,
      );
    }

    final stops = <StopGeometry>[];
    for (var i = 0; i < n; i++) {
      final item = items[i];
      final role = roleOf(item);
      stops.add(place(i, item.id, role, role == StopRouteRole.onRoute && (item.isCompleted || item.id == nowItemId), times[i]));
    }
    final end = finish ? place(n, finishId, StopRouteRole.onRoute, true, null) : null;

    // The main road passes through every point's route position: through the node, or beside it where it deviated.
    final route = [...stops, if (end != null) end];
    double routeX(double y) {
      if (y <= route.first.center.dy) return route.first.routeX;
      if (y >= route.last.center.dy) return route.last.routeX;
      for (var k = 0; k + 1 < route.length; k++) {
        final a = route[k];
        final b = route[k + 1];
        if (y >= a.center.dy && y <= b.center.dy) {
          final u = (y - a.center.dy) / (b.center.dy - a.center.dy);
          return a.routeX + (b.routeX - a.routeX) * _smooth(u);
        }
      }
      return route.last.routeX;
    }

    // Sample grid: the road begins at the first stop and ends at the last point (no lead-in, no tail).
    final yStart = route.first.center.dy;
    final yEnd = route.last.center.dy;
    final sampleYs = <double>[];
    final sampleXs = <double>[];
    final states = <RouteSegmentState>[];
    // The state of the stretch that ARRIVES at a sample: the one whose far end is the first point at or below it.
    var k = 0;
    void addSample(double y) {
      while (k + 1 < route.length && y > route[k].center.dy + 1e-9) {
        k++;
      }
      sampleYs.add(y);
      sampleXs.add(routeX(y));
      states.add(_stateInto(route[k], k > 0 ? route[k - 1] : null, isFinish: end != null && identical(route[k], end)));
    }

    for (var y = yStart; y <= yEnd; y += sampleStep) {
      addSample(y);
    }
    if (yEnd - sampleYs.last > 0.01) addSample(yEnd);

    // The orange way back: from the next point on the road, up to the node, and the road below it carries it home.
    final detours = <RouteDetour>[];
    for (final s in stops) {
      if (s.role != StopRouteRole.recovered && s.role != StopRouteRole.recovering) continue;
      final next = s.index + 1 < route.length ? route[s.index + 1] : null;
      final from = next == null ? Offset(s.routeX, s.center.dy + 24) : Offset(next.routeX, next.center.dy);
      final out = (s.labelOnLeft ? 1.0 : -1.0) * detourBulge;
      final bx = (s.center.dx + out).clamp(20.0, width - 20).toDouble();
      final fx = (from.dx + out).clamp(20.0, width - 20).toDouble();
      final rise = (from.dy - s.center.dy) * 0.35;
      final c1 = Offset(fx, from.dy - rise);
      final c2 = Offset(bx, s.center.dy + rise);
      final pts = <Offset>[];
      for (var j = 0; j <= detourSamples; j++) {
        final u = j / detourSamples;
        final v = 1 - u;
        pts.add(from * (v * v * v) + c1 * (3 * v * v * u) + c2 * (3 * v * u * u) + s.center * (u * u * u));
      }
      detours.add(RouteDetour(stopId: s.id, points: pts));
    }

    return DayRouteGeometry(
      width: width,
      height: height,
      stops: stops,
      finish: end,
      sampleYs: sampleYs,
      sampleXs: sampleXs,
      sampleStates: states,
      tailStart: sampleYs.length, // no faded tail: the road simply ends at the last point
      detours: detours,
    );
  }
}
