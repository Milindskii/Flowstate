import 'package:flutter/services.dart';

/// Centralized, accessible, and error-safe haptic feedback utility for Flowstate.
/// Respects device settings and gracefully handles web, desktop, and test environments.
class FlowHaptics {
  FlowHaptics._();

  /// Standard button press / primary action tap.
  static Future<void> lightTap() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      // Safely ignore on platforms without haptic engine
    }
  }

  /// Option selection (segmented control, radio, emoji, tab change).
  static Future<void> selection() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Positive confirmation / task completed / session finished.
  static Future<void> success() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Critical action / destructive confirmation / validation error.
  static Future<void> warning() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
