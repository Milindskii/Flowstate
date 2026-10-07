import 'dart:math' as math;
import 'dart:ui';

import '../../models/schedule_item.dart';

/// How a stop relates to the main route.
enum StopRouteRole {
  /// The route passes through this stop (planned, active, completed, missed, commitment).
  onRoute,

  /// Skipped or deferred: the route bends AROUND the stop (yellow).
  skipped,

  /// Unfinished past the sleep boundary: the route bends around it (red — true failure only).
  failed,

  /// The slot ended and the task was not done: the route moves past it on its own (derived from the clock, never a
  /// user "skip"), the node stays where it is and the task keeps its history. Distinct from [skipped].
  bypassed,

  /// Skipped/deferred earlier and completed since: the route still bends around it (history is kept)
  /// and an orange detour runs through it.
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

  bool get onRoute => role == StopRouteRole.onRoute;
}

/// A line that leaves the main route to touch a bypassed stop (a short dashed spur).
class RouteSpur {
  final String stopId;
  final StopRouteRole role;
  final Offset from;
  final Offset to;
  const RouteSpur({required this.stopId, required this.role, required this.from, required this.to});
}

/// The orange recovery detour: previous route stop → recovered stop → next route stop.
class RouteDetour {
  final String stopId;
  final List<Offset> points;
  const RouteDetour({required this.stopId, required this.points});
}

/// The single source of truth for the Day Path route.
///
/// The main route is a function of y (it only ever travels forward, top → bottom: the first task of the day is at the
/// top, the last at the bottom), sampled on a fixed grid, so
/// two geometries with the same [layoutSignature] can be morphed by interpolating [sampleXs]. Everything is derived
/// from the items' real state: nothing here is a visual-only flag.
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

  /// How far the route stays from a bypassed stop's centre.
  static const double bypassClearance = nodeRadius + nearHalfWidth + 26;

  final double width;
  final double height;
  final List<StopGeometry> stops;

  /// Main-route samples, top to bottom (y increasing).
  final List<double> sampleYs;
  final List<double> sampleXs;

  /// True when the sample belongs to the walked stretch (green); false is the road ahead (blue).
  final List<bool> sampleTraveled;

  /// Index of the first sample past the last route stop (always the sample count: the road ends at the last stop).
  final int tailStart;
  final List<RouteSpur> spurs;
  final List<RouteDetour> detours;

  const DayRouteGeometry({
    required this.width,
    required this.height,
    required this.stops,
    required this.sampleYs,
    required this.sampleXs,
    required this.sampleTraveled,
    required this.tailStart,
    required this.spurs,
    required this.detours,
  });

  bool get hasRoute => sampleYs.isNotEmpty;

  /// Two geometries with the same signature have the same stops and sample grid, so their routes can morph.
  String get layoutSignature =>
      '${width.round()}|${stops.map((s) => s.id).join(',')}|${sampleYs.length}|${sampleYs.isEmpty ? 0 : sampleYs.first}|${sampleYs.isEmpty ? 0 : sampleYs.last}';

  /// True when [other] would draw the same route (same samples, colors, detours and spurs).
  bool sameRoute(DayRouteGeometry other) {
    if (layoutSignature != other.layoutSignature ||
        sampleXs.length != other.sampleXs.length ||
        detours.length != other.detours.length ||
        spurs.length != other.spurs.length ||
        tailStart != other.tailStart) {
      return false;
    }
    for (var i = 0; i < sampleXs.length; i++) {
      if ((sampleXs[i] - other.sampleXs[i]).abs() > 0.01 || sampleTraveled[i] != other.sampleTraveled[i]) return false;
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

  static DayRouteGeometry compute(List<ScheduleItem> items, String? nowItemId, double width) {
    final n = items.length;
    if (n == 0) {
      return DayRouteGeometry(
          width: width, height: 0, stops: const [], sampleYs: const [], sampleXs: const [], sampleTraveled: const [], tailStart: 0, spurs: const [], detours: const []);
    }

    // Vertical layout: the first (earliest) stop at the TOP, the last at the bottom, one even step per stop. A
    // stop's place is a function of its index in the chronological list only, so a state change never moves it.
    final spacings = List<double>.generate(
        math.max(0, n - 1), (i) => nearSpacing + (farSpacing - nearSpacing) * (n > 2 ? i / (n - 2) : 0.0));
    final height = padTop + spacings.fold<double>(0, (a, b) => a + b) + padBottom;
    final ys = <double>[];
    var fromTop = padTop;
    for (var i = 0; i < n; i++) {
      ys.add(fromTop);
      if (i < n - 1) fromTop += spacings[i];
    }

    final amp = math.min(width * 0.18, 72.0);
    final stops = <StopGeometry>[];
    for (var i = 0; i < n; i++) {
      final depth = n > 1 ? i / (n - 1) : 0.0;
      final bend = math.sin(1.05 * i + 0.5);
      final x = width / 2 + amp * (1 - 0.22 * depth) * bend;
      final item = items[i];
      final role = roleOf(item);
      final walked = role == StopRouteRole.onRoute && (item.isCompleted || item.id == nowItemId);
      final leftOfCentre = (x - width / 2).abs() < 10 ? i.isOdd : x >= width / 2;
      stops.add(StopGeometry(
        id: item.id,
        index: i,
        center: Offset(x, ys[i]),
        depth: depth,
        scale: 1 - (1 - farScale) * depth,
        labelOnLeft: leftOfCentre,
        role: role,
        walked: walked,
      ));
    }

    final route = [for (final s in stops) if (s.onRoute) s];
    if (route.isEmpty) {
      return DayRouteGeometry(
          width: width, height: height, stops: stops, sampleYs: const [], sampleXs: const [], sampleTraveled: const [], tailStart: 0, spurs: const [], detours: const []);
    }

    // Base route: smooth S-curves between consecutive route stops, straight outside the first/last.
    double baseX(double y) {
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

    // Bypassed stops push the route sideways, away from the stop, until it clears them.
    final bypassed = [for (final s in stops) if (!s.onRoute) s];
    final bumps = <(double y, double amp, double half)>[];
    double bumpAt(double y) {
      var sum = 0.0;
      for (final b in bumps) {
        final d = (y - b.$1).abs();
        if (d < b.$3) sum += b.$2 * 0.5 * (1 + math.cos(math.pi * d / b.$3));
      }
      return sum;
    }

    for (var pass = 0; pass < 2; pass++) {
      for (final s in bypassed) {
        final cur = baseX(s.center.dy) + bumpAt(s.center.dy);
        final gap = s.center.dx - cur;
        final need = bypassClearance - gap.abs();
        if (need > 0.5) {
          final away = gap >= 0 ? -1.0 : 1.0;
          bumps.add((s.center.dy, away * need, 104.0));
        }
      }
    }
    double routeX(double y) => (baseX(y) + bumpAt(y)).clamp(28.0, width - 28.0);

    // Sample grid: the road begins at the first stop and ends at the last one (no lead-in, no tail).
    final yStart = stops.first.center.dy;
    final yEnd = stops.last.center.dy;
    final sampleYs = <double>[];
    final sampleXs = <double>[];
    final traveled = <bool>[];
    var tailStart = -1;
    for (var y = yStart; y <= yEnd; y += sampleStep) {
      sampleYs.add(y);
      sampleXs.add(routeX(y));
      if (y <= route.first.center.dy) {
        traveled.add(route.first.walked);
      } else if (y >= route.last.center.dy) {
        traveled.add(false);
        if (tailStart < 0) tailStart = sampleYs.length - 1;
      } else {
        var walked = false;
        for (var k = 0; k + 1 < route.length; k++) {
          if (y >= route[k].center.dy && y <= route[k + 1].center.dy) {
            walked = route[k + 1].walked;
            break;
          }
        }
        traveled.add(walked);
      }
    }
    if (yEnd - sampleYs.last > 0.01) {
      sampleYs.add(yEnd);
      sampleXs.add(routeX(yEnd));
      traveled.add(traveled.last);
    }
    tailStart = sampleYs.length; // no faded tail: the road simply ends at the last stop

    final geo = DayRouteGeometry(
      width: width,
      height: height,
      stops: stops,
      sampleYs: sampleYs,
      sampleXs: sampleXs,
      sampleTraveled: traveled,
      tailStart: tailStart,
      spurs: const [],
      detours: const [],
    );

    final spurs = <RouteSpur>[];
    final detours = <RouteDetour>[];
    for (final s in bypassed) {
      final rx = geo.routeXAt(s.center.dy);
      final dir = s.center.dx >= rx ? 1.0 : -1.0;
      final r = nodeRadius * s.scale;
      final hw = geo.halfWidthAt(s.center.dy);
      final from = Offset(rx + dir * (hw + 1), s.center.dy);
      final to = Offset(s.center.dx - dir * (r + 2), s.center.dy);
      if (s.role != StopRouteRole.recovered && (to.dx - from.dx).abs() > 4) {
        spurs.add(RouteSpur(stopId: s.id, role: s.role, from: from, to: to));
      }
      if (s.role == StopRouteRole.recovered) {
        StopGeometry? before;
        StopGeometry? after;
        for (final r2 in route) {
          if (r2.index < s.index) before = r2;
          if (r2.index > s.index && after == null) after = r2;
        }
        final pts = <Offset>[];
        void leg(Offset a, Offset b) {
          const steps = 18;
          for (var i = 0; i <= steps; i++) {
            final u = i / steps;
            pts.add(Offset(a.dx + (b.dx - a.dx) * _smooth(u), a.dy + (b.dy - a.dy) * u));
          }
        }

        final a = before?.center ?? Offset(s.center.dx, math.max(0.0, s.center.dy - 44));
        final c = after?.center ?? Offset(s.center.dx, math.min(height, s.center.dy + 44));
        leg(a, s.center);
        leg(s.center, c);
        detours.add(RouteDetour(stopId: s.id, points: pts));
      }
    }

    return DayRouteGeometry(
      width: width,
      height: height,
      stops: [for (final s in stops) s.onRoute ? s : _labelAwayFromRoad(s, geo, width)],
      sampleYs: sampleYs,
      sampleXs: sampleXs,
      sampleTraveled: traveled,
      tailStart: tailStart,
      spurs: spurs,
      detours: detours,
    );
  }

  /// A bypassed stop sits off the road, so its label goes on the outer side (never over the road) when there is
  /// room for it. Only the label side changes; the stop itself never moves.
  static StopGeometry _labelAwayFromRoad(StopGeometry s, DayRouteGeometry geo, double width) {
    final outerLeft = s.center.dx < geo.routeXAt(s.center.dy);
    const reserved = 24.0 + 12.0; // half the tap box + the label's outer margin
    final room = outerLeft ? s.center.dx - reserved : width - s.center.dx - reserved;
    if (room < 76 || outerLeft == s.labelOnLeft) return s;
    return StopGeometry(
      id: s.id,
      index: s.index,
      center: s.center,
      depth: s.depth,
      scale: s.scale,
      labelOnLeft: outerLeft,
      role: s.role,
      walked: s.walked,
    );
  }
}
