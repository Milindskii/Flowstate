import 'package:flutter/material.dart';

/// Flowstate Color System
/// Sophisticated dark-first theme with obsidian surfaces and calming cyan/mint/ice-blue accents.
/// Strictly ZERO purple and ZERO orange.
class FlowColors {
  FlowColors._();

  // Dark Theme Surfaces
  // Surfaces (Crisp bright white theme)
  static const Color darkBackground = Color(0xFFFFFFFF);
  static const Color darkSurface = Color(0xFFF8FAFC);
  static const Color darkCard = Color(0xFFF1F5F9);
  static const Color darkCardElevated = Color(0xFFE2E8F0);
  static const Color darkBorder = Color(0xFFE2E8F0);
  static const Color darkDivider = Color(0xFFEEF2F6);

  // Accents (Electric Cyan, Crisp Mint, Ice Blue)
  static const Color cyan = Color(0xFF0891B2);
  static const Color cyanLight = Color(0xFF06B6D4);
  static const Color cyanGlow = Color(0x220891B2);

  static const Color mint = Color(0xFF059669);
  static const Color mintLight = Color(0xFF10B981);
  static const Color mintGlow = Color(0x22059669);

  static const Color iceBlue = Color(0xFF0284C7);
  static const Color iceBlueGlow = Color(0x220284C7);

  static const Color deepTeal = Color(0xFF0E7490);

  // Difficulty & Tag Colors (Clean, pastel tinted backgrounds with crisp text)
  static const Color tagDeepWorkBg = Color(0xFFE0F2FE);
  static const Color tagDeepWorkText = Color(0xFF0369A1);

  static const Color tagMediumBg = Color(0xFFD1FAE5);
  static const Color tagMediumText = Color(0xFF047857);

  static const Color tagLightBg = Color(0xFFF0F9FF);
  static const Color tagLightText = Color(0xFF0284C7);

  static const Color tagPhysicalBg = Color(0xFFCCFBF1);
  static const Color tagPhysicalText = Color(0xFF0F766E);

  static const Color tagRestBg = Color(0xFFF1F5F9);
  static const Color tagRestText = Color(0xFF475569);

  // Text Colors (High contrast, modern slate typography)
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textInverse = Color(0xFFFFFFFF);

  // Status & Utility
  static const Color success = Color(0xFF10B981);
  static const Color info = Color(0xFF06B6D4);
  static const Color error = Color(0xFFF43F5E); // Calm rose red if needed for validation

  // Light Theme Architecture Scaffolding
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFF1F5F9);
  static const Color lightCardElevated = Color(0xFFE2E8F0);
  static const Color lightBorder = Color(0xFFCBD5E1);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF06B6D4), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGlowGradient = LinearGradient(
    colors: [Color(0x0F06B6D4), Color(0x0510B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
