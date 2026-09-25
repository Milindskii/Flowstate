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
  final bool isCompleted;
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
    this.isCompleted = false,
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
    bool? isCompleted,
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
      isCompleted: isCompleted ?? this.isCompleted,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'Focus';
    Color bg = FlowColors.tagDeepWorkBg;
    Color fg = FlowColors.tagDeepWorkText;
    String tag = json['tag_text'] as String? ?? 'DEEP WORK';

    if (typeStr.toLowerCase().contains('study') || typeStr.toLowerCase().contains('medium')) {
      bg = FlowColors.tagMediumBg;
      fg = FlowColors.tagMediumText;
      tag = 'MEDIUM';
    } else if (typeStr.toLowerCase().contains('rest') || typeStr.toLowerCase().contains('break')) {
      bg = FlowColors.tagRestBg;
      fg = FlowColors.tagRestText;
      tag = 'REST';
    } else if (typeStr.toLowerCase().contains('admin') || typeStr.toLowerCase().contains('light')) {
      bg = FlowColors.tagLightBg;
      fg = FlowColors.tagLightText;
      tag = 'LIGHT';
    } else if (typeStr.toLowerCase().contains('physical') || typeStr.toLowerCase().contains('fitness')) {
      bg = FlowColors.tagPhysicalBg;
      fg = FlowColors.tagPhysicalText;
      tag = 'PHYSICAL';
    }

    return ScheduleItem(
      id: json['id'] as String? ?? 'sched-${DateTime.now().millisecondsSinceEpoch}',
      time: json['time'] as String? ?? '9:00',
      period: json['period'] as String? ?? 'AM',
      title: json['title'] as String? ?? 'Focus Block',
      type: typeStr,
      tagText: tag,
      tagBg: bg,
      tagColor: fg,
      isActive: json['is_active'] as bool? ?? false,
      isCompleted: json['is_completed'] as bool? ?? false,
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 60,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time,
        'period': period,
        'title': title,
        'type': type,
        'tag_text': tagText,
        'is_active': isActive,
        'is_completed': isCompleted,
        'duration_minutes': durationMinutes,
      };
}
