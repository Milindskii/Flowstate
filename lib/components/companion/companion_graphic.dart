import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/flow_colors.dart';
import 'flow_companion_animation_controller.dart';

/// High-fidelity custom vector graphic for Flowstate animal companions.
/// Ensures 100% reliable, razor-sharp rendering on all platforms (Web, Windows, iOS, Android)
/// with ZERO missing emoji glyphs, tofu symbols, or font dependencies.
class CompanionGraphic extends StatelessWidget {
  final String species;
  final double size;
  final CompanionAnimState state;
  final bool animate;

  const CompanionGraphic({
    super.key,
    required this.species,
    this.size = 40.0,
    this.state = CompanionAnimState.idle,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final normSpecies = species.toLowerCase().trim();

    String assetPath;
    if (normSpecies == 'fox' || normSpecies.isEmpty || normSpecies == 'nova' || normSpecies == 'noya') {
      switch (state) {
        case CompanionAnimState.focusing:
          // User requested old design style: fox is sleeping peacefully while you focus
          assetPath = 'assets/images/companions/noya_sleeping.png';
          break;
        case CompanionAnimState.success:
          // Noya celebrating with paws up, gold sparkles
          assetPath = 'assets/images/companions/noya_success.png';
          break;
        case CompanionAnimState.tired:
          // Noya sleeping peacefully with ZZZs
          assetPath = 'assets/images/companions/noya_sleeping.png';
          break;
        case CompanionAnimState.evolution:
          // Noya celebrating — reuse success art for now
          assetPath = 'assets/images/companions/noya_success.png';
          break;
        case CompanionAnimState.starting:
          // Noya alert and ready — use the winking idle art
          assetPath = 'assets/images/companions/noya.png';
          break;
        case CompanionAnimState.idle:
        default:
          // Noya sleeping when idle ("waiting for you to start")
          assetPath = 'assets/images/companions/noya_sleeping.png';
          break;
      }
    } else if (normSpecies == 'otter' || normSpecies == 'ludo' || normSpecies == 'bear' || normSpecies == 'bruno') {
      assetPath = 'assets/images/companions/otter.png';
    } else if (normSpecies == 'owl' || normSpecies == 'aria') {
      assetPath = 'assets/images/companions/owl.png';
    } else if (normSpecies == 'capybara' || normSpecies == 'boba') {
      assetPath = 'assets/images/companions/capybara.png';
    } else if (normSpecies == 'cat' || normSpecies == 'mochi') {
      assetPath = 'assets/images/companions/cat.png';
    } else {
      assetPath = 'assets/images/companions/fox.png';
    }

    Widget fallbackPainter = CustomPaint(
      size: Size(size, size),
      painter: _CompanionVectorPainter(
        species: normSpecies,
        state: state,
        isDark: FlowColors.isDark(context),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallbackPainter,
      ),
    );
  }
}

class _CompanionVectorPainter extends CustomPainter {
  final String species;
  final CompanionAnimState state;
  final bool isDark;

  const _CompanionVectorPainter({
    required this.species,
    required this.state,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Scale everything to a normalized 100x100 coordinate canvas
    final scale = size.width / 100.0;
    canvas.scale(scale, scale);

    switch (species) {
      case 'otter':
        _paintOtter(canvas);
        break;
      case 'owl':
        _paintOwl(canvas);
        break;
      case 'capybara':
        _paintCapybara(canvas);
        break;
      case 'fox':
      default:
        _paintFox(canvas);
        break;
    }

    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // 1. NOVA THE FOX (Swift Sprinter - Orange / Amber / White)
  // ---------------------------------------------------------------------------
  void _paintFox(Canvas canvas) {
    const whiteCream = Color(0xFFFFFBEB);
    const earInner = Color(0xFFFDA4AF);
    const darkNose = Color(0xFF1E293B);

    // Left Ear
    final leftEarPath = Path()
      ..moveTo(22, 48)
      ..lineTo(14, 14)
      ..lineTo(44, 32)
      ..close();
    final earPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFEA580C), Color(0xFFF97316)],
      ).createShader(const Rect.fromLTWH(14, 14, 30, 34));
    canvas.drawPath(leftEarPath, earPaint);

    // Left Ear Tip (Dark)
    final leftEarTip = Path()
      ..moveTo(14, 14)
      ..lineTo(21, 23)
      ..lineTo(16, 26)
      ..close();
    canvas.drawPath(leftEarTip, Paint()..color = const Color(0xFF9A3412));

    // Left Inner Ear
    final leftInnerEar = Path()
      ..moveTo(23, 42)
      ..lineTo(19, 23)
      ..lineTo(37, 34)
      ..close();
    canvas.drawPath(leftInnerEar, Paint()..color = earInner);

    // Right Ear
    final rightEarPath = Path()
      ..moveTo(78, 48)
      ..lineTo(86, 14)
      ..lineTo(56, 32)
      ..close();
    final rightEarPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFEA580C), Color(0xFFF97316)],
      ).createShader(const Rect.fromLTWH(56, 14, 30, 34));
    canvas.drawPath(rightEarPath, rightEarPaint);

    // Right Ear Tip (Dark)
    final rightEarTip = Path()
      ..moveTo(86, 14)
      ..lineTo(79, 23)
      ..lineTo(84, 26)
      ..close();
    canvas.drawPath(rightEarTip, Paint()..color = const Color(0xFF9A3412));

    // Right Inner Ear
    final rightInnerEar = Path()
      ..moveTo(77, 42)
      ..lineTo(81, 23)
      ..lineTo(63, 34)
      ..close();
    canvas.drawPath(rightInnerEar, Paint()..color = earInner);

    // Head base (Circle with cute fox cheek fluffs)
    final headPath = Path()
      ..moveTo(50, 24)
      ..cubicTo(70, 24, 84, 38, 86, 52)
      ..cubicTo(93, 62, 88, 72, 78, 76)
      ..cubicTo(66, 88, 56, 92, 50, 92)
      ..cubicTo(44, 92, 34, 88, 22, 76)
      ..cubicTo(12, 72, 7, 62, 14, 52)
      ..cubicTo(16, 38, 30, 24, 50, 24)
      ..close();

    final headGradient = const RadialGradient(
      center: Alignment(0.0, -0.2),
      radius: 0.8,
      colors: [Color(0xFFFB923C), Color(0xFFF97316), Color(0xFFEA580C)],
      stops: [0.0, 0.6, 1.0],
    ).createShader(const Rect.fromLTWH(10, 20, 80, 72));

    canvas.drawPath(headPath, Paint()..shader = headGradient);

    // White cheek fluffs & lower snout
    final muzzlePath = Path()
      ..moveTo(50, 56)
      ..cubicTo(38, 54, 20, 60, 18, 72)
      ..cubicTo(26, 82, 38, 90, 50, 91)
      ..cubicTo(62, 90, 74, 82, 82, 72)
      ..cubicTo(80, 60, 62, 54, 50, 56)
      ..close();

    canvas.drawPath(muzzlePath, Paint()..color = whiteCream);

    // Forehead blaze / diamond
    final blazePath = Path()
      ..moveTo(50, 32)
      ..lineTo(54, 46)
      ..lineTo(50, 54)
      ..lineTo(46, 46)
      ..close();
    canvas.drawPath(blazePath, Paint()..color = whiteCream.withValues(alpha: 0.85));

    // Eyes (Adapt to state)
    if (state == CompanionAnimState.tired) {
      // Content closed / sleepy curved lines
      final eyePaint = Paint()
        ..color = darkNose
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(const Rect.fromLTWH(30, 48, 12, 10), math.pi, math.pi, false, eyePaint);
      canvas.drawArc(const Rect.fromLTWH(58, 48, 12, 10), math.pi, math.pi, false, eyePaint);
    } else if (state == CompanionAnimState.focusing) {
      // Determined focus eyes with cyan shine
      final eyePaint = Paint()..color = darkNose;
      canvas.drawOval(const Rect.fromLTWH(31, 46, 11, 13), eyePaint);
      canvas.drawOval(const Rect.fromLTWH(58, 46, 11, 13), eyePaint);

      // Cyan focus catchlight
      final shinePaint = Paint()..color = const Color(0xFF22D3EE);
      canvas.drawCircle(const Offset(34, 49), 2.8, shinePaint);
      canvas.drawCircle(const Offset(61, 49), 2.8, shinePaint);
    } else {
      // Normal happy alert eyes
      final eyePaint = Paint()..color = darkNose;
      canvas.drawOval(const Rect.fromLTWH(31, 47, 10, 13), eyePaint);
      canvas.drawOval(const Rect.fromLTWH(59, 47, 10, 13), eyePaint);

      // White catchlight
      final shinePaint = Paint()..color = Colors.white;
      canvas.drawCircle(const Offset(34, 50), 3.0, shinePaint);
      canvas.drawCircle(const Offset(62, 50), 3.0, shinePaint);
      canvas.drawCircle(const Offset(36, 54), 1.4, shinePaint);
      canvas.drawCircle(const Offset(64, 54), 1.4, shinePaint);
    }

    // Cute Black Fox Nose
    final nosePath = Path()
      ..moveTo(46, 73)
      ..cubicTo(47, 71, 53, 71, 54, 73)
      ..lineTo(51, 78)
      ..cubicTo(50.5, 79, 49.5, 79, 49, 78)
      ..close();
    canvas.drawPath(nosePath, Paint()..color = darkNose);

    // Nose Highlight
    canvas.drawCircle(const Offset(49, 73.5), 1.2, Paint()..color = Colors.white70);

    // Gentle Smile
    final mouthPaint = Paint()
      ..color = darkNose.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final mouthPath = Path()
      ..moveTo(44, 82)
      ..quadraticBezierTo(47, 85, 50, 81)
      ..quadraticBezierTo(53, 85, 56, 82);
    canvas.drawPath(mouthPath, mouthPaint);
  }

  // ---------------------------------------------------------------------------
  // 2. LUDO THE OTTER (Flow Navigator - Cyan / Teal / Marine)
  // ---------------------------------------------------------------------------
  void _paintOtter(Canvas canvas) {
    const darkCoat = Color(0xFF0891B2);
    const lightMuzzle = Color(0xFFECFEFF);
    const darkNose = Color(0xFF0F172A);

    // Left round ear
    canvas.drawCircle(const Offset(22, 34), 10, Paint()..color = darkCoat);
    canvas.drawCircle(const Offset(23, 34), 6, Paint()..color = const Color(0xFFA5F3FC));

    // Right round ear
    canvas.drawCircle(const Offset(78, 34), 10, Paint()..color = darkCoat);
    canvas.drawCircle(const Offset(77, 34), 6, Paint()..color = const Color(0xFFA5F3FC));

    // Head base (Round & sleek)
    final headPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(18, 26, 64, 64),
        const Radius.circular(32),
      ));
    canvas.drawPath(
      headPath,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.0, -0.3),
          radius: 0.8,
          colors: [Color(0xFF22D3EE), Color(0xFF06B6D4), Color(0xFF0891B2)],
        ).createShader(const Rect.fromLTWH(18, 26, 64, 64)),
    );

    // Soft lighter muzzle
    final muzzleRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(28, 52, 44, 32),
      const Radius.circular(20),
    );
    canvas.drawRRect(muzzleRRect, Paint()..color = lightMuzzle);

    // Eyes
    canvas.drawOval(const Rect.fromLTWH(32, 44, 9, 11), Paint()..color = darkNose);
    canvas.drawOval(const Rect.fromLTWH(59, 44, 9, 11), Paint()..color = darkNose);
    canvas.drawCircle(const Offset(34, 46), 2.5, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(61, 46), 2.5, Paint()..color = Colors.white);

    // Rounded Wide Otter Nose
    final noseRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(44, 58, 12, 8),
      const Radius.circular(4),
    );
    canvas.drawRRect(noseRRect, Paint()..color = darkNose);

    // Whiskers dots
    canvas.drawCircle(const Offset(36, 68), 1.5, Paint()..color = darkCoat);
    canvas.drawCircle(const Offset(40, 71), 1.5, Paint()..color = darkCoat);
    canvas.drawCircle(const Offset(64, 68), 1.5, Paint()..color = darkCoat);
    canvas.drawCircle(const Offset(60, 71), 1.5, Paint()..color = darkCoat);

    // Cute mouth
    final mouthPaint = Paint()
      ..color = darkNose
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final mouth = Path()
      ..moveTo(45, 73)
      ..quadraticBezierTo(50, 77, 55, 73);
    canvas.drawPath(mouth, mouthPaint);
  }

  // ---------------------------------------------------------------------------
  // 3. ARIA THE OWL (Deep Scholar - Violet / Purple / Gold)
  // ---------------------------------------------------------------------------
  void _paintOwl(Canvas canvas) {
    const darkCoat = Color(0xFF7C3AED);
    const lightColor = Color(0xFFF5F3FF);
    const goldColor = Color(0xFFFBBF24);
    const darkEye = Color(0xFF1E1B4B);

    // Feather tufts / horns
    final leftTuft = Path()
      ..moveTo(26, 38)
      ..lineTo(18, 16)
      ..lineTo(38, 28)
      ..close();
    canvas.drawPath(leftTuft, Paint()..color = darkCoat);

    final rightTuft = Path()
      ..moveTo(74, 38)
      ..lineTo(82, 16)
      ..lineTo(62, 28)
      ..close();
    canvas.drawPath(rightTuft, Paint()..color = darkCoat);

    // Body/Head base
    final bodyRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(20, 24, 60, 68),
      const Radius.circular(30),
    );
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6), Color(0xFF6D28D9)],
        ).createShader(const Rect.fromLTWH(20, 24, 60, 68)),
    );

    // Owl Face Mask / Eye rings
    canvas.drawCircle(const Offset(37, 48), 16, Paint()..color = lightColor);
    canvas.drawCircle(const Offset(63, 48), 16, Paint()..color = lightColor);

    // Large Wise Eyes (Gold Iris + Dark Pupil)
    canvas.drawCircle(const Offset(37, 48), 11, Paint()..color = goldColor);
    canvas.drawCircle(const Offset(63, 48), 11, Paint()..color = goldColor);
    canvas.drawCircle(const Offset(37, 48), 7, Paint()..color = darkEye);
    canvas.drawCircle(const Offset(63, 48), 7, Paint()..color = darkEye);

    // Catchlight
    canvas.drawCircle(const Offset(35, 45), 2.5, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(61, 45), 2.5, Paint()..color = Colors.white);

    // Sharp little beak
    final beak = Path()
      ..moveTo(47, 54)
      ..lineTo(53, 54)
      ..lineTo(50, 66)
      ..close();
    canvas.drawPath(beak, Paint()..color = const Color(0xFFD97706));

    // Belly feathers (3 chevrons)
    final featherPaint = Paint()
      ..color = lightColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(const Rect.fromLTWH(42, 72, 16, 6), 0, math.pi, false, featherPaint);
    canvas.drawArc(const Rect.fromLTWH(42, 80, 16, 6), 0, math.pi, false, featherPaint);
  }

  // ---------------------------------------------------------------------------
  // 4. BOBA THE CAPYBARA (Zen Anchor - Emerald / Sage / Warm Ochre)
  // ---------------------------------------------------------------------------
  void _paintCapybara(Canvas canvas) {
    const darkCoat = Color(0xFF059669);
    const lightMuzzle = Color(0xFFD1FAE5);
    const darkNose = Color(0xFF064E3B);

    // Small rounded ears
    canvas.drawCircle(const Offset(22, 34), 8, Paint()..color = darkCoat);
    canvas.drawCircle(const Offset(78, 34), 8, Paint()..color = darkCoat);

    // Signature Zen Blocky / Rounded Capybara Head
    final headRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(20, 26, 60, 66),
      const Radius.circular(22),
    );
    canvas.drawRRect(
      headRRect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.0, -0.2),
          colors: [Color(0xFF34D399), Color(0xFF10B981), Color(0xFF059669)],
        ).createShader(const Rect.fromLTWH(20, 26, 60, 66)),
    );

    // Lower broad snout
    final snoutRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(26, 52, 48, 36),
      const Radius.circular(16),
    );
    canvas.drawRRect(snoutRRect, Paint()..color = lightMuzzle);

    // Zen Peaceful Curved Eyes (Never stressed)
    final eyePaint = Paint()
      ..color = darkNose
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(const Rect.fromLTWH(30, 46, 12, 8), math.pi, math.pi, false, eyePaint);
    canvas.drawArc(const Rect.fromLTWH(58, 46, 12, 8), math.pi, math.pi, false, eyePaint);

    // Characteristic Capybara Wide Nostrils
    canvas.drawOval(const Rect.fromLTWH(42, 64, 6, 9), Paint()..color = darkNose);
    canvas.drawOval(const Rect.fromLTWH(52, 64, 6, 9), Paint()..color = darkNose);

    // Little sprout/leaf on head (Zen vibe)
    final leafPath = Path()
      ..moveTo(50, 26)
      ..quadraticBezierTo(56, 16, 62, 18)
      ..quadraticBezierTo(54, 22, 50, 26);
    canvas.drawPath(leafPath, Paint()..color = const Color(0xFF86EFAC));
  }

  @override
  bool shouldRepaint(covariant _CompanionVectorPainter oldDelegate) {
    return oldDelegate.species != species ||
        oldDelegate.state != state ||
        oldDelegate.isDark != isDark;
  }
}
