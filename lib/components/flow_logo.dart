import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';

/// Flowstate Fluid Focus Emblem
/// Minimal, calming focus rhythm logo matching the design direction.
class FlowLogo extends StatelessWidget {
  final double size;
  final bool showGlow;

  const FlowLogo({
    super.key,
    this.size = 80.0,
    this.showGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: const LinearGradient(
          colors: [FlowColors.cyan, FlowColors.mint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: FlowColors.cyan.withValues(alpha: 0.35),
                  blurRadius: size * 0.35,
                  spreadRadius: size * 0.05,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: FlowColors.mint.withValues(alpha: 0.2),
                  blurRadius: size * 0.45,
                  spreadRadius: size * 0.02,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.48, size * 0.48),
          painter: _FlowEmblemPainter(),
        ),
      ),
    );
  }
}

class _FlowEmblemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Fluid droplet / flow state wave curve
    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(w * 0.5, h * 0.08);
    path.cubicTo(w * 0.82, h * 0.45, w * 0.95, h * 0.68, w * 0.78, h * 0.88);
    path.cubicTo(w * 0.62, h * 1.02, w * 0.38, h * 1.02, w * 0.22, h * 0.88);
    path.cubicTo(w * 0.05, h * 0.68, w * 0.18, h * 0.45, w * 0.5, h * 0.08);
    path.close();

    canvas.drawPath(path, paint);

    // Subtle inner calm rhythm accent
    final innerPaint = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round;

    final arcPath = Path();
    arcPath.addArc(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.68),
        width: w * 0.38,
        height: h * 0.32,
      ),
      0.4,
      1.8,
    );
    canvas.drawPath(arcPath, innerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
