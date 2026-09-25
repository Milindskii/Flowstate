import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'flow_colors.dart';

/// Flowstate Typography Hierarchy using Plus Jakarta Sans
/// Modern, geometric, clean neo-grotesque type with tall x-height,
/// crystal-clear legibility, warm intelligent personality, and enhanced readability.
/// Configured with system emoji fallbacks to guarantee symbols never render as tofu/≡.
class FlowTypography {
  FlowTypography._();

  static const List<String> emojiFallback = [
    'Segoe UI Emoji',
    'Apple Color Emoji',
    'Noto Color Emoji',
    'sans-serif',
  ];

  static TextStyle displayLarge({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 36.0,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.6,
        height: 1.22,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle displayMedium({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 30.0,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.5,
        height: 1.25,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle headlineLarge({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 26.0,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.4,
        height: 1.28,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle headlineMedium({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 22.5,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.3,
        height: 1.3,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle titleMedium({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 20.0,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: -0.2,
        height: 1.35,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle titleSmall({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 17.0,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: -0.1,
        height: 1.35,
      ).copyWith(fontFamilyFallback: emojiFallback);

  /// Readable mobile body font (bumped to 18px)
  static TextStyle bodyLarge({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 18.0,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle bodyMedium({Color color = FlowColors.textSecondary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 16.5,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.45,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle bodySmall({Color color = FlowColors.textSecondary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 14.5,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.4,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle labelLarge({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 17.5,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.1,
        height: 1.3,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle labelMedium({Color color = FlowColors.textSecondary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 15.5,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.1,
        height: 1.3,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle labelSmall({Color color = FlowColors.textMuted}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.2,
        height: 1.25,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle numberHero({Color color = FlowColors.cyanLight}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 38.0,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: -0.5,
      ).copyWith(fontFamilyFallback: emojiFallback);

  static TextStyle badgeText({Color color = FlowColors.textPrimary}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: 13.0,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.6,
      ).copyWith(fontFamilyFallback: emojiFallback);
}
