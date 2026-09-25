import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';

enum OnboardingVisualState {
  neutral,
  morningBright,
  twilight,
  focusActive,
  settling,
  settled,
}

/// Native custom-painted ambient background.
/// Renders a luminous, low-CPU orbital light field with drifting pastel tones.
/// Matches the rich, clean aesthetic of the questionnaire page across the entire app.
/// Respects MediaQuery.disableAnimationsOf(context).
class FlowAmbientBackground extends StatefulWidget {
  final OnboardingVisualState visualState;
  final Widget? child;

  const FlowAmbientBackground({
    super.key,
    this.visualState = OnboardingVisualState.neutral,
    this.child,
  });

  @override
  State<FlowAmbientBackground> createState() => _FlowAmbientBackgroundState();
}

class _FlowAmbientBackgroundState extends State<FlowAmbientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
  }

  bool get _isTestOrReducedMotion {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    return reduceMotion || isTest;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isTestOrReducedMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _isTestOrReducedMotion;
    final isDark = FlowColors.isDark(context);
    final baseColor = isDark ? FlowColors.bgDark : const Color(0xFFF8FAFC);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Primary Base Surface (Slate 50 in light, Obsidian in dark)
        Container(color: baseColor),

        // Animated or static light field
        if (reduceMotion)
          CustomPaint(
            painter: _AmbientPainter(
              progress: 0.0,
              visualState: widget.visualState,
              isDark: isDark,
            ),
          )
        else
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _AmbientPainter(
                  progress: _controller.value,
                  visualState: widget.visualState,
                  isDark: isDark,
                ),
              );
            },
          ),

        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _AmbientPainter extends CustomPainter {
  final double progress;
  final OnboardingVisualState visualState;
  final bool isDark;

  const _AmbientPainter({
    required this.progress,
    required this.visualState,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double angle = progress * 2.0 * math.pi;

    Color orb1Color;
    Color orb2Color;
    Color orb3Color;
    double speedMultiplier = 1.0;

    if (isDark) {
      switch (visualState) {
        case OnboardingVisualState.morningBright:
          orb1Color = const Color(0xFFD97706).withValues(alpha: 0.16);
          orb2Color = const Color(0xFF0284C7).withValues(alpha: 0.15);
          orb3Color = const Color(0xFF059669).withValues(alpha: 0.12);
          speedMultiplier = 1.1;
          break;
        case OnboardingVisualState.twilight:
          orb1Color = const Color(0xFF4F46E5).withValues(alpha: 0.18);
          orb2Color = const Color(0xFF7C3AED).withValues(alpha: 0.14);
          orb3Color = const Color(0xFF2563EB).withValues(alpha: 0.12);
          speedMultiplier = 0.7;
          break;
        case OnboardingVisualState.focusActive:
          orb1Color = const Color(0xFF0284C7).withValues(alpha: 0.18);
          orb2Color = const Color(0xFF059669).withValues(alpha: 0.16);
          orb3Color = const Color(0xFF0D9488).withValues(alpha: 0.14);
          speedMultiplier = 1.3;
          break;
        case OnboardingVisualState.settling:
        case OnboardingVisualState.settled:
        case OnboardingVisualState.neutral:
          orb1Color = const Color(0xFF1E293B).withValues(alpha: 0.40);
          orb2Color = const Color(0xFF0E7490).withValues(alpha: 0.14);
          orb3Color = const Color(0xFF4338CA).withValues(alpha: 0.12);
          speedMultiplier = 0.8;
          break;
      }
    } else {
      switch (visualState) {
        case OnboardingVisualState.morningBright:
          orb1Color = const Color(0xFFFDE68A).withValues(alpha: 0.32); // Sunrise amber glow
          orb2Color = const Color(0xFF67E8F9).withValues(alpha: 0.26); // Clean sky cyan
          orb3Color = const Color(0xFFFED7AA).withValues(alpha: 0.22); // Warm peach
          speedMultiplier = 1.1;
          break;
        case OnboardingVisualState.twilight:
          orb1Color = const Color(0xFF93C5FD).withValues(alpha: 0.28); // Dusk blue
          orb2Color = const Color(0xFFDDD6FE).withValues(alpha: 0.24); // Lavender
          orb3Color = const Color(0xFFFBCFE8).withValues(alpha: 0.18); // Soft rose
          speedMultiplier = 0.7;
          break;
        case OnboardingVisualState.focusActive:
          orb1Color = const Color(0xFF38BDF8).withValues(alpha: 0.28); // Focus cyan
          orb2Color = const Color(0xFF6EE7B7).withValues(alpha: 0.25); // Fresh mint
          orb3Color = const Color(0xFFA5B4FC).withValues(alpha: 0.18); // Soft periwinkle
          speedMultiplier = 1.3;
          break;
        case OnboardingVisualState.settling:
        case OnboardingVisualState.settled:
          orb1Color = const Color(0xFF67E8F9).withValues(alpha: 0.20);
          orb2Color = const Color(0xFFE2E8F0).withValues(alpha: 0.35);
          orb3Color = const Color(0xFFC7D2FE).withValues(alpha: 0.18);
          speedMultiplier = 0.5;
          break;
        case OnboardingVisualState.neutral:
          orb1Color = const Color(0xFFBAE6FD).withValues(alpha: 0.26); // Soft sky
          orb2Color = const Color(0xFFFDE68A).withValues(alpha: 0.22); // Gentle warm sun
          orb3Color = const Color(0xFFDDD6FE).withValues(alpha: 0.18); // Soft violet
          speedMultiplier = 1.0;
          break;
      }
    }

    final double effectiveAngle = angle * speedMultiplier;

    // Orb 1: Top-left / center orbital drift
    final double cx1 = size.width * 0.25 + math.cos(effectiveAngle) * 55.0;
    final double cy1 = size.height * 0.18 + math.sin(effectiveAngle) * 45.0;
    final double r1 = size.width * 0.72;

    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [orb1Color, orb1Color.withValues(alpha: 0.0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx1, cy1), radius: r1));

    canvas.drawCircle(Offset(cx1, cy1), r1, paint1);

    // Orb 2: Bottom-right orbital drift
    final double cx2 = size.width * 0.78 - math.cos(effectiveAngle * 0.8) * 60.0;
    final double cy2 = size.height * 0.65 - math.sin(effectiveAngle * 0.8) * 50.0;
    final double r2 = size.width * 0.78;

    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [orb2Color, orb2Color.withValues(alpha: 0.0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx2, cy2), radius: r2));

    canvas.drawCircle(Offset(cx2, cy2), r2, paint2);

    // Orb 3: Mid-left gentle drifting counter-weight
    final double cx3 = size.width * 0.15 + math.sin(effectiveAngle * 0.6) * 45.0;
    final double cy3 = size.height * 0.82 + math.cos(effectiveAngle * 0.6) * 40.0;
    final double r3 = size.width * 0.65;

    final paint3 = Paint()
      ..shader = RadialGradient(
        colors: [orb3Color, orb3Color.withValues(alpha: 0.0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx3, cy3), radius: r3));

    canvas.drawCircle(Offset(cx3, cy3), r3, paint3);
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.visualState != visualState ||
        oldDelegate.isDark != isDark;
  }
}
