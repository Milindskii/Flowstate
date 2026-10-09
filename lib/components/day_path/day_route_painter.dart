import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'day_route_geometry.dart';

/// Colors the route is drawn with. The ROAD is green (traveled), blue (ahead) or orange (the way into a recovered
/// stop), all on the same line; yellow, red and grey colour the NODES of skipped / failed / missed stops.
class DayRoutePalette {
  final Color traveled;
  final Color ahead;
  final Color skipped;
  final Color recovery;
  final Color failed;
  final Color bed;
  final Color bedEdge;
  final Color fadeTo;

  /// A slot that ended unfinished: the route moved past it on its own (neutral, not a skip and not a failure).
  final Color bypassed;

  const DayRoutePalette({
    required this.traveled,
    required this.ahead,
    required this.skipped,
    required this.recovery,
    required this.failed,
    required this.bed,
    required this.bedEdge,
    required this.fadeTo,
    this.bypassed = const Color(0xFF94A3B8),
  });

  @override
  bool operator ==(Object other) =>
      other is DayRoutePalette &&
      other.traveled == traveled &&
      other.ahead == ahead &&
      other.skipped == skipped &&
      other.recovery == recovery &&
      other.failed == failed &&
      other.bed == bed &&
      other.bedEdge == bedEdge &&
      other.fadeTo == fadeTo &&
      other.bypassed == bypassed;

  @override
  int get hashCode => Object.hash(traveled, ahead, skipped, recovery, failed, bed, bedEdge, fadeTo, bypassed);
}

/// Draws exactly the geometry it is given: the road bed (a ribbon that narrows into the distance) and the colored
/// center line, one segment at a time in that segment's state (green walked, blue ahead, orange recovered). There is
/// only one line: states recolor it, they never add a second one. When [fromXs] is set the route is morphing: sample
/// x values are interpolated by [t].
class DayRoutePainter extends CustomPainter {
  final DayRouteGeometry geometry;
  final DayRoutePalette palette;
  final List<double>? fromXs;

  /// The previous segment states: stretches that just changed color draw in (the new color creeping down the road)
  /// instead of switching at once.
  final List<RouteSegmentState>? fromStates;
  final double t;

  DayRoutePainter({
    required this.geometry,
    required this.palette,
    this.fromXs,
    this.fromStates,
    this.t = 1,
  }) {
    final from = fromStates;
    if (from != null && from.length == geometry.sampleStates.length) {
      var first = -1;
      var last = -1;
      for (var i = 0; i < from.length; i++) {
        final now = geometry.sampleStates[i];
        if (now != from[i] && now != RouteSegmentState.ahead && now != RouteSegmentState.hidden) {
          if (first < 0) first = i;
          last = i;
        }
      }
      _revealFrom = first;
      _revealTo = last;
    }
  }

  int _revealFrom = -1;
  int _revealTo = -1;

  /// The state sample [i] shows right now (mid-reveal, a changed stretch still shows its old color).
  RouteSegmentState _stateAt(int i) {
    final now = geometry.sampleStates[i];
    final from = fromStates;
    if (from == null || _revealFrom < 0 || from.length != geometry.sampleStates.length) return now;
    if (from[i] == now || now == RouteSegmentState.ahead || now == RouteSegmentState.hidden) return now;
    return i < _revealFrom + (_revealTo - _revealFrom + 1) * t ? now : from[i];
  }

  Color _color(RouteSegmentState s) => switch (s) {
        RouteSegmentState.traveled => palette.traveled,
        RouteSegmentState.recovered => palette.recovery,
        RouteSegmentState.ahead => palette.ahead,
        RouteSegmentState.hidden => palette.ahead, // never drawn
      };

  double _x(int i) => fromXs == null ? geometry.sampleXs[i] : ui.lerpDouble(fromXs![i], geometry.sampleXs[i], t)!;

  @override
  void paint(Canvas canvas, Size size) {
    if (!geometry.hasRoute) return;
    final g = geometry;
    // Beds first (the road and every branch share one bed language), then the coloured lines on top, so a branch
    // that leaves the road blends into it instead of being drawn over it. A stretch the traveller did not walk (the
    // journey continues from a branch) is not drawn at all.
    for (final run in g.visibleRuns([for (var i = 0; i < g.sampleYs.length; i++) _x(i)])) {
      if (run.length >= 2) _paintBed(canvas, run);
    }
    for (final b in g.branches) {
      if (b.points.length >= 2) _paintBed(canvas, b.points);
    }
    _paintCenterLine(canvas);
    _paintBranches(canvas);
  }

  /// The way back to a recovered stop, from where the traveller really was to the stop. It is the SAME road: the same
  /// bed, shadow, edges, line width and round caps as the main route; only its colour (orange) says what it is.
  void _paintBranches(Canvas canvas) {
    for (final b in geometry.branches) {
      if (b.points.length < 2) continue;
      final path = Path()..moveTo(b.points.first.dx, b.points.first.dy);
      for (final p in b.points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = centerLineWidth
          ..color = _color(b.state),
      );
    }
  }

  /// Width of the coloured line on every stretch of road (main route and branches alike).
  static const double centerLineWidth = DayRouteGeometry.nearHalfWidth * 0.9;

  void _paintBed(Canvas canvas, List<Offset> pts) {
    final g = geometry;
    final n = pts.length;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i < n; i++) {
      final a = pts[math.max(0, i - 1)];
      final b = pts[math.min(n - 1, i + 1)];
      final tangent = (b - a);
      final len = tangent.distance == 0 ? 1.0 : tangent.distance;
      final normal = Offset(-tangent.dy / len, tangent.dx / len);
      final c = pts[i];
      final hw = g.halfWidthAt(c.dy);
      left.add(c + normal * hw);
      right.add(c - normal * hw);
    }
    final ribbon = Path()..moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      ribbon.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      ribbon.lineTo(p.dx, p.dy);
    }
    ribbon.close();

    // depth: a soft offset shadow under the bed, then the bed itself and its two edges
    canvas.drawPath(ribbon.shift(const Offset(0, 2.5)), Paint()..color = const Color(0x14000000));
    canvas.drawPath(ribbon, Paint()..color = palette.bed);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = palette.bedEdge;
    for (final side in [left, right]) {
      final p = Path()..moveTo(side.first.dx, side.first.dy);
      for (final o in side.skip(1)) {
        p.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(p, edge);
    }
  }

  void _paintCenterLine(Canvas canvas) {
    final g = geometry;
    final n = g.sampleYs.length;
    for (var i = 0; i + 1 < n; i++) {
      // the stretch from sample i to i + 1 is the one that ARRIVES at i + 1: it takes that sample's state
      if (g.sampleStates[i + 1] == RouteSegmentState.hidden) continue;
      canvas.drawLine(
        Offset(_x(i), g.sampleYs[i]),
        Offset(_x(i + 1), g.sampleYs[i + 1]),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = centerLineWidth
          ..color = _color(_stateAt(i + 1)),
      );
    }
  }

  @override
  bool shouldRepaint(DayRoutePainter old) =>
      !identical(old.geometry, geometry) ||
      old.palette != palette ||
      old.t != t ||
      old.fromXs != fromXs ||
      old.fromStates != fromStates;
}
