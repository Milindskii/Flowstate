import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/flow_completion_check.dart';
import 'package:flowstate/components/timeline_item_widget.dart';
import 'package:flowstate/models/schedule_item.dart';

Widget _host(Widget child, {bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: Center(child: child)),
      ),
    );

/// Toggles its own completed state so tests can drive the animation by tapping.
class _Toggle extends StatefulWidget {
  const _Toggle();

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool done = false;

  @override
  Widget build(BuildContext context) => FlowCompletionCheck(
        completed: done,
        onToggle: () => setState(() => done = !done),
      );
}

double _fill(WidgetTester tester) =>
    tester.widget<Opacity>(find.byKey(FlowCompletionCheck.fillKey)).opacity;

ScheduleItem _item({bool completed = false}) => ScheduleItem(
      id: 'r',
      time: '9:30',
      period: 'AM',
      title: 'Write outline',
      type: 'deep_work',
      tagText: 'DEEP WORK',
      isCompleted: completed,
    );

void main() {
  testWidgets('fill animates over 150ms', (tester) async {
    await tester.pumpWidget(_host(const _Toggle()));
    expect(find.byKey(FlowCompletionCheck.fillKey), findsNothing);

    await tester.tap(find.byType(FlowCompletionCheck));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_fill(tester), inExclusiveRange(0.05, 0.99));

    await tester.pump(const Duration(milliseconds: 100)); // 160 ms
    expect(_fill(tester), 1.0);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('48dp hit target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(FlowCompletionCheck(completed: false, onToggle: () => taps++)));
    final size = tester.getSize(find.byType(FlowCompletionCheck));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    // A tap near the edge of the 48 dp target still counts.
    final rect = tester.getRect(find.byType(FlowCompletionCheck));
    await tester.tapAt(rect.topLeft + const Offset(3, 3));
    expect(taps, 1);
  });

  testWidgets('semantics checked state', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(FlowCompletionCheck(completed: false, onToggle: () {})));
    expect(
      tester.getSemantics(find.byType(FlowCompletionCheck)),
      matchesSemantics(label: 'Mark complete', isButton: true, hasCheckedState: true, isChecked: false, hasTapAction: true),
    );
    await tester.pumpWidget(_host(FlowCompletionCheck(completed: true, onToggle: () {})));
    expect(
      tester.getSemantics(find.byType(FlowCompletionCheck)),
      matchesSemantics(label: 'Completed', isButton: true, hasCheckedState: true, isChecked: true, hasTapAction: true),
    );
    await tester.pumpWidget(_host(FlowCompletionCheck(completed: false, label: 'Mark Report as done', onToggle: () {})));
    expect(tester.getSemantics(find.byType(FlowCompletionCheck)).label, 'Mark Report as done');
    handle.dispose();
  });

  testWidgets('reduced motion: instant', (tester) async {
    await tester.pumpWidget(_host(const _Toggle(), reduced: true));
    await tester.tap(find.byType(FlowCompletionCheck));
    await tester.pump();
    expect(_fill(tester), 1.0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('row strike-through animates over 220ms and row height eases via AnimatedSize', (tester) async {
    Widget row(bool completed) => _host(SizedBox(width: 380, child: FlowTimelineRow(item: _item(completed: completed))));
    await tester.pumpWidget(row(false));
    expect(tester.widget<AnimatedSize>(find.byType(AnimatedSize)).duration, const Duration(milliseconds: 220));

    await tester.pumpWidget(row(true));
    await tester.pump(const Duration(milliseconds: 110));
    final mid = tester.widget<Text>(find.text('Write outline')).style!;
    expect(mid.decoration, TextDecoration.lineThrough);
    expect(mid.decorationColor!.a, inExclusiveRange(0.05, 0.95));

    await tester.pump(const Duration(milliseconds: 120)); // 230 ms
    final end = tester.widget<Text>(find.text('Write outline')).style!;
    expect(end.decorationColor!.a, closeTo(1.0, 0.01));
  });

  testWidgets('reduced motion: row completes instantly with no AnimatedSize and no layout error', (tester) async {
    Widget row(bool completed) =>
        _host(SizedBox(width: 380, child: FlowTimelineRow(item: _item(completed: completed))), reduced: true);
    await tester.pumpWidget(row(false));
    await tester.pumpWidget(row(true));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(AnimatedSize), findsNothing);
    expect(tester.widget<Text>(find.text('Write outline')).style!.decoration, TextDecoration.lineThrough);
  });

  testWidgets('row completion uses FlowCompletionCheck with the existing row semantics', (tester) async {
    final handle = tester.ensureSemantics();
    var done = 0;
    await tester.pumpWidget(_host(SizedBox(width: 380, child: FlowTimelineRow(item: _item(), onComplete: () => done++))));
    expect(find.byType(FlowCompletionCheck), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Mark Write outline as done'));
    expect(done, 1);
    handle.dispose();
  });
}
