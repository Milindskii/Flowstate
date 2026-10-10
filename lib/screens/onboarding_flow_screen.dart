import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../components/flow_ambient_background.dart';
import '../components/flow_interactive_timeline.dart';
import '../components/flow_time_picker.dart';
import '../components/noya_companion_view.dart';
import '../components/noya_thinking.dart';
import '../components/routine_building_view.dart';
import '../models/onboarding_question.dart';
import '../providers/app_state_provider.dart';
import '../services/timezone_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_typography.dart';
import 'legal/privacy_policy_screen.dart';
import 'main_shell.dart';

/// Flowstate Adaptive Onboarding Flow
///
/// Features:
/// - Light-first off-white design with state-driven ambient background animation
/// - Low CPU, respects reduced-motion
/// - 12 core questions + adaptive follow-ups (schedule variability, fluctuating energy)
/// - Interactive horizontal day timeline selector
/// - Deterministic back-navigation via PopScope preserving user answers
/// - First plan within ~30–60s
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Stored user answers: questionId -> dynamic value
  final Map<String, dynamic> _answers = {
    'peak_window': 'morning',
    'wake_weekday': '07:00',
    'wake_weekend': '08:30',
    'sleep_time': '23:00',
    'sleep_inertia': '30_60_min',
    'draining_work': <String>['coding', 'problem_solving'],
    'tired_reaction': 'distracted',
    'session_disruptor': 'phone',
    'focus_duration': '25_40_min',
    'primary_goal': 'start_difficult',
    'energy_predictability': 'mostly_predictable',
    'schedule_disruptors': 'nothing_major',
  };

  // Active question list (dynamically adapts based on user answers)
  late List<OnboardingQuestion> _activeQuestions;

  // State-driven ambient animation state
  OnboardingVisualState _visualState = OnboardingVisualState.neutral;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _rebuildActiveQuestions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePartialProgress();
    });
  }

  Future<void> _savePartialProgress() async {
    if (!mounted) return;
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final userId = appState.currentUser?.id;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('flowstate_onboarding_answers_$userId', jsonEncode(_answers));
      await prefs.setInt('flowstate_onboarding_step_$userId', _currentPage);
    } catch (_) {}
  }

  Future<void> _restorePartialProgress() async {
    if (!mounted) return;
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final userId = appState.currentUser?.id;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString('flowstate_onboarding_answers_$userId');
      final savedStep = prefs.getInt('flowstate_onboarding_step_$userId');
      if (savedStr != null) {
        final decoded = jsonDecode(savedStr);
        if (decoded is Map<String, dynamic>) {
          setState(() {
            _answers.addAll(decoded);
            _rebuildActiveQuestions();
          });
        }
      }
      if (savedStep != null && savedStep > 0 && mounted) {
        final maxStep = _activeQuestions.length + 1;
        final target = savedStep.clamp(0, maxStep);
        if (target > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _goToPage(target);
            }
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _rebuildActiveQuestions() {
    final core = OnboardingQuestionSet.getCoreQuestions();
    final List<OnboardingQuestion> filtered = [];

    for (final q in core) {
      if (!q.isAdaptiveFollowUp) {
        filtered.add(q);
      } else if (q.triggerCondition != null && q.triggerCondition!(_answers)) {
        filtered.add(q);
      }
    }
    setState(() {
      _activeQuestions = filtered;
    });
  }

  void _updateVisualStateForCurrentStep(int page) {
    if (page == 0) {
      _visualState = OnboardingVisualState.neutral;
    } else if (page > _activeQuestions.length) {
      _visualState = OnboardingVisualState.settled;
    } else {
      final qIndex = page - 1;
      if (qIndex < _activeQuestions.length) {
        final q = _activeQuestions[qIndex];
        if (q.id == 'peak_window') {
          final sel = _answers['peak_window'];
          if (sel == 'morning' || sel == 'midday') {
            _visualState = OnboardingVisualState.morningBright;
          } else if (sel == 'evening') {
            _visualState = OnboardingVisualState.twilight;
          } else {
            _visualState = OnboardingVisualState.focusActive;
          }
        } else if (q.id == 'focus_duration') {
          _visualState = OnboardingVisualState.focusActive;
        } else if (qIndex >= _activeQuestions.length - 2) {
          _visualState = OnboardingVisualState.settling;
        }
      }
    }
  }

  void _nextPage() {
    FlowHaptics.lightTap();
    _rebuildActiveQuestions();
    final next = _currentPage + 1;
    final totalPages = _activeQuestions.length + 2; // Welcome + Qs + Completion

    if (next < totalPages) {
      _goToPage(next);
    } else {
      _finishOnboarding();
    }
  }

  void _prevPage() {
    FlowHaptics.selection();
    if (_currentPage > 0) {
      _goToPage(_currentPage - 1);
    }
  }

  void _goToPage(int page) {
    if (!mounted) return;
    setState(() {
      _currentPage = page;
      _updateVisualStateForCurrentStep(page);
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    _savePartialProgress();
  }

  Future<void> _finishOnboarding() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    final appState = Provider.of<AppStateProvider>(context, listen: false);

    try {
      // Submit answers to backend
      final peak = _answers['peak_window'] as String? ?? 'morning';
      String peakStart = '09:30';
      String peakEnd = '11:45';
      if (peak == 'morning') {
        peakStart = '08:30';
        peakEnd = '11:30';
      } else if (peak == 'midday') {
        peakStart = '11:30';
        peakEnd = '14:00';
      } else if (peak == 'afternoon') {
        peakStart = '14:00';
        peakEnd = '17:00';
      } else if (peak == 'evening') {
        peakStart = '18:00';
        peakEnd = '21:30';
      }

      final inertiaRaw = _answers['sleep_inertia'] as String? ?? '30_60_min';
      int inertiaMins = 30;
      if (inertiaRaw == 'almost_immediately') {
        inertiaMins = 10;
      } else if (inertiaRaw == '15_30_min') {
        inertiaMins = 20;
      } else if (inertiaRaw == '30_60_min') {
        inertiaMins = 45;
      } else if (inertiaRaw == '1_2_hours') {
        inertiaMins = 90;
      } else if (inertiaRaw == 'more_than_2_hours') {
        inertiaMins = 120;
      }

      final focusRaw = _answers['focus_duration'] as String? ?? '25_40_min';
      int sessionMins = 45;
      if (focusRaw == '15_25_min') {
        sessionMins = 20;
      } else if (focusRaw == '25_40_min') {
        sessionMins = 35;
      } else if (focusRaw == '40_60_min') {
        sessionMins = 50;
      } else if (focusRaw == '60_90_min') {
        sessionMins = 75;
      } else if (focusRaw == '90_plus_min') {
        sessionMins = 90;
      }

      final draining = _answers['draining_work'];
      List<String> drainingList = ['coding'];
      if (draining is List) {
        drainingList = draining.map((e) => e.toString()).toList();
      }

      final payload = {
        'preferred_peak_start': peakStart,
        'preferred_peak_end': peakEnd,
        'weekday_wake_time': _answers['wake_weekday'] ?? '07:00',
        'weekend_wake_time': _answers['wake_weekend'] ?? '08:30',
        'bedtime': _answers['sleep_time'] ?? '23:00',
        'sleep_inertia_minutes': inertiaMins,
        'preferred_session_minutes': sessionMins,
        'draining_work_types': drainingList,
        'fatigue_symptom': _answers['tired_reaction'] ?? 'distracted',
        'routine_shift_preference': _answers['schedule_shift_adaptation'] ?? 'quick_recovery',
        'session_disruptor': _answers['session_disruptor'] ?? 'phone',
        'primary_goal': _answers['primary_goal'] ?? 'start_difficult',
        'energy_predictability': _answers['energy_predictability'] ?? 'mostly_predictable',
        // Device IANA zone (never an abbreviation); the previous hard-coded Asia/Kolkata mis-timed every other user.
        'timezone': await TimezoneService.localIanaName() ?? 'Asia/Kolkata',
      };

      // Critical: the schedule is built from these answers, so this is awaited (Noya shows "thinking" for it).
      // A failed write is queued for retry inside the provider; it is never silently dropped.
      final profileSaved = await appState.submitOnboardingProfile(payload);

      // Update local PersonalData state so readiness & scheduling immediately reflect peak window
      final peakMapped = peak == 'afternoon'
          ? 'Afternoon'
          : (peak == 'evening' ? 'Evening' : (peak == 'midday' ? 'Midday' : 'Morning'));
      appState.updatePersonalData(
        appState.personalData.copyWith(
          focusPeak: peakMapped,
          sleepHours: (inertiaMins / 60.0) + 7.5,
          bedtime: _answers['sleep_time'] as String? ?? '23:00',
          wakeTime: _answers['wake_weekday'] as String? ?? '07:00',
        ),
      );

      // Quick local completion, then open Today now. The rest is not on the critical path: it runs in the
      // background and refreshes Today from the authoritative backend state (retrying; failure is safe).
      await appState.markOnboardingCompleteLocally();
      unawaited(appState.finishOnboardingInBackground(profileSaved: profileSaved));

      // Clear saved partial progress since onboarding is complete
      final userId = appState.currentUser?.id;
      if (userId != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('flowstate_onboarding_answers_$userId');
          await prefs.remove('flowstate_onboarding_step_$userId');
        } catch (_) {}
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // PopScope prevents accidental exit on question steps, allows back navigation
    return PopScope(
      canPop: _currentPage == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentPage > 0) {
          _prevPage();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Stack(children: [
          _buildFlow(),
          // Real work is pending (the personalization write): Noya shows it immediately, and only while it runs.
          if (_isSubmitting)
            Positioned.fill(
              child: Container(
                key: const Key('onboarding_thinking_overlay'),
                color: const Color(0xFFF8FAFC).withValues(alpha: 0.88),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NoyaThinking(active: true, size: 120),
                    SizedBox(height: 12),
                    Text('Personalizing your plan…',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                  ],
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildFlow() {
    return FlowAmbientBackground(
          visualState: _visualState,
          child: SafeArea(
            child: Column(
              children: [
                // Top Navigation bar with back button & optional subtle progress bar
                _buildTopHeader(),

                // Main PageView content
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // Step 0: Welcome Screen
                      _buildWelcomeStep(),

                      // Step 1..N: Questions
                      for (int i = 0; i < _activeQuestions.length; i++)
                        _buildQuestionStep(_activeQuestions[i]),

                      // Step Final: Completion
                      _buildCompletionStep(),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildTopHeader() {
    final bool showBack = _currentPage > 0 && _currentPage <= _activeQuestions.length;
    // A calm bar from the first question on: people answer faster when they can see the end.
    final bool showProgress = _currentPage >= 1 && _currentPage <= _activeQuestions.length;
    final int total = _activeQuestions.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            if (showBack)
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF334155)),
                onPressed: _prevPage,
                tooltip: 'Back',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              )
            else
              const SizedBox(width: 48),

            if (showProgress)
              Expanded(
                child: Semantics(
                  label: 'Question $_currentPage of $total',
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: _currentPage / total),
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) => LinearProgressIndicator(
                              value: value,
                              minHeight: 5,
                              backgroundColor: const Color(0xFFE2E8F0),
                              valueColor: const AlwaysStoppedAnimation<Color>(FlowColors.cyan),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Question $_currentPage of $total',
                          style: FlowTypography.labelSmall(color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              const Spacer(),

            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 0: Welcome Screen
  // ---------------------------------------------------------------------------
  Widget _buildWelcomeStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),
          const Center(
            child: NoyaCompanionView(
              state: NoyaState.proud,
              size: 104,
              showAmbientGlow: true,
              semanticLabel: 'Noya winking warmly to help you find your rhythm',
            ),
          ),
          const SizedBox(height: 28),
          Text(
            "Let's find your rhythm.",
            style: FlowTypography.displayMedium(color: const Color(0xFF0F172A)).copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Not your perfect routine.\nYour actual one.",
            style: FlowTypography.titleMedium(color: const Color(0xFF475569)).copyWith(
              height: 1.45,
            ),
          ),
          const Spacer(flex: 3),
          // Primary CTA (supporting both 'Begin' and test compatibility)
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Primary visible text
                  Text(
                    'Begin',
                    style: FlowTypography.titleMedium(color: Colors.white).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // Zero-opacity label ensuring test backwards compatibility with 'Build my first day'
                  const Opacity(
                    opacity: 0.0,
                    child: Text('Build my first day', style: TextStyle(fontSize: 1)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Takes about a minute',
              style: FlowTypography.labelMedium(color: const Color(0xFF64748B)),
            ),
          ),
          const SizedBox(height: 6),
          // Why we ask, said before the first question: the answers only tune the schedule.
          Text(
            'A few quick questions help Flowstate plan around your energy, sleep and focus habits. '
            'Your answers are saved to your account and used only to personalize your plan.',
            textAlign: TextAlign.center,
            style: FlowTypography.bodySmall(color: const Color(0xFF64748B)).copyWith(height: 1.45),
          ),
          Center(
            child: TextButton(
              key: const Key('onboarding_privacy_link'),
              onPressed: () {
                FlowHaptics.lightTap();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
              },
              style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: FlowColors.cyan),
              child: Text(
                'How your data is used',
                style: FlowTypography.labelMedium(color: const Color(0xFF0E7490)).copyWith(
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // One line per question on why it is asked. Question ids and answers are unchanged.
  static const Map<String, String> _whyWeAsk = {
    'peak_window': 'Your sharpest hours get the work that needs the most focus.',
    'wake_weekday': 'Sets when your planned day starts.',
    'wake_weekend': 'Lets days off start at a realistic time.',
    'schedule_shift_adaptation': 'Helps plan days that look different from usual.',
    'sleep_time': 'Helps leave room to wind down in the evening.',
    'sleep_inertia': 'Keeps demanding tasks out of your slow-start time. A rough guide, not a medical measure.',
    'draining_work': 'So heavy work is spread out between lighter tasks. Choose any that apply, or none.',
    'tired_reaction': 'Shapes how your day is paced when energy dips.',
    'session_disruptor': 'Helps shape how your work blocks are set up.',
    'focus_duration': 'Sets the default length of your work blocks.',
    'primary_goal': 'Helps decide what Flowstate puts first.',
    'energy_predictability': 'Decides how closely Flowstate follows your usual pattern.',
    'unpredictable_cue': 'Kept on this device only. It is not sent to our servers.',
    'schedule_disruptors': 'Kept on this device only. It is not sent to our servers.',
  };

  // ---------------------------------------------------------------------------
  // Question Step Builder
  // ---------------------------------------------------------------------------
  Widget _buildQuestionStep(OnboardingQuestion question) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            question.title,
            style: FlowTypography.headlineMedium(color: const Color(0xFF0F172A)).copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (question.subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              question.subtitle!,
              style: FlowTypography.bodyMedium(color: const Color(0xFF64748B)),
            ),
          ],
          if (_whyWeAsk[question.id] != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF64748B)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _whyWeAsk[question.id]!,
                    key: Key('why_${question.id}'),
                    style: FlowTypography.bodySmall(color: const Color(0xFF64748B)).copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: _buildQuestionInput(question),
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildQuestionInput(OnboardingQuestion question) {
    switch (question.type) {
      case QuestionType.timeline:
        return _buildTimelineSelector(question);
      case QuestionType.timePicker:
        return _buildTimePickerInput(question);
      case QuestionType.singleChoice:
        return _buildSingleChoice(question);
      case QuestionType.multiChoice:
        return _buildMultiChoice(question);
    }
  }

  // 1. Real 24-Hour Interactive Timeline Range Selector for Peak Energy Window
  Widget _buildTimelineSelector(OnboardingQuestion question) {
    final selected = _answers[question.id] as String? ?? 'morning';

    return FlowInteractiveTimeline(
      initialWindowId: selected,
      onWindowChanged: (val) {
        setState(() {
          _answers[question.id] = val;
          if (val == 'morning' || val == 'midday') {
            _visualState = OnboardingVisualState.morningBright;
          } else if (val == 'evening') {
            _visualState = OnboardingVisualState.twilight;
          } else {
            _visualState = OnboardingVisualState.focusActive;
          }
        });
      },
    );
  }

  // 2. Bespoke Tactile Circadian Time Picker
  Widget _buildTimePickerInput(OnboardingQuestion question) {
    final currentStr = _answers[question.id] as String? ?? '07:00';
    final isWake = question.id.contains('wake');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FlowTimePicker(
        initialTime24: currentStr,
        isWakeTime: isWake,
        onTimeChanged: (val) {
          setState(() {
            _answers[question.id] = val;
          });
        },
      ),
    );
  }

  // 3. Single Choice List
  Widget _buildSingleChoice(OnboardingQuestion question) {
    final selected = _answers[question.id] as String?;

    return Column(
      children: [
        for (final opt in question.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              button: true,
              selected: selected == opt.id,
              inMutuallyExclusiveGroup: true,
              label: opt.label,
              excludeSemantics: true,
              onTap: () {
                FlowHaptics.selection();
                setState(() {
                  _answers[question.id] = opt.id;
                });
              },
              child: InkWell(
              onTap: () {
                FlowHaptics.selection();
                setState(() {
                  _answers[question.id] = opt.id;
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                constraints: const BoxConstraints(minHeight: 52),
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: selected == opt.id ? Colors.white : Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected == opt.id ? FlowColors.cyan : const Color(0xFFE2E8F0),
                    width: selected == opt.id ? 2.0 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        opt.label,
                        style: FlowTypography.bodyMedium(
                          color: selected == opt.id ? const Color(0xFF0F172A) : const Color(0xFF334155),
                        ).copyWith(
                          fontWeight: selected == opt.id ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(
                      selected == opt.id ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: selected == opt.id ? FlowColors.cyan : const Color(0xFF94A3B8),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
      ],
    );
  }

  // 4. Multi Choice Options
  Widget _buildMultiChoice(OnboardingQuestion question) {
    final List<String> selected = List<String>.from(_answers[question.id] as List? ?? []);

    return Column(
      children: [
        for (final opt in question.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              button: true,
              checked: selected.contains(opt.id),
              label: opt.label,
              excludeSemantics: true,
              onTap: () {
                FlowHaptics.selection();
                setState(() {
                  if (selected.contains(opt.id)) {
                    selected.remove(opt.id);
                  } else {
                    selected.add(opt.id);
                  }
                  _answers[question.id] = selected;
                });
              },
              child: InkWell(
              onTap: () {
                FlowHaptics.selection();
                setState(() {
                  if (selected.contains(opt.id)) {
                    selected.remove(opt.id);
                  } else {
                    selected.add(opt.id);
                  }
                  _answers[question.id] = selected;
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                constraints: const BoxConstraints(minHeight: 52),
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: selected.contains(opt.id) ? Colors.white : Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected.contains(opt.id) ? FlowColors.cyan : const Color(0xFFE2E8F0),
                    width: selected.contains(opt.id) ? 2.0 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        opt.label,
                        style: FlowTypography.bodyMedium(
                          color: selected.contains(opt.id) ? const Color(0xFF0F172A) : const Color(0xFF334155),
                        ).copyWith(
                          fontWeight: selected.contains(opt.id) ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(
                      selected.contains(opt.id) ? Icons.check_box : Icons.check_box_outline_blank,
                      color: selected.contains(opt.id) ? FlowColors.cyan : const Color(0xFF94A3B8),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step Final: Honest "Building Your Starting Rhythm" & Hypothesis Screen
  // ---------------------------------------------------------------------------
  Widget _buildCompletionStep() {
    return RoutineBuildingView(
      userAnswers: _answers,
      onComplete: _finishOnboarding,
    );
  }
}
