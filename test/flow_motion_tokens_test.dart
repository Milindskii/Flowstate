import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/theme/flow_motion.dart';

/// Peak position of a unit step driven by [spring] (start 0 → end 1, at rest), sampled every 1 ms for 1.5 s.
double _peak(SpringDescription spring) {
  final sim = SpringSimulation(spring, 0, 1, 0);
  var peak = 0.0;
  for (var ms = 0; ms <= 1500; ms++) {
    final x = sim.x(ms / 1000);
    if (x > peak) peak = x;
  }
  return peak;
}

void main() {
  group('FlowMotion tokens (spec §10/§11)', () {
    test('token values match spec §10', () {
      expect(FlowMotion.instant, const Duration(milliseconds: 100));
      expect(FlowMotion.microDuration, const Duration(milliseconds: 150));
      expect(FlowMotion.standardDuration, const Duration(milliseconds: 220));
      expect(FlowMotion.screenDuration, const Duration(milliseconds: 280));
      expect(FlowMotion.onboardingDuration, const Duration(milliseconds: 340));
      expect(FlowMotion.posePivot, const Duration(milliseconds: 260));
      expect(FlowMotion.poseFadeReduced, const Duration(milliseconds: 120));
      expect(FlowMotion.enterFadeReduced, const Duration(milliseconds: 150));
      expect(FlowMotion.characterEnter, const Duration(milliseconds: 420));
      expect(FlowMotion.characterExit, const Duration(milliseconds: 200));
      expect(FlowMotion.reaction, const Duration(milliseconds: 700));
      expect(FlowMotion.celebration, const Duration(milliseconds: 1600));
      expect(FlowMotion.highlightFade, const Duration(milliseconds: 1200));
      expect(FlowMotion.breathPeriod, const Duration(milliseconds: 3800));
      expect(FlowMotion.thinkPeriod, const Duration(milliseconds: 2600));
      expect(FlowMotion.pacePeriod, const Duration(milliseconds: 4000));
      expect(FlowMotion.focusPeriod, const Duration(milliseconds: 5200));
      expect(FlowMotion.windDownPeriod, const Duration(milliseconds: 6000));
      expect(FlowMotion.idleWindow, const Duration(seconds: 30));
      expect(FlowMotion.focusBobWindow, const Duration(seconds: 20));
    });

    test('curves match spec §11', () {
      expect(FlowMotion.exit, Curves.easeInCubic);
      expect(FlowMotion.emphasized, const Cubic(0.2, 0.0, 0.0, 1.0));
      expect(FlowMotion.loop, Curves.easeInOutSine);
    });

    test('reactionSpring overshoots 2–4%', () {
      final peak = _peak(FlowMotion.reactionSpring);
      expect(peak, greaterThan(1.02));
      expect(peak, lessThan(1.04));
    });

    test('celebrationSpring overshoots 10–15%', () {
      final peak = _peak(FlowMotion.celebrationSpring);
      expect(peak, greaterThan(1.10));
      expect(peak, lessThan(1.15));
    });

    test('settleSpring does not overshoot', () {
      expect(_peak(FlowMotion.settleSpring), lessThanOrEqualTo(1.0005));
    });
  });

  group('FlowMotion.loopsEnabled', () {
    Future<bool> loopsEnabledIn(WidgetTester tester, Widget Function(Widget probe) wrap) async {
      late bool result;
      await tester.pumpWidget(wrap(Builder(builder: (context) {
        result = FlowMotion.loopsEnabled(context);
        return const SizedBox();
      })));
      return result;
    }

    testWidgets('test config disables loops by default', (tester) async {
      expect(FlowMotion.debugLoopsEnabled, isFalse);
      expect(await loopsEnabledIn(tester, (probe) => probe), isFalse);
    });

    testWidgets('FlowMotionScope(loopsEnabled: true) overrides debugLoopsEnabled=false', (tester) async {
      expect(
        await loopsEnabledIn(tester, (probe) => FlowMotionScope(loopsEnabled: true, child: probe)),
        isTrue,
      );
    });

    testWidgets('loopsEnabled false under reduced motion even inside an enabling scope', (tester) async {
      expect(
        await loopsEnabledIn(
          tester,
          (probe) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: FlowMotionScope(loopsEnabled: true, child: probe),
          ),
        ),
        isFalse,
      );
    });

    testWidgets('switcher fades and rises a new child in', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: FlowMotion.switcher(child: const Text('a', key: ValueKey('a'))),
      ));
      await tester.pumpWidget(MaterialApp(
        home: FlowMotion.switcher(child: const Text('b', key: ValueKey('b'))),
      ));
      await tester.pump(const Duration(milliseconds: 110));
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: find.text('b'), matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, inExclusiveRange(0.0, 1.0));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsNothing);
    });
  });
}
