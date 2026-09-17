import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'flow_colors.dart';

/// Flowstate Typography Hierarchy using Manrope
/// Optimized for mobile legibility: min 16px body, comfortable line-heights,
/// calm, intelligent, friendly and non-corporate.
class FlowTypography {
  FlowTypography._();

  static TextStyle displayLarge({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.manrope(
        fontSize: 32.0,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.5,
        height: 1.25,
      );

  static TextStyle displayMedium({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.manrope(
        fontSize: 26.0,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.4,
        height: 1.28,
      );

  static TextStyle headlineLarge({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.manrope(
        fontSize: 24.0,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.3,
        height: 1.3,
      );

  static TextStyle headlineMedium({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.manrope(
        fontSize: 20.0,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.2,
        height: 1.32,
      );

  static TextStyle titleMedium({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.manrope(
        fontSize: 18.0,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: -0.1,
        height: 1.35,
      );

  /// Readable mobile body font (16px minimum recommendation)
  static TextStyle bodyLarge({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.manrope(
        fontSize: 16.0,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      );

  static TextStyle bodyMedium({Color color = FlowColors.textSecondary}) =>
      GoogleFonts.manrope(
        fontSize: 15.0,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.45,
      );

  static TextStyle labelLarge({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.manrope(
        fontSize: 16.0,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.1,
        height: 1.3,
      );

  static TextStyle labelMedium({Color color = FlowColors.textSecondary}) =>
      GoogleFonts.manrope(
        fontSize: 14.0,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.1,
        height: 1.3,
      );

  static TextStyle labelSmall({Color color = FlowColors.textMuted}) =>
      GoogleFonts.manrope(
        fontSize: 12.0,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.2,
        height: 1.25,
      );

  static TextStyle numberHero({Color color = FlowColors.cyanLight}) =>
      GoogleFonts.manrope(
        fontSize: 32.0,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.5,
      );

  static TextStyle badgeText({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.manrope(
        fontSize: 12.0,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.6,
      );
}
