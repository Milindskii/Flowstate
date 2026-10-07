import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'flow_colors.dart';
import 'flow_radii.dart';

/// Flowstate Theme Configuration
/// Enforces the 60-30-10 principle with a serene White primary identity and an optional Charcoal/Obsidian dark mode.
class FlowTheme {
  FlowTheme._();

  /// Primary Light Theme (Default Flowstate Experience)
  static ThemeData lightTheme([Color accentColor = FlowColors.accentCyan]) {
    return ThemeData(
      useMaterial3: true,
      splashFactory: InkRipple.splashFactory,
      brightness: Brightness.light,
      scaffoldBackgroundColor: FlowColors.bgLight,
      colorScheme: ColorScheme.light(
        primary: accentColor,
        secondary: FlowColors.accentMint,
        surface: FlowColors.surfaceLight,
        surfaceContainerHighest: FlowColors.surfaceElevatedLight,
        outline: FlowColors.borderLight,
        onPrimary: FlowColors.textInverse,
        onSecondary: FlowColors.textInverse,
        onSurface: FlowColors.textPrimaryLight,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.light().textTheme,
      ).apply(
        bodyColor: FlowColors.textPrimaryLight,
        displayColor: FlowColors.textPrimaryLight,
        fontFamilyFallback: const ['Segoe UI Emoji', 'Apple Color Emoji', 'Noto Color Emoji', 'sans-serif'],
      ),
      cardTheme: const CardThemeData(
        color: FlowColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadii.cardRadius,
          side: BorderSide(color: FlowColors.borderLight, width: 1.0),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: FlowColors.textInverse,
          minimumSize: const Size(double.infinity, 52), // Touch target >= 48px
          shape: const RoundedRectangleBorder(
            borderRadius: FlowRadii.buttonRadius,
          ),
          elevation: 0,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: FlowColors.textPrimaryLight,
          side: const BorderSide(color: FlowColors.borderLight, width: 1.0),
          minimumSize: const Size(double.infinity, 52),
          shape: const RoundedRectangleBorder(
            borderRadius: FlowRadii.buttonRadius,
          ),
          elevation: 0,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: FlowColors.surfaceLight,
        hintStyle: GoogleFonts.plusJakartaSans(
          color: FlowColors.textMutedLight,
          fontSize: 16.0,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: const OutlineInputBorder(
          borderRadius: FlowRadii.inputRadius,
          borderSide: BorderSide(color: FlowColors.borderLight, width: 1.0),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: FlowRadii.inputRadius,
          borderSide: BorderSide(color: FlowColors.borderLight, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: FlowRadii.inputRadius,
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: FlowColors.surfaceLight,
        selectedItemColor: accentColor,
        unselectedItemColor: FlowColors.textMutedLight,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  /// Secondary Dark Theme (Optional Obsidian / Charcoal Experience)
  static ThemeData darkTheme([Color accentColor = FlowColors.accentCyanDark]) {
    return ThemeData(
      useMaterial3: true,
      splashFactory: InkRipple.splashFactory,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: FlowColors.bgDark,
      colorScheme: ColorScheme.dark(
        primary: accentColor,
        secondary: FlowColors.accentMintDark,
        surface: FlowColors.surfaceDark,
        // Material 3 derives dialogs, menus, sheets and pickers from the container tones; pin
        // them to Flowstate's dark surfaces instead of the default purple-grey palette.
        surfaceContainerLowest: FlowColors.bgDark,
        surfaceContainerLow: FlowColors.surfaceDark,
        surfaceContainer: FlowColors.surfaceDark,
        surfaceContainerHigh: FlowColors.surfaceElevatedDark,
        surfaceContainerHighest: FlowColors.surfaceElevatedDark,
        surfaceTint: Colors.transparent,
        outline: FlowColors.borderDark,
        outlineVariant: FlowColors.dividerDark,
        onPrimary: FlowColors.bgDark,
        onSecondary: FlowColors.bgDark,
        onSurface: FlowColors.textPrimaryDark,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.dark().textTheme,
      ).apply(
        bodyColor: FlowColors.textPrimaryDark,
        displayColor: FlowColors.textPrimaryDark,
        fontFamilyFallback: const ['Segoe UI Emoji', 'Apple Color Emoji', 'Noto Color Emoji', 'sans-serif'],
      ),
      cardTheme: const CardThemeData(
        color: FlowColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadii.cardRadius,
          side: BorderSide(color: FlowColors.borderDark, width: 1.0),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: FlowColors.bgDark,
          minimumSize: const Size(double.infinity, 52),
          shape: const RoundedRectangleBorder(
            borderRadius: FlowRadii.buttonRadius,
          ),
          elevation: 0,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: FlowColors.textPrimaryDark,
          side: const BorderSide(color: FlowColors.borderDark, width: 1.0),
          minimumSize: const Size(double.infinity, 52),
          shape: const RoundedRectangleBorder(
            borderRadius: FlowRadii.buttonRadius,
          ),
          elevation: 0,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: FlowColors.surfaceDark,
        hintStyle: GoogleFonts.plusJakartaSans(
          color: FlowColors.textMutedDark,
          fontSize: 16.0,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: const OutlineInputBorder(
          borderRadius: FlowRadii.inputRadius,
          borderSide: BorderSide(color: FlowColors.borderDark, width: 1.0),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: FlowRadii.inputRadius,
          borderSide: BorderSide(color: FlowColors.borderDark, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: FlowRadii.inputRadius,
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: FlowColors.surfaceElevatedDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadii.cardRadius,
          side: BorderSide(color: FlowColors.borderDark, width: 1.0),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: FlowColors.surfaceDark,
        modalBackgroundColor: FlowColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: FlowColors.surfaceElevatedDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadii.chipRadius,
          side: BorderSide(color: FlowColors.borderDark, width: 1.0),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: FlowColors.surfaceElevatedDark,
        contentTextStyle: TextStyle(color: FlowColors.textPrimaryDark),
        behavior: SnackBarBehavior.floating,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: FlowColors.textPrimaryDark,
        elevation: 0,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: FlowColors.surfaceDark,
        selectedItemColor: accentColor,
        unselectedItemColor: FlowColors.textMutedDark,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
