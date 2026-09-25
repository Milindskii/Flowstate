import 'package:intl/intl.dart';
import '../models/task_item.dart';
import 'api_service.dart';

/// Task parsing service.
///
/// Flow:
/// 1. Connected: POST /api/v1/tasks/parse → backend DeterministicTaskParser & AIService
/// 2. Resilient Offline Fallback: Client-side deterministic clause splitter and metadata extractor.
///
/// Under NO circumstance does this service replace user input with fake demo tasks.
class TaskParseService {
  final ApiService api;

  const TaskParseService({required this.api});

  /// Parse a natural-language task entry or brain dump.
  Future<List<TaskItem>> parseBrainDump(
    String rawText, {
    bool isDemoMode = false,
  }) async {
    final cleanInput = rawText.trim();
    if (cleanInput.isEmpty) return [];

    // Client-side length cap
    final textToSend = cleanInput.length > 1500 ? cleanInput.substring(0, 1500) : cleanInput;

    try {
      final response = await api.post(
        '/api/v1/tasks/parse',
        body: {
          'raw_text': textToSend,
          'use_ai': true,
        },
      );

      if (response is List && response.isNotEmpty) {
        return response
            .whereType<Map<String, dynamic>>()
            .map((json) => TaskItem.fromJson(json))
            .toList();
      }
    } catch (_) {
      // Backend unreachable or offline: run client-side deterministic parser
    }

    return deterministicFallbackParse(cleanInput);
  }

  /// Client-side deterministic rule-based parser that preserves the user's raw text.
  static List<TaskItem> deterministicFallbackParse(String text) {
    if (text.trim().isEmpty) return [];

    // 1. Split compound text on newlines, bullets, and compound conjunctions
    final rawClauses = _splitClauses(text);
    final List<TaskItem> results = [];
    final now = DateTime.now();

    for (int i = 0; i < rawClauses.length; i++) {
      final clause = rawClauses[i].trim();
      if (clause.isEmpty) continue;

      String title = clause;
      final lower = clause.toLowerCase();
      final List<String> ambiguities = [];

      // Duration extraction
      int durationMinutes = 45;
      final durationRegex = RegExp(r'\b(?:for\s+)?(\d+(?:\.\d+)?)\s*(mins?|minutes?|m|hrs?|hours?|h)\b', caseSensitive: false);
      final durMatch = durationRegex.firstMatch(lower);
      if (durMatch != null) {
        final val = double.tryParse(durMatch.group(1) ?? '45') ?? 45.0;
        final unit = durMatch.group(2)?.toLowerCase() ?? 'm';
        if (unit.startsWith('h')) {
          durationMinutes = (val * 60).clamp(5, 480).toInt();
        } else {
          durationMinutes = val.clamp(5, 480).toInt();
        }
        title = title.replaceAll(RegExp(durMatch.group(0)!, caseSensitive: false), '').trim();
      } else if (lower.contains('one hour') || lower.contains('an hour')) {
        durationMinutes = 60;
        title = title.replaceAll(RegExp(r'\b(?:for\s+)?(?:one hour|an hour)\b', caseSensitive: false), '').trim();
      } else if (lower.contains('half an hour')) {
        durationMinutes = 30;
        title = title.replaceAll(RegExp(r'\b(?:for\s+)?half an hour\b', caseSensitive: false), '').trim();
      }

      // Scheduled time extraction
      String? scheduledTimeStr;
      DateTime? scheduledStart;
      final timeRegex = RegExp(r'\b(?:at|around)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b', caseSensitive: false);
      final timeMatch = timeRegex.firstMatch(lower);
      if (timeMatch != null) {
        final hourRaw = int.tryParse(timeMatch.group(1) ?? '9') ?? 9;
        final minRaw = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
        final ampm = timeMatch.group(3)?.toLowerCase();

        int targetHour = hourRaw;
        if (ampm != null) {
          if (ampm == 'pm' && hourRaw < 12) targetHour += 12;
          if (ampm == 'am' && hourRaw == 12) targetHour = 0;
        } else {
          // Ambiguous time without AM/PM (e.g. "gym at 6")
          ambiguities.add('time_am_pm');
          targetHour = (hourRaw <= 7) ? hourRaw + 12 : hourRaw; // default 6 -> 6 PM
        }

        scheduledStart = DateTime(now.year, now.month, now.day, targetHour, minRaw);
        scheduledTimeStr = DateFormat('h:mm a').format(scheduledStart);
        title = title.replaceAll(RegExp(timeMatch.group(0)!, caseSensitive: false), '').trim();
      }

      // Deadline extraction
      String? deadlineStr;
      DateTime? deadlineAt;
      if (lower.contains('tomorrow')) {
        deadlineAt = DateTime(now.year, now.month, now.day + 1, 18, 0);
        deadlineStr = 'Tomorrow 6:00 PM';
        title = title.replaceAll(RegExp(r'\b(?:by|due|on|before)?\s*tomorrow(?:\s+night|\s+morning)?\b', caseSensitive: false), '').trim();
      } else if (lower.contains('today') || lower.contains('tonight')) {
        deadlineAt = DateTime(now.year, now.month, now.day, 23, 59);
        deadlineStr = 'Tonight 11:59 PM';
        title = title.replaceAll(RegExp(r'\b(?:by|due|on|before)?\s*(?:today|tonight)\b', caseSensitive: false), '').trim();
      } else if (lower.contains('friday')) {
        final daysAhead = (DateTime.friday - now.weekday) % 7;
        final addDays = daysAhead == 0 ? 7 : daysAhead;
        deadlineAt = DateTime(now.year, now.month, now.day + addDays, 17, 0);
        deadlineStr = 'Friday 5:00 PM';
        title = title.replaceAll(RegExp(r'\b(?:by|due|on|before)?\s*friday\b', caseSensitive: false), '').trim();
      }

      // Category and Type categorization
      TaskType taskType = TaskType.deepWork;
      TaskDifficulty difficulty = TaskDifficulty.medium;
      TaskPriority priority = TaskPriority.medium;
      String category = 'General';

      if (RegExp(r'\b(gym|workout|exercise|run|leg day|yoga|cardio)\b', caseSensitive: false).hasMatch(lower)) {
        taskType = TaskType.physical;
        difficulty = TaskDifficulty.physical;
        category = 'Fitness';
      } else if (RegExp(r'\b(assignment|study|dbms|ml|code|coding|thesis|math|algorithm|homework)\b', caseSensitive: false).hasMatch(lower)) {
        taskType = TaskType.deepWork;
        difficulty = TaskDifficulty.high;
        priority = TaskPriority.high;
        category = 'Study';
      } else if (RegExp(r'\b(email|call|meet|schedule|buy|pay|clean|admin|errand)\b', caseSensitive: false).hasMatch(lower)) {
        taskType = TaskType.admin;
        difficulty = TaskDifficulty.light;
        category = 'Admin';
      }

      // Clean leading and trailing prepositions or punctuation
      title = title.replaceAll(RegExp(r'^[,\s\-•*]+|[,\s\-•*]+$'), '').trim();
      if (title.isEmpty) {
        title = clause;
      }

      // Capitalize first letter
      if (title.isNotEmpty) {
        title = title[0].toUpperCase() + title.substring(1);
      }

      results.add(
        TaskItem(
          id: 'parsed-${now.millisecondsSinceEpoch}-$i',
          title: title,
          durationMinutes: durationMinutes,
          difficulty: difficulty,
          deadline: deadlineStr ?? (deadlineAt != null ? DateFormat('MMM d').format(deadlineAt) : 'Today'),
          deadlineAt: deadlineAt,
          scheduledTime: scheduledTimeStr,
          scheduledStart: scheduledStart,
          taskType: taskType,
          priority: priority,
          category: category,
          isPriority: priority == TaskPriority.high,
          ambiguities: ambiguities,
        ),
      );
    }

    return results;
  }

  static List<String> _splitClauses(String text) {
    // 1. Primary delimiters: newlines, semicolons, bullets
    final primaryChunks = text.split(RegExp(r'[\n;•\*\-]+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final List<String> clauses = [];
    const actionVerbs = r'(?:finish|study|go to|gym|workout|review|call|email|buy|read|write|prep|pay|meet|clean|submit|update|complete)';

    for (final chunk in primaryChunks) {
      final parts = chunk
          .split(RegExp(
            r'(?:,\s*(?:and|then|and then)\s+|\s+(?:and then|then)\s+|,\s*(?=' + actionVerbs + r'\b)|\s+and\s+(?=' + actionVerbs + r'\b))',
            caseSensitive: false,
          ))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      clauses.addAll(parts);
    }

    return clauses.isEmpty ? [text.trim()] : clauses;
  }
}
