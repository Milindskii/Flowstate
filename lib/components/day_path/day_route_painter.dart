import 'dart:math' as math;

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

/// Draws exactly the geometry it is given: the road bed (a ribbon that narrows into the distance), the colored
/// center line, one segment at a time in that segment's state (green walked, blue ahead, orange the way back from a
/// recovered stop), and the orange return paths that loop back to recovering / recovered stops. While the route
/// morphs, the caller hands in the interpolated geometry; the painter itself holds no animation state.
class DayRoutePainter extends CustomPainter {
  final DayRouteGeometry geometry;
  final DayRoutePalette palette;

  DayRoutePainter({required this.geometry, required this.palette});

  Color _color(RouteSegmentState s) => switch (s) {
        RouteSegmentState.traveled => palette.traveled,
        RouteSegmentState.recovered => palette.recovery,
        RouteSegmentState.ahead => palette.ahead,
      };

  double _x(int i) => geometry.sampleXs[i];

  @override
  void paint(Canvas canvas, Size size) {
    if (!geometry.hasRoute) return;
    _paintBed(canvas);
    _paintCenterLine(canvas);
    _paintDetours(canvas);
  }

  void _paintBed(Canvas canvas) {
    final g = geometry;
    final n = g.sampleYs.length;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i < n; i++) {
      final a = Offset(_x(math.max(0, i - 1)), g.sampleYs[math.max(0, i - 1)]);
      final b = Offset(_x(math.min(n - 1, i + 1)), g.sampleYs[math.min(n - 1, i + 1)]);
      final tangent = (b - a);
      final len = tangent.distance == 0 ? 1.0 : tangent.distance;
      final normal = Offset(-tangent.dy / len, tangent.dx / len);
      final c = Offset(_x(i), g.sampleYs[i]);
      final hw = g.halfWidthAt(g.sampleYs[i]);
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
      canvas.drawLine(
        Offset(_x(i), g.sampleYs[i]),
        Offset(_x(i + 1), g.sampleYs[i + 1]),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = g.halfWidthAt(g.sampleYs[i]) * 0.9
          ..color = _color(g.sampleStates[i + 1]),
      );
    }
  }

  /// The orange way back to a skipped stop: drawn over the road bed's own width so it reads as a path, not a doodle.
  void _paintDetours(Canvas canvas) {
    for (final d in geometry.detours) {
      final count = (d.points.length * d.reveal.clamp(0.0, 1.0)).ceil();
      if (count < 2) continue;
      final path = Path()..moveTo(d.points.first.dx, d.points.first.dy);
      for (var i = 1; i < count; i++) {
        path.lineTo(d.points[i].dx, d.points[i].dy);
      }
      final width = geometry.halfWidthAt(d.points.first.dy) * 0.9;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width + 5
          ..color = palette.bed,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width
          ..color = palette.recovery,
      );
    }
  }

  @override
  bool shouldRepaint(DayRoutePainter old) => !identical(old.geometry, geometry) || old.palette != palette;
}
