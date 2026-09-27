import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/engines/scheduling_engine.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/services/task_parse_service.dart';

void main() {
  group('Master Repair Acceptance Tests', () {
    test('TEST 1: "I have gym work and assignments" produces 3 independent tasks', () {
      final input = "I have gym work and assignments";
      final parsed = TaskParseService.deterministicFallbackParse(input);

      expect(parsed.length, 3, reason: 'Must produce 3 independent tasks, not 1 combined task');
      final titles = parsed.map((t) => t.title.toLowerCase()).toList();
      expect(titles, contains('gym'));
      expect(titles, contains('work'));
      expect(titles, anyOf(contains('assignments'), contains('assignment')));

      // Independent types
      final gymTask = parsed.firstWhere((t) => t.title.toLowerCase().contains('gym'));
      final workTask = parsed.firstWhere((t) => t.title.toLowerCase().contains('work'));
      final assignTask = parsed.firstWhere((t) => t.title.toLowerCase().contains('assign'));

      expect(gymTask.difficulty, TaskDifficulty.physical);
      expect(workTask.difficulty, isNot(TaskDifficulty.physical));
      expect(assignTask.difficulty, isNot(TaskDifficulty.physical));

      // No invented fixed times
      expect(gymTask.scheduledTime, isNull);
      expect(workTask.scheduledTime, isNull);
      expect(assignTask.scheduledTime, isNull);

      // No invented priority
      expect(gymTask.priority, isNull);
      expect(gymTask.prioritySource, 'unspecified');
      expect(workTask.priority, isNull);
      expect(workTask.prioritySource, 'unspecified');
      expect(assignTask.priority, isNull);
      expect(assignTask.prioritySource, 'unspecified');

      // Estimated duration distinguished
      expect(gymTask.isDurationExplicit, isFalse);
      expect(workTask.isDurationExplicit, isFalse);
      expect(assignTask.isDurationExplicit, isFalse);
    });

    test('TEST 2: "gym at 6, important assignment tomorrow, work for 90 minutes" parses accurately and independently', () {
      final input = "gym at 6, important assignment tomorrow, work for 90 minutes";
      final parsed = TaskParseService.deterministicFallbackParse(input);

      expect(parsed.length, 3);
      final gymTask = parsed.firstWhere((t) => t.title.toLowerCase().contains('gym'));
      final assignTask = parsed.firstWhere((t) => t.title.toLowerCase().contains('assign'));
      final workTask = parsed.firstWhere((t) => t.title.toLowerCase().contains('work'));

      // Gym has fixed time at 6
      expect(gymTask.scheduledTime, isNotNull);
      expect(gymTask.scheduledTime, contains('6:00'));

      // Assignment has deadline tomorrow
      expect(assignTask.deadline.toLowerCase(), contains('tomorrow'));

      // Work has explicit 90 min duration
      expect(workTask.durationMinutes, 90);
      expect(workTask.isDurationExplicit, isTrue);

      // Gym and assignment durations are estimated, not explicit
      expect(gymTask.isDurationExplicit, isFalse);
    });

    test('TEST 3: Late evening (10:15 PM) scheduling does NOT invent 10:15 PM start time', () {
      final lateNight = DateTime(2026, 9, 27, 22, 15); // 10:15 PM
      const workTask = TaskItem(
        id: 't-work',
        title: 'Important work',
        category: 'Work',
        durationMinutes: 60,
        difficulty: TaskDifficulty.high,
        deadline: 'No deadline',
        taskType: TaskType.deepWork,
      );

      final rec = const SchedulingEngine().evaluateCandidateSlot(
        workTask,
        nowLocal: lateNight,
      );

      // Must be scheduled for tomorrow morning, not tonight at 10:15 PM
      expect(rec.slotStart.day, lateNight.day + 1,
          reason: 'Non-urgent deep work at 10:15 PM must be scheduled tomorrow, not tonight');
      expect(rec.slotStart.hour, inInclusiveRange(9, 11));
      expect(rec.primaryReason, 'peak_window');
    });

    test('TEST 4: Late evening (10:15 PM) with imminent deadline (tomorrow 8 AM) schedules safely tonight', () {
      final lateNight = DateTime(2026, 9, 27, 22, 15); // 10:15 PM
      final deadlineAt = DateTime(2026, 9, 28, 8, 0); // Tomorrow 8:00 AM (less than 10 hours away)
      final urgentTask = TaskItem(
        id: 't-urgent',
        title: 'Important assignment due tomorrow at 8 AM',
        category: 'Study',
        durationMinutes: 60,
        difficulty: TaskDifficulty.high,
        deadline: 'Tomorrow 8:00 AM',
        deadlineAt: deadlineAt,
        taskType: TaskType.deepWork,
      );

      final rec = const SchedulingEngine().evaluateCandidateSlot(
        urgentTask,
        nowLocal: lateNight,
      );

      // Must be scheduled tonight to beat tomorrow 8 AM deadline!
      expect(rec.slotStart.day, lateNight.day,
          reason: 'Task with tomorrow 8 AM deadline must be scheduled tonight before deadline');
      expect(rec.slotStart.isBefore(deadlineAt), isTrue);
      expect(rec.primaryReason, 'deadline_imminent');
    });

    test('Semantic preservation: "finish my Python assignment and submit it" remains ONE task', () {
      final input = "finish my Python assignment and submit it";
      final parsed = TaskParseService.deterministicFallbackParse(input);

      expect(parsed.length, 1, reason: 'Transitive action with pronoun reference must remain a single task');
      expect(parsed.first.title.toLowerCase(), contains('python assignment'));
    });

    test('Gemini Economy: simple input is routed locally with 0 AI credits', () {
      const simple1 = "gym at 6";
      const simple2 = "work on presentation for 2 hours";
      const simple3 = "meeting tomorrow at 4 PM";

      expect(TaskParseService.canParseDeterministically(simple1), isTrue);
      expect(TaskParseService.requiresAiEnrichment(simple1), isFalse);
      expect(TaskParseService.canParseDeterministically(simple2), isTrue);
      expect(TaskParseService.requiresAiEnrichment(simple2), isFalse);
      expect(TaskParseService.canParseDeterministically(simple3), isTrue);
      expect(TaskParseService.requiresAiEnrichment(simple3), isFalse);

      // Complex ambiguous input requires AI enrichment
      const complex = "I need to get my project thing handled sometime before that meeting but I'm not sure exactly how long it will take";
      expect(TaskParseService.requiresAiEnrichment(complex), isTrue);
    });

    test('Flowstate Scheduler: returns structured reason codes without calling Gemini for explanations', () {
      final now = DateTime(2026, 9, 27, 9, 0); // 9:00 AM (peak cognitive window)
      const studyTask = TaskItem(
        id: 't-study',
        title: 'Study math',
        category: 'Study',
        durationMinutes: 60,
        difficulty: TaskDifficulty.high,
        deadline: 'No deadline',
        taskType: TaskType.deepWork,
      );

      final rec = const SchedulingEngine().evaluateCandidateSlot(
        studyTask,
        nowLocal: now,
      );

      expect(rec.primaryReason, isNotEmpty);
      expect(rec.secondaryReasons, isNotEmpty);
      expect(rec.explanation, isNotEmpty);
      expect(rec.explanation.toLowerCase(), anyOf(contains('peak'), contains('focus'), contains('strongest')));
    });
  });
}
