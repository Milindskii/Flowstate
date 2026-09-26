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

  /// Helper indicating if text can be handled deterministically without AI
  static bool canParseDeterministically(String text) => !requiresAiEnrichment(text);

  /// Checks whether an input contains complex or ambiguous natural language
  /// that cannot be confidently and safely structured by deterministic rules alone.
  static bool requiresAiEnrichment(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return false;

    // Vague references or complex relative dependencies without clear timestamps
    final ambiguousPatterns = [
      RegExp(r'\b(?:that\s+project\s+thing|stuff\s+i\s+told\s+you|the\s+thing\s+we\s+talked\s+about|whatever\s+we\s+discussed)\b'),
      RegExp(r'\b(?:sometime\s+before\s+my\s+meeting|before\s+the\s+call\s+with|after\s+my\s+sync)\b'),
      RegExp(r'\b(?:help\s+me\s+figure\s+out|not\s+sure\s+when|whenever\s+you\s+can|sometime\s+this\s+week)\b'),
    ];

    for (final pattern in ambiguousPatterns) {
      if (pattern.hasMatch(lower)) return true;
    }

    final localTasks = deterministicFallbackParse(text);
    // If text was substantial but local parser found no tasks, AI is needed
    if (localTasks.isEmpty && text.trim().length >= 12) {
      return true;
    }

    return false;
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

      // Priority extraction (explicit user words always win)
      TaskPriority priority = TaskPriority.medium;
      String prioritySource = 'unspecified';
      if (RegExp(r'\b(?:urgent|critical|p0|asap)\b', caseSensitive: false).hasMatch(lower)) {
        priority = TaskPriority.urgent;
        prioritySource = 'explicit';
        title = title.replaceAll(RegExp(r'\b(?:urgent|critical|p0|asap)\b', caseSensitive: false), '').trim();
      } else if (RegExp(r'\b(?:high\s+priority|p1|important|top\s+priority)\b', caseSensitive: false).hasMatch(lower)) {
        priority = TaskPriority.high;
        prioritySource = 'explicit';
        title = title.replaceAll(RegExp(r'\b(?:high\s+priority|p1|important|top\s+priority)\b', caseSensitive: false), '').trim();
      } else if (RegExp(r'\b(?:low\s+priority|p3|optional)\b', caseSensitive: false).hasMatch(lower)) {
        priority = TaskPriority.low;
        prioritySource = 'explicit';
        title = title.replaceAll(RegExp(r'\b(?:low\s+priority|p3|optional)\b', caseSensitive: false), '').trim();
      } else if (RegExp(r'\b(?:medium\s+priority|p2|normal\s+priority)\b', caseSensitive: false).hasMatch(lower)) {
        priority = TaskPriority.medium;
        prioritySource = 'explicit';
        title = title.replaceAll(RegExp(r'\b(?:medium\s+priority|p2|normal\s+priority)\b', caseSensitive: false), '').trim();
      } else {
        // Priority was not explicitly specified by user
        ambiguities.add('priority_unspecified');
      }

      // Duration extraction
      int? durationMinutes;
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

      // Scheduled time extraction (never invent a fixed time if not stated)
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
          // Ambiguous time without AM/PM (e.g. "gym at 6" -> default 6 PM)
          ambiguities.add('time_am_pm');
          targetHour = (hourRaw <= 7) ? hourRaw + 12 : hourRaw;
        }

        scheduledStart = DateTime(now.year, now.month, now.day, targetHour, minRaw);
        scheduledTimeStr = DateFormat('h:mm a').format(scheduledStart);
        title = title.replaceAll(RegExp(timeMatch.group(0)!, caseSensitive: false), '').trim();
      }

      // Deadline extraction (never invent a deadline if not stated)
      String? deadlineStr;
      DateTime? deadlineAt;
      if (lower.contains('tomorrow')) {
        deadlineAt = DateTime(now.year, now.month, now.day + 1, 18, 0);
        deadlineStr = 'Tomorrow';
        title = title.replaceAll(RegExp(r'\b(?:by|due|on|before)?\s*tomorrow(?:\s+night|\s+morning)?\b', caseSensitive: false), '').trim();
      } else if (lower.contains('today') || lower.contains('tonight')) {
        deadlineAt = DateTime(now.year, now.month, now.day, 23, 59);
        deadlineStr = 'Today';
        title = title.replaceAll(RegExp(r'\b(?:by|due|on|before)?\s*(?:today|tonight)\b', caseSensitive: false), '').trim();
      } else {
        const daysMap = {
          'monday': DateTime.monday,
          'tuesday': DateTime.tuesday,
          'wednesday': DateTime.wednesday,
          'thursday': DateTime.thursday,
          'friday': DateTime.friday,
          'saturday': DateTime.saturday,
          'sunday': DateTime.sunday,
        };
        for (final entry in daysMap.entries) {
          if (lower.contains(entry.key)) {
            final daysAhead = (entry.value - now.weekday) % 7;
            final addDays = daysAhead == 0 ? 7 : daysAhead;
            deadlineAt = DateTime(now.year, now.month, now.day + addDays, 17, 0);
            deadlineStr = entry.key[0].toUpperCase() + entry.key.substring(1);
            title = title.replaceAll(RegExp(r'\b(?:by|due|on|before)?\s*' + entry.key + r'\b', caseSensitive: false), '').trim();
            break;
          }
        }
      }

      // Category and Type categorization with sensible defaults
      TaskType taskType = TaskType.deepWork;
      TaskDifficulty difficulty = TaskDifficulty.medium;
      String category = 'General';

      if (RegExp(r'\b(gym|workout|exercise|run|leg day|yoga|cardio)\b', caseSensitive: false).hasMatch(lower)) {
        taskType = TaskType.physical;
        difficulty = TaskDifficulty.physical;
        category = 'Fitness';
        durationMinutes ??= 60;
      } else if (RegExp(r'\b(assignment|study|dbms|ml|code|coding|thesis|math|algorithm|homework|lab|arrays)\b', caseSensitive: false).hasMatch(lower)) {
        taskType = TaskType.study;
        difficulty = TaskDifficulty.high;
        category = 'Study';
        durationMinutes ??= 45;
      } else if (RegExp(r'\b(work|client|meeting|sync|email|call|schedule|buy|pay|clean|admin|errand|dentist|doctor)\b', caseSensitive: false).hasMatch(lower)) {
        taskType = RegExp(r'\b(work|client)\b', caseSensitive: false).hasMatch(lower)
            ? TaskType.deepWork
            : TaskType.admin;
        difficulty = TaskDifficulty.light;
        category = 'Admin';
        durationMinutes ??= 30;
      } else {
        durationMinutes ??= 45;
      }

      // Clean, concise, user-faithful task title
      title = sanitizeTitle(title);
      if (title.isEmpty) {
        title = sanitizeTitle(clause);
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
          prioritySource: prioritySource,
          category: category,
          isPriority: priority == TaskPriority.high || priority == TaskPriority.urgent,
          ambiguities: ambiguities,
        ),
      );
    }

    return results;
  }

  /// Ensures task titles are concise, natural, and user-faithful.
  /// Removes bloated filler ('to do', 'task for', 'task', redundant 'my'/'the').
  static String sanitizeTitle(String rawTitle) {
    if (rawTitle.trim().isEmpty) return 'Task';
    String t = rawTitle.trim();
    // Strip leading/trailing punctuation or bullet marks
    t = t.replaceAll(RegExp(r'^[,\s\-•*:]+|[,\s\-•*:]+$'), '').trim();
    // Strip prefixes like "task for ", "task: ", "to do: "
    t = t.replaceAll(RegExp(r'^(?:task\s+for|task\s*:|to\s*do\s*:)\s*', caseSensitive: false), '').trim();
    // Strip suffixes like " to do", " todo", " task"
    t = t.replaceAll(RegExp(r'\s+(?:to\s+do|todo|task)$', caseSensitive: false), '').trim();
    // Strip filler like 'my' or 'the' after action verbs (e.g. 'finish my assignment' -> 'Finish assignment')
    t = t.replaceAll(RegExp(r'\b(?:my|the)\s+(?=assignment|project|lab|homework|thesis|work|task|exam|quiz|session|workout)\b', caseSensitive: false), '');
    // Strip leading filler words ("and", "to", "go to", "also", "then")
    t = t.replaceAll(RegExp(r'^(?:and\s+|then\s+|also\s+|go\s+to\s+|to\s+)', caseSensitive: false), '').trim();
    // Strip extra whitespace
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Capitalize first letter
    if (t.length > 1) {
      t = t[0].toUpperCase() + t.substring(1);
    } else if (t.length == 1) {
      t = t.toUpperCase();
    }
    return t.isEmpty ? 'Task' : t;
  }

  static List<String> _splitClauses(String text) {
    // 1. Primary delimiters: newlines, semicolons, bullets
    final primaryChunks = text.split(RegExp(r'[\n;•\*\-]+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final List<String> clauses = [];
    const actionVerbs = r'(?:finish|study|go to|gym|workout|review|call|email|buy|read|write|prep|pay|meet|clean|submit|update|complete|dentist|doctor|appointment|sync|class|lecture|groceries|errands?|pick up|drop off|walk|exercise|run)';

    for (final chunk in primaryChunks) {
      final lower = chunk.toLowerCase().trim();

      // Task Segmentation: independently executable activities
      // e.g. "gym work assignment" -> ["Gym", "Work", "Assignment"]
      // Preserves single outcome phrases like "finish my work assignment" or "finish my python assignment and submit it"
      final isSingleTransitiveAction = RegExp(r'^(?:finish|complete|submit|do|start|review|write|read)\b', caseSensitive: false).hasMatch(lower);
      final hasPronounReference = RegExp(r'\b(?:and\s+submit\s+it|and\s+send\s+it|and\s+file\s+it)\b', caseSensitive: false).hasMatch(lower);

      if (!isSingleTransitiveAction && !hasPronounReference) {
        final seg3 = RegExp(r'^(gym|workout|exercise|run)\s+(work|meeting|emails?)\s+(assignment|study|homework|thesis)$', caseSensitive: false).firstMatch(lower);
        if (seg3 != null) {
          clauses.addAll([
            sanitizeTitle(seg3.group(1)!),
            sanitizeTitle(seg3.group(2)!),
            sanitizeTitle(seg3.group(3)!),
          ]);
          continue;
        }

        final seg2 = RegExp(r'^(gym|workout|exercise|run)\s+(work|meeting|emails?|assignment|study|homework|thesis|dentist|groceries)$', caseSensitive: false).firstMatch(lower);
        if (seg2 != null) {
          clauses.addAll([
            sanitizeTitle(seg2.group(1)!),
            sanitizeTitle(seg2.group(2)!),
          ]);
          continue;
        }
      }

      final parts = chunk
          .split(RegExp(
            r'(?:,\s*(?:and|then|and then)\s+|\s+(?:and then|then)\s+|,\s*(?=' + actionVerbs + r'\b)|\s+and\s+(?=' + actionVerbs + r'\b(?!\s+(?:it|them)\b))|,\s*(?=[a-zA-Z0-9_\-\s]+\b(?:at|by|for)\s+\d+))',
            caseSensitive: false,
          ))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      clauses.addAll(parts);
    }

    return clauses.isEmpty ? [text.trim()] : clauses;
  }
}
