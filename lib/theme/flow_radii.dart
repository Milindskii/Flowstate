import 'package:flutter/material.dart';

/// Flowstate Corner Radius Standards
/// Prominent rounded corners form a major part of the visual identity.
class FlowRadii {
  FlowRadii._();

  static const double card = 24.0;
  static const double cardLarge = 28.0;
  static const double heroContainer = 30.0;
  static const double button = 18.0;
  static const double inputField = 18.0;
  static const double chip = 14.0;
  static const double badge = 8.0;
  static const double pill = 999.0;
  static const double avatar = 999.0;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(card));
  static const BorderRadius cardLargeRadius = BorderRadius.all(Radius.circular(cardLarge));
  static const BorderRadius heroRadius = BorderRadius.all(Radius.circular(heroContainer));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(button));
  static const BorderRadius inputRadius = BorderRadius.all(Radius.circular(inputField));
  static const BorderRadius chipRadius = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius badgeRadius = BorderRadius.all(Radius.circular(badge));
  static const BorderRadius pillRadius = BorderRadius.all(Radius.circular(pill));
}
