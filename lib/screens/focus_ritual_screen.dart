import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/companion/flow_companion_animation_controller.dart';
import '../components/companion/flow_companion_view.dart';
import '../components/flow_ambient_background.dart';
import '../models/flow_companion.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/flow_provider.dart';
import '../providers/theme_provider.dart';
import '../services/focus_soundscape_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';
import 'task_feedback_sheet.dart';

/// Clean Timer Controller abstraction — avoids test-only branches in product logic.
abstract class FocusTimerController {
  int get elapsedSeconds;
  bool get isRunning;
  void start({
    required void Function(int elapsed) onTick,
    required VoidCallback onComplete,
  });
  void pause();
  void resume();
  void setElapsed(int seconds);
  void dispose();
}

class RealFocusTimerController implements FocusTimerController {
  final int targetSeconds;
  int _elapsedSeconds = 0;
  bool _isRunning = false;
  Timer? _ticker;
  void Function(int elapsed)? _onTick;
  VoidCallback? _onComplete;

  RealFocusTimerController({required this.targetSeconds});

  @override
  int get elapsedSeconds => _elapsedSeconds;

  @override
  bool get isRunning => _isRunning;

  @override
  void setElapsed(int seconds) {
    _elapsedSeconds = seconds;
    _onTick?.call(_elapsedSeconds);
  }

  @override
  void start({
    required void Function(int elapsed) onTick,
    required VoidCallback onComplete,
  }) {
    _ticker?.cancel();
    _onTick = onTick;
    _onComplete = onComplete;
    _isRunning = true;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
      _onTick?.call(_elapsedSeconds);
      if (_elapsedSeconds >= targetSeconds) {
        timer.cancel();
        _isRunning = false;
        _onComplete?.call();
      }
    });
  }

  @override
  void pause() {
    _ticker?.cancel();
    _isRunning = false;
  }

  @override
  void resume() {
    if (_isRunning) return;
    _isRunning = true;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
      _onTick?.call(_elapsedSeconds);
      if (_elapsedSeconds >= targetSeconds) {
        timer.cancel();
        _isRunning = false;
        _onComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _isRunning = false;
  }
}

class FakeFocusTimerController implements FocusTimerController {
  final int targetSeconds;
  int _elapsedSeconds = 0;
  bool _isRunning = false;
  void Function(int elapsed)? _onTick;
  VoidCallback? _onComplete;

  FakeFocusTimerController({required this.targetSeconds});

  @override
  int get elapsedSeconds => _elapsedSeconds;

  @override
  bool get isRunning => _isRunning;

  @override
  void setElapsed(int seconds) {
    _elapsedSeconds = seconds;
    _onTick?.call(_elapsedSeconds);
    if (_elapsedSeconds >= targetSeconds) {
      _isRunning = false;
      _onComplete?.call();
    }
  }

  @override
  void start({
    required void Function(int elapsed) onTick,
    required VoidCallback onComplete,
  }) {
    _onTick = onTick;
    _onComplete = onComplete;
    _isRunning = true;
  }

  @override
  void pause() {
    _isRunning = false;
  }

  @override
  void resume() {
    _isRunning = true;
  }

  @override
  void dispose() {
    _isRunning = false;
  }
}

/// Centerpiece Focus Ritual Screen.
///
/// Features:
/// - 3-2-1 animated countdown entrance
/// - High-contrast, instant-read (0.2s glanceability) MM:SS timer typography
/// - Circular radial progress surrounding Noya
/// - Event-driven Noya companion reactions (starting, focusing, milestone, celebration)
/// - Integrated soundscape coordinator (Rain, Cafe, Library, Ocean, Night, White Noise)
/// - Milestone detection (e.g. 25 min)
/// - Single economic event guarantee (no double rewarding)
/// - Post-focus feeling & reflection integration
class FocusRitualScreen extends StatefulWidget {
  final TaskItem? task;
  final int initialMinutes;
  final FocusTimerController? timerController;
  final bool skipCountdown;

  static FocusTimerController Function(int targetSeconds)? defaultTimerControllerFactory;
  static bool defaultSkipCountdown = false;

  const FocusRitualScreen({
    super.key,
    this.task,
    this.initialMinutes = 25,
    this.timerController,
    this.skipCountdown = false,
  });

  @override
  State<FocusRitualScreen> createState() => _FocusRitualScreenState();
}

class _FocusRitualScreenState extends State<FocusRitualScreen>
    with TickerProviderStateMixin {
  // Countdown phase: 3, 2, 1, 0 (active)
  int _countdownNumber = 3;
  bool _isCountingDown = true;
  Timer? _countdownTimer;

  // Session state
  late int _targetSeconds;
  int _elapsedSeconds = 0;
  bool _isRunning = false;
  bool _sessionStarted = false;
  late FocusTimerController _timerController;
  bool _milestoneTriggered = false;

  // Completion state
  bool _isComplete = false;
  bool _taskFinishedByUser = false;
  int? _xpEarned;
  int? _flowEarned;
  String? _completionRhythmNote;

  late FlowCompanionAnimationController _animController;
  final FocusSoundscapeService _soundService = FocusSoundscapeService();

  @override
  void initState() {
    super.initState();
    final targetMins = (widget.task?.durationMinutes ?? widget.initialMinutes).clamp(1, 180);
    _targetSeconds = targetMins * 60;
    _timerController = widget.timerController ??
        FocusRitualScreen.defaultTimerControllerFactory?.call(_targetSeconds) ??
        RealFocusTimerController(targetSeconds: _targetSeconds);
    _animController = FlowCompanionAnimationController();

    if (widget.skipCountdown || FocusRitualScreen.defaultSkipCountdown) {
      _beginFocusSession();
    } else {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _isCountingDown = true;
    _countdownNumber = 3;
    _animController.setStarting(taskTitle: widget.task?.title);

    _countdownTimer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      if (!mounted) return;
      FlowHaptics.lightTap();
      if (_countdownNumber > 1) {
        setState(() {
          _countdownNumber--;
        });
      } else {
        timer.cancel();
        _beginFocusSession();
      }
    });
  }

  void _skipCountdown() {
    if (!_isCountingDown) return;
    _countdownTimer?.cancel();
    _beginFocusSession();
  }

  void _beginFocusSession() {
    FlowHaptics.selection();
    setState(() {
      _isCountingDown = false;
      _isRunning = true;
      _elapsedSeconds = 0;
    });

    final task = widget.task;
    final taskTitle = task?.title;

    _animController.setFocusing(
      taskTitle: taskTitle,
      elapsedMinutes: 0,
    );

    // Coordinate with AppState and FlowProvider safely and idempotently
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sessionStarted || !mounted) return;
      _sessionStarted = true;

      try {
        final appState = Provider.of<AppStateProvider>(context, listen: false);
        if (task != null) {
          appState.setActiveFocusTask(task);
        }
      } catch (_) {}

      try {
        Provider.of<FlowProvider>(context, listen: false).startSession(
          taskId: task?.id,
          taskTitle: taskTitle,
        );
      } catch (_) {
        // Fallback in offline or test mode
      }
    });

    // Start interval ticker via FocusTimerController
    _timerController.start(
      onTick: (elapsed) {
        if (!mounted) return;
        setState(() {
          _elapsedSeconds = elapsed;
        });

        // 25-minute milestone celebration
        if (_elapsedSeconds == 25 * 60 && !_milestoneTriggered) {
          _milestoneTriggered = true;
          FlowHaptics.selection();
          _animController.triggerMilestone(25);
        }

        // Update focusing status every 5 minutes
        if (_elapsedSeconds > 0 && _elapsedSeconds % 300 == 0) {
          _animController.setFocusing(
            taskTitle: taskTitle,
            elapsedMinutes: _elapsedSeconds ~/ 60,
          );
        }
      },
      onComplete: () {
        if (mounted) {
          _completeFocusSession();
        }
      },
    );
  }

  void _togglePauseResume() {
    FlowHaptics.lightTap();
    if (_isRunning) {
      _timerController.pause();
      setState(() {
        _isRunning = false;
      });
      _animController.setState(
        CompanionAnimState.idle,
        statusText: 'Paused · Catch your breath',
      );
    } else {
      _timerController.resume();
      setState(() {
        _isRunning = true;
      });
      _animController.setFocusing(
        taskTitle: widget.task?.title,
        elapsedMinutes: _elapsedSeconds ~/ 60,
      );
    }
  }

  Future<void> _completeFocusSession() async {
    _timerController.pause();
    _soundService.stop();
    FlowHaptics.success();

    FlowProvider? flowProvider;
    AppStateProvider? appState;
    try {
      flowProvider = Provider.of<FlowProvider>(context, listen: false);
    } catch (_) {}
    try {
      appState = Provider.of<AppStateProvider>(context, listen: false);
    } catch (_) {}
    final task = widget.task;

    final elapsedMins = math.max(1, (_elapsedSeconds / 60).ceil());

    Map<String, dynamic>? result;
    try {
      if (flowProvider != null && flowProvider.isFocusing) {
        result = await flowProvider.completeSession(
          taskCompleted: task != null,
        );
      }
    } catch (_) {
      // Fallback
    }

    final xp = result?['xp_awarded'] as int? ?? (elapsedMins * 1);
    final flowPts = result?['flow_awarded'] as int? ?? (elapsedMins ~/ 5 + 2);

    // Invariant: Focus session completion is decoupled from task completion.
    // Completing a focus session rewards the session (+XP, +Flow). The task remains
    // in_progress unless the user explicitly confirms it is finished.
    if (task != null) {
      appState?.clearActiveFocusTask();
    }


    // Dynamic rhythm response from Noya
    final personalBest = flowProvider?.overview.personalBestFocusMinutes ?? 25;
    String rhythmNote = 'Noya noticed your focus rhythm. Great session!';
    if (elapsedMins >= personalBest) {
      rhythmNote = 'New Personal Best! Noya is thrilled with your endurance.';
    } else if (DateTime.now().hour >= 9 && DateTime.now().hour <= 12) {
      rhythmNote = 'You focus best around this morning window. Noya noticed.';
    }

    _animController.triggerSuccess(
      message: 'Session Complete! +$xp XP · +$flowPts Flow',
    );

    if (mounted) {
      setState(() {
        _isComplete = true;
        _isRunning = false;
        _xpEarned = xp;
        _flowEarned = flowPts;
        _completionRhythmNote = rhythmNote;
      });
    }
  }

  Future<bool> _onWillPop() async {
    if (_isComplete) return true;
    if (!_isRunning && !_isCountingDown) return true;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlowColors.surface(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
        ),
        title: Text(
          'Leave Focus Session?',
          style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)),
        ),
        content: Text(
          'Your progress for this focus ritual will be abandoned.',
          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep Focusing', style: FlowTypography.labelLarge(color: FlowColors.textSecondaryOf(context))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FlowColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (shouldLeave == true && mounted) {
      _timerController.dispose();
      _countdownTimer?.cancel();
      _soundService.stop();
      try {
        Provider.of<FlowProvider>(context, listen: false).abandonSession();
      } catch (_) {}
      try {
        Provider.of<AppStateProvider>(context, listen: false).clearActiveFocusTask();
      } catch (_) {}
      return true;
    }
    return false;
  }

  void _showSoundscapePicker() {
    FlowHaptics.lightTap();
    showModalBottomSheet(
      context: context,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: FlowSpacing.pageMargin(context),
                  vertical: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: FlowColors.border(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Focus Soundscapes',
                      style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Calm background audio to help you maintain flow.',
                      style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: SoundscapeTrack.values.map((track) {
                        final isSelected = _soundService.currentTrack == track;
                        return ChoiceChip(
                          label: Text(track.label),
                          selected: isSelected,
                          selectedColor: FlowColors.mint.withValues(alpha: 0.25),
                          side: BorderSide(
                            color: isSelected ? FlowColors.mint : FlowColors.border(context),
                          ),
                          onSelected: (_) {
                            _soundService.selectTrack(track);
                            setModalState(() {});
                            setState(() {});
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(Icons.volume_down_rounded, color: FlowColors.textSecondaryOf(context), size: 20),
                        Expanded(
                          child: Slider(
                            value: _soundService.volume,
                            activeColor: FlowColors.mint,
                            onChanged: (val) {
                              _soundService.setVolume(val);
                              setModalState(() {});
                              setState(() {});
                            },
                          ),
                        ),
                        Icon(Icons.volume_up_rounded, color: FlowColors.textSecondaryOf(context), size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _timerController.dispose();
    _animController.dispose();
    _soundService.stop();
    super.dispose();
  }

  String _formatInstantTime(int remainingSeconds) {
    final safeSeconds = math.max(0, remainingSeconds);
    final mins = (safeSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (safeSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.mint;
    try {
      accent = Provider.of<ThemeProvider>(context).resolveAccent(context);
    } catch (_) {}

    FlowCompanion companion = const FlowCompanion(id: 'noya', name: 'Noya');
    try {
      companion = Provider.of<FlowProvider>(context).companion;
    } catch (_) {}
    final remainingSeconds = _targetSeconds - _elapsedSeconds;
    final progress = _targetSeconds > 0 ? (_elapsedSeconds / _targetSeconds).clamp(0.0, 1.0) : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: FlowColors.textPrimaryOf(context),
            onPressed: () async {
              final canLeave = await _onWillPop();
              if (canLeave && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          centerTitle: true,
          title: Text(
            widget.task?.title ?? 'Focus Ritual',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                _soundService.isPlaying ? Icons.waves_rounded : Icons.music_note_outlined,
                color: _soundService.isPlaying ? FlowColors.mint : FlowColors.textSecondaryOf(context),
              ),
              tooltip: 'Focus Sounds',
              onPressed: _showSoundscapePicker,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: FlowAmbientBackground(
          visualState: OnboardingVisualState.focusActive,
          child: SafeArea(
            child: _isComplete
                ? _buildCompletionCelebration(context, accent, companion)
                : _isCountingDown
                    ? _buildCountdownOverlay(context, accent, companion)
                    : _buildActiveFocusStage(context, accent, companion, remainingSeconds, progress),
          ),
        ),
      ),
    );
  }

  /// 3-2-1 Countdown screen
  Widget _buildCountdownOverlay(
    BuildContext context,
    Color accent,
    FlowCompanion companion,
  ) {
    return GestureDetector(
      onTap: _skipCountdown,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'GET READY TO FOCUS',
              style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            FlowCompanionView(
              companion: companion,
              controller: _animController,
              size: 130,
              showStageBadge: false,
              showStatusText: false,
            ),
            const SizedBox(height: 36),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
              child: Text(
                '$_countdownNumber',
                key: ValueKey(_countdownNumber),
                style: const TextStyle(
                  fontSize: 84,
                  fontWeight: FontWeight.w900,
                  color: FlowColors.mint,
                  letterSpacing: -2,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Tap anywhere to start immediately',
              style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context).withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }

  /// Active Focus Stage with High-Contrast Instant-Read Timer
  Widget _buildActiveFocusStage(
    BuildContext context,
    Color accent,
    FlowCompanion companion,
    int remainingSeconds,
    double progress,
  ) {
    final isDark = FlowColors.isDark(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: FlowSpacing.pageMargin(context)),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: 8),

                  // Hero task title or Free Flow header
                  Text(
                    widget.task?.title ?? 'Flow',
                    style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.task != null
                        ? '${widget.task!.durationMinutes} min · ${widget.task!.importanceLabel} importance'
                        : 'Focus with Noya · Free Flow',
                    style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: 16),

                  // Noya inside radial progress circle
                  Center(
                    child: SizedBox(
                      width: 260,
                      height: 260,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Radial custom painter
                          CustomPaint(
                            size: const Size(260, 260),
                            painter: FocusRadialTimerPainter(
                              progress: progress,
                              trackColor: FlowColors.border(context).withValues(alpha: 0.35),
                              progressColor: _isRunning ? FlowColors.mint : FlowColors.warning,
                              strokeWidth: 8.0,
                            ),
                          ),
                          // Noya character
                          FlowCompanionView(
                            companion: companion,
                            controller: _animController,
                            size: 130,
                            showStageBadge: false,
                            showStatusText: false,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Status badge (Focusing / Paused)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_isRunning ? FlowColors.mint : FlowColors.warning).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(FlowRadii.pill),
                      border: Border.all(
                        color: (_isRunning ? FlowColors.mint : FlowColors.warning).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRunning ? FlowColors.mint : FlowColors.warning,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isRunning ? 'FOCUSING' : 'PAUSED',
                          style: FlowTypography.labelMedium(
                            color: _isRunning ? FlowColors.mint : FlowColors.warning,
                          ).copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.0),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // HIGH-CONTRAST INSTANT-READ MM:SS TIMER (Read in < 0.2 seconds)
                  Semantics(
                    label: '${remainingSeconds ~/ 60} minutes and ${remainingSeconds % 60} seconds remaining',
                    child: Text(
                      _formatInstantTime(remainingSeconds),
                      style: TextStyle(
                        fontFamily: 'Roboto', // Monospace-like clear digital read
                        fontSize: 60,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        color: FlowColors.textPrimaryOf(context),
                        shadows: [
                          if (isDark)
                            BoxShadow(
                              color: FlowColors.mint.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                        ],
                      ),
                    ),
                  ),

                  Text(
                    '${(_targetSeconds ~/ 60)} min target · ${(_elapsedSeconds ~/ 60)} min focused',
                    style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
                  ),

                  if (_soundService.isPlaying) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.volume_up_rounded, size: 14, color: FlowColors.mint),
                        const SizedBox(width: 4),
                        Text(
                          'Playing: ${_soundService.currentTrack.label}',
                          style: FlowTypography.labelSmall(color: FlowColors.mint),
                        ),
                      ],
                    ),
                  ],

                  const Spacer(),

                  // Bottom Action Controls
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24.0, top: 16.0),
                    child: Row(
                      children: [
                        // Pause / Resume Button
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: FlowColors.border(context)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(FlowRadii.button),
                              ),
                            ),
                            icon: Icon(
                              _isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: FlowColors.textPrimaryOf(context),
                            ),
                            label: Text(
                              _isRunning ? 'Pause' : 'Resume',
                              style: FlowTypography.labelLarge(color: FlowColors.textPrimaryOf(context)),
                            ),
                            onPressed: _togglePauseResume,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Complete Session Button
                        Expanded(
                          flex: 3,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: FlowColors.mint,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(FlowRadii.button),
                              ),
                            ),
                            icon: const Icon(Icons.check_circle_rounded, size: 20),
                            label: Text(
                              'Done',
                              style: FlowTypography.labelLarge(color: Colors.black).copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: _completeFocusSession,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Completion Celebration + XP/Flow Points Reveal + Unified Task Feedback
  Widget _buildCompletionCelebration(
    BuildContext context,
    Color accent,
    FlowCompanion companion,
  ) {
    final elapsedMinutes = math.max(1, (_elapsedSeconds / 60).ceil());

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: FlowSpacing.pageMargin(context),
        vertical: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          // Mode A vs Mode B completion header
          Text(
            widget.task != null ? 'Session Complete 🎉' : 'Flow Complete 🎉',
            style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Noya Celebration
          FlowCompanionView(
            companion: companion,
            controller: _animController,
            size: 140,
            showStageBadge: true,
            showStatusText: true,
          ),
          const SizedBox(height: 20),

          // Rewards Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: FlowColors.surfaceElevated(context),
              borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
              border: Border.all(color: FlowColors.mint.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: FlowColors.mint.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: FlowColors.mint.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(FlowRadii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt_rounded, color: FlowColors.mint, size: 20),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '+${_xpEarned ?? (elapsedMinutes * 1)} Companion XP',
                              overflow: TextOverflow.ellipsis,
                              style: FlowTypography.labelLarge(color: FlowColors.mint).copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAB308).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(FlowRadii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.stars_rounded, color: Color(0xFFEAB308), size: 20),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '+${_flowEarned ?? 10} Flow',
                              overflow: TextOverflow.ellipsis,
                              style: FlowTypography.labelLarge(color: const Color(0xFFEAB308)).copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_completionRhythmNote != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FlowColors.surface(context),
                      borderRadius: BorderRadius.circular(FlowRadii.card),
                      border: Border.all(color: FlowColors.border(context)),
                    ),
                    child: Text(
                      _completionRhythmNote!,
                      textAlign: TextAlign.center,
                      style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Explicit Task Completion Decoupling Prompt
          if (widget.task != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: FlowColors.surfaceElevated(context),
                borderRadius: BorderRadius.circular(FlowRadii.card),
                border: Border.all(color: FlowColors.border(context)),
              ),
              child: Column(
                children: [
                  Text(
                    'Finished "${widget.task!.title}"?',
                    style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)).copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            FlowHaptics.lightTap();
                            setState(() => _taskFinishedByUser = false);
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: !_taskFinishedByUser ? FlowColors.cyan.withValues(alpha: 0.12) : null,
                            side: BorderSide(
                              color: !_taskFinishedByUser ? FlowColors.cyan : FlowColors.border(context),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            'Keep in progress',
                            style: TextStyle(
                              color: !_taskFinishedByUser ? FlowColors.cyan : FlowColors.textSecondaryOf(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            FlowHaptics.success();
                            setState(() => _taskFinishedByUser = true);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _taskFinishedByUser ? FlowColors.mint : FlowColors.surface(context),
                            foregroundColor: _taskFinishedByUser ? Colors.black : FlowColors.textPrimaryOf(context),
                            elevation: 0,
                            side: BorderSide(
                              color: _taskFinishedByUser ? FlowColors.mint : FlowColors.border(context),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text(
                            'Yes, mark complete',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (widget.task == null) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.mint,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
                ),
                child: Text(
                  'Done',
                  style: FlowTypography.labelLarge(color: Colors.black).copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ] else ...[
            // Unified Post-Task Feedback
            TaskFeedbackContent(
              taskId: widget.task!.id,
              actualMinutes: elapsedMinutes,
              showHandle: false,
              onSubmit: (feedback) {
                try {
                  final appState = Provider.of<AppStateProvider>(context, listen: false);
                  appState.recordTaskFeedback(
                    taskId: widget.task!.id,
                    actualMinutes: feedback.actualMinutes,
                    feeling: feedback.feeling,
                    durationFeedback: feedback.durationFeedback,
                    blockerNote: feedback.blockerNote,
                  );
                  if (_taskFinishedByUser) {
                    appState.toggleTaskCompletion(widget.task!.id);
                  }
                } catch (_) {}
                Navigator.of(context).pop();
              },
              onDismiss: () {
                if (_taskFinishedByUser) {
                  try {
                    Provider.of<AppStateProvider>(context, listen: false).toggleTaskCompletion(widget.task!.id);
                  } catch (_) {}
                }
                Navigator.of(context).pop();
              },
            ),
          ],

        ],
      ),
    );
  }
}

/// CustomPainter for smooth circular progress timer with soft glowing arc.
class FocusRadialTimerPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  FocusRadialTimerPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    this.strokeWidth = 8.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Active progress arc
    if (progress > 0.0) {
      final activePaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2;
      final sweepAngle = 2 * math.pi * progress;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FocusRadialTimerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
