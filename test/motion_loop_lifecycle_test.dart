import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/components/companion/flow_companion_animation_controller.dart';
import 'package:flowstate/components/companion/flow_companion_view.dart';
import 'package:flowstate/components/flow_ambient_background.dart';
import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/noya_motion_view.dart';
import 'package:flowstate/models/flow_companion.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/theme/flow_motion.dart';

Widget _app(Widget child, {bool loops = true}) => MaterialApp(
      home: FlowMotionScope(loopsEnabled: loops, child: Scaffold(body: Center(child: child))),
    );

void main() {
  const companion = FlowCompanion(id: 'c1', name: 'Noya');

  // Same as other suites: FlowClock's singleton otherwise starts a periodic auto-tick timer
  // (reached here through the reaction controller's default clock).
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
  });
  tearDown(() => FlowClock().stopTimer());

  group('FlowCompanionView loop lifecycle (spec §6.4, §6.8, §17 P2)', () {
    Future<void> pumpFor(WidgetTester tester, Duration total) async {
      for (var t = Duration.zero; t < total; t += const Duration(milliseconds: 500)) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    testWidgets('idle breath is bounded: no frames after idleWindow even with loops enabled', (tester) async {
      final controller = FlowCompanionAnimationController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(FlowCompanionView(companion: companion, controller: controller)));
      await pumpFor(tester, const Duration(seconds: 32));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('focusing bob runs, then stops after focusBobWindow (20 s)', (tester) async {
      final controller = FlowCompanionAnimationController()..setFocusing();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(FlowCompanionView(companion: companion, controller: controller)));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(tester.widget<NoyaMotionView>(find.byType(NoyaMotionView)).mood, NoyaMood.focusing);
      await pumpFor(tester, const Duration(seconds: 22));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the old scale pulse is gone: no Transform.scale wraps the companion card', (tester) async {
      final controller = FlowCompanionAnimationController()..setFocusing();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(FlowCompanionView(companion: companion, controller: controller)));
      await tester.pump(const Duration(milliseconds: 600));
      final scaled = tester.widgetList<Transform>(find.ancestor(
        of: find.byType(NoyaMotionView),
        matching: find.byType(Transform),
      ));
      expect(scaled.where((t) => t.transform.entry(0, 0) != 1.0), isEmpty);
    });

    testWidgets('fox renders through NoyaMotionView; other species are unchanged', (tester) async {
      await tester.pumpWidget(_app(const FlowCompanionView(companion: companion)));
      expect(find.byType(NoyaMotionView), findsOneWidget);
      await tester.pumpWidget(_app(const FlowCompanionView(
        companion: FlowCompanion(id: 'c2', name: 'Ludo', species: 'otter'),
      )));
      expect(find.byType(NoyaMotionView), findsNothing);
    });

    testWidgets('controller reactions reach Noya (greet waves)', (tester) async {
      final controller = FlowCompanionAnimationController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(FlowCompanionView(companion: companion, controller: controller), loops: false));
      controller.reactions.react(NoyaReaction.greet);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final poses = tester.widgetList<NoyaCompanionView>(find.byType(NoyaCompanionView)).map((v) => v.state);
      expect(poses.last, NoyaState.encouraging);
    });
  });

  group('FlowAmbientBackground', () {
    testWidgets('painter sits behind a RepaintBoundary that does not contain the child', (tester) async {
      await tester.pumpWidget(_app(
        const FlowAmbientBackground(child: Text('tab content')),
        loops: false,
      ));
      final boundaries = find.descendant(
        of: find.byType(FlowAmbientBackground),
        matching: find.byType(RepaintBoundary),
      );
      final painterBoundary = boundaries.evaluate().where((e) {
        final hasPainter = find.descendant(of: find.byWidget(e.widget), matching: find.byType(CustomPaint))
            .evaluate()
            .isNotEmpty;
        final hasChild = find.descendant(of: find.byWidget(e.widget), matching: find.text('tab content'))
            .evaluate()
            .isNotEmpty;
        return hasPainter && !hasChild;
      });
      expect(painterBoundary, isNotEmpty);
    });

    testWidgets('does not animate when loops are disabled', (tester) async {
      await tester.pumpWidget(_app(const FlowAmbientBackground(child: SizedBox()), loops: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('animates when loops are enabled', (tester) async {
      await tester.pumpWidget(_app(const FlowAmbientBackground(child: SizedBox())));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
    });
  });
}
