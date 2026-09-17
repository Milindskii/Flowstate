import 'package:flutter/material.dart';

/// Flowstate Color System
/// Sophisticated dark-first theme with obsidian surfaces and calming cyan/mint/ice-blue accents.
/// Strictly ZERO purple and ZERO orange.
class FlowColors {
  FlowColors._();

  // Dark Theme Surfaces
  static const Color darkBackground = Color(0xFF090D14);
  static const Color darkSurface = Color(0xFF111722);
  static const Color darkCard = Color(0xFF161F2E);
  static const Color darkCardElevated = Color(0xFF1C273A);
  static const Color darkBorder = Color(0xFF222C3E);
  static const Color darkDivider = Color(0xFF1A2232);

  // Accents (Electric Cyan, Crisp Mint, Ice Blue)
  static const Color cyan = Color(0xFF06B6D4);
  static const Color cyanLight = Color(0xFF22D3EE);
  static const Color cyanGlow = Color(0x3306B6D4);

  static const Color mint = Color(0xFF10B981);
  static const Color mintLight = Color(0xFF34D399);
  static const Color mintGlow = Color(0x3310B981);

  static const Color iceBlue = Color(0xFF38BDF8);
  static const Color iceBlueGlow = Color(0x3338BDF8);

  static const Color deepTeal = Color(0xFF0E7490);

  // Difficulty & Tag Colors (All strictly cyan, mint, ice-blue, slate)
  static const Color tagDeepWorkBg = Color(0xFF0C2B38);
  static const Color tagDeepWorkText = Color(0xFF22D3EE);

  static const Color tagMediumBg = Color(0xFF0E2E2A);
  static const Color tagMediumText = Color(0xFF34D399);

  static const Color tagLightBg = Color(0xFF172235);
  static const Color tagLightText = Color(0xFF7DD3FC);

  static const Color tagPhysicalBg = Color(0xFF122828);
  static const Color tagPhysicalText = Color(0xFF2DD4BF);

  static const Color tagRestBg = Color(0xFF1E293B);
  static const Color tagRestText = Color(0xFF94A3B8);

  // Text Colors
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textInverse = Color(0xFF090D14);

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
    colors: [Color(0x1A06B6D4), Color(0x0510B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF111C2B), Color(0xFF142236)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
