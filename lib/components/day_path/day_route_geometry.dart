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

  /// A stretch of the main road the traveller did NOT walk (the route's head had moved on to another stop, so a
  /// [RecoveryBranch] carries the journey from there instead). Never drawn; it only keeps the sample grid whole.
  hidden,
}

/// Where a stop's label may be drawn: a horizontal span beside the node, inside the row, that neither the road (bed
/// included) nor a recovery branch crosses within the label's height. [onLeft] says which side of the node it is on;
/// the text hugs the node (right-aligned on the left, left-aligned on the right).
class LabelSlot {
  final double left;
  final double right;
  final bool onLeft;

  const LabelSlot({required this.left, required this.right, required this.onLeft});

  double get width => math.max(0, right - left);

  @override
  String toString() => 'LabelSlot(${left.toStringAsFixed(1)}..${right.toStringAsFixed(1)}, ${onLeft ? 'left' : 'right'})';
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

  /// The road-free span its label uses (computed once the road and branches are known).
  final LabelSlot? label;

  /// True when Noya's focus avatar fits beside the node, on the side away from the label, without touching the road,
  /// a branch or the screen edge. When it does not, Noya is simply not drawn there (nothing ever overlaps).
  final bool companionFits;

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
    this.label,
    this.companionFits = false,
  });

  StopGeometry copyWith({bool? walked, bool? detached, LabelSlot? label, bool? companionFits}) => StopGeometry(
        id: id,
        index: index,
        center: center,
        depth: depth,
        scale: scale,
        labelOnLeft: labelOnLeft,
        role: role,
        walked: walked ?? this.walked,
        detached: detached ?? this.detached,
        label: label ?? this.label,
        companionFits: companionFits ?? this.companionFits,
      );
}

/// A branch of the one road that runs from where the traveller REALLY is: the way back to a recovered stop, or the way
/// on from the journey head (a recovered stop) to the next stop. For the way back: from the stop where the traveller actually WAS (their latest real position) to
/// the recovered stop, which keeps its place on the timeline. It exists only for a stop completed after it was
/// skipped or missed and not reached from the stop before it; it is never drawn from the chronological predecessor.
class RecoveryBranch {
  final String fromId;
  final String toId;

  /// The branch as a polyline, from [fromId]'s node to [toId]'s node.
  final List<Offset> points;

  /// Its colour: orange for the way back ([RouteSegmentState.recovered]); a way ON from the journey head is green when
  /// the stop it reaches is done or running and blue when it is still ahead.
  final RouteSegmentState state;

  /// Where this branch crosses the main road: a stop on the far side of the road from its lane, and the reach of the
  /// turn out of it. It crosses there once, level and straight across, like a junction; nowhere else does it touch
  /// the road.
  final List<(Offset stop, double reach)> junctions;

  const RecoveryBranch({
    required this.fromId,
    required this.toId,
    required this.points,
    this.state = RouteSegmentState.recovered,
    this.junctions = const [],
  });
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
      if (a.fromId != b.fromId || a.toId != b.toId || a.state != b.state || a.points.length != b.points.length) return false;
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
    if (item.isSkipped || item.deviation == 'skipped' || item.deviation == 'deferred' || item.deviation == 'auto_skipped') {
      return StopRouteRole.skipped;
    }
    if (item.isFailed) return StopRouteRole.failed;
    // Time alone moves the route past a task whose slot ended unfinished. Commitments are protected: their time
    // passing is not a miss, so the route keeps running through them.
    if (item.isMissed && !item.isCommitment) return StopRouteRole.bypassed;
    return StopRouteRole.onRoute;
  }

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
    final timed = completedAt != null && done.every((i) => completedAt[items[i].id] != null);
    if (recovered.isEmpty && !timed) return const {};
    final out = <int, int?>{};
    if (timed) {
      final order = [...done]..sort((a, b) {
          final byTime = completedAt[items[a].id]!.compareTo(completedAt[items[b].id]!);
          return byTime != 0 ? byTime : a.compareTo(b);
        });
      for (var pos = 0; pos < order.length; pos++) {
        final r = order[pos];
        final origin = pos > 0 ? order[pos - 1] : null;
        // A flagged recovery always has an origin; an on-plan completion has one only when the traveller came BACK to
        // it from a later stop (it was passed by, then done): that is a change of course, drawn like a recovery.
        if (items[r].isCompletedAfterDeviation) {
          out[r] = origin;
        } else if (origin != null && origin > r) {
          out[r] = origin;
        }
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

  /// The finished stops' indices in the order the traveller really finished them, or null when any finished stop has no
  /// completion time (the order is then unknown and no journey head is inferred).
  static List<int>? timedCompletionOrder(List<ScheduleItem> items, Map<String, DateTime>? completedAt) {
    if (completedAt == null) return null;
    final done = <int>[for (var i = 0; i < items.length; i++) if (items[i].isCompleted) i];
    if (done.isEmpty || !done.every((i) => completedAt[items[i].id] != null)) return null;
    return done
      ..sort((a, b) {
        final byTime = completedAt[items[a].id]!.compareTo(completedAt[items[b].id]!);
        return byTime != 0 ? byTime : a.compareTo(b);
      });
  }

  /// How far a branch's bow clears the road and the stops it passes, and the step between nested bows: a node's box
  /// plus the branch's bed, with air, so a bow never touches a stop or another bow.
  static const double laneGap = nodeBoxHalf + nearHalfWidth + 10;

  /// How far (centre to centre) the road passes from a bypassed node: node radius + road half-width + air.
  static const double detourDistance = nodeRadius + nearHalfWidth + 11;

  /// The road's x beside a bypassed stop: away from its label, or to the other side when that would leave the screen.
  static double _detourX(StopGeometry s, double width) {
    final dir = s.labelOnLeft ? 1.0 : -1.0;
    final preferred = s.center.dx + dir * detourDistance;
    const margin = nearHalfWidth + 4;
    if (preferred >= margin && preferred <= width - margin) return preferred;
    return s.center.dx - dir * detourDistance;
  }

  /// Half the height a stop's label may take (two title lines + one meta line + one state line), centred on the node.
  static const double labelHalfHeight = 36;

  /// Clear space kept between a label and the road bed / the node.
  static const double labelAir = 6;

  /// Screen-edge margin for labels.
  static const double labelMargin = 12;

  /// Below this width a label side is too cramped: the other side is used when it has more room.
  static const double minLabelWidth = 112;

  /// Visible node box half-width (the node plus its state badge).
  static const double nodeBoxHalf = 24;

  /// The road-free span beside [s] for its label: every polyline (the road, each recovery branch) that passes
  /// within the label's height blocks the x range it covers (plus the bed and some air). The widest free span on
  /// the stop's preferred side is used unless it is cramped and the other side offers more. Deterministic: the same
  /// geometry always gives the same slot.
  static LabelSlot labelSlotFor(StopGeometry s, List<List<Offset>> polylines, double width) {
    final top = s.center.dy - labelHalfHeight;
    final bottom = s.center.dy + labelHalfHeight;
    const pad = nearHalfWidth + labelAir;
    final blocked = <(double, double)>[(s.center.dx - nodeBoxHalf - labelAir, s.center.dx + nodeBoxHalf + labelAir)];
    for (final line in polylines) {
      for (var k = 0; k + 1 < line.length; k++) {
        final a = line[k];
        final b = line[k + 1];
        final lo = math.min(a.dy, b.dy);
        final hi = math.max(a.dy, b.dy);
        if (hi < top || lo > bottom) continue;
        // the part of this segment inside the band
        double xAt(double y) => (b.dy - a.dy).abs() < 1e-9 ? a.dx : a.dx + (b.dx - a.dx) * ((y - a.dy) / (b.dy - a.dy));
        final y0 = math.max(lo, top);
        final y1 = math.min(hi, bottom);
        final x0 = xAt(y0);
        final x1 = xAt(y1);
        blocked.add((math.min(x0, x1) - pad, math.max(x0, x1) + pad));
      }
    }
    // free spans on each side of the node, inside the screen margins
    List<(double, double)> free(double from, double to) {
      if (to - from <= 0) return const [];
      final cuts = blocked.where((b) => b.$2 > from && b.$1 < to).toList()..sort((a, b) => a.$1.compareTo(b.$1));
      final out = <(double, double)>[];
      var x = from;
      for (final c in cuts) {
        if (c.$1 > x) out.add((x, c.$1));
        x = math.max(x, c.$2);
      }
      if (to > x) out.add((x, to));
      return out;
    }

    (double, double)? widest(List<(double, double)> spans, {required bool leftSide}) {
      (double, double)? best;
      for (final sp in spans) {
        final w = sp.$2 - sp.$1;
        if (best == null) {
          best = sp;
          continue;
        }
        final bw = best.$2 - best.$1;
        // wider wins; on a near-tie the span closer to the node (the text stays attached to its stop)
        final closer = leftSide ? sp.$2 > best.$2 : sp.$1 < best.$1;
        if (w > bw + 8 || ((w - bw).abs() <= 8 && closer)) best = sp;
      }
      return best;
    }

    final leftSpan = widest(free(labelMargin, s.center.dx), leftSide: true);
    final rightSpan = widest(free(s.center.dx, width - labelMargin), leftSide: false);
    double w((double, double)? sp) => sp == null ? 0 : sp.$2 - sp.$1;
    var onLeft = s.labelOnLeft;
    final preferred = onLeft ? leftSpan : rightSpan;
    final other = onLeft ? rightSpan : leftSpan;
    if (w(preferred) < minLabelWidth && w(other) > w(preferred)) onLeft = !onLeft;
    final span = onLeft ? leftSpan : rightSpan;
    if (span == null) {
      // nothing free at all (a pathological width): fall back to the plain side beside the node
      return onLeft
          ? LabelSlot(left: labelMargin, right: math.max(labelMargin, s.center.dx - nodeBoxHalf - labelAir), onLeft: true)
          : LabelSlot(left: math.min(width - labelMargin, s.center.dx + nodeBoxHalf + labelAir), right: width - labelMargin, onLeft: false);
    }
    return LabelSlot(left: span.$1, right: span.$2, onLeft: onLeft);
  }

  /// A branch is drawn like a line on a transit map: a rounded corner out of its top stop into a straight vertical lane,
  /// down the lane, and a rounded corner into its bottom stop. Lanes stay exactly one step apart along their whole
  /// length.
  ///
  /// One corner at [end] (the branch's [top] or bottom stop) into the lane at [laneX], [r] tall. [tilt] says how it
  /// leaves the stop: 0 is level (straight out, away from the road), positive tips it toward the lane's run, negative
  /// the other way. Returned in top-to-bottom order.
  static List<Offset> _corner(Offset end, double laneX, double r, double tilt, {required bool top}) {
    final (p0, c, p2) = top
        ? (end, Offset(laneX, end.dy + r * tilt), Offset(laneX, end.dy + r))
        : (Offset(laneX, end.dy - r), Offset(laneX, end.dy - r * tilt), end);
    // about one point per road sample step along the curve, like the main road
    final n = math.max(12, (((c - p0).distance + (p2 - c).distance) / (sampleStep * 0.75)).ceil());
    return [
      for (var k = 0; k <= n; k++)
        () {
          final t = k / n;
          final u = 1 - t;
          return p0 * (u * u) + c * (2 * u * t) + p2 * (t * t);
        }(),
    ];
  }

  /// How much room [pts] leave (negative: by how much they overlap) to the [lines] (bed against bed) and to the stop
  /// [nodes] (node against bed). Points within a node's reach of [own] (the stop they leave) are not counted.
  static double _slack(List<Offset> pts, Offset own, List<List<Offset>> lines, List<Offset> nodes) {
    var best = double.infinity;
    for (final p in pts) {
      if ((p - own).distance < nodeRadius + nearHalfWidth * 2) continue;
      for (final line in lines) {
        for (var i = 0; i + 1 < line.length; i++) {
          final a = line[i];
          final b = line[i + 1];
          if (math.min(a.dy, b.dy) - p.dy > best + nearHalfWidth * 2 ||
              p.dy - math.max(a.dy, b.dy) > best + nearHalfWidth * 2) {
            continue; // too far above / below to matter
          }
          final ab = b - a;
          final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
          final t = len2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
          best = math.min(best, (p - (a + ab * t)).distance - nearHalfWidth * 2);
        }
      }
      for (final c in nodes) {
        best = math.min(best, (p - c).distance - nodeRadius - nearHalfWidth);
      }
    }
    return best;
  }

  /// True when a branch's [pts] keep clear (bed against bed, with air) of the [road] runs, of every stop node but its own
  /// [ends], and of the [others] branches (each with its own ends): checked both ways, away from the stops each line
  /// leaves (within a node and a lane of them, branches meet stops by design).
  ///
  /// [junctions]: ends on the far side of the road from the branch's lane, each with the reach of its turn. Within that
  /// turn the branch crosses the road (once, level, as a junction), so the road is not counted there.
  static bool _branchClear(List<Offset> pts, List<Offset> ends, List<List<Offset>> road, List<Offset> nodes,
      List<(List<Offset>, List<Offset>)> others, {List<(Offset, double)> junctions = const []}) {
    const reachOfEnd = nodeRadius + laneGap;
    const bedPair = nearHalfWidth * 2 - 0.5;
    bool near(Offset p, List<Offset> es) => es.any((e) => (p - e).distance < reachOfEnd);
    double dist(Offset p, List<Offset> line) {
      var best = double.infinity;
      for (var i = 0; i + 1 < line.length; i++) {
        final a = line[i];
        final b = line[i + 1];
        final ab = b - a;
        final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
        final t = len2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
        best = math.min(best, (p - (a + ab * t)).distance);
      }
      return best;
    }

    for (final p in pts) {
      if (near(p, ends)) continue;
      final atJunction = junctions.any((j) => (p - j.$1).distance < j.$2);
      for (final run in road) {
        if (!atJunction && dist(p, run) < bedPair) return false;
      }
      for (final c in nodes) {
        if (!ends.contains(c) && (p - c).distance < nodeRadius + nearHalfWidth - 0.5) return false;
      }
      for (final (line, oEnds) in others) {
        if (!near(p, oEnds) && dist(p, line) < bedPair) return false;
      }
    }
    for (final (line, oEnds) in others) {
      for (final p in line) {
        if (near(p, oEnds) || near(p, ends)) continue;
        if (dist(p, pts) < bedPair) return false;
      }
    }
    return true;
  }

  /// Size of Noya's focus avatar beside a node, and its gap from the node's box (see the day path row).
  static const double companionSize = 44;
  static const double companionGap = 30;

  /// Where Noya's avatar sits beside a node centred at [c]: on the side away from the label.
  static Rect companionBox(Offset c, {required bool labelOnLeft}) {
    final left = labelOnLeft ? c.dx + companionGap : c.dx - companionGap - companionSize;
    return Rect.fromLTWH(left, c.dy - companionSize / 2, companionSize, companionSize);
  }

  /// True when [box] is on screen and no polyline's bed (plus a little air) enters it.
  static bool boxClear(Rect box, List<List<Offset>> polylines, double width) {
    if (box.left < 0 || box.right > width) return false;
    final r = box.inflate(nearHalfWidth + 2);
    for (final line in polylines) {
      for (var k = 0; k + 1 < line.length; k++) {
        final a = line[k];
        final b = line[k + 1];
        // sample the segment finely enough that a bed cannot slip between two checks
        final n = math.max(1, ((b - a).distance / 2).ceil());
        for (var j = 0; j <= n; j++) {
          if (r.contains(Offset.lerp(a, b, j / n)!)) return false;
        }
      }
    }
    return true;
  }

  /// The colour of the road arriving at [s].
  static RouteSegmentState _stateInto(StopGeometry s, {required bool isFinish}) {
    if (isFinish) return RouteSegmentState.traveled; // the finish only exists once the day is done
    if (s.role == StopRouteRole.recovered && !s.detached) return RouteSegmentState.recovered;
    return s.walked ? RouteSegmentState.traveled : RouteSegmentState.ahead;
  }

  /// The drawn stretches of the road: runs of consecutive samples joined by non-hidden stretches (the stretch from
  /// sample i to i + 1 takes the state of sample i + 1).
  static List<List<Offset>> _visibleRuns(List<double> xs, List<double> ys, List<RouteSegmentState> states) {
    final runs = <List<Offset>>[];
    List<Offset>? cur;
    for (var i = 1; i < ys.length; i++) {
      if (states[i] == RouteSegmentState.hidden) {
        cur = null;
        continue;
      }
      if (cur == null) {
        cur = [Offset(xs[i - 1], ys[i - 1])];
        runs.add(cur);
      }
      cur.add(Offset(xs[i], ys[i]));
    }
    return runs;
  }

  /// The drawn stretches for the painter, with its own (possibly morphing) x values.
  List<List<Offset>> visibleRuns(List<double> xs) => _visibleRuns(xs, sampleYs, sampleStates);

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

    // a gentler swing on narrow phones leaves room beside the road for branches and labels
    final amp = math.min(width * 0.15, 64.0);
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

    // The journey head is the stop the traveller finished LAST (by completion time). Recovering an old stop moves it
    // there, so the road ahead must start from it, not from the stop that comes before the next one on the timeline:
    //   * a stop finished right after the head, when the head is not the stop just above it, is reached FROM the head;
    //   * if the head is behind the furthest finished stop, the next stop on the timeline is reached from the head too.
    // Either way the main road's stretch into that stop is not walked (hidden) and a branch carries the journey from
    // the head. Derived from the states every time, so undoing a recovery brings the plain road back.
    final forwardTo = <int, int>{}; // route index reached -> index of the head it is reached from
    final order = timedCompletionOrder(items, completedAt);
    if (order != null) {
      for (var pos = 1; pos < order.length; pos++) {
        final x = order[pos];
        final p = order[pos - 1];
        final above = order.indexOf(x - 1); // the stop just above x, if it was finished BEFORE x
        if (!stops[x].detached && p < x - 1 && above >= 0 && above < pos) forwardTo[x] = p;
      }
      final head = order.last;
      final furthest = order.reduce(math.max);
      if (head < furthest && furthest + 1 < route.length) forwardTo[furthest + 1] = head;
    }
    // One smooth curve through the waypoints (x as a function of y, Catmull-Rom tangents): the road flows from point to
    // point instead of straightening up at every stop, so a detour reads as one gentle bend, not an S-kink.
    final tangents = <double>[
      for (var k = 0; k < waypoints.length; k++)
        if (waypoints.length < 2)
          0.0
        else
          (waypoints[math.min(k + 1, waypoints.length - 1)].dx - waypoints[math.max(k - 1, 0)].dx) /
              (waypoints[math.min(k + 1, waypoints.length - 1)].dy - waypoints[math.max(k - 1, 0)].dy) *
              ((k == 0 || k == waypoints.length - 1) ? 0.5 : 1.0)
    ];
    const edge = nearHalfWidth + 4;
    double routeX(double y) {
      if (y <= waypoints.first.dy) return waypoints.first.dx;
      if (y >= waypoints.last.dy) return waypoints.last.dx;
      for (var k = 0; k + 1 < waypoints.length; k++) {
        final a = waypoints[k];
        final b = waypoints[k + 1];
        if (y >= a.dy && y <= b.dy) {
          final h = b.dy - a.dy;
          final u = (y - a.dy) / h;
          final u2 = u * u;
          final u3 = u2 * u;
          final x = (2 * u3 - 3 * u2 + 1) * a.dx +
              (u3 - 2 * u2 + u) * h * tangents[k] +
              (-2 * u3 + 3 * u2) * b.dx +
              (u3 - u2) * h * tangents[k + 1];
          return x.clamp(edge, width - edge);
        }
      }
      return waypoints.last.dx;
    }

    // Sample grid: the road begins at the first stop and ends at the last point (no lead-in, no tail).
    final yStart = route.first.center.dy;
    final yEnd = route.last.center.dy;
    final sampleYs = <double>[];
    final sampleXs = <double>[];
    // The stretch that ARRIVES at a sample: the one whose far end is the first point at or below it.
    final arriving = <int>[];
    var k = 0;
    void addSample(double y) {
      while (k + 1 < route.length && y > route[k].center.dy + 1e-9) {
        k++;
      }
      sampleYs.add(y);
      sampleXs.add(routeX(y));
      arriving.add(k);
    }

    // A stretch the journey left by a way-on branch is hidden (the branch carries the journey there instead).
    List<RouteSegmentState> statesFor(Map<int, int> forward) => [
          for (final a in arriving)
            forward.containsKey(a)
                ? RouteSegmentState.hidden
                : _stateInto(route[a], isFinish: end != null && identical(route[a], end)),
        ];

    for (var y = yStart; y <= yEnd; y += sampleStep) {
      addSample(y);
    }
    if (yEnd - sampleYs.last > 0.01) addSample(yEnd);

    // Branches are laid out against the road as it is drawn for [forward] (the way-on stretches it hides). A branch
    // that cannot be placed without touching the road, a stop or another branch is not drawn at all (nothing ever
    // overlaps): a way back leaves the recovered stop's ring to tell the story, and a dropped way on is reported in
    // [dropped] so the plain road stretch comes back in its place.
    List<RecoveryBranch> buildBranches(Map<int, int> forward, List<RouteSegmentState> st, Set<int> dropped) {
      // Branches: the way BACK to each detached recovered stop (orange, from where the traveller really was) and the way
      // ON from the journey head. Each is ONE smooth bow from its start node to its end node, swung out beside the main
      // road so it clears every stop and stretch of road between its ends. All bows sit on one side and are nested like
      // lanes: two branches that share a stretch of the day never share a lane, the ways back take the inner lanes, so
      // no line crosses or runs on top of another.
      final specs = <(Offset from, Offset to, String fromId, String toId, RouteSegmentState state)>[];
      final forwardTargetOf = <int?>[];
      origins.forEach((r, originIndex) {
        if (originIndex == null || !stops[r].detached) return;
        final from = stops[originIndex];
        final to = stops[r];
        specs.add((from.center, to.center, from.id, to.id, RouteSegmentState.recovered));
        forwardTargetOf.add(null);
      });
      forward.forEach((target, headIndex) {
        final from = stops[headIndex];
        final to = route[target];
        final isFinish = end != null && identical(to, end);
        specs.add((from.center, waypoints[target], from.id, to.id,
            isFinish || to.walked ? RouteSegmentState.traveled : RouteSegmentState.ahead));
        forwardTargetOf.add(target);
      });

      // The preferred side: the one the detached stops sit on (away from the road's detours), else the roomier one.
      var lean = 0.0;
      for (final s in stops) {
        if (s.detached) lean += s.center.dx - routeX(s.center.dy);
      }
      if (lean.abs() < 1e-6) {
        for (final sp in specs) {
          lean += (width / 2) - routeX((sp.$1.dy + sp.$2.dy) / 2);
        }
      }
      final preferred = lean < 0 ? -1.0 : 1.0;

      // Think of each branch as a chord between two points of the day. Two chords whose ends interleave (a starts, b
      // starts, a ends, b ends) cannot both lie on one side of the road without crossing, so they go on opposite sides
      // (a two-colouring). Chords on the same side are then nested or apart, never crossing.
      final count = specs.length;
      double topOf(int i) => math.min(specs[i].$1.dy, specs[i].$2.dy);
      double bottomOf(int i) => math.max(specs[i].$1.dy, specs[i].$2.dy);
      const eps = 0.5;
      bool interleave(int i, int j) {
        final (a0, a1, b0, b1) = (topOf(i), bottomOf(i), topOf(j), bottomOf(j));
        return (a0 + eps < b0 && b0 + eps < a1 && a1 + eps < b1) || (b0 + eps < a0 && a0 + eps < b1 && b1 + eps < a1);
      }

      // Each chord would rather lie on the side its end stops sit on (a stop the road bends around is off to one side):
      // going the other way would cut across the road beside the stop.
      double prefOf(int i) {
        var off = 0.0;
        for (final e in [specs[i].$1, specs[i].$2]) {
          final d = e.dx - routeX(e.dy);
          if (d.abs() > 1) off += d;
        }
        return off.abs() < 1e-6 ? preferred : off.sign;
      }

      final sideOf = List<double?>.filled(count, null);
      for (var i = 0; i < count; i++) {
        if (sideOf[i] != null) continue;
        sideOf[i] = 1.0;
        final group = [i];
        final queue = [i];
        while (queue.isNotEmpty) {
          final c = queue.removeLast();
          for (var j = 0; j < count; j++) {
            if (j == c || !interleave(c, j)) continue;
            if (sideOf[j] == null) {
              sideOf[j] = -sideOf[c]!;
              group.add(j);
              queue.add(j);
            }
          }
        }
        // the group's two possible colourings are mirror images: keep the one most of its chords prefer
        var vote = 0.0;
        for (final g in group) {
          vote += prefOf(g) * sideOf[g]!;
        }
        if (vote < 0 || (vote == 0 && sideOf[i] != preferred)) {
          for (final g in group) {
            sideOf[g] = -sideOf[g]!;
          }
        }
      }

      // Lanes: a chord sits one lane outside every same-side chord it contains (sharing an end counts as containing). Its
      // lane hugs the road locally: just past the road and the stops over its own stretch, and one step outside the
      // lanes of the chords it contains. A side that runs out of room first narrows its steps (never below two beds side
      // by side with air); a chord that still does not fit moves to the other side when nothing there crosses it.
      bool contains(int outer, int inner) =>
          outer != inner &&
          topOf(inner) >= topOf(outer) - eps &&
          bottomOf(inner) <= bottomOf(outer) + eps &&
          (bottomOf(inner) - topOf(inner) < bottomOf(outer) - topOf(outer) - eps || inner < outer);
      final bySize = [for (var i = 0; i < count; i++) i]
        ..sort((x, y) => (bottomOf(x) - topOf(x)).compareTo(bottomOf(y) - topOf(y)));
      double localReach(int i, double side) {
        final from = specs[i].$1;
        final to = specs[i].$2;
        var reach = side < 0 ? math.min(from.dx, to.dx) : math.max(from.dx, to.dx);
        for (var y = topOf(i) + nodeRadius; y <= bottomOf(i) - nodeRadius; y += sampleStep) {
          final x = routeX(y);
          reach = side < 0 ? math.min(reach, x) : math.max(reach, x);
        }
        for (final st in route) {
          if (st.center.dy > topOf(i) + 1 && st.center.dy < bottomOf(i) - 1) {
            reach = side < 0 ? math.min(reach, st.center.dx) : math.max(reach, st.center.dx);
          }
        }
        return reach;
      }

      const minGap = nearHalfWidth * 2 + 12;
      bool fits(double x) => x >= edge - 0.01 && x <= width - edge + 0.01;
      (List<int>, List<double>) lanesFor(List<double?> sides) {
        final lane = List<int>.filled(count, 0);
        for (final i in bySize) {
          for (final j in bySize) {
            if (sides[j] == sides[i] && contains(i, j)) lane[i] = math.max(lane[i], lane[j] + 1);
          }
        }
        final xs = List<double>.filled(count, 0);
        for (final side in {for (final x in sides) x!}) {
          for (final gap in const [laneGap, minGap]) {
            var ok = true;
            for (final i in bySize) {
              if (sides[i] != side) continue;
              var x = localReach(i, side) + side * gap;
              for (final c in bySize) {
                if (sides[c] == side && contains(i, c)) x = side < 0 ? math.min(x, xs[c] - gap) : math.max(x, xs[c] + gap);
              }
              xs[i] = x;
              ok = ok && fits(x);
            }
            if (ok) break;
          }
        }
        return (lane, xs);
      }

      var (laneOf, laneXs) = lanesFor(sideOf);
      for (final i in bySize) {
        if (fits(laneXs[i])) continue;
        final other = -sideOf[i]!;
        final free = [for (var j = 0; j < count; j++) if (j != i && sideOf[j] == other && interleave(i, j)) j].isEmpty;
        if (!free) continue;
        final trial = [...sideOf]..[i] = other;
        final (tLane, tXs) = lanesFor(trial);
        int misfits(List<double> xs) => [for (final x in xs) if (!fits(x)) x].length;
        if (misfits(tXs) < misfits(laneXs)) {
          sideOf[i] = other;
          laneOf = tLane;
          laneXs = tXs;
        }
      }

      // Inner lanes first, so every outer branch is laid out knowing the ones inside it. Each corner starts from its
      // designed shape (lone ends leave nearly level; ends several branches share fan out: inner tipped in, outer
      // tipped out); only if that would touch the road, a placed branch or a stop are other angles and radii tried, and
      // the one with the most room is kept.
      final placed = List<RecoveryBranch?>.filled(count, null);
      final junctionsOf = List<List<(Offset, double)>>.filled(count, const []);
      final roadRuns = _visibleRuns(sampleXs, sampleYs, st);
      const clearance = nearHalfWidth * 2 + 8;
      final placing = [for (var i = 0; i < count; i++) i]..sort((x, y) => laneOf[x] != laneOf[y] ? laneOf[x] - laneOf[y] : x - y);
      for (final b in placing) {
        final (from, to, fromId, toId, state) = specs[b];
        final side = sideOf[b]!;
        final laneX = laneXs[b].clamp(edge, width - edge).toDouble();
        final topEnd = from.dy <= to.dy ? from : to;
        final bottomEnd = from.dy <= to.dy ? to : from;
        final span = bottomEnd.dy - topEnd.dy;
        // an outer lane turns in only past the ends of the chords it contains (a shared stop is fine: the fan parts them)
        var maxTop = span / 2;
        var maxBottom = span / 2;
        for (var o = 0; o < count; o++) {
          if (sideOf[o] != side || laneOf[o] >= laneOf[b]) continue;
          for (final e in [specs[o].$1, specs[o].$2]) {
            if (e == from || e == to || e.dy <= topEnd.dy || e.dy >= bottomEnd.dy) continue;
            if (e.dy - topEnd.dy <= bottomEnd.dy - e.dy) {
              maxTop = math.min(maxTop, e.dy - topEnd.dy - clearance);
            } else {
              maxBottom = math.min(maxBottom, bottomEnd.dy - e.dy - clearance);
            }
          }
        }
        double designedTilt(Offset e) {
          final sharing = [
            for (var o = 0; o < count; o++)
              if (sideOf[o] == side && (specs[o].$1 == e || specs[o].$2 == e)) o
          ]..sort((x, y) => laneOf[x].compareTo(laneOf[y]));
          if (sharing.length < 2) return 0.2;
          return 0.6 - 1.2 * sharing.indexOf(b) / (sharing.length - 1);
        }

        bool acrossRoad(Offset e) {
          final off = e.dx - routeX(e.dy);
          return off.abs() > 1 && off.sign != side;
        }

        final obstacles = <List<Offset>>[...roadRuns, for (final p in placed) if (p != null) p.points];
        final nodes = <Offset>[
          for (final st in route)
            if (st.center != from && st.center != to) st.center,
        ];
        List<Offset> bestCorner(Offset e, double cap, {required bool top}) {
          final lateral = (laneX - e.dx).abs();
          const minR = sampleStep * 2;
          double rFor(double scale) => (lateral * scale).clamp(minR, math.max(minR, cap)).toDouble();
          // a stop on the far side of the road from the lane: the branch crosses the road there, once, as a junction:
          // level and straight across, then the turn into its lane
          if (acrossRoad(e)) return _corner(e, laneX, rFor(1), 0, top: top);
          final designed = _corner(e, laneX, rFor(1), designedTilt(e), top: top);
          if (_slack(designed, e, obstacles, nodes) >= 0) return designed;
          var best = designed;
          var bestSlack = _slack(designed, e, obstacles, nodes);
          for (final scale in const [0.6, 0.8, 1.0, 1.3, 1.7]) {
            for (final t in const [-0.6, -0.3, 0.0, 0.3, 0.6, 0.9]) {
              final c = _corner(e, laneX, rFor(scale), t, top: top);
              final sl = _slack(c, e, obstacles, nodes);
              if (sl > bestSlack + 0.25) {
                best = c;
                bestSlack = sl;
              }
            }
          }
          return best;
        }

        final topCorner = bestCorner(topEnd, maxTop, top: true);
        final bottomCorner = bestCorner(bottomEnd, maxBottom, top: false);
        final pts = <Offset>[
          ...topCorner,
          for (var y = topCorner.last.dy + sampleStep; y < bottomCorner.first.dy; y += sampleStep) Offset(laneX, y),
          ...bottomCorner,
        ];
        final ordered = topEnd == from ? pts : pts.reversed.toList();
        ordered[0] = from;
        ordered[ordered.length - 1] = to;
        junctionsOf[b] = [
          for (final e in [topEnd, bottomEnd])
            if (acrossRoad(e)) (e, (laneX - e.dx).abs() + nodeRadius),
        ];
        placed[b] = RecoveryBranch(
            fromId: fromId, toId: toId, state: state, points: ordered, junctions: junctionsOf[b]);
      }
      final kept = <int>[];
      final allNodes = [for (final s in route) s.center];
      for (final b in placing) {
        final br = placed[b]!;
        final ends = [specs[b].$1, specs[b].$2];
        final others = [for (final o in kept) (placed[o]!.points, [specs[o].$1, specs[o].$2])];
        if (_branchClear(br.points, ends, roadRuns, allNodes, others, junctions: junctionsOf[b])) {
          kept.add(b);
        } else if (forwardTargetOf[b] != null) {
          dropped.add(forwardTargetOf[b]!);
        }
      }
      kept.sort();
      return [for (final b in kept) placed[b]!];
    }

    var forwardDrawn = Map<int, int>.of(forwardTo);
    late List<RouteSegmentState> states;
    late List<RecoveryBranch> branches;
    while (true) {
      states = statesFor(forwardDrawn);
      final dropped = <int>{};
      branches = buildBranches(forwardDrawn, states, dropped);
      if (dropped.isEmpty) break;
      forwardDrawn = {for (final e in forwardDrawn.entries) if (!dropped.contains(e.key)) e.key: e.value};
    }

    // Labels: placed like a map, AFTER the road and its branches are known, so text never sits on either.
    final polylines = <List<Offset>>[
      ..._visibleRuns(sampleXs, sampleYs, states),
      for (final b in branches) b.points,
    ];
    for (var i = 0; i < stops.length; i++) {
      final label = labelSlotFor(stops[i], polylines, width);
      stops[i] = stops[i].copyWith(
          label: label, companionFits: boxClear(companionBox(stops[i].center, labelOnLeft: label.onLeft), polylines, width));
    }
    final finishWithLabel = end?.copyWith(label: labelSlotFor(end, polylines, width));

    return DayRouteGeometry(
      width: width,
      height: height,
      stops: stops,
      finish: finishWithLabel,
      sampleYs: sampleYs,
      sampleXs: sampleXs,
      sampleStates: states,
      tailStart: sampleYs.length, // no faded tail: the road simply ends at the last point
      branches: branches,
    );
  }
}
