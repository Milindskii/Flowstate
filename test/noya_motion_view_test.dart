import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/components/companion/noya_reaction_controller.dart';
import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/noya_motion_view.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/theme/flow_motion.dart';

Widget _host(Widget child, {bool loops = false, bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: FlowMotionScope(loopsEnabled: loops, child: Scaffold(body: Center(child: child))),
      ),
    );

Matrix4 _motionTransform(WidgetTester tester) =>
    tester.widget<Transform>(find.byKey(NoyaMotionView.transformKey)).transform;

double _motionOpacity(WidgetTester tester) =>
    tester.widget<FadeTransition>(find.byKey(NoyaMotionView.fadeKey)).opacity.value;

List<NoyaState> _shownPoses(WidgetTester tester) =>
    tester.widgetList<NoyaCompanionView>(find.byType(NoyaCompanionView)).map((v) => v.state).toList();

void main() {
  group('Task 7: pose crossfade, enter (spec §6.1, §6.3)', () {
    testWidgets('mood maps to its default pose', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.thinking, size: 76)));
      expect(_shownPoses(tester), [NoyaState.thinking]);
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.asleep, size: 76)));
      await tester.pumpAndSettle();
      expect(_shownPoses(tester), [NoyaState.sleepy]);
    });

    testWidgets('pose override wins over the mood default', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(pose: NoyaState.proud, size: 76)));
      expect(_shownPoses(tester), [NoyaState.proud]);
    });

    testWidgets('pose change crossfades over 260 ms', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(size: 76)));
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.thinking, size: 76)));
      await tester.pump(const Duration(milliseconds: 130));
      expect(find.byType(NoyaCompanionView), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();
      expect(_shownPoses(tester), [NoyaState.thinking]);
    });

    testWidgets('outgoing pose is excluded from semantics mid-crossfade', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const NoyaMotionView(size: 76)));
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.thinking, size: 76)));
      await tester.pump(const Duration(milliseconds: 130));
      // Query the live semantics tree (find.bySemanticsLabel reads possibly stale per-object nodes).
      expect(find.semantics.byLabel(NoyaState.idle.semanticLabel), findsNothing);
      expect(find.semantics.byLabel(NoyaState.thinking.semanticLabel), findsOne);
      handle.dispose();
    });

    testWidgets('different-framing pose change scales the incoming pose 0.97 → 1', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(size: 76)));
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.focusing, size: 76)));
      await tester.pump(const Duration(milliseconds: 40));
      final scales = tester.widgetList<ScaleTransition>(
        find.descendant(of: find.byType(NoyaMotionView), matching: find.byType(ScaleTransition)),
      );
      expect(scales.any((s) => s.scale.value >= 0.97 && s.scale.value < 1.0), isTrue);
    });

    testWidgets('reduced motion: pose change is a 120 ms fade with no scale', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(size: 76), reduced: true));
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.focusing, size: 76), reduced: true));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(NoyaCompanionView), findsNWidgets(2));
      final scales = tester.widgetList<ScaleTransition>(
        find.descendant(of: find.byType(NoyaMotionView), matching: find.byType(ScaleTransition)),
      );
      expect(scales.where((s) => s.scale.value != 1.0), isEmpty);
      await tester.pump(const Duration(milliseconds: 70));
      await tester.pump();
      expect(_shownPoses(tester), [NoyaState.focusing]);
    });

    testWidgets('enter: true fades in over 420 ms', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(size: 76, enter: true)));
      expect(_motionOpacity(tester), 0.0);
      await tester.pump(const Duration(milliseconds: 420));
      expect(_motionOpacity(tester), greaterThan(0.9));
      await tester.pumpAndSettle();
      expect(_motionOpacity(tester), 1.0);
      expect(_motionTransform(tester), Matrix4.identity());
    });

    testWidgets('enter: false is fully opaque on the first frame', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(size: 76)));
      expect(_motionOpacity(tester), 1.0);
    });

    testWidgets('reduced motion enter is a 150 ms fade without transform', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(size: 76, enter: true), reduced: true));
      await tester.pump(const Duration(milliseconds: 75));
      expect(_motionOpacity(tester), inExclusiveRange(0.0, 1.0));
      expect(_motionTransform(tester), Matrix4.identity());
      await tester.pump(const Duration(milliseconds: 80));
      expect(_motionOpacity(tester), 1.0);
    });

    testWidgets('paused frame equals the static view', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(size: 76)));
      await tester.pumpAndSettle();
      expect(_motionTransform(tester), Matrix4.identity());
      expect(_motionOpacity(tester), 1.0);
      expect(_shownPoses(tester), [NoyaState.idle]);
    });
  });

  group('Task 8: bounded mood loops (spec §6.4, §6.6–§6.9, §6.13, §17)', () {
    const s = 76.0;
    double rotationDeg(Matrix4 m) => math.atan2(m.entry(1, 0), m.entry(0, 0)) * 180 / math.pi;

    Future<void> pumpFor(WidgetTester tester, Duration total, {Duration step = const Duration(milliseconds: 100)}) async {
      var elapsed = Duration.zero;
      while (elapsed < total) {
        await tester.pump(step);
        elapsed += step;
      }
    }

    testWidgets('rest breath runs, then stops at rest after idleWindow', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(size: s), loops: true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(_motionTransform(tester), isNot(Matrix4.identity()));
      await pumpFor(tester, const Duration(seconds: 32), step: const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(_motionTransform(tester), Matrix4.identity());
    });

    testWidgets('breath stays within 1.2% scale and 0.006*s rise', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(size: s), loops: true));
      var maxScaleY = 1.0, maxRise = 0.0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final m = _motionTransform(tester);
        maxScaleY = math.max(maxScaleY, m.entry(1, 1));
        maxRise = math.max(maxRise, -m.getTranslation().y);
      }
      expect(maxScaleY, inInclusiveRange(1.01, 1.0121));
      expect(maxRise, lessThanOrEqualTo(0.006 * s + 1e-9));
    });

    testWidgets('pointer down inside NoyaWakeScope restarts the window', (tester) async {
      await tester.pumpWidget(_host(
        const NoyaWakeScope(child: SizedBox(width: 300, height: 300, child: Center(child: NoyaMotionView(size: s)))),
        loops: true,
      ));
      await pumpFor(tester, const Duration(seconds: 32), step: const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.tapAt(tester.getCenter(find.byType(NoyaWakeScope)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('no loop below 48 px', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(size: 40), loops: true));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('TickerMode disabled stops the loop', (tester) async {
      await tester.pumpWidget(_host(const TickerMode(enabled: false, child: NoyaMotionView(size: s)), loops: true));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('thinking loop tilts within 2 degrees', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.thinking, size: s), loops: true));
      var maxTilt = 0.0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        maxTilt = math.max(maxTilt, rotationDeg(_motionTransform(tester)).abs());
      }
      expect(maxTilt, greaterThan(1.5));
      expect(maxTilt, lessThanOrEqualTo(2.0 + 1e-6));
    });

    testWidgets('pacing sways within 0.08*s and shows a ground shadow', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.pacing, size: s), loops: true));
      expect(find.byKey(NoyaMotionView.groundShadowKey), findsOneWidget);
      var maxSway = 0.0;
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        maxSway = math.max(maxSway, _motionTransform(tester).getTranslation().x.abs());
      }
      expect(maxSway, greaterThan(0.07 * s));
      expect(maxSway, lessThanOrEqualTo(0.08 * s + 1e-9));
    });

    testWidgets('no ground shadow outside pacing', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.thinking, size: s), loops: true));
      expect(find.byKey(NoyaMotionView.groundShadowKey), findsNothing);
    });

    testWidgets('focusing bob stops after focusBobWindow (20 s)', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.focusing, size: s), loops: true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await pumpFor(tester, const Duration(seconds: 22), step: const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(_motionTransform(tester), Matrix4.identity());
    });

    testWidgets('energetic bob stays within 0.02*s and stops after 6 cycles', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.energetic, size: s), loops: true));
      var maxRise = 0.0;
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        maxRise = math.max(maxRise, -_motionTransform(tester).getTranslation().y);
      }
      expect(maxRise, greaterThan(0.015 * s));
      expect(maxRise, lessThanOrEqualTo(0.02 * s + 1e-9));
      await pumpFor(tester, const Duration(milliseconds: 6600));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('wind-down breath is softer than rest (x0.8)', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(mood: NoyaMood.windDown, size: s), loops: true));
      var maxScaleY = 1.0;
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        maxScaleY = math.max(maxScaleY, _motionTransform(tester).entry(1, 1));
      }
      expect(maxScaleY, inInclusiveRange(1.009, 1.0097));
    });

    testWidgets('reduced motion turned on mid-loop stops at rest on the next frame', (tester) async {
      await tester.pumpWidget(_host(const NoyaMotionView(size: s), loops: true));
      await tester.pump(const Duration(milliseconds: 900));
      expect(_motionTransform(tester), isNot(Matrix4.identity()));
      await tester.pumpWidget(_host(const NoyaMotionView(size: s), loops: true, reduced: true));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_motionTransform(tester), Matrix4.identity());
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('Task 9: reactions (spec §5.2–§5.3, §6.5, §6.10–§6.12, §6.14)', () {
    const s = 76.0;
    double rotationDeg(Matrix4 m) => math.atan2(m.entry(1, 0), m.entry(0, 0)) * 180 / math.pi;
    NoyaState currentPose(WidgetTester tester) => tester
        .widgetList<NoyaCompanionView>(find.descendant(
          of: find.byType(NoyaMotionView),
          matching: find.byType(NoyaCompanionView),
        ))
        .last
        .state;

    late NoyaReactionController reactions;
    setUp(() {
      // Same as other suites: FlowClock's singleton otherwise starts a periodic auto-tick timer.
      FlowClock.enableAutoTick = false;
      FlowClock().stopTimer();
      reactions = NoyaReactionController();
    });
    tearDown(() {
      reactions.dispose();
      FlowClock().stopTimer();
    });

    Widget view({NoyaMood mood = NoyaMood.rest, bool reduced = false, NoyaReaction? Function(NoyaReaction)? filter}) =>
        _host(NoyaMotionView(mood: mood, size: s, reactions: reactions, reactionFilter: filter), reduced: reduced);

    testWidgets('greet sways, waves and returns to the mood pose', (tester) async {
      await tester.pumpWidget(view());
      reactions.react(NoyaReaction.greet);
      await tester.pump();
      var maxTilt = 0.0;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        maxTilt = math.max(maxTilt, rotationDeg(_motionTransform(tester)).abs());
      }
      expect(currentPose(tester), NoyaState.encouraging);
      expect(maxTilt, greaterThan(1.0));
      expect(maxTilt, lessThanOrEqualTo(4.0 + 1e-6));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(rotationDeg(_motionTransform(tester)), closeTo(0, 1e-9));
      await tester.pumpAndSettle();
      expect(_shownPoses(tester), [NoyaState.idle]);
    });

    testWidgets('taskDone shows proud and hops at most 0.06*s', (tester) async {
      await tester.pumpWidget(view());
      reactions.react(NoyaReaction.taskDone);
      await tester.pump();
      var maxRise = 0.0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        maxRise = math.max(maxRise, -_motionTransform(tester).getTranslation().y);
      }
      expect(currentPose(tester), NoyaState.proud);
      expect(maxRise, greaterThan(0.05 * s));
      expect(maxRise, lessThanOrEqualTo(0.06 * s * 1.04));
      await tester.pumpAndSettle();
      expect(_motionTransform(tester), Matrix4.identity());
    });

    testWidgets('planReady shows delighted, then proud', (tester) async {
      await tester.pumpWidget(view(mood: NoyaMood.thinking));
      reactions.react(NoyaReaction.planReady);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(currentPose(tester), NoyaState.delighted);
      await tester.pump(const Duration(milliseconds: 900));
      expect(currentPose(tester), NoyaState.proud);
    });

    testWidgets('celebrate hops at most 0.12*s, glows, and settles by 3.1 s', (tester) async {
      await tester.pumpWidget(view());
      reactions.react(NoyaReaction.celebrate);
      await tester.pump();
      var maxRise = 0.0;
      var sawGlow = false;
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        maxRise = math.max(maxRise, -_motionTransform(tester).getTranslation().y);
        sawGlow = sawGlow || find.byKey(NoyaMotionView.glowKey).evaluate().isNotEmpty;
      }
      expect(currentPose(tester), NoyaState.celebrating);
      expect(sawGlow, isTrue);
      expect(maxRise, greaterThan(0.1 * s));
      expect(maxRise, lessThanOrEqualTo(0.12 * s * 1.04));
      // The controller reports completion on the first frame after its 3,100 ms duration.
      await tester.pump(const Duration(milliseconds: 1520));
      expect(_motionTransform(tester), Matrix4.identity());
      expect(find.byKey(NoyaMotionView.glowKey), findsNothing);
    });

    testWidgets('recover never rotates, settles within 500 ms, and leaves thinking for idle', (tester) async {
      await tester.pumpWidget(view(mood: NoyaMood.thinking));
      reactions.react(NoyaReaction.recover);
      await tester.pump();
      var maxTilt = 0.0;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        maxTilt = math.max(maxTilt, rotationDeg(_motionTransform(tester)).abs());
        if (i == 5) expect(currentPose(tester), NoyaState.idle); // during the 500 ms reaction
      }
      expect(maxTilt, 0.0);
      await tester.pump(const Duration(milliseconds: 20));
      expect(_motionTransform(tester), Matrix4.identity());
    });

    testWidgets('reduced motion: reactions are pose crossfades only', (tester) async {
      await tester.pumpWidget(view(reduced: true));
      reactions.react(NoyaReaction.celebrate);
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(_motionTransform(tester), Matrix4.identity());
      }
      expect(currentPose(tester), NoyaState.celebrating);
      expect(find.byKey(NoyaMotionView.glowKey), findsNothing);
    });

    testWidgets('reactionFilter can downgrade or ignore', (tester) async {
      await tester.pumpWidget(view(filter: (r) => r == NoyaReaction.celebrate ? NoyaReaction.taskDone : null));
      reactions.react(NoyaReaction.celebrate);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(currentPose(tester), NoyaState.proud);
      await tester.pumpAndSettle();
      reactions.react(NoyaReaction.recover);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_shownPoses(tester), [NoyaState.idle]);
    });

    testWidgets('playRecentOnMount plays a fresh event and ignores a stale one', (tester) async {
      reactions.react(NoyaReaction.greet);
      await tester.pumpWidget(_host(NoyaMotionView(
        size: s, reactions: reactions, playRecentOnMount: const Duration(seconds: 2))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(currentPose(tester), NoyaState.encouraging);
      await tester.pumpAndSettle();

      final stale = NoyaReactionController(clock: () => DateTime.now().subtract(const Duration(seconds: 10)));
      addTearDown(stale.dispose);
      stale.react(NoyaReaction.greet);
      await tester.pumpWidget(_host(NoyaMotionView(
        key: const ValueKey('fresh'), size: s, reactions: stale, playRecentOnMount: const Duration(seconds: 2))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_shownPoses(tester), [NoyaState.idle]);
    });

    testWidgets('without playRecentOnMount an existing event is never replayed on mount', (tester) async {
      reactions.react(NoyaReaction.greet);
      await tester.pumpWidget(view());
      await tester.pump(const Duration(milliseconds: 300));
      expect(_shownPoses(tester), [NoyaState.idle]);
    });

    testWidgets('dispose mid-reaction throws nothing and a remount does not replay', (tester) async {
      await tester.pumpWidget(view());
      reactions.react(NoyaReaction.celebrate);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(view());
      await tester.pump(const Duration(milliseconds: 300));
      expect(_shownPoses(tester), [NoyaState.idle]);
    });
  });
}
