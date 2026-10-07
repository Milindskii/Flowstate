import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/components/skeleton_loaders.dart';
import 'package:flowstate/theme/flow_motion.dart';

Widget _app(Widget child, {required bool loops}) =>
    MaterialApp(home: FlowMotionScope(loopsEnabled: loops, child: child));

Widget _boxes() => const Column(children: [
      FlowShimmerBox(width: 40, height: 10),
      FlowShimmerBox(width: 40, height: 10),
      FlowShimmerBox(width: 40, height: 10),
      FlowShimmerBox(width: 40, height: 10),
    ]);

void main() {
  testWidgets('boxes inside a FlowShimmerScope share one ticker', (tester) async {
    await tester.pumpWidget(_app(FlowShimmerScope(child: _boxes()), loops: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, 1);
  });

  testWidgets('TodayDashboardSkeleton runs a single shimmer ticker', (tester) async {
    await tester.pumpWidget(_app(const TodayDashboardSkeleton(), loops: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FlowShimmerBox).evaluate().length, greaterThan(1));
    expect(tester.binding.transientCallbackCount, 1);
  });

  testWidgets('TaskInboxSkeleton runs a single shimmer ticker', (tester) async {
    await tester.pumpWidget(_app(const TaskInboxSkeleton(), loops: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FlowShimmerBox).evaluate().length, greaterThan(1));
    expect(tester.binding.transientCallbackCount, 1);
  });

  testWidgets('a box without a scope still shimmers on its own (backward compatible)', (tester) async {
    await tester.pumpWidget(_app(const FlowShimmerBox(width: 40, height: 10), loops: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, 1);
  });

  testWidgets('shimmer is static at the 0.55 midpoint when loops are disabled', (tester) async {
    await tester.pumpWidget(_app(FlowShimmerScope(child: _boxes()), loops: false));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.hasScheduledFrame, isFalse);
    final decoration = tester.widget<Container>(
      find.descendant(of: find.byType(FlowShimmerBox).first, matching: find.byType(Container)),
    ).decoration! as BoxDecoration;
    expect(decoration.color!.a, closeTo(0.55, 0.001));
  });
}
