import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'day_route_geometry.dart';

/// Colors the route is drawn with. Green = traveled, blue = the road ahead, yellow = skipped/deferred,
/// orange = recovery detour, red = true failure only.
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
/// center line (solid where walked, dashed where ahead), the orange recovery detours and the short spurs to
/// bypassed stops. When [fromXs] is set the route is morphing: sample x values are interpolated by [t].
class DayRoutePainter extends CustomPainter {
  final DayRouteGeometry geometry;
  final DayRoutePalette palette;
  final List<double>? fromXs;

  /// The previous traveled flags: stretches that just became traveled draw in (green creeping up the road)
  /// instead of switching color at once.
  final List<bool>? fromTraveled;
  final double t;
  final double extrasOpacity;

  DayRoutePainter({
    required this.geometry,
    required this.palette,
    this.fromXs,
    this.fromTraveled,
    this.t = 1,
    this.extrasOpacity = 1,
  }) {
    final from = fromTraveled;
    if (from != null && from.length == geometry.sampleTraveled.length) {
      var first = -1;
      var last = -1;
      for (var i = 0; i < from.length; i++) {
        if (geometry.sampleTraveled[i] && !from[i]) {
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

  bool _isTraveled(int i) {
    if (!geometry.sampleTraveled[i]) return false;
    if (fromTraveled == null || _revealFrom < 0 || fromTraveled![i]) return true;
    return i < _revealFrom + (_revealTo - _revealFrom + 1) * t;
  }

  double _x(int i) => fromXs == null ? geometry.sampleXs[i] : ui.lerpDouble(fromXs![i], geometry.sampleXs[i], t)!;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    if (g.hasRoute) {
      _paintBed(canvas);
      _paintCenterLine(canvas);
    }
    if (extrasOpacity > 0) {
      for (final d in g.detours) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 4
          ..color = palette.recovery.withValues(alpha: extrasOpacity);
        final path = Path()..moveTo(d.points.first.dx, d.points.first.dy);
        for (final p in d.points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
      for (final s in g.spurs) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3
          ..color = (switch (s.role) {
            StopRouteRole.failed => palette.failed,
            StopRouteRole.bypassed => palette.bypassed,
            _ => palette.skipped,
          })
              .withValues(alpha: extrasOpacity);
        _dashedLine(canvas, s.from, s.to, paint, 12, 8);
      }
    }
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
    final tailLen = math.max(1, n - g.tailStart);
    for (var i = 0; i + 1 < n; i++) {
      final a = Offset(_x(i), g.sampleYs[i]);
      final b = Offset(_x(i + 1), g.sampleYs[i + 1]);
      final isTraveled = _isTraveled(i);
      var color = isTraveled ? palette.traveled : palette.ahead;
      if (i >= g.tailStart) {
        final f = ((i - g.tailStart) / tailLen).clamp(0.0, 1.0);
        color = Color.lerp(color, palette.fadeTo, 0.25 + 0.75 * f)!;
      }
      canvas.drawLine(
        a,
        b,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = g.halfWidthAt(g.sampleYs[i]) * 0.9
          ..color = color,
      );
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint, double dash, double gap) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(DayRoutePainter old) =>
      !identical(old.geometry, geometry) ||
      old.palette != palette ||
      old.t != t ||
      old.fromXs != fromXs ||
      old.fromTraveled != fromTraveled ||
      old.extrasOpacity != extrasOpacity;
}
