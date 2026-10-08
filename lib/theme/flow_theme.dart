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
      dialogTheme: const DialogThemeData(
        backgroundColor: FlowColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadii.cardRadius,
          side: BorderSide(color: FlowColors.borderLight, width: 1.0),
        ),
      ),
      datePickerTheme: buildDatePickerTheme(false, accentColor),
      timePickerTheme: buildTimePickerTheme(false, accentColor),
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
      datePickerTheme: buildDatePickerTheme(true, accentColor),
      timePickerTheme: buildTimePickerTheme(true, accentColor),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: FlowColors.surfaceDark,
        selectedItemColor: accentColor,
        unselectedItemColor: FlowColors.textMutedDark,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  /// Generates a unified Flowstate DatePickerThemeData matching the app design system.
  static DatePickerThemeData buildDatePickerTheme(bool isDark, Color accentColor) {
    final surface = isDark ? FlowColors.surfaceElevatedDark : FlowColors.surfaceLight;
    final surfaceContainer = isDark ? FlowColors.surfaceContainerDark : FlowColors.surfaceContainerLight;
    final border = isDark ? FlowColors.borderDark : FlowColors.borderLight;
    final textPrimary = isDark ? FlowColors.textPrimaryDark : FlowColors.textPrimaryLight;
    final textSecondary = isDark ? FlowColors.textSecondaryDark : FlowColors.textSecondaryLight;
    final textMuted = isDark ? FlowColors.textMutedDark : FlowColors.textMutedLight;
    final divider = isDark ? FlowColors.dividerDark : FlowColors.dividerLight;

    return DatePickerThemeData(
      backgroundColor: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: FlowRadii.cardLargeRadius,
        side: BorderSide(color: border, width: 1.0),
      ),
      headerBackgroundColor: surfaceContainer,
      headerForegroundColor: textPrimary,
      headerHeadlineStyle: GoogleFonts.plusJakartaSans(
        fontSize: 22.0,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.3,
      ),
      headerHelpStyle: GoogleFonts.plusJakartaSans(
        fontSize: 12.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: textMuted,
      ),
      weekdayStyle: GoogleFonts.plusJakartaSans(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: textMuted,
      ),
      dayStyle: GoogleFonts.plusJakartaSans(
        fontSize: 14.0,
        fontWeight: FontWeight.w600,
      ),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return FlowColors.textInverse;
        }
        if (states.contains(WidgetState.disabled)) {
          return textMuted.withValues(alpha: 0.38);
        }
        return textPrimary;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accentColor;
        }
        return null;
      }),
      dayOverlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return accentColor.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.pressed)) {
          return accentColor.withValues(alpha: 0.16);
        }
        return null;
      }),
      dayShape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowRadii.chip),
        ),
      ),
      todayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return FlowColors.textInverse;
        }
        return accentColor;
      }),
      todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accentColor;
        }
        return accentColor.withValues(alpha: 0.12);
      }),
      todayBorder: BorderSide(
        color: accentColor,
        width: 1.5,
      ),
      yearStyle: GoogleFonts.plusJakartaSans(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
      ),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return FlowColors.textInverse;
        }
        if (states.contains(WidgetState.disabled)) {
          return textMuted.withValues(alpha: 0.38);
        }
        return textPrimary;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accentColor;
        }
        return null;
      }),
      dividerColor: divider,
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: textSecondary,
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowRadii.button),
        ),
      ),
      confirmButtonStyle: FilledButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: FlowColors.textInverse,
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowRadii.button),
        ),
        elevation: 0,
      ),
    );
  }

  /// Generates a unified Flowstate TimePickerThemeData matching the app design system.
  static TimePickerThemeData buildTimePickerTheme(bool isDark, Color accentColor) {
    final surface = isDark ? FlowColors.surfaceElevatedDark : FlowColors.surfaceLight;
    final surfaceContainer = isDark ? FlowColors.surfaceContainerDark : FlowColors.surfaceContainerLight;
    final border = isDark ? FlowColors.borderDark : FlowColors.borderLight;
    final textPrimary = isDark ? FlowColors.textPrimaryDark : FlowColors.textPrimaryLight;
    final textSecondary = isDark ? FlowColors.textSecondaryDark : FlowColors.textSecondaryLight;
    final textMuted = isDark ? FlowColors.textMutedDark : FlowColors.textMutedLight;

    return TimePickerThemeData(
      backgroundColor: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FlowRadii.cardLargeRadius,
        side: BorderSide(color: border, width: 1.0),
      ),
      dialBackgroundColor: surfaceContainer,
      dialHandColor: accentColor,
      dialTextColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return FlowColors.textInverse;
        }
        return textPrimary;
      }),
      dialTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
      ),
      hourMinuteColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accentColor.withValues(alpha: 0.15);
        }
        return surfaceContainer;
      }),
      hourMinuteTextColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accentColor;
        }
        return textPrimary;
      }),
      hourMinuteTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 44.0,
        fontWeight: FontWeight.w700,
      ),
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FlowRadii.inputField),
        side: BorderSide(color: border, width: 1.0),
      ),
      dayPeriodColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accentColor.withValues(alpha: 0.18);
        }
        return surfaceContainer;
      }),
      dayPeriodTextColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accentColor;
        }
        return textMuted;
      }),
      dayPeriodTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 14.0,
        fontWeight: FontWeight.w700,
      ),
      dayPeriodBorderSide: BorderSide(color: border, width: 1.0),
      dayPeriodShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FlowRadii.chip),
        side: BorderSide(color: border, width: 1.0),
      ),
      helpTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 12.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: textMuted,
      ),
      entryModeIconColor: textMuted,
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: textSecondary,
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowRadii.button),
        ),
      ),
      confirmButtonStyle: FilledButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: FlowColors.textInverse,
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowRadii.button),
        ),
        elevation: 0,
      ),
      timeSelectorSeparatorColor: WidgetStateColor.resolveWith((_) => textPrimary),
      timeSelectorSeparatorTextStyle: WidgetStateProperty.all(
        GoogleFonts.plusJakartaSans(
          fontSize: 40.0,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
    );
  }
}
