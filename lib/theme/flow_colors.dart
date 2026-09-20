import 'package:flutter/material.dart';

/// User Accent Customization Options
enum FlowAccent {
  cyan,
  mint,
  blue,
  amber,
  rose,
  lime;

  String get label {
    switch (this) {
      case FlowAccent.cyan:
        return 'Cyan';
      case FlowAccent.mint:
        return 'Mint';
      case FlowAccent.blue:
        return 'Blue';
      case FlowAccent.amber:
        return 'Amber';
      case FlowAccent.rose:
        return 'Rose';
      case FlowAccent.lime:
        return 'Lime';
    }
  }

  /// Light theme accent (vibrant, WCAG AA compliant on pure white)
  Color get color {
    switch (this) {
      case FlowAccent.cyan:
        return FlowColors.accentCyan;
      case FlowAccent.mint:
        return FlowColors.accentMint;
      case FlowAccent.blue:
        return FlowColors.accentBlue;
      case FlowAccent.amber:
        return FlowColors.accentAmber;
      case FlowAccent.rose:
        return FlowColors.accentRose;
      case FlowAccent.lime:
        return FlowColors.accentLime;
    }
  }

  Color get lightColor => color;

  /// Dark theme accent (brilliant, WCAG AA compliant on obsidian/charcoal)
  Color get darkColor {
    switch (this) {
      case FlowAccent.cyan:
        return FlowColors.accentCyanDark;
      case FlowAccent.mint:
        return FlowColors.accentMintDark;
      case FlowAccent.blue:
        return FlowColors.accentBlueDark;
      case FlowAccent.amber:
        return FlowColors.accentAmberDark;
      case FlowAccent.rose:
        return FlowColors.accentRoseDark;
      case FlowAccent.lime:
        return FlowColors.accentLimeDark;
    }
  }

  Color resolve(BuildContext context) {
    return FlowColors.isDark(context) ? darkColor : lightColor;
  }

  static FlowAccent fromString(String? name) {
    switch (name?.toLowerCase()) {
      case 'mint':
        return FlowAccent.mint;
      case 'blue':
        return FlowAccent.blue;
      case 'amber':
        return FlowAccent.amber;
      case 'rose':
        return FlowAccent.rose;
      case 'lime':
        return FlowAccent.lime;
      case 'cyan':
      default:
        return FlowAccent.cyan;
    }
  }
}

/// Flowstate Color System
/// Rooted in the 60-30-10 principle:
/// ~60% Neutral Canvas (White in Light, Obsidian Charcoal in Dark)
/// ~30% Secondary Neutral Surfaces & Subtle Borders
/// ~10% High-Intentional Accent & Semantic Feedback
class FlowColors {
  FlowColors._();

  // ─────────────────────────────────────────────────────────
  // LIGHT PALETTE (Primary Default Identity)
  // ─────────────────────────────────────────────────────────
  static const Color bgLight = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFF8FAFC); // Slate 50
  static const Color surfaceContainerLight = Color(0xFFF1F5F9); // Slate 100
  static const Color borderLight = Color(0xFFE2E8F0); // Slate 200
  static const Color dividerLight = Color(0xFFF1F5F9); // Slate 100
  static const Color textPrimaryLight = Color(0xFF0F172A); // Slate 900 (Deep Charcoal)
  static const Color textSecondaryLight = Color(0xFF475569); // Slate 600
  static const Color textMutedLight = Color(0xFF94A3B8); // Slate 400
  static const Color softShadowLight = Color(0x0A000000); // 4% black

  // ─────────────────────────────────────────────────────────
  // DARK PALETTE (Secondary Optional Theme)
  // ─────────────────────────────────────────────────────────
  static const Color bgDark = Color(0xFF0B0F17); // Obsidian Charcoal
  static const Color surfaceDark = Color(0xFF131B2A); // Charcoal Slate
  static const Color surfaceElevatedDark = Color(0xFF1A2436); // Elevated Slate
  static const Color surfaceContainerDark = Color(0xFF223046); // Chip / Input Fill
  static const Color borderDark = Color(0xFF243248); // Low-contrast dark border
  static const Color dividerDark = Color(0xFF1C2739);
  static const Color textPrimaryDark = Color(0xFFF8FAFC); // Slate 50 (Crisp off-white)
  static const Color textSecondaryDark = Color(0xFF94A3B8); // Slate 400 (Cool gray)
  static const Color textMutedDark = Color(0xFF64748B); // Slate 500 (Muted gray)
  static const Color softShadowDark = Color(0x28000000); // Subtle dark shadow

  // ─────────────────────────────────────────────────────────
  // ACCENTS (Light vs Dark Adapted)
  // ─────────────────────────────────────────────────────────
  // Light Mode Accents (Sky-600, Emerald-600, Blue-600, Amber-600, Rose-600, Lime-600)
  static const Color accentCyan = Color(0xFF0284C7);
  static const Color accentMint = Color(0xFF059669);
  static const Color accentBlue = Color(0xFF2563EB);
  static const Color accentAmber = Color(0xFFD97706);
  static const Color accentRose = Color(0xFFE11D48);
  static const Color accentLime = Color(0xFF65A30D);

  // Dark Mode Accents (Sky-400, Emerald-400, Blue-400, Amber-400, Rose-400, Lime-400)
  static const Color accentCyanDark = Color(0xFF38BDF8);
  static const Color accentMintDark = Color(0xFF34D399);
  static const Color accentBlueDark = Color(0xFF60A5FA);
  static const Color accentAmberDark = Color(0xFFFBBF24);
  static const Color accentRoseDark = Color(0xFFFB7185);
  static const Color accentLimeDark = Color(0xFF65A30D);

  // ─────────────────────────────────────────────────────────
  // SEMANTIC COLORS
  // ─────────────────────────────────────────────────────────
  static const Color positive = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color critical = Color(0xFFDC2626);
  static const Color success = positive;
  static const Color info = accentCyan;
  static const Color error = critical;

  static const Color positiveDark = Color(0xFF34D399);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color criticalDark = Color(0xFFF87171);

  // ─────────────────────────────────────────────────────────
  // DYNAMIC CONTEXT ACCESSORS
  // ─────────────────────────────────────────────────────────
  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color background(BuildContext context) => isDark(context) ? bgDark : bgLight;
  static Color surface(BuildContext context) => isDark(context) ? surfaceDark : surfaceLight;
  static Color surfaceElevated(BuildContext context) => isDark(context) ? surfaceElevatedDark : surfaceElevatedLight;
  static Color surfaceContainer(BuildContext context) => isDark(context) ? surfaceContainerDark : surfaceContainerLight;
  static Color border(BuildContext context) => isDark(context) ? borderDark : borderLight;
  static Color divider(BuildContext context) => isDark(context) ? dividerDark : dividerLight;
  static Color textPrimaryOf(BuildContext context) => isDark(context) ? textPrimaryDark : textPrimaryLight;
  static Color textSecondaryOf(BuildContext context) => isDark(context) ? textSecondaryDark : textSecondaryLight;
  static Color textMutedOf(BuildContext context) => isDark(context) ? textMutedDark : textMutedLight;
  static Color softShadow(BuildContext context) => isDark(context) ? softShadowDark : softShadowLight;
  static Color card(BuildContext context) => surface(context);
  static Color cardElevated(BuildContext context) => surfaceElevated(context);
  static Color successOf(BuildContext context) => isDark(context) ? positiveDark : positive;
  static Color warningOf(BuildContext context) => isDark(context) ? warningDark : warning;
  static Color errorOf(BuildContext context) => isDark(context) ? criticalDark : critical;

  // ─────────────────────────────────────────────────────────
  // BACKWARDS-COMPATIBLE ALIASES
  // (Preserves existing legacy references safely defaulting to light values)
  // ─────────────────────────────────────────────────────────
  static const Color darkBackground = bgLight;
  static const Color darkSurface = surfaceLight;
  static const Color darkCard = surfaceLight;
  static const Color darkCardElevated = surfaceElevatedLight;
  static const Color darkBorder = borderLight;
  static const Color darkDivider = dividerLight;

  static const Color textPrimary = textPrimaryLight;
  static const Color textSecondary = textSecondaryLight;
  static const Color textMuted = textMutedLight;
  static const Color textInverse = Color(0xFFFFFFFF);

  static const Color cyan = accentCyan;
  static const Color cyanLight = accentCyan;
  static const Color mint = accentMint;
  static const Color mintLight = accentMint;
  static const Color iceBlue = accentBlue;
  static const Color deepTeal = Color(0xFF0E7490);

  // Tag Colors (Clean Tinted Badges)
  static const Color tagDeepWorkBg = Color(0xFFF0F9FF);
  static const Color tagDeepWorkText = Color(0xFF0284C7);
  static const Color tagMediumBg = Color(0xFFECFDF5);
  static const Color tagMediumText = Color(0xFF059669);
  static const Color tagLightBg = Color(0xFFF1F5F9);
  static const Color tagLightText = Color(0xFF475569);
  static const Color tagPhysicalBg = Color(0xFFF7FEE7);
  static const Color tagPhysicalText = Color(0xFF65A30D);
  static const Color tagRestBg = Color(0xFFF8FAFC);
  static const Color tagRestText = Color(0xFF64748B);

  // Light Theme Scaffold Aliases
  static const Color lightBackground = bgLight;
  static const Color lightSurface = surfaceLight;
  static const Color lightCard = surfaceLight;
  static const Color lightCardElevated = surfaceElevatedLight;
  static const Color lightBorder = borderLight;
  static const Color lightTextPrimary = textPrimaryLight;
  static const Color lightTextSecondary = textSecondaryLight;
  static const Color lightTextMuted = textMutedLight;

  // Gradients
  static const LinearGradient energyCurveGradient = LinearGradient(
    colors: [Color(0xFF0284C7), Color(0xFF059669)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient performanceGraphGradient = LinearGradient(
    colors: [Color(0x660284C7), Color(0x000284C7)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF0284C7), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
