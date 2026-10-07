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

  /// Skipped/deferred earlier and completed since: a done node ringed in orange; the road into it is orange.
  recovered,
}

/// How one stretch of the route is coloured. The route's shape is the same whatever these are.
enum RouteSegmentState {
  /// The road ahead (blue).
  ahead,

  /// Already walked (green).
  traveled,

  /// The road into a stop that was done after being skipped (orange): same line, different colour.
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
    required this.walked,
  });
}

/// The single source of truth for the Day Path route.
///
/// ONE canonical route runs through every stop, top to bottom (the first task of the day at the top, the last at the
/// bottom), sampled on a fixed grid. Its shape depends on the stops' positions only, never on their state:
///
///   stop position  ->  route geometry  ->  segment state  ->  node state
///
/// The route is cut into segments, one per stop (the stretch arriving at it), and each segment gets a colour from
/// its stop: green when walked, orange when the stop was recovered, blue otherwise. So a skipped, missed or
/// recovered stop changes how it is drawn, but the road through it is the same line, still continuous.
///
/// Two geometries with the same [layoutSignature] can be morphed by interpolating [sampleXs].
class DayRouteGeometry {
  static const double padBottom = 72;
  static const double padTop = 64;
  static const double nearSpacing = 148;
  static const double farSpacing = 148; // uniform: stop positions depend on the index only, never on state
  static const double farScale = 1.0;
  static const double sampleStep = 4;

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

  const DayRouteGeometry({
    required this.width,
    required this.height,
    required this.stops,
    this.finish,
    required this.sampleYs,
    required this.sampleXs,
    required this.sampleStates,
    required this.tailStart,
  });

  bool get hasRoute => sampleYs.isNotEmpty;

  /// Two geometries with the same signature have the same stops and sample grid, so their routes can morph.
  String get layoutSignature =>
      '${width.round()}|${stops.map((s) => s.id).join(',')}${finish == null ? '' : '|finish'}|${sampleYs.length}|${sampleYs.isEmpty ? 0 : sampleYs.first}|${sampleYs.isEmpty ? 0 : sampleYs.last}';

  /// True when [other] would draw the same route (same samples, colours and node states).
  bool sameRoute(DayRouteGeometry other) {
    if (layoutSignature != other.layoutSignature ||
        sampleXs.length != other.sampleXs.length ||
        tailStart != other.tailStart) {
      return false;
    }
    for (var i = 0; i < sampleXs.length; i++) {
      if ((sampleXs[i] - other.sampleXs[i]).abs() > 0.01 || sampleStates[i] != other.sampleStates[i]) return false;
    }
    for (var i = 0; i < stops.length; i++) {
      if (stops[i].role != other.stops[i].role) return false;
    }
    return true;
  }

  double halfWidthAt(double y) {
    final depth = (y / height).clamp(0.0, 1.0);
    return nearHalfWidth + (farHalfWidth - nearHalfWidth) * depth;
  }

  /// The route's x at [y] (linear between samples); the nearest end sample outside the route.
  double routeXAt(double y) {
    if (!hasRoute) return width / 2;
    if (y <= sampleYs.first) return sampleXs.first;
    if (y >= sampleYs.last) return sampleXs.last;
    final i = ((y - sampleYs.first) / sampleStep).floor().clamp(0, sampleYs.length - 2);
    final y0 = sampleYs[i];
    final y1 = sampleYs[i + 1];
    final t = y0 == y1 ? 0.0 : (y - y0) / (y1 - y0);
    return sampleXs[i] + (sampleXs[i + 1] - sampleXs[i]) * t;
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

  static StopRouteRole roleOf(ScheduleItem item) {
    if (item.isCompleted) return item.isCompletedAfterDeviation ? StopRouteRole.recovered : StopRouteRole.onRoute;
    if (item.isSkipped || item.deviation == 'skipped' || item.deviation == 'deferred') return StopRouteRole.skipped;
    if (item.isFailed) return StopRouteRole.failed;
    // Time alone moves the route past a task whose slot ended unfinished. Commitments are protected: their time
    // passing is not a miss, so the route keeps running through them.
    if (item.isMissed && !item.isCommitment) return StopRouteRole.bypassed;
    return StopRouteRole.onRoute;
  }

  static double _smooth(double u) => u * u * (3 - 2 * u);

  /// The colour of the road arriving at [s].
  static RouteSegmentState _stateInto(StopGeometry s, {required bool isFinish}) {
    if (isFinish) return RouteSegmentState.traveled; // the finish only exists once the day is done
    if (s.role == StopRouteRole.recovered) return RouteSegmentState.recovered;
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

    // Vertical layout: the first (earliest) stop at the TOP, the last at the bottom, one even step per stop. A
    // stop's place is a function of its index in the chronological list only, so a state change never moves it.
    final spacings = List<double>.generate(
        math.max(0, points - 1), (i) => nearSpacing + (farSpacing - nearSpacing) * (points > 2 ? i / (points - 2) : 0.0));
    final height = padTop + spacings.fold<double>(0, (a, b) => a + b) + padBottom;
    final ys = <double>[];
    var fromTop = padTop;
    for (var i = 0; i < points; i++) {
      ys.add(fromTop);
      if (i < points - 1) fromTop += spacings[i];
    }

    final amp = math.min(width * 0.18, 72.0);
    StopGeometry place(int i, String id, StopRouteRole role, bool walked) {
      // depth is measured over the task stops only: adding the finish after the last one moves no stop
      final depth = (n > 1 ? i / (n - 1) : i.toDouble()).clamp(0.0, 1.0);
      final bend = math.sin(1.05 * i + 0.5);
      final x = width / 2 + amp * (1 - 0.22 * depth) * bend;
      final leftOfCentre = (x - width / 2).abs() < 10 ? i.isOdd : x >= width / 2;
      return StopGeometry(
        id: id,
        index: i,
        center: Offset(x, ys[i]),
        depth: depth,
        scale: 1 - (1 - farScale) * depth,
        labelOnLeft: leftOfCentre,
        role: role,
        walked: walked,
      );
    }

    final stops = <StopGeometry>[];
    for (var i = 0; i < n; i++) {
      final item = items[i];
      final role = roleOf(item);
      stops.add(place(i, item.id, role, role == StopRouteRole.onRoute && (item.isCompleted || item.id == nowItemId)));
    }
    final end = finish ? place(n, finishId, StopRouteRole.onRoute, true) : null;

    // The route passes through EVERY point, whatever its state: smooth S-curves between consecutive points.
    final route = [...stops, if (end != null) end];
    double routeX(double y) {
      if (y <= route.first.center.dy) return route.first.center.dx;
      if (y >= route.last.center.dy) return route.last.center.dx;
      for (var k = 0; k + 1 < route.length; k++) {
        final a = route[k].center;
        final b = route[k + 1].center;
        if (y >= a.dy && y <= b.dy) {
          final u = (y - a.dy) / (b.dy - a.dy);
          return a.dx + (b.dx - a.dx) * _smooth(u);
        }
      }
      return route.last.center.dx;
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
      states.add(_stateInto(route[k], isFinish: end != null && identical(route[k], end)));
    }

    for (var y = yStart; y <= yEnd; y += sampleStep) {
      addSample(y);
    }
    if (yEnd - sampleYs.last > 0.01) addSample(yEnd);

    return DayRouteGeometry(
      width: width,
      height: height,
      stops: stops,
      finish: end,
      sampleYs: sampleYs,
      sampleXs: sampleXs,
      sampleStates: states,
      tailStart: sampleYs.length, // no faded tail: the road simply ends at the last point
    );
  }
}
