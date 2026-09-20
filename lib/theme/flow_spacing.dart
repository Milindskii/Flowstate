import 'package:flutter/material.dart';

/// Flowstate Consistent Grid & Spacing System
///
/// Principles:
/// - Small, predictable 4/8-pt token scale
/// - Consistent alignment rather than rigid identical numbers everywhere
/// - Responsive page margins (20px on <=360px small screens, 24px default on standard screens)
class FlowSpacing {
  FlowSpacing._();

  // Core Tokens
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;

  // Touch Target Minimums
  static const double minTouchTarget = 48.0;
  static const double buttonHeight = 50.0;

  /// Responsive page margin: 20px on small screens (<= 360px wide) to maximize
  /// content space without cramping; 24px default on normal and larger screens.
  static double pageMargin(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width <= 360.0 ? 20.0 : 24.0;
  }

  /// Responsive page padding applying horizontal margin and standard vertical rhythm
  static EdgeInsets pagePadding(BuildContext context) {
    return EdgeInsets.symmetric(
      horizontal: pageMargin(context),
      vertical: 16.0,
    );
  }
}
