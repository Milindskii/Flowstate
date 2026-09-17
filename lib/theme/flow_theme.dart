import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'flow_colors.dart';
import 'flow_radii.dart';

/// Flowstate Theme Configuration
class FlowTheme {
  FlowTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: FlowColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: FlowColors.cyan,
        secondary: FlowColors.mint,
        surface: FlowColors.darkSurface,
        background: FlowColors.darkBackground,
        onPrimary: FlowColors.textInverse,
        onSecondary: FlowColors.textInverse,
        onSurface: FlowColors.textPrimary,
        onBackground: FlowColors.textPrimary,
        outline: FlowColors.darkBorder,
      ),
      textTheme: GoogleFonts.manropeTextTheme(
        ThemeData.dark().textTheme,
      ),
      cardTheme: CardThemeData(
        color: FlowColors.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadii.cardRadius,
          side: const BorderSide(color: FlowColors.darkBorder, width: 1.0),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: FlowColors.cyan,
          foregroundColor: FlowColors.textInverse,
          minimumSize: const Size(double.infinity, 52), // Mobile thumb target min 48px
          shape: RoundedRectangleBorder(
            borderRadius: FlowRadii.buttonRadius,
          ),
          elevation: 0,
          textStyle: GoogleFonts.manrope(
            fontSize: 16.0,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: FlowColors.darkSurface,
        hintStyle: GoogleFonts.manrope(
          color: FlowColors.textMuted,
          fontSize: 16.0,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: FlowRadii.inputRadius,
          borderSide: const BorderSide(color: FlowColors.darkBorder, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: FlowRadii.inputRadius,
          borderSide: const BorderSide(color: FlowColors.darkBorder, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: FlowRadii.inputRadius,
          borderSide: const BorderSide(color: FlowColors.cyan, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: FlowColors.darkSurface,
        selectedItemColor: FlowColors.cyan,
        unselectedItemColor: FlowColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: FlowColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: FlowColors.deepTeal,
        secondary: FlowColors.mint,
        surface: FlowColors.lightSurface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: FlowColors.lightTextPrimary,
        outline: FlowColors.lightBorder,
      ),
      textTheme: GoogleFonts.manropeTextTheme(
        ThemeData.light().textTheme,
      ),
      cardTheme: CardThemeData(
        color: FlowColors.lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadii.cardRadius,
          side: const BorderSide(color: FlowColors.lightBorder, width: 1.0),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    );
  }
}
