import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation;
import '../services/flow_clock.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_motion.dart';
import 'companion/noya_reaction_controller.dart';
import 'noya_companion_view.dart';

/// Milliseconds until a spring released at rest from −1 first reaches its target 0: the landing
/// moment of a hop driven by [spring] (independent of hop height, the system is linear).
final Map<SpringDescription, double> _landingMs = {};
double _springLandingMs(SpringDescription spring) => _landingMs.putIfAbsent(spring, () {
      final sim = SpringSimulation(spring, -1, 0, 0);
      for (var ms = 1; ms < 2000; ms++) {
        if (sim.x(ms / 1000) >= 0) return ms.toDouble();
      }
      return 2000;
    });

double _spring(SpringDescription spring, double from, double to, double elapsedMs) =>
    SpringSimulation(spring, from, to, 0).x(elapsedMs / 1000);

/// A hop: ease up to [height] over [riseMs], fall back on [spring], squash for 90 ms on landing.
/// Returns (dy, scaleX, scaleY); dy is negative upwards.
(double, double, double) _hop(double e, double height, double riseMs, SpringDescription spring,
    double squashY, double squashX) {
  if (e < 0) return (0, 1, 1);
  if (e < riseMs) return (-height * FlowMotion.easeOut.transform(e / riseMs), 1, 1);
  final fall = e - riseMs;
  final dy = _spring(spring, -height, 0, fall);
  final land = _springLandingMs(spring);
  if (fall >= land && fall <= land + 90) {
    final w = math.sin(math.pi * (fall - land) / 90);
    return (dy, 1 + squashX * w, 1 - squashY * w);
  }
  return (dy, 1, 1);
}

/// Greet sway keyframes (spec §6.5): 0 → −4° → +3° → −1.5° → 0 over 640 ms.
const List<double> _greetKeyMs = [0, 160, 320, 480, 640];
const List<double> _greetKeyDeg = [0, -4, 3, -1.5, 0];
double _greetSwayDeg(double e) {
  if (e <= 0 || e >= _greetKeyMs.last) return 0;
  var i = 0;
  while (e > _greetKeyMs[i + 1]) {
    i++;
  }
  final p = (e - _greetKeyMs[i]) / (_greetKeyMs[i + 1] - _greetKeyMs[i]);
  return _greetKeyDeg[i] + (_greetKeyDeg[i + 1] - _greetKeyDeg[i]) * FlowMotion.easeInOut.transform(p);
}

/// planReady keeps the sparkle-eyed pose this long, then settles into proud (spec §6.11).
const double _planReadyDelightedMs = 1150;

/// Sustained Noya moods (spec §5). A mood picks Noya's default pose and her (bounded) loop.
enum NoyaMood { rest, thinking, pacing, focusing, energetic, windDown, asleep }

extension NoyaMoodPose on NoyaMood {
  /// Default pose per mood (spec §5.1, §6.9 interim exercise pose).
  NoyaState get defaultPose {
    switch (this) {
      case NoyaMood.rest:
        return NoyaState.idle;
      case NoyaMood.thinking:
      case NoyaMood.pacing:
        return NoyaState.thinking;
      case NoyaMood.focusing:
        return NoyaState.focusing;
      case NoyaMood.energetic:
        return NoyaState.encouraging;
      case NoyaMood.windDown:
        return NoyaState.windDown;
      case NoyaMood.asleep:
        return NoyaState.sleepy;
    }
  }
}

/// Poses drawn on the same canvas framing as the default sit; switching between them reads as an
/// expression change, so it is a pure crossfade with no scale (spec §6.3).
const Set<NoyaState> _sameFraming = {
  NoyaState.idle,
  NoyaState.thinking,
  NoyaState.delighted,
  NoyaState.windDown,
};

/// Loops never run below this size: the motion would be sub-pixel noise (spec §17 P1).
const double _minLoopSize = 48;

/// Interim exercise bob (spec §6.9): one hop per 1.2 s, 6 hops at most.
const Duration _energeticPeriod = Duration(milliseconds: 1200);
const int _energeticCycles = 6;

/// One mood loop: its period and how many cycles fit its window (spec §10, §17 P2).
class _LoopSpec {
  final Duration period;
  final int cycles;

  const _LoopSpec(this.period, this.cycles);

  factory _LoopSpec.bounded(Duration period, Duration window) =>
      _LoopSpec(period, (window.inMilliseconds / period.inMilliseconds).ceil());

  static _LoopSpec of(NoyaMood mood) {
    switch (mood) {
      case NoyaMood.rest:
        return _LoopSpec.bounded(FlowMotion.breathPeriod, FlowMotion.idleWindow);
      case NoyaMood.thinking:
        return _LoopSpec.bounded(FlowMotion.thinkPeriod, FlowMotion.idleWindow);
      case NoyaMood.pacing:
        return _LoopSpec.bounded(FlowMotion.pacePeriod, FlowMotion.idleWindow);
      case NoyaMood.focusing:
        return _LoopSpec.bounded(FlowMotion.focusPeriod, FlowMotion.focusBobWindow);
      case NoyaMood.energetic:
        return const _LoopSpec(_energeticPeriod, _energeticCycles);
      case NoyaMood.windDown:
      case NoyaMood.asleep:
        return _LoopSpec.bounded(FlowMotion.windDownPeriod, FlowMotion.idleWindow);
    }
  }
}

/// Restarts the idle window of every [NoyaMotionView] below it when the user touches the screen
/// (spec §6.4: the breath restarts on the next interaction).
class NoyaWakeScope extends StatefulWidget {
  final Widget child;

  const NoyaWakeScope({super.key, required this.child});

  @override
  State<NoyaWakeScope> createState() => _NoyaWakeScopeState();
}

class _NoyaWakeScopeState extends State<NoyaWakeScope> {
  final ValueNotifier<int> _wakes = ValueNotifier<int>(0);

  @override
  void dispose() {
    _wakes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _wakes.value++,
      child: _NoyaWake(notifier: _wakes, child: widget.child),
    );
  }
}

class _NoyaWake extends InheritedNotifier<ValueNotifier<int>> {
  const _NoyaWake({required super.notifier, required super.child});
}

/// Noya, alive: the unchanged static [NoyaCompanionView] plus pose crossfades, a one-time entrance,
/// bounded mood loops and one-shot reactions (spec §6). At rest it renders exactly like the static
/// view (the paused test, spec §4.1).
class NoyaMotionView extends StatefulWidget {
  final NoyaMood mood;

  /// Overrides the mood's default pose (e.g. a task-resolved pose).
  final NoyaState? pose;
  final double size;

  /// Play the entrance (spec §6.1) when first mounted.
  final bool enter;
  final ValueListenable<NoyaReactionEvent?>? reactions;

  /// Maps an incoming reaction to the one this view plays, or null to ignore it.
  final NoyaReaction? Function(NoyaReaction reaction)? reactionFilter;

  /// On first build, play the current reaction if it is newer than this.
  final Duration? playRecentOnMount;
  final VoidCallback? onTap;
  final bool showAmbientGlow;
  final String? semanticLabel;

  const NoyaMotionView({
    super.key,
    this.mood = NoyaMood.rest,
    this.pose,
    this.size = NoyaSize.normal,
    this.enter = false,
    this.reactions,
    this.reactionFilter,
    this.playRecentOnMount,
    this.onTap,
    this.showAmbientGlow = false,
    this.semanticLabel,
  });

  @visibleForTesting
  static const Key transformKey = ValueKey('noya_motion_transform');
  @visibleForTesting
  static const Key fadeKey = ValueKey('noya_motion_fade');
  @visibleForTesting
  static const Key groundShadowKey = ValueKey('noya_motion_ground_shadow');
  @visibleForTesting
  static const Key glowKey = ValueKey('noya_motion_celebration_glow');

  @override
  State<NoyaMotionView> createState() => _NoyaMotionViewState();
}

class _NoyaMotionViewState extends State<NoyaMotionView> with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _loop;
  late final AnimationController _react;
  late NoyaState _shownPose;
  NoyaState? _previousPose;
  int _cyclesLeft = 0;
  bool _precached = false;
  ValueNotifier<int>? _wake;
  NoyaReaction? _reaction;
  int _lastSeenEventId = 0;

  NoyaState get _restingPose => widget.pose ?? widget.mood.defaultPose;

  /// The pose a reaction shows at this moment, or null when no reaction is playing (spec §5.2).
  NoyaState? get _reactionPose {
    switch (_reaction) {
      case null:
        return null;
      case NoyaReaction.greet:
        return NoyaState.encouraging;
      case NoyaReaction.taskDone:
        return NoyaState.proud;
      case NoyaReaction.planReady:
        return _elapsedMs < _planReadyDelightedMs ? NoyaState.delighted : NoyaState.proud;
      case NoyaReaction.celebrate:
        return NoyaState.celebrating;
      case NoyaReaction.recover:
        // Never alarming: leave the thinking pose ("?") for the calm default (spec §6.14).
        return (widget.mood == NoyaMood.thinking || widget.mood == NoyaMood.pacing) ? NoyaState.idle : _restingPose;
    }
  }

  NoyaState get _targetPose => _reactionPose ?? _restingPose;

  double get _elapsedMs => _react.value * (_react.duration?.inMilliseconds ?? 0);

  bool get _reduced => FlowMotion.isReducedMotion(context);

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync: this, value: widget.enter ? 0.0 : 1.0);
    _loop = AnimationController(vsync: this)..addStatusListener(_onLoopStatus);
    _react = AnimationController(vsync: this)
      ..addListener(_onReactionTick)
      ..addStatusListener(_onReactionStatus);
    _shownPose = _restingPose;
    _subscribe(widget.reactions, playRecent: widget.playRecentOnMount);
    _shownPose = _targetPose;
    _previousPose = null;
  }

  void _subscribe(ValueListenable<NoyaReactionEvent?>? reactions, {Duration? playRecent}) {
    reactions?.addListener(_onReactionEvent);
    final current = reactions?.value;
    // Never replay an event that happened before this view existed, unless asked to (spec §5.3).
    _lastSeenEventId = current?.id ?? 0;
    if (current != null && playRecent != null && FlowClock().now.difference(current.at) < playRecent) {
      _startReaction(current.reaction);
    }
  }

  void _onReactionEvent() {
    final event = widget.reactions?.value;
    if (event == null || event.id <= _lastSeenEventId) return;
    _lastSeenEventId = event.id;
    final filter = widget.reactionFilter;
    final reaction = filter == null ? event.reaction : filter(event.reaction);
    if (reaction == null || !mounted) return;
    setState(() => _startReaction(reaction));
  }

  void _startReaction(NoyaReaction reaction) {
    _reaction = reaction;
    _react
      ..duration = reaction.activeWindow
      ..forward(from: 0.0);
    _updatePose();
  }

  void _onReactionTick() {
    // planReady changes pose mid-reaction.
    if (_reaction == NoyaReaction.planReady && _targetPose != _shownPose) setState(_updatePose);
  }

  void _onReactionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _reaction = null;
      _react.value = 0.0;
      _updatePose();
    });
    _syncLoop(restart: true); // the idle window restarts after a reaction (spec §6.4)
  }

  void _updatePose() {
    final target = _targetPose;
    if (target != _shownPose) {
      _previousPose = _shownPose;
      _shownPose = target;
    }
  }

  /// Warm the cache for every pose this view can switch to, at display size (spec §17 P6),
  /// so a pose change never shows an undecoded frame.
  void _precacheReachablePoses() {
    if (_precached) return;
    _precached = true;
    final poses = <NoyaState>{
      _targetPose,
      if (widget.reactions != null) ...const [
        NoyaState.encouraging,
        NoyaState.proud,
        NoyaState.delighted,
        NoyaState.celebrating,
      ],
    };
    NoyaAssets.precache(context, poses, widget.size).catchError((Object _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheReachablePoses();
    if (widget.enter && _enter.value == 0.0 && !_enter.isAnimating) {
      _enter.duration = _reduced ? FlowMotion.enterFadeReduced : FlowMotion.characterEnter;
      _enter.forward();
    }
    final wake = context.dependOnInheritedWidgetOfExactType<_NoyaWake>()?.notifier;
    if (wake != _wake) {
      _wake?.removeListener(_restartLoop);
      _wake = wake?..addListener(_restartLoop);
    }
    _syncLoop(restart: false);
  }

  @override
  void didUpdateWidget(NoyaMotionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reactions != widget.reactions) {
      oldWidget.reactions?.removeListener(_onReactionEvent);
      _subscribe(widget.reactions);
    }
    _updatePose();
    if (oldWidget.mood != widget.mood || oldWidget.size != widget.size) _syncLoop(restart: true);
  }

  @override
  void dispose() {
    widget.reactions?.removeListener(_onReactionEvent);
    _wake?.removeListener(_restartLoop);
    _enter.dispose();
    _loop.dispose();
    _react.dispose();
    super.dispose();
  }

  bool get _loopAllowed => widget.size >= _minLoopSize && FlowMotion.loopsEnabled(context);

  void _restartLoop() => _syncLoop(restart: true);

  /// Starts the mood loop for a fresh window, or parks it at rest when loops are not allowed.
  void _syncLoop({required bool restart}) {
    if (!mounted) return;
    if (!_loopAllowed) {
      _cyclesLeft = 0;
      _loop
        ..stop()
        ..value = 0.0;
      return;
    }
    if (_loop.isAnimating && !restart) return;
    final spec = _LoopSpec.of(widget.mood);
    _loop.duration = spec.period;
    _cyclesLeft = spec.cycles;
    if (!_loop.isAnimating) _loop.forward(from: _loop.value >= 1.0 ? 0.0 : _loop.value);
  }

  /// Each cycle ends at rest (phase 1.0 ≡ 0.0), so stopping after the last cycle is seamless.
  void _onLoopStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _cyclesLeft--;
    if (_cyclesLeft > 0 && _loopAllowed) {
      _loop.forward(from: 0.0);
    } else {
      _loop.value = 0.0;
    }
  }

  /// Bottom-center anchored transform for the current frame (spec §6: Noya pivots on her ground).
  Matrix4 _composeTransform() {
    final m = Matrix4.identity();
    if (_reduced) return m;
    final s = widget.size;

    var tx = 0.0, ty = 0.0, rotation = 0.0, sx = 1.0, sy = 1.0;

    final e = FlowMotion.emphasized.transform(_enter.value);
    if (e < 1.0) {
      final enterScale = 0.92 + 0.08 * e;
      ty += 0.06 * s * (1 - e);
      sx *= enterScale;
      sy *= enterScale;
    }

    final t = _loop.value;
    if (t > 0.0 && t < 1.0) {
      final wave = (1 - math.cos(2 * math.pi * t)) / 2; // 0 → 1 → 0, rest at both ends
      switch (widget.mood) {
        case NoyaMood.rest:
        case NoyaMood.windDown:
        case NoyaMood.asleep:
          final k = widget.mood == NoyaMood.rest ? 1.0 : 0.8;
          sy *= 1 + 0.012 * k * wave; // volume-preserving breath (spec §6.4)
          sx *= 1 - 0.004 * k * wave;
          ty -= 0.006 * s * k * wave;
        case NoyaMood.thinking:
          rotation += 2 * math.pi / 180 * math.sin(2 * math.pi * t); // ±2° tilt (spec §6.6)
          ty -= 0.008 * s * wave;
        case NoyaMood.pacing:
          tx += math.sin(2 * math.pi * t) * 0.08 * s; // sway + step bob (spec §6.7)
          ty -= math.sin(4 * math.pi * t).abs() * 0.025 * s;
        case NoyaMood.focusing:
          ty -= 0.004 * s * wave; // "typing" micro-bob (spec §6.8)
        case NoyaMood.energetic:
          ty -= 0.02 * s * math.sin(math.pi * t); // one hop per cycle (spec §6.9)
      }
    }

    final r = _reaction;
    if (r != null) {
      final e = _elapsedMs;
      switch (r) {
        case NoyaReaction.greet:
          rotation += _greetSwayDeg(e) * math.pi / 180;
          if (e < 320) ty -= 0.03 * s * math.sin(math.pi * e / 320);
        case NoyaReaction.taskDone:
          final (dy, hx, hy) = _hop(e, 0.06 * s, 180, FlowMotion.reactionSpring, 0.03, 0.02);
          ty += dy;
          sx *= hx;
          sy *= hy;
        case NoyaReaction.planReady:
          final grow = e < 160
              ? 1 + 0.04 * FlowMotion.easeOut.transform(e / 160)
              : _spring(FlowMotion.reactionSpring, 1.04, 1.0, e - 160);
          sx *= grow;
          sy *= grow;
        case NoyaReaction.celebrate:
          final firstLand = 200 + _springLandingMs(FlowMotion.celebrationSpring) + 90;
          final (dy1, ax, ay) = _hop(e, 0.12 * s, 200, FlowMotion.celebrationSpring, 0.04, 0.03);
          final (dy2, bx, by) = _hop(e - firstLand, 0.07 * s, 200, FlowMotion.celebrationSpring, 0.04, 0.03);
          ty += e < firstLand ? dy1 : dy2;
          sx *= e < firstLand ? ax : bx;
          sy *= e < firstLand ? ay : by;
        case NoyaReaction.recover:
          ty += 0.02 * s * math.sin(math.pi * math.min(e, 500) / 500); // a small downward exhale
      }
    }

    m
      ..translateByDouble(tx, ty, 0.0, 1.0)
      ..rotateZ(rotation)
      ..scaleByDouble(sx, sy, 1.0, 1.0);
    return m;
  }

  Widget _groundShadow() {
    final s = widget.size;
    return AnimatedBuilder(
      key: NoyaMotionView.groundShadowKey,
      animation: _loop,
      builder: (context, _) {
        final t = _loop.value;
        final step = (t > 0.0 && t < 1.0) ? math.sin(4 * math.pi * t).abs() : 0.0;
        final scale = 1.0 - 0.07 * step; // the shadow tightens as Noya lifts
        return Transform.scale(
          scaleX: scale,
          scaleY: scale * 0.9,
          child: Container(
            width: 0.72 * s,
            height: 0.1 * s,
            decoration: BoxDecoration(
              color: FlowColors.softShadow(context),
              borderRadius: BorderRadius.circular(0.05 * s),
            ),
          ),
        );
      },
    );
  }

  /// The existing warm ambient gradient, faded 0 → 0.18 → 0 over the celebration (spec §6.12).
  Widget _celebrationGlow() {
    return AnimatedBuilder(
      animation: _react,
      builder: (context, _) {
        final e = _elapsedMs;
        final alpha = e < 1600 ? 0.18 * math.sin(math.pi * e / 1600) : 0.0;
        if (alpha <= 0) return const SizedBox.shrink();
        return DecoratedBox(
          key: NoyaMotionView.glowKey,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [const Color(0xFFF97316).withValues(alpha: alpha), Colors.transparent],
            ),
          ),
        );
      },
    );
  }

  Widget _poseSwitcher() {
    final reduced = _reduced;
    final previous = _previousPose;
    final pureCrossfade =
        reduced || previous == null || (_sameFraming.contains(previous) && _sameFraming.contains(_shownPose));
    return AnimatedSwitcher(
      duration: reduced ? FlowMotion.poseFadeReduced : FlowMotion.posePivot,
      switchInCurve: FlowMotion.easeInOut,
      switchOutCurve: FlowMotion.easeInOut,
      layoutBuilder: (current, previousChildren) => Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [...previousChildren, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        final isCurrent = child.key == ValueKey<NoyaState>(_shownPose);
        Widget result = FadeTransition(opacity: animation, child: child);
        if (isCurrent && !pureCrossfade) {
          result = ScaleTransition(
            alignment: Alignment.bottomCenter,
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(animation),
            child: result,
          );
        }
        // Only the incoming pose is announced; the outgoing one is purely visual (spec §18).
        // AnimatedSwitcher caches each child's transition, so read the live direction:
        // an outgoing child's animation runs in reverse.
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => ExcludeSemantics(
            excluding: animation.status == AnimationStatus.reverse,
            child: child,
          ),
          child: result,
        );
      },
      child: NoyaCompanionView(
        key: ValueKey<NoyaState>(_shownPose),
        state: _shownPose,
        size: widget.size,
        showAmbientGlow: widget.showAmbientGlow,
        semanticLabel: widget.semanticLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final character = FadeTransition(
      key: NoyaMotionView.fadeKey,
      opacity: _enter,
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _loop, _react]),
        builder: (context, child) => Transform(
          key: NoyaMotionView.transformKey,
          alignment: Alignment.bottomCenter,
          transform: _composeTransform(),
          child: child,
        ),
        child: SizedBox(width: widget.size, height: widget.size, child: _poseSwitcher()),
      ),
    );

    final celebrating = _reaction == NoyaReaction.celebrate && !_reduced;
    Widget content = RepaintBoundary(
      child: (widget.mood == NoyaMood.pacing || celebrating)
          ? Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                if (widget.mood == NoyaMood.pacing) _groundShadow(),
                if (celebrating) Positioned.fill(child: _celebrationGlow()),
                character,
              ],
            )
          : character,
    );
    if (widget.onTap != null) {
      content = GestureDetector(onTap: widget.onTap, behavior: HitTestBehavior.opaque, child: content);
    }
    return content;
  }
}
