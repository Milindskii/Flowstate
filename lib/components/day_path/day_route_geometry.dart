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

  /// A recovered stop the traveller did NOT reach from the stop before it: the road bends around it (like any
  /// bypassed stop) and a [RecoveryBranch] runs to it from where the traveller really was.
  final bool detached;

  const StopGeometry({
    required this.id,
    required this.index,
    required this.center,
    required this.depth,
    required this.scale,
    required this.labelOnLeft,
    required this.role,
    required this.walked,
    this.detached = false,
  });

  StopGeometry copyWith({bool? walked, bool? detached}) => StopGeometry(
        id: id,
        index: index,
        center: center,
        depth: depth,
        scale: scale,
        labelOnLeft: labelOnLeft,
        role: role,
        walked: walked ?? this.walked,
        detached: detached ?? this.detached,
      );
}

/// The way back to a recovered stop: from the stop where the traveller actually WAS (their latest real position) to
/// the recovered stop, which keeps its place on the timeline. It exists only for a stop completed after it was
/// skipped or missed and not reached from the stop before it; it is never drawn from the chronological predecessor.
class RecoveryBranch {
  final String fromId;
  final String toId;

  /// The branch as a polyline, from [fromId]'s node to [toId]'s node.
  final List<Offset> points;

  const RecoveryBranch({required this.fromId, required this.toId, required this.points});
}

/// The single source of truth for the Day Path route.
///
/// ONE canonical route runs top to bottom (the first task of the day at the top, the last at the bottom), sampled on
/// a fixed grid. Stops never move: their places depend on the chronological index only. The road's shape is derived
/// from the latest stop states every time they change:
///
///   task states  ->  stop roles  ->  route points  ->  sampled geometry  ->  segment state / node state
///
/// The road runs through each stop, except a skipped, missed or failed one: there it swings past the node (which stays
/// at its timeline slot) and continues to the next stop. A stop recovered later is back on the road.
/// The route is cut into segments, one per stop (the stretch arriving at it), and each segment gets a colour from
/// its stop: green when walked, orange when the stop was recovered, blue otherwise.
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

  /// Orange recovery branches, one per detached recovered stop (see [RecoveryBranch]).
  final List<RecoveryBranch> branches;

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
    this.branches = const [],
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
      if (stops[i].role != other.stops[i].role || stops[i].detached != other.stops[i].detached) return false;
    }
    if (branches.length != other.branches.length) return false;
    for (var i = 0; i < branches.length; i++) {
      final a = branches[i];
      final b = other.branches[i];
      if (a.fromId != b.fromId || a.toId != b.toId || a.points.length != b.points.length) return false;
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

  /// Roles whose node the road does not run through.
  static bool isDeviation(StopRouteRole role) =>
      role == StopRouteRole.skipped || role == StopRouteRole.bypassed || role == StopRouteRole.failed;

  /// True when the road does not run through this stop's node: a deviation role, or a recovered stop that was
  /// reached from somewhere other than the stop before it.
  static bool isBypassed(StopGeometry s) => isDeviation(s.role) || s.detached;

  /// Where the traveller was just before each recovered stop was completed, as {recovered index: origin index}.
  ///
  /// With a completion time for every finished stop the traveller's real order is the completion order, and a
  /// recovered stop's origin is the stop completed right before it. Without the times the latest stop the traveller
  /// finished on plan AFTER the recovered one is where they were; with none, the stop completed before it.
  /// A recovered stop that is the traveller's first completion has no origin: it stays on the road, with no branch.
  static Map<int, int?> recoveryOrigins(List<ScheduleItem> items, Map<String, DateTime>? completedAt) {
    final done = <int>[for (var i = 0; i < items.length; i++) if (items[i].isCompleted) i];
    final recovered = <int>[for (final i in done) if (items[i].isCompletedAfterDeviation) i];
    if (recovered.isEmpty) return const {};
    final timed = completedAt != null && done.every((i) => completedAt[items[i].id] != null);
    final out = <int, int?>{};
    if (timed) {
      final order = [...done]..sort((a, b) {
          final byTime = completedAt[items[a].id]!.compareTo(completedAt[items[b].id]!);
          return byTime != 0 ? byTime : a.compareTo(b);
        });
      for (final r in recovered) {
        final pos = order.indexOf(r);
        out[r] = pos > 0 ? order[pos - 1] : null;
      }
      return out;
    }
    for (final r in recovered) {
      int? later;
      int? earlier;
      for (final i in done) {
        if (i == r) continue;
        if (i > r && !items[i].isCompletedAfterDeviation) later = i;
        if (i < r) earlier = i;
      }
      out[r] = later ?? earlier;
    }
    return out;
  }

  /// How far a recovery branch swings out from the road between its two ends.
  static const double branchBulge = 26;

  /// How far (centre to centre) the road passes from a bypassed node: node radius + road half-width + air.
  static const double detourDistance = nodeRadius + nearHalfWidth + 5;

  /// The road's x beside a bypassed stop: away from its label, or to the other side when that would leave the screen.
  static double _detourX(StopGeometry s, double width) {
    final dir = s.labelOnLeft ? 1.0 : -1.0;
    final preferred = s.center.dx + dir * detourDistance;
    const margin = nearHalfWidth + 4;
    if (preferred >= margin && preferred <= width - margin) return preferred;
    return s.center.dx - dir * detourDistance;
  }

  /// The colour of the road arriving at [s].
  static RouteSegmentState _stateInto(StopGeometry s, {required bool isFinish}) {
    if (isFinish) return RouteSegmentState.traveled; // the finish only exists once the day is done
    if (s.role == StopRouteRole.recovered && !s.detached) return RouteSegmentState.recovered;
    return s.walked ? RouteSegmentState.traveled : RouteSegmentState.ahead;
  }

  /// [finish] adds the end of the road after the last stop: the day's Trophy sits there, on the same route.
  static DayRouteGeometry compute(List<ScheduleItem> items, String? nowItemId, double width,
      {bool finish = false, Map<String, DateTime>? completedAt}) {
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
    // A recovered stop the traveller reached from the stop right before it (or as their first finished stop) is on
    // the road (orange into it). One reached from anywhere else (latest real position, e.g. D -> B) is detached: the road bends around it like any
    // bypassed stop and a recovery branch carries the traveller there, so no A -> B travel is invented.
    final origins = recoveryOrigins(items, completedAt);
    origins.forEach((r, origin) {
      if (origin != null && origin != r - 1) stops[r] = stops[r].copyWith(detached: true);
    });
    // The journey went past a skipped / missed / failed stop when something after it was walked: the road that
    // arrives at it is then already travelled (the node keeps its own look, so nothing is faked as done).
    var lastWalked = -1;
    for (var i = 0; i < n; i++) {
      if (stops[i].walked) lastWalked = i;
    }
    for (var i = 0; i < n; i++) {
      if (isBypassed(stops[i]) && i < lastWalked) stops[i] = stops[i].copyWith(walked: true);
    }
    final end = finish ? place(n, finishId, StopRouteRole.onRoute, true) : null;

    // The route is a function of the stops' STATES as well as their places: every point it passes through is the
    // stop itself, except a stop the journey bypassed (skipped / missed / failed), where the road swings past the
    // node on the side its label is not on. The node stays at its timeline slot; the road bends around it and
    // carries on to the next stop. Between consecutive points: smooth S-curves.
    final route = [...stops, if (end != null) end];
    final waypoints = <Offset>[
      for (final s in route) isBypassed(s) ? Offset(_detourX(s, width), s.center.dy) : s.center,
    ];
    double routeX(double y) {
      if (y <= waypoints.first.dy) return waypoints.first.dx;
      if (y >= waypoints.last.dy) return waypoints.last.dx;
      for (var k = 0; k + 1 < waypoints.length; k++) {
        final a = waypoints[k];
        final b = waypoints[k + 1];
        if (y >= a.dy && y <= b.dy) {
          final u = (y - a.dy) / (b.dy - a.dy);
          return a.dx + (b.dx - a.dx) * _smooth(u);
        }
      }
      return waypoints.last.dx;
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

    // Recovery branches: from the traveller's real previous position to each detached recovered stop. The branch
    // leaves the road at the origin stop and arrives at the recovered node (which stays at its timeline slot),
    // swinging out to the side the node is on so it never runs along the road it left.
    final branches = <RecoveryBranch>[];
    origins.forEach((r, originIndex) {
      if (originIndex == null || !stops[r].detached) return;
      final from = stops[originIndex];
      final to = stops[r];
      final yFrom = from.center.dy;
      final yTo = to.center.dy;
      final steps = math.max(2, ((yTo - yFrom).abs() / sampleStep).ceil());
      final startOff = from.center.dx - routeX(yFrom);
      final endOff = to.center.dx - routeX(yTo);
      final side = endOff == 0 ? 1.0 : endOff.sign;
      const margin = nearHalfWidth + 4;
      final pts = <Offset>[];
      for (var k = 0; k <= steps; k++) {
        final u = k / steps;
        final y = yFrom + (yTo - yFrom) * u;
        final off = startOff + (endOff - startOff) * _smooth(u) + side * branchBulge * math.sin(math.pi * u);
        pts.add(Offset((routeX(y) + off).clamp(margin, width - margin), y));
      }
      pts[0] = from.center;
      pts[pts.length - 1] = to.center;
      branches.add(RecoveryBranch(fromId: from.id, toId: to.id, points: pts));
    });

    return DayRouteGeometry(
      width: width,
      height: height,
      stops: stops,
      finish: end,
      sampleYs: sampleYs,
      sampleXs: sampleXs,
      sampleStates: states,
      tailStart: sampleYs.length, // no faded tail: the road simply ends at the last point
      branches: branches,
    );
  }
}
