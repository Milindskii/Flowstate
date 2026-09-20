import 'package:flutter/material.dart';
import '../models/readiness_model.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_typography.dart';

/// Smooth Custom Painter for Circadian Energy Rhythm Curve
/// Renders an organic, non-medical wave of energy peaks and recovery dips.
class EnergyCurvePainter extends CustomPainter {
  final List<EnergyPoint> points;
  final bool animatePeak;

  EnergyCurvePainter({
    required this.points,
    this.animatePeak = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final double width = size.width;
    final double graphHeight = size.height - 24.0; // Reserve bottom 24px for time labels

    final double stepX = width / (points.length - 1);

    // Compute pixel coordinates
    final List<Offset> offsets = [];
    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      // Invert Y because canvas (0,0) is top-left
      final y = graphHeight - (points[i].level * (graphHeight * 0.85)) - 4.0;
      offsets.add(Offset(x, y));
    }

    // Build smooth cubic Bezier path
    final Path curvePath = Path();
    curvePath.moveTo(offsets.first.dx, offsets.first.dy);

    for (int i = 0; i < offsets.length - 1; i++) {
      final p0 = offsets[i];
      final p1 = offsets[i + 1];
      final controlPoint1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final controlPoint2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      curvePath.cubicTo(
        controlPoint1.dx,
        controlPoint1.dy,
        controlPoint2.dx,
        controlPoint2.dy,
        p1.dx,
        p1.dy,
      );
    }

    // Fill path under the curve with cyan/mint gradient
    final Path fillPath = Path.from(curvePath);
    fillPath.lineTo(width, graphHeight);
    fillPath.lineTo(0, graphHeight);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          FlowColors.cyan.withValues(alpha: 0.32),
          FlowColors.mint.withValues(alpha: 0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, width, graphHeight))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Stroke line
    final strokePaint = Paint()
      ..shader = const LinearGradient(
        colors: [FlowColors.cyanLight, FlowColors.mintLight],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(0, 0, width, graphHeight))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(curvePath, strokePaint);

    // Peak focus glowing indicator (at 10am point, index 2)
    if (offsets.length > 2) {
      final peak = offsets[2];

      final glowPaint = Paint()
        ..color = FlowColors.cyan.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(peak, 8, glowPaint);

      final outerDot = Paint()..color = FlowColors.cyanLight;
      canvas.drawCircle(peak, 4.5, outerDot);

      final innerDot = Paint()..color = Colors.white;
      canvas.drawCircle(peak, 2.0, innerDot);
    }

    // Draw baseline
    final linePaint = Paint()
      ..color = FlowColors.darkBorder.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, graphHeight), Offset(width, graphHeight), linePaint);

    // Draw time labels (6a, 8a, 10a, 12p, 2p, 4p, 6p)
    final textStyle = FlowTypography.labelSmall(color: FlowColors.textMuted);

    for (int i = 0; i < points.length; i++) {
      final textSpan = TextSpan(text: points[i].label, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      double labelX = offsets[i].dx - (textPainter.width / 2);
      if (i == 0) labelX = 0;
      if (i == points.length - 1) labelX = width - textPainter.width;

      textPainter.paint(canvas, Offset(labelX, graphHeight + 6.0));
    }
  }

  @override
  bool shouldRepaint(covariant EnergyCurvePainter oldDelegate) => true;
}
