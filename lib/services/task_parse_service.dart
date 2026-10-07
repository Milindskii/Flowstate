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
  ///
  /// CRITICAL: A multi-sentence paragraph brain dump (even if the deterministic
  /// parser returns non-empty results) MUST be routed to Gemini, because the
  /// deterministic clause splitter collapses multi-sentence paragraphs into a
  /// single task blob — producing "Physical · 90 min" for a 9-task brain dump.
  static bool requiresAiEnrichment(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return false;

    // 1. Vague references or complex relative dependencies without clear timestamps
    final ambiguousPatterns = [
      RegExp(r'\b(?:project\s+thing|stuff\s+i\s+told\s+you|the\s+thing\s+we\s+talked\s+about|whatever\s+we\s+discussed)\b'),
      RegExp(r'\b(?:sometime\s+before\s+(?:that|the|my)?\s*meeting|before\s+the\s+call\s+with|after\s+my\s+sync)\b'),
      RegExp(r'\b(?:help\s+me\s+figure\s+out|not\s+sure\s+(?:when|exactly|how\s+long)|whenever\s+you\s+can|sometime\s+this\s+week)\b'),
    ];
    for (final pattern in ambiguousPatterns) {
      if (pattern.hasMatch(lower)) return true;
    }

    // 2. Multi-sentence paragraph brain dump — deterministic splitter cannot segment
    // these correctly. Sentence count >= 3 is the primary signal.
    final sentences = text.trim().split(RegExp(r'[.!?]+')).where((s) => s.trim().length > 4).toList();
    if (sentences.length >= 3) return true;

    // 3. High word count with multiple distinct task-action verbs targeting different
    // objects (e.g. "finish X ... call Y ... clean Z") — strong multi-task signal.
    final words = lower.split(RegExp(r'\s+'));
    if (words.length > 40) {
      // Count distinct action verb occurrences targeting distinct objects
      final actionVerbPattern = RegExp(
        r'\b(?:finish|fix|call|clean|review|study|email|submit|buy|pay|meet|run|gym|workout|prep|read|write|do|complete|reply|send|check|update|prepare|schedule|go\s+to)\b',
      );
      final matches = actionVerbPattern.allMatches(lower);
      if (matches.length >= 3) return true;
    }

    // 4. If text was substantial but local parser found no tasks, AI is needed
    final localTasks = deterministicFallbackParse(text);
    if (localTasks.isEmpty && text.trim().length >= 12) {
      return true;
    }

    return false;
  }

  /// Client-side deterministic rule-based parser that preserves the user's raw text.
  static List<TaskItem> deterministicFallbackParse(String text) =>
      _parseWithSequence(text, resolveNamed: true);

  /// Parses each clause, then wires ordering: a clause introduced by "then" / "after that" depends on
  /// the one before it, and "after I finish X" depends on the task that names X (when there is one).
  static List<TaskItem> _parseWithSequence(String text, {required bool resolveNamed}) {
    if (text.trim().isEmpty) return [];

    // 1. Split compound text on newlines, bullets, and compound conjunctions
    final links = _splitClausesWithLinks(text);
    final List<TaskItem> results = [];
    final List<({String raw, bool follows, ({String stripped, String x})? named})> meta = [];
    final now = DateTime.now();

    for (int i = 0; i < links.length; i++) {
      final rawClause = links[i].text.trim();
      final named = resolveNamed ? _extractNamedPredecessor(rawClause) : null;
      final clause = named?.stripped ?? rawClause;
      if (clause.isEmpty) continue;

      String title = clause;
      final lower = clause.toLowerCase();

      // ── Context-statement guard ──────────────────────────────────────────
      // Availability / context phrases are NOT actionable tasks.
      // They describe scheduling constraints and must not create task cards.
      final contextPatterns = [
        RegExp(r'^\s*(?:i\s+)?(?:work|working|office|in\s+office)\s+(?:from\s+)?[\d][\d:apm]*\s*(?:[-–]|to)\s*[\d]', caseSensitive: false),
        RegExp(r'^\s*(?:i\s+have\s+)?class\s+(?:from\s+)?[\d][\d:apm]*\s*(?:[-–]|to)\s*[\d]', caseSensitive: false),
        RegExp(r'^\s*(?:i\s+)?lea(?:ve|ving)(?:\s+home)?\s+at\s+\d', caseSensitive: false),
        RegExp(r'^\s*(?:lunch|breakfast|dinner)\s+(?:at|around)\s+\d[\d:]*(?: ?[apm]*)?\s*$', caseSensitive: false),
      ];
      if (contextPatterns.any((p) => p.hasMatch(lower))) continue;
      // ─────────────────────────────────────────────────────────────────────

      // Orphan guard: a clause with nothing but attributes ("It will probably
      // take around 90 minutes") names no task.
      if (_contentWords(clause.replaceAll(_durationPhrase, ' ').replaceAll(_clockTime, ' ')).isEmpty) {
        continue;
      }

      // The title comes from the naming part of the clause only. Duration
      // phrases are removed together with their lead-in words so no broken
      // prose ("take around .") is left behind.
      final head = _titleHead(clause);
      title = head.replaceAll(_durationPhrase, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

      final List<String> ambiguities = [];

      // Priority extraction (explicit user words always win)
      TaskPriority? priority;
      String prioritySource = 'unspecified';
      if (RegExp(r'\b(?:urgent|critical|p0|asap)\b', caseSensitive: false).hasMatch(lower)) {
        priority = TaskPriority.urgent;
        prioritySource = 'explicit';
        title = title.replaceAll(RegExp(r'\b(?:urgent|critical|p0|asap)\b', caseSensitive: false), '').trim();
      } else if (_highPriority.hasMatch(lower)) {
        // "the important stuff" refers to other tasks, not to this one.
        priority = TaskPriority.high;
        prioritySource = 'explicit';
        title = title.replaceAll(_highPriority, '').trim();
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
      bool durationFound = false;
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
        durationFound = true;
        title = title.replaceAll(RegExp(durMatch.group(0)!, caseSensitive: false), '').trim();
      } else if (lower.contains('one hour') || lower.contains('an hour')) {
        durationMinutes = 60;
        durationFound = true;
        title = title.replaceAll(RegExp(r'\b(?:for\s+)?(?:one hour|an hour)\b', caseSensitive: false), '').trim();
      } else if (lower.contains('half an hour')) {
        durationMinutes = 30;
        durationFound = true;
        title = title.replaceAll(RegExp(r'\b(?:for\s+)?half an hour\b', caseSensitive: false), '').trim();
      }

      final List<String> missingFields = [];
      if (!durationFound) {
        missingFields.add('duration');
      }
      if (prioritySource == 'unspecified') {
        missingFields.add('priority');
      }

      // Scheduled time extraction (never invent a fixed time if not stated)
      String? scheduledTimeStr;
      DateTime? scheduledStart;
      bool explicitFixedTime = false; // lock source L1: "at 6 PM" only (not "around", not a bare hour)
      var timeMatch = _clockTime.firstMatch(lower);
      if (timeMatch != null &&
          ((int.tryParse(timeMatch.group(1) ?? '') ?? 99) > 23 ||
              (int.tryParse(timeMatch.group(2) ?? '0') ?? 99) > 59)) {
        timeMatch = null;
      }

      // Target date & deadline resolution
      DateTime targetDate = DateTime(now.year, now.month, now.day);
      DateTime? deadlineAt;
      String? deadlineStr;

      const daysMap = {
        'monday': DateTime.monday,
        'tuesday': DateTime.tuesday,
        'wednesday': DateTime.wednesday,
        'thursday': DateTime.thursday,
        'friday': DateTime.friday,
        'saturday': DateTime.saturday,
        'sunday': DateTime.sunday,
      };

      final hasByTomorrow = RegExp(r'\b(?:by|due|before)\s+tomorrow\b', caseSensitive: false).hasMatch(lower);
      final hasByToday = RegExp(r'\b(?:by|due|before)\s+(?:today|tonight)\b', caseSensitive: false).hasMatch(lower);

      if (hasByTomorrow) {
        deadlineAt = DateTime(now.year, now.month, now.day + 1, 23, 59);
        deadlineStr = 'Tomorrow';
        title = title.replaceAll(RegExp(r'\b(?:by|due|before)\s+tomorrow(?:\s+night|\s+morning)?\b', caseSensitive: false), '').trim();
      } else if (hasByToday) {
        deadlineAt = DateTime(now.year, now.month, now.day, 23, 59);
        deadlineStr = 'Today';
        title = title.replaceAll(RegExp(r'\b(?:by|due|before)\s*(?:today|tonight)\b', caseSensitive: false), '').trim();
      } else {
        // Check for weekday mention
        String? matchedWeekday;
        int? matchedWeekdayVal;
        int? weekdayMatchStart;
        for (final entry in daysMap.entries) {
          final regex = RegExp(r'\b' + entry.key + r'\b', caseSensitive: false);
          final m = regex.firstMatch(lower);
          if (m != null) {
            matchedWeekday = entry.key;
            matchedWeekdayVal = entry.value;
            weekdayMatchStart = m.start;
            break;
          }
        }

        if (matchedWeekday != null && matchedWeekdayVal != null && weekdayMatchStart != null) {
          final prefix = lower.substring(0, weekdayMatchStart).trim();
          final isDeadlinePrefix = RegExp(r'\b(?:by|due|before)\s*$', caseSensitive: false).hasMatch(prefix);
          final daysAhead = (matchedWeekdayVal - now.weekday) % 7;
          final addDays = daysAhead == 0 ? 7 : daysAhead;
          final resolvedDate = DateTime(now.year, now.month, now.day + addDays);

          if (isDeadlinePrefix) {
            deadlineAt = DateTime(resolvedDate.year, resolvedDate.month, resolvedDate.day, 23, 59);
            deadlineStr = matchedWeekday[0].toUpperCase() + matchedWeekday.substring(1);
            title = title.replaceAll(RegExp(r'\b(?:by|due|before)\s+' + matchedWeekday + r'\b', caseSensitive: false), '').trim();
          } else {
            targetDate = resolvedDate;
            if (timeMatch == null) {
              deadlineAt = DateTime(resolvedDate.year, resolvedDate.month, resolvedDate.day, 18, 0);
              deadlineStr = matchedWeekday[0].toUpperCase() + matchedWeekday.substring(1);
            }
            title = title.replaceAll(RegExp(r'\b(?:on\s+)?' + matchedWeekday + r'\b', caseSensitive: false), '').trim();
          }
        } else if (RegExp(r'\btomorrow\b', caseSensitive: false).hasMatch(lower)) {
          targetDate = DateTime(now.year, now.month, now.day + 1);
          if (timeMatch == null) {
            deadlineAt = DateTime(now.year, now.month, now.day + 1, 18, 0);
            deadlineStr = 'Tomorrow';
          }
          title = title.replaceAll(RegExp(r'\b(?:on\s+)?tomorrow(?:\s+night|\s+morning)?\b', caseSensitive: false), '').trim();
        } else if (RegExp(r'\b(?:today|tonight)\b', caseSensitive: false).hasMatch(lower)) {
          targetDate = DateTime(now.year, now.month, now.day);
          if (timeMatch == null) {
            deadlineAt = DateTime(now.year, now.month, now.day, 23, 59);
            deadlineStr = 'Today';
          }
          title = title.replaceAll(RegExp(r'\b(?:on\s+)?(?:today|tonight)\b', caseSensitive: false), '').trim();
        }
      }

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

        scheduledStart = DateTime(targetDate.year, targetDate.month, targetDate.day, targetHour, minRaw);
        explicitFixedTime = ampm != null && timeMatch.group(0)!.toLowerCase().startsWith('at');
        scheduledTimeStr = DateFormat('h:mm a').format(scheduledStart);
        title = title.replaceAll(RegExp(timeMatch.group(0)!, caseSensitive: false), '').trim();
      }

      // Explicit "by HH:MM" deadline if present
      final beforeTimeRegex = RegExp(r'\b(?:by|before)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b', caseSensitive: false);
      final beforeTimeMatch = beforeTimeRegex.firstMatch(lower);
      if (beforeTimeMatch != null) {
        final bh = int.tryParse(beforeTimeMatch.group(1) ?? '17') ?? 17;
        final bm = int.tryParse(beforeTimeMatch.group(2) ?? '0') ?? 0;
        final ampm = beforeTimeMatch.group(3)?.toLowerCase();
        int targetHour = bh;
        if (ampm != null) {
          if (ampm == 'pm' && bh < 12) targetHour += 12;
          if (ampm == 'am' && bh == 12) targetHour = 0;
        }
        deadlineAt = DateTime(targetDate.year, targetDate.month, targetDate.day, targetHour, bm);
        deadlineStr = DateFormat('h:mm a').format(deadlineAt);
        title = title.replaceAll(RegExp(beforeTimeMatch.group(0)!, caseSensitive: false), '').trim();
      }

      if (deadlineAt == null && scheduledStart == null) {
        missingFields.add('deadline');
      }

      title = title.replaceAll(RegExp(r'\s+on$', caseSensitive: false), '').trim();

      // Clean, concise, user-faithful task title
      title = sanitizeTitle(_repairTitle(_stripTitleOpeners(title)));
      if (_isMalformedTitle(title)) {
        // Attribute removal broke the sentence: keep the user's own words
        // (minus a cleanly removable duration phrase).
        title = sanitizeTitle(_repairTitle(_stripTitleOpeners(head.replaceAll(_durationPhrase, ' '))));
        if (_isMalformedTitle(title)) {
          title = sanitizeTitle(_repairTitle(_stripTitleOpeners(head)));
        }
      }
      final cleanLower = title.toLowerCase();

      // Category and Type categorization with sensible defaults
      TaskType taskType = TaskType.deepWork;
      TaskDifficulty difficulty = TaskDifficulty.medium;
      String category = 'General';

      if (RegExp(r'\b(gym|workout|exercise|run|leg day|yoga|cardio)\b', caseSensitive: false).hasMatch(cleanLower)) {
        taskType = TaskType.physical;
        difficulty = TaskDifficulty.physical;
        category = 'Fitness';
        durationMinutes ??= 60;
      } else if (RegExp(r'\b(assignment|assignments|study|dbms|ml|code|coding|thesis|math|algorithm|homework|lab|arrays)\b', caseSensitive: false).hasMatch(cleanLower)) {
        taskType = RegExp(r'\b(thesis|ml|algorithm|code|coding)\b', caseSensitive: false).hasMatch(cleanLower)
            ? TaskType.deepWork
            : TaskType.study;
        difficulty = TaskDifficulty.high;
        category = 'College';
        durationMinutes ??= 45;
      } else if (RegExp(r'\b(work|client|meeting|sync|email|call|schedule|buy|pay|clean|admin|errand|dentist|doctor)\b', caseSensitive: false).hasMatch(cleanLower)) {
        taskType = RegExp(r'\b(work|client|project)\b', caseSensitive: false).hasMatch(cleanLower)
            ? TaskType.deepWork
            : TaskType.admin;
        difficulty = TaskDifficulty.medium;
        category = RegExp(r'\b(work|client|project)\b', caseSensitive: false).hasMatch(cleanLower)
            ? 'Work'
            : 'Personal';
        durationMinutes ??= 45;
      } else {
        durationMinutes ??= 45;
      }

      meta.add((raw: rawClause, follows: links[i].follows, named: named));
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
          timeLocked: scheduledStart != null && explicitFixedTime,
          taskType: taskType,
          priority: priority,
          prioritySource: prioritySource,
          category: category,
          isPriority: priority == TaskPriority.high || priority == TaskPriority.urgent,
          missingFields: missingFields,
          ambiguities: ambiguities,
        ),
      );
    }

    // Pass A: resolve named predecessors. An unmatched phrase is left in the title, untouched.
    final Map<int, int> predOf = {};
    for (int i = 0; i < meta.length; i++) {
      final named = meta[i].named;
      if (named == null) continue;
      final j = _matchPredecessor(named.x, results, i);
      if (j != null) {
        predOf[i] = j;
        continue;
      }
      final restored = _parseWithSequence(meta[i].raw, resolveNamed: false);
      if (restored.isNotEmpty) results[i] = restored.first.copyWith(id: results[i].id);
    }

    // Pass B: assign dependencies (ids are the confirm step's client_refs).
    for (int i = 0; i < results.length; i++) {
      final deps = <String>[];
      if (predOf.containsKey(i)) deps.add(results[predOf[i]!].id);
      if (meta[i].follows && i > 0 && !deps.contains(results[i - 1].id)) deps.add(results[i - 1].id);
      if (deps.isNotEmpty) results[i] = results[i].copyWith(dependsOn: deps);
    }
    _breakDependencyCycles(results);

    return results;
  }

  // ── Sequencing: "after that" / "then" / "after I finish X" ──────────────────
  // Mirrors backend/app/services/ai_service.py. These phrases are ordering constraints, not title words.
  static const _seqAtom =
      r"(?:after\s+that|following\s+that|after\s+which|once\s+that(?:['\u2019]s|\s+is)\s+done|then)";
  static final _seqLink = RegExp(
    [
      r'(?:,\s*)?(?:\band\s+)?\b', _seqAtom, r'\b',
      r'(?:(?:\s*,\s*|\s+)(?:and\s+)?', _seqAtom, r'\b)*(?:\s*,)?\s*',
    ].join(),
    caseSensitive: false,
  );
  static const _finishPhrase = r"(?:i(?:['\u2019]m|\s+am)?\s+)?(?:finish(?:ed|ing)?|done\s+with)";
  static final _namedPredLead = RegExp(
    r'^(?:after|once|when)\s+' + _finishPhrase + r'\s+(?<x>[^,]+?)\s*,\s*(?:then\s+)?(?<y>.+)$',
    caseSensitive: false,
  );
  static final _namedPredTail = RegExp(
    r'\s*,?\s*\b(?:(?:after|once|when)\s+' + _finishPhrase + r'\s+(?<x1>.+?)|once\s+(?<x2>.+?)\s+is\s+done)\s*[.!?]*$',
    caseSensitive: false,
  );

  /// Splits a chunk on sequencing linkers. `follows` says "this segment follows the previous one".
  static List<({String text, bool follows})> _splitSequential(String chunk) {
    final segments = <({String text, bool follows})>[];
    var pos = 0;
    var follows = false;
    for (final m in _seqLink.allMatches(chunk)) {
      final seg = chunk.substring(pos, m.start).replaceAll(RegExp(r'^[ ,]+|[ ,]+$'), '');
      if (seg.isNotEmpty) segments.add((text: seg, follows: follows));
      follows = true;
      pos = m.end;
    }
    final tail = chunk.substring(pos).replaceAll(RegExp(r'^[ ,]+|[ ,]+$'), '');
    if (tail.isNotEmpty) segments.add((text: tail, follows: follows));
    return segments;
  }

  /// "After I finish X, do Y" -> "do Y after I finish X" (one form for the extractor).
  static String _normaliseLeadingNamedPredecessor(String chunk) {
    final m = _namedPredLead.firstMatch(chunk.trim());
    if (m == null || _contentWords(m.namedGroup('y')!).isEmpty) return chunk;
    return '${m.namedGroup('y')!.trim()} after I finish ${m.namedGroup('x')!.trim()}';
  }

  /// ("do Y", "X") for "do Y after I finish X" / "... when I'm done with X" / "... once X is done".
  static ({String stripped, String x})? _extractNamedPredecessor(String clause) {
    final m = _namedPredTail.firstMatch(clause);
    if (m == null) return null;
    final x = (m.namedGroup('x1') ?? m.namedGroup('x2') ?? '').trim();
    final stripped = clause.substring(0, m.start).replaceAll(RegExp(r'^[ ,]+|[ ,]+$'), '');
    if (_contentWords(x).isEmpty || _contentWords(stripped).isEmpty) return null;
    return (stripped: stripped, x: x);
  }

  /// Index of the other task whose title best overlaps the named predecessor, if any.
  static int? _matchPredecessor(String x, List<TaskItem> items, int ownIndex) {
    final wanted = _contentWords(x).toSet();
    int? best;
    var bestScore = 0;
    for (int j = 0; j < items.length; j++) {
      if (j == ownIndex) continue;
      final score = _contentWords(items[j].title).toSet().intersection(wanted).length;
      if (score > bestScore) {
        best = j;
        bestScore = score;
      }
    }
    return best;
  }

  /// Drops every dependency edge that sits on a cycle (a plan must be orderable).
  static void _breakDependencyCycles(List<TaskItem> items) {
    final byId = {for (final t in items) t.id: t};
    bool reaches(String from, String target, Set<String> seen) {
      if (!seen.add(from)) return false;
      for (final d in byId[from]?.dependsOn ?? const <String>[]) {
        if (d == target || reaches(d, target, seen)) return true;
      }
      return false;
    }

    for (int i = 0; i < items.length; i++) {
      final t = items[i];
      if (t.dependsOn.isEmpty) continue;
      final kept = t.dependsOn.where((d) => d != t.id && !reaches(d, t.id, <String>{})).toList();
      if (kept.length != t.dependsOn.length) {
        items[i] = t.copyWith(dependsOn: kept);
        byId[t.id] = items[i];
      }
    }
  }

  /// Ensures task titles are concise, natural, and user-faithful.
  /// Removes bloated filler ('to do', 'task for', 'task', redundant 'my'/'the', conversational openers).
  static String sanitizeTitle(String rawTitle) {
    if (rawTitle.trim().isEmpty) return 'Task';
    String t = rawTitle.trim();
    // Strip leading/trailing punctuation or bullet marks
    t = t.replaceAll(RegExp(r'^[,\s\-•*:]+|[,\s\-•*:]+$'), '').trim();
    // Strip conversational openers
    t = t.replaceAll(RegExp(r"^(?:i have|i've got|i need to do|i need to|i have to|on my plate:?|my tasks are:?|plan for today:?|today i have|today:?)\s+", caseSensitive: false), '').trim();
    // Strip prefixes like "task for ", "task: ", "to do: "
    t = t.replaceAll(RegExp(r'^(?:task\s+for|task\s*:|to\s*do\s*:)\s*', caseSensitive: false), '').trim();
    // Strip suffixes like " to do", " todo", " task"
    t = t.replaceAll(RegExp(r'\s+(?:to\s+do|todo|task)$', caseSensitive: false), '').trim();
    // Strip filler like 'my' or 'the' after action verbs (e.g. 'finish my assignment' -> 'Finish assignment')
    t = t.replaceAll(RegExp(r'\b(?:my|the)\s+(?=assignment|project|lab|homework|thesis|work|task|exam|quiz|session|workout)\b', caseSensitive: false), '');
    // Strip sequencing phrases ("after that", "following that"): they order tasks, they don't name them
    t = t.replaceAll(RegExp(r'^(?:after\s+that|following\s+that)\b[\s,]*', caseSensitive: false), '').trim();
    t = t.replaceAll(RegExp(r'[\s,]*\b(?:after\s+that|following\s+that)$', caseSensitive: false), '').trim();
    // Strip leading filler words ("and", "to", "go to", "also", "then", "the", "my", "maybe", "perhaps")
    t = t.replaceAll(RegExp(r'^(?:and\s+|then\s+|also\s+|maybe\s+|perhaps\s+|go\s+to\s+|to\s+|the\s+|my\s+)', caseSensitive: false), '').trim();
    // Strip trailing temporal filler ("later", "soon")
    t = t.replaceAll(RegExp(r'\s+(?:later|soon)$', caseSensitive: false), '').trim();
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

  /// (clause, follows) pairs. `follows` is set for a clause introduced by a sequencing linker
  /// ("then", "after that", "once that's done", ...).
  static List<({String text, bool follows})> _splitClausesWithLinks(String text) {
    // Strip conversational openers
    final clean = text.trim().replaceAll(RegExp(r"^(?:i have|i've got|i need to do|i need to|i have to|on my plate:?|my tasks are:?|plan for today:?|today i have|today:?)\s+", caseSensitive: false), '').trim();
    // Split on newlines, semicolons, and bullet markers ONLY.
    // Do NOT split on hyphens between word/digit chars (e.g. "9-6", "9am-5pm").
    // Regex: split on [\n;•*] or on a hyphen NOT preceded/followed by \w
    // Then split each chunk into sentences.
    final primaryChunks = clean
        .split(RegExp(r'[\n;•\*]|(?<!\w)-(?!\w)'))
        .expand((c) => c.split(RegExp(r'(?<=[.!?])\s+')))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final List<({String text, bool follows})> clauses = [];
    const actWords = r'(?:gym|workout|work|assignments?|homework|dentist|doctor|groceries|meeting|emails?)';
    const actionVerbs = r'(?:finish|study|go to|gym|workout|review|call|email|reply|buy|read|write|prep|pay|meet|clean|submit|update|complete|dentist|doctor|appointment|sync|class|lecture|groceries|errands?|pick up|drop off|walk|exercise|run|work)';

    for (var chunk in primaryChunks) {
      if (_isInstruction(chunk)) continue;
      chunk = _normaliseLeadingNamedPredecessor(chunk);
      // "finish X and then submit it" is one intention: never split it on the linker.
      final chunkHasPronounRef = RegExp(r'\b(?:and\s+(?:then\s+)?(?:submit|send|review|file)\s+it)\b', caseSensitive: false).hasMatch(chunk.toLowerCase());
      final segments = chunkHasPronounRef ? [(text: chunk, follows: false)] : _splitSequential(chunk);

      for (final segment in segments) {
        if (_isInstruction(segment.text)) continue;
        final lower = segment.text.toLowerCase().trim();

        // Task Segmentation: independently executable activities
        // e.g. "I have gym work and assignments" -> ["Gym", "Work", "Assignments"]
        // e.g. "gym work assignment" -> ["Gym", "Work", "Assignment"]
        // e.g. "gym, work, assignment" -> ["Gym", "Work", "Assignment"]
        // Preserves single outcome phrases like "finish my work assignment" or "finish my python assignment and submit it"
        final isSingleTransitiveAction = RegExp(r'^(?:finish|complete|submit|do|start|review|write|read|work on)\b', caseSensitive: false).hasMatch(lower);
        final hasPronounReference = RegExp(r'\b(?:and\s+(?:then\s+)?(?:submit|send|review|file)\s+it)\b', caseSensitive: false).hasMatch(lower);

        var parts = <String>[];
        if (!isSingleTransitiveAction && !hasPronounReference) {
          // Insert comma between adjacent standalone activities, e.g. "gym work assignment" -> "gym, work, assignment"
          var normChunk = segment.text;
          for (int r = 0; r < 3; r++) {
            normChunk = normChunk.replaceAllMapped(
              RegExp(r'\b(' + actWords + r')\s+(' + actWords + r')\b', caseSensitive: false),
              (m) => '${m[1]}, ${m[2]}',
            );
          }

          final listParts = normChunk
              .split(RegExp(r'(?:,\s*(?:and\s+)?|\s+and\s+)', caseSensitive: false))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (listParts.length > 1 && listParts.every((p) => p.length > 1)) {
            parts = listParts;
          }
        }

        if (parts.isEmpty) {
          parts = segment.text
              .split(RegExp(
                r'(?:,\s*(?:and|then|and then|also|later|maybe|perhaps)\s+|\s+(?:and then|then)\s+|,\s*(?:(?:maybe|perhaps|also|later)\s+)?(?=' + actionVerbs + r'\b)|\s+and\s+(?=' + actionVerbs + r'\b(?!\s+(?:it|them)\b))|,\s*(?=[a-zA-Z0-9_\-\s]+\b(?:at|by|for)\s+\d+))',
                caseSensitive: false,
              ))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }

        for (int k = 0; k < parts.length; k++) {
          clauses.add((text: parts[k], follows: segment.follows && k == 0));
        }
      }
    }

    // One intention -> one clause: attribute-only and back-referring parts
    // attach to the clause before them; instructions are dropped. A dependent
    // part with nothing to attach to is an orphan and is dropped.
    final List<({String text, bool follows})> units = [];
    for (final part in clauses) {
      if (_isInstruction(part.text)) continue;
      if (_isDependentFragment(part.text)) {
        if (units.isNotEmpty) {
          final joiner = RegExp(r'[.!?]$').hasMatch(units.last.text) ? ' ' : ', ';
          units[units.length - 1] = (text: '${units.last.text}$joiner${part.text}', follows: units.last.follows);
        }
        continue;
      }
      units.add(part);
    }
    return units;
  }

  // ── Conservative fallback helpers ─────────────────────────────────────────
  // Same rules as backend/app/services/ai_service.py. The fallback may
  // under-split; it must never fragment or invent.

  static const _durationUnit = r'(?:mins?|minutes?|hrs?|hours?|h)\b';

  /// "at 6 PM" / "around 6". Never a duration ("around 90 minutes") or a
  /// decimal ("around 1.5 hours").
  static final _clockTime = RegExp(
    r'\b(?:at|around)\s+(\d{1,2})(?::(\d{2}))?(?!\d)(?!\.\d)\s*(am|pm)?\b(?!\s*' + _durationUnit + r')',
    caseSensitive: false,
  );

  static final _highPriority = RegExp(
    r'\b(?:high\s+priority|p1|(?<!the\s)(?<!other\s)(?<!more\s)important|top\s+priority)\b',
    caseSensitive: false,
  );

  /// A duration phrase with its lead-in words, so removing it from a title
  /// leaves no "take around ." remnant.
  static final _durationPhrase = RegExp(
    r'(?:,\s*)?'
    r'(?:\b(?:it|this|that)\s+)?'
    r'(?:\b(?:will|should|would|might|may|could)\s+)?'
    r'(?:\b(?:probably|likely|maybe|roughly)\s+)?'
    r'(?:\b(?:take|takes|taking|spend|spending|for|lasting)\s+)?'
    r'(?:\b(?:at\s+least|at\s+most|about|around|roughly|approximately|approx\.?|maybe|probably|up\s+to)\s+)?'
    r'(?:\b\d+(?:\.\d+)?\s*(?:mins?|minutes?|m|hrs?|hours?|h)\b'
    r'|\b(?:half\s+an\s+hour|an\s+hour|one\s+hour|two\s+hours|three\s+hours|four\s+hours)\b)'
    r'(?:\s+(?:of\s+work|there|on\s+it|or\s+so))?',
    caseSensitive: false,
  );

  /// Subordinate tails that describe a task rather than name it.
  static final _titleTail = RegExp(
    r'(?:,\s*(?:which|but|preferably|ideally|so|because|since|though|although|if|when|unless)\b'
    r'|\s+(?:because|so\s+that|since|although|though|unless|but)\b'
    r"|\s+when\s+i(?:'m|\s+am)\b"
    r'|,\s*(?:it|this|that)\s+(?:will|should|may|might|can|could|would|is)\b).*$',
    caseSensitive: false,
    dotAll: true,
  );

  static final _titleOpener = RegExp(
    r'^(?:also|and|then|plus|'
    r'i\s+(?:also\s+)?(?:should|must|need\s+to|have\s+to|want\s+to|gotta|will|plan\s+to|'
    r'am\s+going\s+to|would\s+like\s+to)|'
    r"i'(?:ll|d\s+like\s+to|m\s+going\s+to)|"
    r"i\s+(?:also\s+)?have(?:\s+(?:a|an))?|i've\s+got(?:\s+(?:a|an))?|"
    r"don'?t\s+forget\s+to|remember\s+to|remind\s+me\s+to)\s+",
    caseSensitive: false,
  );

  /// A clause that cannot stand alone: it refers back to the previous task.
  static final _dependentStart = RegExp(
    r"^(?:which|it|it's|its|but|so|because|since|though|although|"
    r'preferably|ideally|hopefully|otherwise|'
    r"(?:this|that)(?:'s|\s+(?:is|will|should|can|could|may|might|would))|"
    r'(?:can|could|should|might|may|will|would|must)\s+be|'
    r"shouldn'?t|should\s+not|won'?t|can'?t|cannot|mustn'?t|must\s+not|doesn'?t|does\s+not|"
    r"i'd\s+(?:like|prefer|rather)|i\s+would\s+(?:like|prefer|rather)|"
    r'(?:i\s+)?(?:want|need)\s+to\s+do\s+(?:that|it)|do\s+(?:that|it))\b',
    caseSensitive: false,
  );

  /// Planning instructions and mood statements: context, never tasks.
  static final _instruction = RegExp(
    r"^(?:(?:don'?t|do\s+not|never)\b(?!\s+forget\b)|"
    r'avoid\s+scheduling|make\s+sure|keep\s+(?:enough|some)\b|'
    r'leave\s+(?:enough|some)\s+(?:time|buffer|gap|room)\b|'
    r'prioriti[sz]e\b|remind\s+me\s+(?:that|about\s+that)\b|'
    r'if\s+(?:something|anything|there|everything|the\s+day)\b|'
    r'(?:tomorrow|today|tonight|my\s+day|the\s+day|this\s+week)\s+'
    r'(?:is|will\s+be|is\s+going\s+to\s+be|looks|seems)\b)',
    caseSensitive: false,
  );

  static final _leadingLinker = RegExp(r'^(?:and|so|but|also|then|please)\s+', caseSensitive: false);

  static final Set<String> _nonContentWords = '''
a an the and or but so then also too just only really about around approximately approx roughly
probably maybe perhaps likely at least most for of on in by to from until till before after over
under within up it its it's this that these those there here which will would should could can
may might must shall be is are was were been being take takes taking took spend spending spent
need needs i i'm i'll i'd me my we our you min mins minute minutes hr hrs hour hours half today
tonight tomorrow morning afternoon evening night sometime later soon early earlier am pm
monday tuesday wednesday thursday friday saturday sunday high low medium normal priority urgent
important optional one two three four five
'''.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

  static const _leadingDangling = {
    'on', 'of', 'for', 'about', 'around', 'at', 'with', 'to', 'by', 'than', 'and', 'or', 'but',
    'which', 'it', 'there', 'take', 'takes', 'spend',
  };
  static const _trailingDangling = {
    'about', 'around', 'for', 'at', 'by', 'take', 'takes', 'least', 'most', 'than', 'the', 'a',
    'an', 'to', 'and', 'or', 'but', 'which', 'is', 'of', 'with', 'sometime', 'approximately',
    'roughly', 'probably', 'spend', 'in', 'on',
  };

  static List<String> _contentWords(String text) => RegExp(r"[a-z][a-z']*")
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!)
      .where((w) => w.length > 1 && !_nonContentWords.contains(w))
      .toList();

  static bool _isInstruction(String text) =>
      _instruction.hasMatch(text.trim().replaceFirst(_leadingLinker, ''));

  /// True when a clause only describes the previous task (or describes nothing).
  static bool _isDependentFragment(String text) {
    final stripped = text.trim();
    if (_dependentStart.hasMatch(stripped)) return true;
    final withoutAttrs = stripped.replaceAll(_durationPhrase, ' ').replaceAll(_clockTime, ' ');
    return _contentWords(withoutAttrs).isEmpty;
  }

  static String _stripTitleOpeners(String text) {
    var t = text.trim();
    for (int i = 0; i < 4; i++) {
      final next = t.replaceFirst(_titleOpener, '').trim();
      if (next == t) break;
      t = next;
    }
    return t;
  }

  /// The clause's naming part: first sentence, minus a descriptive tail.
  static String _titleHead(String clause) {
    var head = clause.trim().split(RegExp(r'(?<=[.!?])\s+')).first;
    head = head.replaceAll(RegExp(r'[.!?]+$'), '').trim();
    final cut = head.replaceFirst(_titleTail, '').trim();
    if (_contentWords(cut).isNotEmpty) head = cut;
    return head;
  }

  static String _repairTitle(String title) {
    var t = title.replaceAllMapped(RegExp(r'\s+([.,;:!?])'), (m) => m[1]!);
    t = t.replaceAll(RegExp(r'[,;:\s]+$'), '');
    t = t.replaceAll(RegExp(r'[.!?]+$'), '').trim();
    t = t.replaceAll(RegExp(r'\s+(?:on|at|by|in)$', caseSensitive: false), '').trim();
    return t.replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _isMalformedTitle(String title) {
    final t = title.trim();
    if (t.isEmpty || _contentWords(t).isEmpty) return true;
    if (RegExp(r'\s[.,;:!?]|[,;:]$|^[.,;:!?]').hasMatch(t)) return true;
    final words = t.replaceAll(RegExp(r'[.!?]+$'), '').toLowerCase().split(RegExp(r'\s+'));
    return _leadingDangling.contains(words.first) || _trailingDangling.contains(words.last);
  }
}
