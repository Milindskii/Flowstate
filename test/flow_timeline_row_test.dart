import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/timeline_item_widget.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/theme/flow_colors.dart';

ScheduleItem _item(
  String id, {
  String title = 'Write chapter outline',
  String time = '9:30',
  String period = 'AM',
  int minutes = 60,
  String type = 'deep_work',
  bool fixed = false,
  bool conflict = false,
  bool missed = false,
  bool suggested = false,
  bool completed = false,
  String? explanation,
}) =>
    ScheduleItem(
      id: id,
      time: time,
      period: period,
      title: title,
      type: type,
      tagText: 'DEEP WORK',
      durationMinutes: minutes,
      isFixed: fixed,
      isConflict: conflict,
      isMissed: missed,
      isSuggested: suggested,
      isCompleted: completed,
      explanation: explanation,
    );

Widget _host(Widget child, {double width = 412, double textScale = 1.0, Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(20), child: child))),
    ),
  );
}

final _emoji = RegExp('[\u{1F300}-\u{1FAFF}☀-➿]', unicode: true);

void main() {
  group('timelineRowStateOf precedence', () {
    test('completed > conflict > fixed > missed > suggested > now > normal', () {
      expect(timelineRowStateOf(_item('a', completed: true, conflict: true, fixed: true), isNow: true), TimelineRowState.completed);
      expect(timelineRowStateOf(_item('a', conflict: true, fixed: true, missed: true), isNow: true), TimelineRowState.conflict);
      expect(timelineRowStateOf(_item('a', fixed: true, missed: true, suggested: true), isNow: true), TimelineRowState.fixed);
      expect(timelineRowStateOf(_item('a', missed: true, suggested: true), isNow: true), TimelineRowState.missed);
      expect(timelineRowStateOf(_item('a', suggested: true), isNow: true), TimelineRowState.suggested);
      expect(timelineRowStateOf(_item('a'), isNow: true), TimelineRowState.now);
      expect(timelineRowStateOf(_item('a'), isNow: false), TimelineRowState.normal);
    });

    test('unscheduled flag wins over everything but completed', () {
      expect(timelineRowStateOf(_item('a', conflict: true), isNow: false, isUnscheduled: true), TimelineRowState.unscheduled);
      expect(timelineRowStateOf(_item('a', completed: true), isNow: false, isUnscheduled: true), TimelineRowState.completed);
    });
  });

  group('FlowTimelineRow states', () {
    final cases = <String, (ScheduleItem, bool, bool, String)>{
      'fixed': (_item('f', fixed: true), false, false, 'Fixed'),
      'conflict': (_item('c', conflict: true), false, false, 'Conflict'),
      'missed': (_item('m', missed: true), false, false, 'Missed'),
      'suggested': (_item('s', suggested: true), false, false, 'Suggested'),
      'unscheduled': (_item('u'), false, true, 'Unscheduled'),
    };

    for (final entry in cases.entries) {
      testWidgets('${entry.key}: indicator key, label, icon, semantics, no emoji', (tester) async {
        final (item, isNow, unscheduled, label) = entry.value;
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(_host(FlowTimelineRow(
          item: item,
          isNow: isNow,
          isUnscheduled: unscheduled,
          showTimeGutter: !unscheduled,
        )));

        final indicator = find.byKey(Key('timeline_state_${entry.key}_${item.id}'));
        expect(indicator, findsOneWidget);
        expect(find.descendant(of: indicator, matching: find.text(label)), findsOneWidget);
        expect(find.descendant(of: indicator, matching: find.byType(Icon)), findsOneWidget);
        // No ALL-CAPS state label anywhere.
        expect(find.text(label.toUpperCase()), findsNothing);

        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          expect(_emoji.hasMatch(text.data ?? ''), isFalse, reason: 'emoji in "${text.data}"');
        }

        expect(find.semantics.byLabel(RegExp('^${item.title}, .*$label\$')), findsOneWidget);
        handle.dispose();
      });
    }

    testWidgets('normal row has no badge and no reason line', (tester) async {
      await tester.pumpWidget(_host(FlowTimelineRow(item: _item('n', explanation: 'Aligned with focus window'))));
      expect(find.byKey(const Key('timeline_row_n')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('timeline_state_')), findsNothing);
      expect(find.text('Aligned with focus window'), findsNothing);
      expect(find.byKey(const Key('timeline_reason_n')), findsNothing);
    });

    testWidgets('now row shows reason line and tinted surface', (tester) async {
      await tester.pumpWidget(_host(FlowTimelineRow(item: _item('w', explanation: 'Peak energy focus window'), isNow: true)));
      expect(find.byKey(const Key('timeline_state_now_w')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('timeline_state_now_w')), matching: find.text('NOW')), findsOneWidget);
      expect(find.text('Peak energy focus window'), findsOneWidget);

      final box = tester.widget<Container>(find.byKey(const Key('timeline_row_w')));
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
      expect(decoration.color!.a, closeTo(0.06, 0.005));
      expect(decoration.borderRadius, BorderRadius.circular(14));
      expect(decoration.boxShadow, isNull);
    });

    testWidgets("completed row: strike-through title, check node, no '✓ Done'", (tester) async {
      await tester.pumpWidget(_host(FlowTimelineRow(item: _item('d', completed: true))));
      final title = tester.widget<Text>(find.text('Write chapter outline'));
      expect(title.style?.decoration, TextDecoration.lineThrough);
      final node = find.byKey(const Key('timeline_state_completed_d'));
      expect(node, findsOneWidget);
      expect(find.descendant(of: node, matching: find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
      expect(find.text('✓ Done'), findsNothing);
      expect(find.textContaining('Completed'), findsNothing);
    });

    testWidgets('conflict uses errorOf color, missed uses warningOf', (tester) async {
      await tester.pumpWidget(_host(Column(children: [
        FlowTimelineRow(item: _item('c', conflict: true)),
        FlowTimelineRow(item: _item('m', missed: true)),
      ])));
      final ctx = tester.element(find.byKey(const Key('timeline_row_c')));
      Color labelColor(String key, String text) =>
          tester.widget<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.text(text))).style!.color!;
      expect(labelColor('timeline_state_conflict_c', 'Conflict'), FlowColors.errorOf(ctx));
      expect(labelColor('timeline_state_missed_m', 'Missed'), FlowColors.warningOf(ctx));
    });

    testWidgets('default row ≤ 72dp tall at textScale 1.0', (tester) async {
      await tester.pumpWidget(_host(FlowTimelineRow(item: _item('h', title: 'Short title'))));
      expect(tester.getSize(find.byKey(const Key('timeline_row_h'))).height, lessThanOrEqualTo(72));
    });

    testWidgets('times left-aligned on one axis', (tester) async {
      await tester.pumpWidget(_host(Column(children: [
        FlowTimelineRow(item: _item('a', time: '9:30')),
        FlowTimelineRow(item: _item('b', time: '12:45', period: 'PM')),
        FlowTimelineRow(item: _item('c', time: '1:00', period: 'PM', fixed: true)),
      ])));
      final xs = ['9:30', '12:45', '1:00'].map((t) => tester.getTopLeft(find.text(t)).dx).toSet();
      expect(xs.length, 1);
      // Titles share one axis too: the gutter is the same width on every row.
      final titleXs = tester.widgetList<Text>(find.text('Write chapter outline')).length;
      expect(titleXs, 3);
      final lefts = find.text('Write chapter outline').evaluate().map((e) => tester.getTopLeft(find.byWidget(e.widget)).dx).toSet();
      expect(lefts.length, 1);
    });

    testWidgets('textScale 1.3 at 360dp: gutter grows, time not truncated, no overflow', (tester) async {
      await tester.pumpWidget(_host(
        Column(children: [
          FlowTimelineRow(item: _item('a', time: '12:45', period: 'PM', title: 'A rather long task title that will need to wrap onto two lines')),
          FlowTimelineRow(item: _item('b', conflict: true, explanation: 'Direct conflict with Dentist Appointment')),
        ]),
        width: 360,
        textScale: 1.3,
      ));
      expect(tester.takeException(), isNull);
      final time = tester.widget<Text>(find.text('12:45'));
      expect(time.overflow, isNot(TextOverflow.ellipsis));
      expect(time.maxLines, isNull);
      final timeRect = tester.getRect(find.text('12:45'));
      final titleRect = tester.getRect(find.textContaining('A rather long task'));
      expect(timeRect.right, lessThan(titleRect.left));
      expect(tester.widget<Text>(find.textContaining('A rather long task')).maxLines, 2);
    });

    testWidgets('states distinguishable without color', (tester) async {
      final rows = <(ScheduleItem, bool, bool)>[
        (_item('n'), false, false),
        (_item('w'), true, false),
        (_item('f', fixed: true), false, false),
        (_item('c', conflict: true), false, false),
        (_item('m', missed: true), false, false),
        (_item('s', suggested: true), false, false),
        (_item('d', completed: true), false, false),
        (_item('u'), false, true),
      ];
      final signatures = <String>{};
      for (final (item, isNow, unscheduled) in rows) {
        await tester.pumpWidget(_host(FlowTimelineRow(item: item, isNow: isNow, isUnscheduled: unscheduled, showTimeGutter: !unscheduled)));
        final row = find.byKey(Key('timeline_row_${item.id}'));
        final icons = tester
            .widgetList<Icon>(find.descendant(of: row, matching: find.byType(Icon)))
            .map((i) => i.icon?.codePoint)
            .toList()
          ..sort();
        signatures.add(icons.join(','));
      }
      expect(signatures.length, rows.length, reason: 'every state needs its own icon signature');
    });
  });

  group('FlowTimelineRow actions (Today)', () {
    testWidgets('keeps completion semantics and callbacks', (tester) async {
      var completed = 0, started = 0, tapped = 0;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(FlowTimelineRow(
        item: _item('a', title: 'Upcoming Report'),
        onTap: () => tapped++,
        onComplete: () => completed++,
        onStart: () => started++,
      )));

      await tester.tap(find.bySemanticsLabel('Mark Upcoming Report as done'));
      await tester.tap(find.bySemanticsLabel('Start focus on Upcoming Report'));
      await tester.tap(find.text('Upcoming Report'));
      expect((completed, started, tapped), (1, 1, 1));
      handle.dispose();
    });

    testWidgets('"Do this now" lives in the ⋯ menu and fires onDoThisNow', (tester) async {
      var doNow = 0;
      await tester.pumpWidget(_host(FlowTimelineRow(
        item: _item('a', title: 'Upcoming Report'),
        onComplete: () {},
        onStart: () {},
        onDoThisNow: () => doNow++,
      )));
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Do this now'));
      await tester.pumpAndSettle();
      expect(doNow, 1);
    });

    testWidgets('narrow row drops the menu before Start and Complete, without overflow', (tester) async {
      await tester.pumpWidget(_host(
        SizedBox(
          width: 300, // test font: room for exactly one 40 dp action
          child: FlowTimelineRow(item: _item('a', title: 'Upcoming Report'), onComplete: () {}, onStart: () {}, onDoThisNow: () {}),
        ),
        width: 320,
      ));
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
    });

  });
}
