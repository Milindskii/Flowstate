import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/framer_motion_wrapper.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../services/task_parse_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'main_shell.dart';

/// Flowstate 7-Step Onboarding — Aha Moment Flow
///
/// Target: user sees their first plan within ~30–45 seconds.
///
/// Step 1 — Welcome (animated task→plan visual, CTA: Build my first day)
/// Step 2 — Brain Dump (free-text input, voice placeholder isolated)
/// Step 3 — Processing (staged text animation, auto-advances ~2.4s)
/// Step 4 — First Plan (parsed tasks, staggered reveal, inline edit)
/// Step 5 — Why (one sentence only — no dashboard)
/// Step 6 — Personalization (4 auto-advancing selectable-row questions)
/// Step 7 — Rhythm (two focus windows, CTA: Take me to Today)
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Brain dump state
  final TextEditingController _brainDumpController = TextEditingController();
  bool _isDumpValid = false;

  // Parsed candidates (from backend or demo stub)
  List<TaskItem> _parsedTasks = [];
  bool _isParsing = false;
  bool _processingComplete = false;

  // Personalization answers
  String _focusPeak = '';
  String _energyDip = '';
  String _sleepDuration = '';
  String _primaryGoal = '';
  int _personalizationSubStep = 0;

  @override
  void initState() {
    super.initState();
    _brainDumpController.addListener(() {
      final valid = _brainDumpController.text.trim().length >= 10;
      if (valid != _isDumpValid) setState(() => _isDumpValid = valid);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _brainDumpController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    if (!mounted) return;
    setState(() => _currentPage = page);
    _pageController.animateToPage(
      page,
      duration: FlowMotion.responsiveDuration(context, const Duration(milliseconds: 320)),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _startParsing() async {
    if (!_isDumpValid) return;
    FlowHaptics.lightTap();
    setState(() {
      _isParsing = true;
      _processingComplete = false;
    });
    _goToPage(2); // Go to processing screen

    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final parseService = TaskParseService(api: provider.apiService);

    try {
      final results = await parseService.parseBrainDump(
        _brainDumpController.text.trim(),
        isDemoMode: provider.isDemoMode,
      );
      if (mounted) setState(() => _parsedTasks = results);
    } catch (_) {
      if (mounted) setState(() => _parsedTasks = TaskParseService.demoFallbackTasks());
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }

    // If processing animation already finished, advance immediately
    if (_processingComplete && mounted) _goToPage(3);
  }

  void _onProcessingAnimationComplete() {
    setState(() => _processingComplete = true);
    if (!_isParsing && mounted) {
      _goToPage(3);
    }
    // else: _startParsing will advance when it finishes
  }

  void _onPersonalizationAnswer(String value) {
    FlowHaptics.selection();
    switch (_personalizationSubStep) {
      case 0: { _focusPeak = value; break; }
      case 1: { _energyDip = value; break; }
      case 2: { _sleepDuration = value; break; }
      case 3: { _primaryGoal = value; break; }
    }
    if (_personalizationSubStep < 3) {
      setState(() => _personalizationSubStep++);
    } else {
      _savePersonalizationAndContinue();
    }
  }

  void _savePersonalizationAndContinue() {
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final current = provider.personalData;

    double sleepHours = 7.5;
    if (_sleepDuration.contains('<6')) { sleepHours = 5.5; }
    else if (_sleepDuration.contains('6–7')) { sleepHours = 6.5; }
    else if (_sleepDuration.contains('8–9')) { sleepHours = 8.5; }
    else if (_sleepDuration.contains('9h+')) { sleepHours = 9.5; }

    // _energyDip maps to a time-of-day label; stored as energyDipTime for future use
    String energyDipTime = current.energyDipTime;
    if (_energyDip == 'Morning') { energyDipTime = '10:00 AM'; }
    else if (_energyDip == 'Afternoon') { energyDipTime = '2:00 PM'; }
    else if (_energyDip == 'Evening') { energyDipTime = '7:00 PM'; }

    provider.updatePersonalData(
      current.copyWith(
        focusPeak: _focusPeak.isNotEmpty ? _focusPeak : current.focusPeak,
        sleepHours: sleepHours,
        primaryGoal: _primaryGoal.isNotEmpty ? _primaryGoal : current.primaryGoal,
        energyDipTime: energyDipTime,
      ),
    );
    _goToPage(6);
  }

  void _finishOnboarding() {
    FlowHaptics.success();
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    if (_parsedTasks.isNotEmpty) {
      provider.confirmCandidates(_parsedTasks);
    }
    provider.markOnboardingComplete();

    Navigator.of(context).pushReplacement(
      FlowPageRoute.fadeUp(
        builder: (_) => const MainShell(),
        duration: const Duration(milliseconds: 280),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try { accent = Provider.of<ThemeProvider>(context).resolveAccent(context); } catch (_) {}

    return PopScope(
      canPop: _currentPage == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentPage == 5 && _personalizationSubStep > 0) {
          setState(() => _personalizationSubStep--);
        } else if (_currentPage > 0) {
          final targetPage = _currentPage == 3 ? 1 : _currentPage - 1;
          _goToPage(targetPage);
        }
      },
      child: Scaffold(
        backgroundColor: FlowColors.background(context),
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (p) => setState(() => _currentPage = p),
          children: [
            _WelcomeStep(accent: accent, onContinue: () {
              FlowHaptics.lightTap();
              _goToPage(1);
            }),
            _BrainDumpStep(
              controller: _brainDumpController,
              isValid: _isDumpValid,
              accent: accent,
              onBuild: _startParsing,
            ),
            _ProcessingStep(accent: accent, onComplete: _onProcessingAnimationComplete),
            _FirstPlanStep(
              parsedTasks: _parsedTasks,
              accent: accent,
              onConfirm: () {
                FlowHaptics.selection();
                _goToPage(4);
              },
              onTasksUpdated: (updated) => setState(() => _parsedTasks = updated),
            ),
            _WhyStep(accent: accent, onContinue: () {
              FlowHaptics.lightTap();
              _goToPage(5);
            }),
            _PersonalizationStep(
              accent: accent,
              subStep: _personalizationSubStep,
              onAnswer: _onPersonalizationAnswer,
              onSkip: _savePersonalizationAndContinue,
            ),
            _RhythmStep(accent: accent, onFinish: _finishOnboarding),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STEP 1 — WELCOME
// ─────────────────────────────────────────────────────────

class _WelcomeStep extends StatefulWidget {
  final Color accent;
  final VoidCallback onContinue;
  const _WelcomeStep({required this.accent, required this.onContinue});
  @override
  State<_WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<_WelcomeStep> with TickerProviderStateMixin {
  late final AnimationController _demoCtrl;
  late final List<Animation<double>> _fades;
  late final List<Animation<Offset>> _slides;

  @override
  void initState() {
    super.initState();
    _demoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    _fades = List.generate(3, (i) => Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _demoCtrl, curve: Interval(i * 0.20, i * 0.20 + 0.30, curve: Curves.easeOut)),
    ));
    _slides = List.generate(3, (i) => Tween<Offset>(
      begin: Offset(0.25, (i - 1) * 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _demoCtrl, curve: Interval(i * 0.20, i * 0.20 + 0.45, curve: Curves.easeOutCubic))));
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _demoCtrl.repeat(period: const Duration(seconds: 4));
    });
  }

  @override
  void dispose() { _demoCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    const tasks = ['Finish ML assignment', 'Gym at 6:00 PM', 'DBMS revision'];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(flex: 2),
            Center(
              child: SizedBox(
                height: 130,
                child: AnimatedBuilder(
                  animation: _demoCtrl,
                  builder: (_, __) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(3, (i) => FadeTransition(
                      opacity: _fades[i],
                      child: SlideTransition(
                        position: _slides[i],
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 2, height: 24,
                                decoration: BoxDecoration(
                                  color: widget.accent.withValues(alpha: i == 0 ? 1.0 : 0.4),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(tasks[i], style: FlowTypography.bodyMedium(
                                color: i == 0 ? FlowColors.textPrimaryOf(context) : FlowColors.textSecondaryOf(context),
                              ).copyWith(fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400)),
                            ],
                          ),
                        ),
                      ),
                    )),
                  ),
                ),
              ),
            ),
            const Spacer(flex: 1),
            FramerMotionFadeSlide(
              delay: const Duration(milliseconds: 200),
              child: Text('Work with your rhythm.', style: FlowTypography.displayMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            ),
            const SizedBox(height: 14),
            FramerMotionFadeSlide(
              delay: const Duration(milliseconds: 350),
              child: Text(
                'Give Flowstate your day.\nWe\'ll help you figure out what to do first.',
                style: FlowTypography.bodyLarge(color: FlowColors.textSecondaryOf(context)),
              ),
            ),
            const Spacer(flex: 2),
            FramerMotionFadeSlide(
              delay: const Duration(milliseconds: 500),
              child: Column(
                children: [
                  FramerMotionPressScale(
                    onTap: widget.onContinue,
                    child: SizedBox(
                      width: double.infinity, height: 52,
                      child: ElevatedButton(
                        onPressed: widget.onContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.accent,
                          foregroundColor: FlowColors.textInverse,
                          elevation: 0,
                          shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                        ),
                        child: Text('Build my first day', style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Already have an account? Sign in', style: FlowTypography.bodySmall(color: FlowColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STEP 2 — BRAIN DUMP
// ─────────────────────────────────────────────────────────

class _BrainDumpStep extends StatelessWidget {
  final TextEditingController controller;
  final bool isValid;
  final Color accent;
  final VoidCallback onBuild;
  const _BrainDumpStep({required this.controller, required this.isValid, required this.accent, required this.onBuild});

  void _onVoiceTap(BuildContext ctx) {
    // DEMO PLACEHOLDER — replace with real STT (e.g., speech_to_text package)
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('Voice input coming soon', style: FlowTypography.bodySmall(color: FlowColors.textPrimary)),
      backgroundColor: FlowColors.darkCardElevated,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 28,
              right: 28,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FramerMotionFadeSlide(
                      delay: Duration.zero,
                      child: Text("What's on your plate?", style: FlowTypography.displayMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                    ),
                    const SizedBox(height: 8),
                    FramerMotionFadeSlide(
                      delay: const Duration(milliseconds: 100),
                      child: Text('Just write it out. Messy is fine.', style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context))),
                    ),
                    const SizedBox(height: 24),
                    FramerMotionFadeSlide(
                      delay: const Duration(milliseconds: 180),
                      child: Container(
                        decoration: BoxDecoration(
                          color: FlowColors.surface(context),
                          borderRadius: FlowRadii.cardRadius,
                          border: Border.all(color: FlowColors.border(context), width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: FlowColors.softShadow(context),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: controller,
                              autofocus: true,
                              maxLines: 6,
                              minLines: 4,
                              style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)),
                              decoration: InputDecoration(
                                hintText: 'e.g. College from 9–4, ML assignment due tomorrow, gym at 6, study DBMS for 2 hours...',
                                hintStyle: FlowTypography.bodyMedium(color: FlowColors.textMutedOf(context)),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.all(18),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(border: Border(top: BorderSide(color: FlowColors.border(context), width: 1.0))),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  GestureDetector(
                                    onTap: () => _onVoiceTap(context),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: FlowColors.surfaceElevated(context), borderRadius: BorderRadius.circular(8)),
                                      child: Icon(Icons.mic_none_rounded, color: FlowColors.textMutedOf(context), size: 20),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: 16),
                    FramerMotionFadeSlide(
                      delay: const Duration(milliseconds: 280),
                      child: FramerMotionPressScale(
                        onTap: isValid ? onBuild : null,
                        child: SizedBox(
                          width: double.infinity, height: 52,
                          child: ElevatedButton(
                            onPressed: isValid ? onBuild : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isValid ? accent : FlowColors.border(context),
                              foregroundColor: isValid ? FlowColors.textInverse : FlowColors.textMutedOf(context),
                              elevation: 0,
                              shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                            ),
                            child: Text('Build my day', style: FlowTypography.labelLarge(color: isValid ? FlowColors.textInverse : FlowColors.textMuted).copyWith(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STEP 3 — PROCESSING (Auto-advance after ~2.4s)
// ─────────────────────────────────────────────────────────

class _ProcessingStep extends StatefulWidget {
  final Color accent;
  final VoidCallback onComplete;
  const _ProcessingStep({required this.accent, required this.onComplete});
  @override
  State<_ProcessingStep> createState() => _ProcessingStepState();
}

class _ProcessingStepState extends State<_ProcessingStep> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<Animation<double>> _stageFades;
  int _currentStage = 0;

  static const _stages = ['Understanding your tasks...', 'Finding priorities...', 'Building your day...'];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
    _stageFades = List.generate(3, (i) => Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Interval((i * 0.28).clamp(0.0, 1.0), (i * 0.28 + 0.25).clamp(0.0, 1.0), curve: Curves.easeOut)),
    ));
    _ctrl.addListener(() {
      final stage = (_ctrl.value / 0.34).floor().clamp(0, 2);
      if (stage != _currentStage && mounted) setState(() => _currentStage = stage);
    });
    _ctrl.addStatusListener((s) { if (s == AnimationStatus.completed && mounted) widget.onComplete(); });
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.background(context),
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_stages.length, (i) => FadeTransition(
              opacity: _stageFades[i],
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_stages[i], style: i == _currentStage
                  ? FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w600)
                  : FlowTypography.bodyMedium(color: FlowColors.textMutedOf(context))),
              ),
            )),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STEP 4 — FIRST PLAN
// ─────────────────────────────────────────────────────────

class _FirstPlanStep extends StatefulWidget {
  final List<TaskItem> parsedTasks;
  final Color accent;
  final VoidCallback onConfirm;
  final ValueChanged<List<TaskItem>> onTasksUpdated;
  const _FirstPlanStep({required this.parsedTasks, required this.accent, required this.onConfirm, required this.onTasksUpdated});
  @override
  State<_FirstPlanStep> createState() => _FirstPlanStepState();
}

class _FirstPlanStepState extends State<_FirstPlanStep> {
  late List<TaskItem> _tasks;
  int? _editingIndex;

  @override
  void initState() { super.initState(); _tasks = List.from(widget.parsedTasks); }
  @override
  void didUpdateWidget(_FirstPlanStep old) {
    super.didUpdateWidget(old);
    if (old.parsedTasks != widget.parsedTasks) setState(() => _tasks = List.from(widget.parsedTasks));
  }

  String _slotTime(int i) => const ['9:30', '11:00', '12:30', '2:00', '3:30', '5:30', '7:00'][i % 7];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Row(children: [
              Text('✦', style: TextStyle(color: widget.accent, fontSize: 13)),
              const SizedBox(width: 8),
              Text('Flowstate', style: FlowTypography.labelSmall(color: widget.accent).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            ]),
            const SizedBox(height: 8),
            Text('Your first plan', style: FlowTypography.displayMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(height: 4),
            Text('Tap any task to adjust.', style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))),
            const SizedBox(height: 24),
            Expanded(
              child: _tasks.isEmpty
                ? Center(child: Text('Add more detail to your brain dump and try again.', style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)), textAlign: TextAlign.center))
                : ListView.builder(
                  itemCount: _tasks.length,
                  itemBuilder: (ctx, i) => FramerMotionFadeSlide(
                    delay: Duration(milliseconds: i * 80),
                    translateY: 10,
                    child: _buildTaskRow(i, context),
                  ),
                ),
            ),
            Column(children: [
              FramerMotionPressScale(
                onTap: widget.onConfirm,
                child: SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: widget.onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accent, foregroundColor: FlowColors.textInverse,
                      elevation: 0, shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                    ),
                    child: Text('Looks good', style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  FlowHaptics.lightTap();
                  setState(() => _editingIndex = 0);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('Edit', style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskRow(int i, BuildContext context) {
    final task = _tasks[i];
    final editing = _editingIndex == i;
    return GestureDetector(
      onTap: () {
        FlowHaptics.selection();
        setState(() => _editingIndex = editing ? null : i);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 44, child: Text(_slotTime(i), style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)).copyWith(fontWeight: FontWeight.w600))),
            const SizedBox(width: 10),
            Container(
              width: 2,
              color: widget.accent.withValues(alpha: editing ? 1.0 : 0.4),
              constraints: const BoxConstraints(minHeight: 40),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title, style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${task.durationMinutes} min · ${task.taskType.label}', style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))),
                  if (editing) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: [30, 45, 60, 90, 120].map((m) {
                      final sel = task.durationMinutes == m;
                      return GestureDetector(
                        onTap: () {
                          FlowHaptics.selection();
                          final u = List<TaskItem>.from(_tasks)..[i] = task.copyWith(durationMinutes: m);
                          setState(() { _tasks = u; _editingIndex = null; });
                          widget.onTasksUpdated(u);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: sel ? widget.accent.withValues(alpha: 0.12) : FlowColors.surfaceElevated(context),
                            borderRadius: FlowRadii.pillRadius,
                            border: Border.all(color: sel ? widget.accent : FlowColors.border(context)),
                          ),
                          child: Text('$m min', style: FlowTypography.labelSmall(color: sel ? widget.accent : FlowColors.textSecondaryOf(context)).copyWith(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                        ),
                      );
                    }).toList()),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () {
                        FlowHaptics.warning();
                        final u = List<TaskItem>.from(_tasks)..removeAt(i);
                        setState(() { _tasks = u; _editingIndex = null; });
                        widget.onTasksUpdated(u);
                      },
                      child: Text('Remove', style: FlowTypography.labelSmall(color: FlowColors.critical).copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
            Icon(editing ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: FlowColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STEP 5 — WHY (one sentence only)
// ─────────────────────────────────────────────────────────

class _WhyStep extends StatelessWidget {
  final Color accent;
  final VoidCallback onContinue;
  const _WhyStep({required this.accent, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(flex: 2),
            FramerMotionFadeSlide(
              delay: Duration.zero,
              child: Text('Why this order?', style: FlowTypography.headlineLarge(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 32),
            FramerMotionFadeSlide(
              delay: const Duration(milliseconds: 150),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('✦', style: TextStyle(color: accent, fontSize: 14, height: 1.6)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your difficult work is placed in your longest uninterrupted window.',
                      style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w500, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 3),
            FramerMotionFadeSlide(
              delay: const Duration(milliseconds: 300),
              child: FramerMotionPressScale(
                onTap: onContinue,
                child: SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: onContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent, foregroundColor: FlowColors.textInverse,
                      elevation: 0, shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                    ),
                    child: Text('Makes sense', style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STEP 6 — PERSONALIZATION (selectable rows, auto-advance)
// ─────────────────────────────────────────────────────────

class _PersonalizationStep extends StatelessWidget {
  final Color accent;
  final int subStep;
  final ValueChanged<String> onAnswer;
  final VoidCallback onSkip;
  const _PersonalizationStep({required this.accent, required this.subStep, required this.onAnswer, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    const questions = [
      'When do you do your best work?',
      'When does your energy dip?',
      'How much sleep do you usually get?',
      'What are you mainly planning?',
    ];
    const answerGroups = [
      ['Morning', 'Afternoon', 'Evening', 'It depends'],
      ['Morning', 'Afternoon', 'Evening', 'It varies'],
      ['<6h', '6–7h', '7–8h', '8–9h', '9h+'],
      ['College', 'Work', 'Projects', 'Personal', 'Mixed'],
    ];
    final q = questions[subStep.clamp(0, 3)];
    final answers = answerGroups[subStep.clamp(0, 3)];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            Text('${subStep + 1} of 4', style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context))),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Align(
                key: ValueKey(subStep),
                alignment: Alignment.centerLeft,
                child: Text(q, style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 32),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Column(
                key: ValueKey(subStep),
                children: answers.map((a) => _SelectableRow(label: a, accent: accent, onTap: () => onAnswer(a))).toList(),
              ),
            ),
            const Spacer(),
            Center(
              child: GestureDetector(
                onTap: () {
                  FlowHaptics.lightTap();
                  onSkip();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text('Skip for now', style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Full-width selectable row — accent left-border on selection, no pill shape
class _SelectableRow extends StatefulWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;
  const _SelectableRow({required this.label, required this.accent, required this.onTap});
  @override
  State<_SelectableRow> createState() => _SelectableRowState();
}

class _SelectableRowState extends State<_SelectableRow> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: _pressed ? widget.accent.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: FlowRadii.cardRadius,
          border: Border(left: BorderSide(color: _pressed ? widget.accent : Colors.transparent, width: 2.5)),
        ),
        child: Text(
          widget.label,
          style: FlowTypography.bodyLarge(
            color: _pressed ? widget.accent : FlowColors.textPrimaryOf(context),
          ).copyWith(
            fontWeight: _pressed ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STEP 7 — RHYTHM
// ─────────────────────────────────────────────────────────

class _RhythmStep extends StatelessWidget {
  final Color accent;
  final VoidCallback onFinish;
  const _RhythmStep({required this.accent, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(flex: 2),
            FramerMotionFadeSlide(
              delay: Duration.zero,
              child: Text('Your first Flowstate rhythm', style: FlowTypography.headlineLarge(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 32),
            FramerMotionFadeSlide(
              delay: const Duration(milliseconds: 100),
              child: _FocusWindowRow(label: 'Strong focus', time: '9:30 AM – 11:30 AM', accent: accent),
            ),
            const SizedBox(height: 16),
            FramerMotionFadeSlide(
              delay: const Duration(milliseconds: 200),
              child: _FocusWindowRow(label: 'Light work', time: '2:00 PM – 4:00 PM', accent: accent.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 28),
            FramerMotionFadeSlide(
              delay: const Duration(milliseconds: 300),
              child: Text("We'll keep learning from how you actually work.", style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))),
            ),
            const Spacer(flex: 3),
            FramerMotionFadeSlide(
              delay: const Duration(milliseconds: 400),
              child: FramerMotionPressScale(
                onTap: onFinish,
                child: SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: onFinish,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent, foregroundColor: FlowColors.textInverse,
                      elevation: 0, shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                    ),
                    child: Text('Take me to Today', style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _FocusWindowRow extends StatelessWidget {
  final String label;
  final String time;
  final Color accent;
  const _FocusWindowRow({required this.label, required this.time, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 2, height: 40,
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(1)),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.3)),
            const SizedBox(height: 2),
            Text(time, style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}
