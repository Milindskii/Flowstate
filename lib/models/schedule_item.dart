import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';

/// Schedule Item Model
/// Timeblock representation for Today's Schedule and Calendar.
class ScheduleItem {
  final String id;
  final String time; // "9:30"
  final String period; // "AM" or "PM"
  final String title; // "ML Assignment"
  final String type; // "High Focus"
  final String tagText; // "DEEP WORK"
  final Color tagBg;
  final Color tagColor;
  final bool isActive;
  final int durationMinutes;

  const ScheduleItem({
    required this.id,
    required this.time,
    required this.period,
    required this.title,
    required this.type,
    required this.tagText,
    this.tagBg = FlowColors.tagDeepWorkBg,
    this.tagColor = FlowColors.tagDeepWorkText,
    this.isActive = false,
    this.durationMinutes = 60,
  });

  ScheduleItem copyWith({
    String? id,
    String? time,
    String? period,
    String? title,
    String? type,
    String? tagText,
    Color? tagBg,
    Color? tagColor,
    bool? isActive,
    int? durationMinutes,
  }) {
    return ScheduleItem(
      id: id ?? this.id,
      time: time ?? this.time,
      period: period ?? this.period,
      title: title ?? this.title,
      type: type ?? this.type,
      tagText: tagText ?? this.tagText,
      tagBg: tagBg ?? this.tagBg,
      tagColor: tagColor ?? this.tagColor,
      isActive: isActive ?? this.isActive,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }
}
