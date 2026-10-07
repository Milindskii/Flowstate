import 'package:flutter/material.dart';

/// A commitment is a time window, not work with a deadline: an end clock time at or before the start means
/// it runs past midnight (10:30 PM → 12:30 AM ends on the next day). Shared by every commitment editor.
const Duration maxCommitmentSpan = Duration(hours: 12);

DateTime commitmentEnd(DateTime day, TimeOfDay start, TimeOfDay end) {
  final s = DateTime(day.year, day.month, day.day, start.hour, start.minute);
  final sameDay = DateTime(day.year, day.month, day.day, end.hour, end.minute);
  return sameDay.isAfter(s) ? sameDay : sameDay.add(const Duration(days: 1));
}
