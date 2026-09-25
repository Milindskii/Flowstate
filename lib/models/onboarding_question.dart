enum QuestionType {
  timeline,
  timePicker,
  singleChoice,
  multiChoice,
}

class OnboardingOption {
  final String id;
  final String label;
  final String? subtitle;

  const OnboardingOption({
    required this.id,
    required this.label,
    this.subtitle,
  });
}

class OnboardingQuestion {
  final String id;
  final String title;
  final String? subtitle;
  final QuestionType type;
  final List<OnboardingOption> options;
  final bool isAdaptiveFollowUp;
  final bool Function(Map<String, dynamic> answers)? triggerCondition;

  const OnboardingQuestion({
    required this.id,
    required this.title,
    this.subtitle,
    required this.type,
    this.options = const [],
    this.isAdaptiveFollowUp = false,
    this.triggerCondition,
  });
}

/// Standard 12 Core Questions with Structured Adaptive Follow-ups
class OnboardingQuestionSet {
  static List<OnboardingQuestion> getCoreQuestions() {
    return [
      // 1. Interactive horizontal timeline
      const OnboardingQuestion(
        id: 'peak_window',
        title: 'When does your brain usually feel most switched on?',
        subtitle: 'Drag or select your strongest window.',
        type: QuestionType.timeline,
        options: [
          OnboardingOption(id: 'morning', label: 'Morning', subtitle: '8:30 AM – 11:30 AM'),
          OnboardingOption(id: 'midday', label: 'Midday', subtitle: '11:30 AM – 2:00 PM'),
          OnboardingOption(id: 'afternoon', label: 'Afternoon', subtitle: '2:00 PM – 5:00 PM'),
          OnboardingOption(id: 'evening', label: 'Evening', subtitle: '6:00 PM – 9:30 PM'),
        ],
      ),

      // 2. Weekday Wake time
      const OnboardingQuestion(
        id: 'wake_weekday',
        title: 'When do you usually wake up on days you have somewhere to be?',
        subtitle: 'Your baseline schedule anchor.',
        type: QuestionType.timePicker,
      ),

      // 3. Weekend Wake time
      const OnboardingQuestion(
        id: 'wake_weekend',
        title: "When do you usually wake up on days you don't?",
        subtitle: 'Helps estimate weekend schedule shifts.',
        type: QuestionType.timePicker,
      ),

      // Adaptive Follow-up: Schedule variability if difference > 1.5 hours
      OnboardingQuestion(
        id: 'schedule_shift_adaptation',
        title: 'How does your routine adapt on days with major schedule shifts?',
        subtitle: 'We noticed a notable difference between your schedules.',
        type: QuestionType.singleChoice,
        isAdaptiveFollowUp: true,
        triggerCondition: (answers) {
          final w1 = answers['wake_weekday'] as String? ?? '07:00';
          final w2 = answers['wake_weekend'] as String? ?? '07:00';
          final h1 = _parseHour(w1);
          final h2 = _parseHour(w2);
          return (h2 - h1).abs() >= 1.5;
        },
        options: const [
          OnboardingOption(id: 'quick_recovery', label: 'I adapt smoothly within a few hours'),
          OnboardingOption(id: 'slower_tempo', label: 'My morning focus shifts later in the day'),
          OnboardingOption(id: 'lighter_work', label: 'I reserve shifted days for lighter work'),
        ],
      ),

      // 4. Bedtime
      const OnboardingQuestion(
        id: 'sleep_time',
        title: 'When do you normally fall asleep?',
        subtitle: 'Used solely to calculate recovery buffer.',
        type: QuestionType.timePicker,
      ),

      // 5. Sleep inertia
      const OnboardingQuestion(
        id: 'sleep_inertia',
        title: 'How long after waking do you feel properly awake?',
        subtitle: 'Non-medical cognitive warmup window.',
        type: QuestionType.singleChoice,
        options: [
          OnboardingOption(id: 'almost_immediately', label: 'Almost immediately'),
          OnboardingOption(id: '15_30_min', label: '15–30 min'),
          OnboardingOption(id: '30_60_min', label: '30–60 min'),
          OnboardingOption(id: '1_2_hours', label: '1–2 hours'),
          OnboardingOption(id: 'more_than_2_hours', label: 'More than 2 hours'),
        ],
      ),

      // 6. Draining work types (multi-select)
      const OnboardingQuestion(
        id: 'draining_work',
        title: 'Which kind of work drains the most brain power?',
        subtitle: 'Select all that apply.',
        type: QuestionType.multiChoice,
        options: [
          OnboardingOption(id: 'coding', label: 'Coding'),
          OnboardingOption(id: 'studying', label: 'Studying / Memorization'),
          OnboardingOption(id: 'problem_solving', label: 'Problem solving'),
          OnboardingOption(id: 'writing', label: 'Writing'),
          OnboardingOption(id: 'creative', label: 'Creative work'),
          OnboardingOption(id: 'meetings', label: 'Meetings / Conversations'),
          OnboardingOption(id: 'admin', label: 'Admin'),
          OnboardingOption(id: 'planning', label: 'Planning'),
        ],
      ),

      // 7. Tired reaction
      const OnboardingQuestion(
        id: 'tired_reaction',
        title: "When you're tired, what usually happens?",
        type: QuestionType.singleChoice,
        options: [
          OnboardingOption(id: 'distracted', label: 'I get distracted'),
          OnboardingOption(id: 'procrastinate', label: 'I procrastinate'),
          OnboardingOption(id: 'slower', label: 'I work slower'),
          OnboardingOption(id: 'mistakes', label: 'I make more mistakes'),
          OnboardingOption(id: 'switch_tasks', label: 'I switch tasks'),
          OnboardingOption(id: 'can_still_work', label: 'I can still work, just slower'),
        ],
      ),

      // 8. Work session disruptors
      const OnboardingQuestion(
        id: 'session_disruptor',
        title: 'What usually ruins a good work session?',
        type: QuestionType.singleChoice,
        options: [
          OnboardingOption(id: 'phone', label: 'Phone'),
          OnboardingOption(id: 'social_media', label: 'Social media'),
          OnboardingOption(id: 'noise', label: 'Noise'),
          OnboardingOption(id: 'interruptions', label: 'Interruptions'),
          OnboardingOption(id: 'racing_thoughts', label: 'Racing thoughts'),
          OnboardingOption(id: 'too_little_time', label: 'Too little time'),
          OnboardingOption(id: 'too_difficult', label: 'Task feels too difficult'),
          OnboardingOption(id: 'dont_know_where_to_start', label: "I don't know where to start"),
          OnboardingOption(id: 'other', label: 'Other'),
        ],
      ),

      // 9. Focus duration
      const OnboardingQuestion(
        id: 'focus_duration',
        title: 'How long can you comfortably focus before you want a break?',
        type: QuestionType.singleChoice,
        options: [
          OnboardingOption(id: '15_25_min', label: '15–25 min'),
          OnboardingOption(id: '25_40_min', label: '25–40 min'),
          OnboardingOption(id: '40_60_min', label: '40–60 min'),
          OnboardingOption(id: '60_90_min', label: '60–90 min'),
          OnboardingOption(id: '90_plus_min', label: '90+ min'),
          OnboardingOption(id: 'depends', label: 'Depends on task'),
        ],
      ),

      // 10. Help goal
      const OnboardingQuestion(
        id: 'primary_goal',
        title: 'What do you want Flowstate to help you with most?',
        type: QuestionType.singleChoice,
        options: [
          OnboardingOption(id: 'start_difficult', label: 'Start difficult work'),
          OnboardingOption(id: 'stop_procrastinating', label: 'Stop procrastinating'),
          OnboardingOption(id: 'plan_my_day', label: 'Plan my day'),
          OnboardingOption(id: 'stay_focused', label: 'Stay focused'),
          OnboardingOption(id: 'use_energy_better', label: 'Use my energy better'),
          OnboardingOption(id: 'finish_on_time', label: 'Finish things on time'),
        ],
      ),

      // 11. Energy predictability
      const OnboardingQuestion(
        id: 'energy_predictability',
        title: 'How predictable is your energy from day to day?',
        type: QuestionType.singleChoice,
        options: [
          OnboardingOption(id: 'very_predictable', label: 'Very predictable'),
          OnboardingOption(id: 'mostly_predictable', label: 'Mostly predictable'),
          OnboardingOption(id: 'changes_a_lot', label: 'Changes a lot'),
          OnboardingOption(id: 'completely_unpredictable', label: 'Completely unpredictable'),
        ],
      ),

      // Adaptive Follow-up: If energy changes a lot or completely unpredictable
      OnboardingQuestion(
        id: 'unpredictable_cue',
        title: 'When your energy fluctuates, what usually predicts a good day?',
        subtitle: 'Helps calibrate early morning check-ins.',
        type: QuestionType.singleChoice,
        isAdaptiveFollowUp: true,
        triggerCondition: (answers) {
          final pred = answers['energy_predictability'] as String?;
          return pred == 'changes_a_lot' || pred == 'completely_unpredictable';
        },
        options: const [
          OnboardingOption(id: 'solid_sleep', label: 'Solid uninterrupted sleep'),
          OnboardingOption(id: 'clear_starting_task', label: 'A crystal clear first task'),
          OnboardingOption(id: 'uncluttered_morning', label: 'A quiet, unhurried morning'),
        ],
      ),

      // 12. Schedule disruptors
      const OnboardingQuestion(
        id: 'schedule_disruptors',
        title: 'What regularly changes your schedule?',
        type: QuestionType.singleChoice,
        options: [
          OnboardingOption(id: 'college', label: 'College'),
          OnboardingOption(id: 'work_shifts', label: 'Work shifts'),
          OnboardingOption(id: 'commute', label: 'Commute'),
          OnboardingOption(id: 'gym_sports', label: 'Gym / sports'),
          OnboardingOption(id: 'family', label: 'Family responsibilities'),
          OnboardingOption(id: 'irregular_sleep', label: 'Irregular sleep'),
          OnboardingOption(id: 'nothing_major', label: 'Nothing major'),
        ],
      ),
    ];
  }

  static double _parseHour(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return int.parse(parts[0]) + int.parse(parts[1]) / 60.0;
    } catch (_) {
      return 7.0;
    }
  }
}
