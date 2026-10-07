import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/companion/noya_moments.dart';
import 'package:flowstate/components/flow_day_path.dart';
import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/noya_motion_view.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/models/task_reflection.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/theme/flow_motion.dart';
import 'package:flowstate/theme/flow_theme.dart';

ScheduleItem _item(String id, String title, String time, String period,
        {bool completed = false, bool active = false, bool missed = false, bool fixed = false, int minutes = 60}) =>
    ScheduleItem(
      id: id,
      taskId: id.replaceFirst(RegExp('^(sched|comp)-'), ''),
      time: time,
      period: period,
      title: title,
      type: 'physical',
      tagText: completed ? 'COMPLETED' : 'PHYSICAL',
      isCompleted: completed,
      isActive: active,
      isMissed: missed,
      isFixed: fixed,
      durationMinutes: minutes,
      startTime: DateTime(2026, 10, 3, period == 'PM' && time != '12:00' ? int.parse(time.split(':')[0]) + 12 : int.parse(time.split(':')[0])),
    );

final _gymReflection = TaskReflection(
  taskId: 'gym',
  title: 'Gym',
  feeling: 4,
  energy: 4,
  focus: 5,
  difficulty: 3,
  distraction: 1,
  completedAt: DateTime(2026, 10, 3, 8, 5),
  actualMinutes: 52,
  plannedMinutes: 60,
  plannedStart: DateTime(2026, 10, 3, 7),
  durationFeedback: 'shorter',
  note: 'Felt strong',
);

final _items = [
  _item('comp-gym', 'Gym', '7:00', 'AM', completed: true),
  _item('comp-read', 'Read', '8:30', 'AM', completed: true),
  _item('sched-study', 'Study arrays', '10:00', 'AM', active: true),
  _item('sched-call', 'Call mom', '6:00', 'PM', fixed: true),
];

Widget _host(Widget child, {ThemeData? theme, double width = 412, double textScale = 1.0}) => MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(20), child: child))),
      ),
    );

FlowDayPath _path({void Function(ScheduleItem)? onTap}) => FlowDayPath(
      items: _items,
      nowItemId: 'sched-study',
      reflectionFor: (item) => item.taskId == 'gym' ? _gymReflection : null,
      completedAtFor: (item) => item.taskId == 'read' ? DateTime(2026, 10, 3, 9, 10) : null,
      onTap: onTap ?? (_) {},
    );

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
  });

  group('Noya moments', () {
    test('completed pose follows how the task felt; no reflection reads as quietly done', () {
      TaskReflection felt(int f) => TaskReflection(
            taskId: 'x', title: 'x', feeling: f, energy: 3, focus: 3, difficulty: 3, distraction: 1,
            completedAt: DateTime(2026), actualMinutes: 1,
          );
      expect(noyaStateForMoment(felt(4)), NoyaState.celebrating);
      expect(noyaStateForMoment(felt(3)), NoyaState.proud);
      expect(noyaStateForMoment(felt(2)), NoyaState.idle);
      expect(noyaStateForMoment(felt(1)), NoyaState.sleepy);
      expect(noyaStateForMoment(null), NoyaState.proud);
    });
  });

  group('FlowDayPath', () {
    testWidgets('one stop per timeline item, chronological from the top (first task) down the road', (tester) async {
      await tester.pumpWidget(_host(_path()));
      final ys = ['comp-gym', 'comp-read', 'sched-study', 'sched-call']
          .map((id) => tester.getCenter(find.byKey(Key('path_stop_$id'))).dy)
          .toList();
      expect(ys, orderedEquals([...ys]..sort((a, b) => a.compareTo(b))), reason: 'earliest at the top, latest at the bottom');
      expect(find.byKey(const Key('flow_day_route')), findsOneWidget, reason: 'one route painted from one geometry');
    });

    testWidgets('completed stops are calm checks with time, duration and how it felt — no Noya, no glow', (tester) async {
      await tester.pumpWidget(_host(_path()));
      final gym = find.byKey(const Key('path_stop_comp-gym'));
      expect(find.descendant(of: gym, matching: find.byKey(const Key('path_check_comp-gym'))), findsOneWidget);
      expect(find.descendant(of: gym, matching: find.byIcon(Icons.check_rounded)), findsOneWidget);
      final check = tester.getSize(find.byKey(const Key('path_check_comp-gym')));
      expect(check.width, FlowDayPath.doneNodeSize, reason: 'a medium circle, not a dot');

      // History is static and Noya-free: no motion view, no companion image, no shadows.
      expect(find.descendant(of: gym, matching: find.byType(NoyaMotionView)), findsNothing);
      expect(find.descendant(of: gym, matching: find.byType(NoyaCompanionView)), findsNothing);
      final shadows = tester
          .widgetList<Container>(find.descendant(of: gym, matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.boxShadow != null && d.boxShadow!.isNotEmpty);
      expect(shadows, isEmpty);

      // Actual minutes from the reflection; planned duration when there is none.
      expect(find.text('Done 8:05 AM · 52 min'), findsOneWidget);
      expect(find.text('Physical · Felt on fire'), findsOneWidget);
      expect(find.text('Done 9:10 AM · 60 min'), findsOneWidget);
    });

    testWidgets('the current stop is the strongest node; Noya appears only while it is in focus', (tester) async {
      await tester.pumpWidget(_host(_path()));
      final now = find.byKey(const Key('path_stop_sched-study'));
      expect(find.descendant(of: now, matching: find.byKey(const Key('path_now_sched-study'))), findsOneWidget);
      expect(find.byType(NoyaMotionView), findsOneWidget);
      final live = tester.widget<NoyaMotionView>(find.descendant(of: now, matching: find.byType(NoyaMotionView)));
      expect(live.mood, NoyaMood.focusing);
      expect(find.descendant(of: now, matching: find.text('In focus · Physical')), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('path_now_sched-study'))).width,
          greaterThan(tester.getSize(find.byKey(const Key('path_check_comp-gym'))).width));

      final call = find.byKey(const Key('path_stop_sched-call'));
      expect(find.descendant(of: call, matching: find.byType(NoyaCompanionView)), findsNothing);
      expect(find.descendant(of: call, matching: find.byIcon(Icons.lock_rounded)), findsOneWidget);
      expect(find.descendant(of: call, matching: find.text('6:00 PM · 60 min')), findsOneWidget);
      expect(find.descendant(of: call, matching: find.text('Fixed · Physical')), findsOneWidget);
    });

    testWidgets('a current task that has not started has no Noya', (tester) async {
      await tester.pumpWidget(_host(FlowDayPath(
        items: [_item('sched-a', 'Write', '9:00', 'AM'), _item('sched-b', 'Read', '11:00', 'AM')],
        nowItemId: 'sched-a',
        reflectionFor: (_) => null,
        completedAtFor: (_) => null,
        categoryFor: (item) => item.id == 'sched-a' ? 'Study' : 'General',
        onTap: (_) {},
      )));
      expect(find.byType(NoyaMotionView), findsNothing);
      expect(find.byType(NoyaCompanionView), findsNothing);
      expect(find.text('Up now · Study'), findsOneWidget);
      // A generic category is dropped; the item's type is the fallback.
      expect(find.text('Physical'), findsOneWidget);
    });

    testWidgets('a fully finished day ends with one Noya milestone', (tester) async {
      await tester.pumpWidget(_host(FlowDayPath(
        items: [_items[0], _items[1]],
        nowItemId: null,
        reflectionFor: (item) => item.taskId == 'gym' ? _gymReflection : null,
        completedAtFor: (_) => null,
        onTap: (_) {},
      )));
      final end = find.byKey(const Key('path_day_complete'));
      expect(end, findsOneWidget);
      expect(tester.widget<NoyaCompanionView>(find.descendant(of: end, matching: find.byType(NoyaCompanionView))).state,
          NoyaState.goodJob);
      expect(find.byType(NoyaCompanionView), findsOneWidget);
      expect(find.text('2 tasks · 1h 52m'), findsOneWidget);
    });

    testWidgets('every stop is a 48dp target with a descriptive semantics label', (tester) async {
      final handle = tester.ensureSemantics();
      ScheduleItem? tapped;
      await tester.pumpWidget(_host(_path(onTap: (i) => tapped = i)));
      for (final id in ['comp-gym', 'comp-read', 'sched-study', 'sched-call']) {
        final size = tester.getSize(find.byKey(Key('path_node_$id')));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(find.semantics.byLabel('Gym, completed at 8:05 AM, felt On fire'), findsOneWidget);
      expect(find.semantics.byLabel('Study arrays, now, 10:00 AM, 60 minutes'), findsOneWidget);
      expect(find.semantics.byLabel('Call mom, 6:00 PM, 60 minutes, Fixed'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('path_node_comp-gym'))); // the road opens at NOW, scrolled past the first stop
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('path_node_comp-gym')));
      expect(tapped?.id, 'comp-gym');
      handle.dispose();
    });

    testWidgets('the path is drawn organically behind the stops', (tester) async {
      await tester.pumpWidget(_host(_path()));
      final xs = ['comp-gym', 'comp-read', 'sched-study', 'sched-call']
          .map((id) => tester.getCenter(find.byKey(Key('path_node_$id'))).dx)
          .toSet();
      expect(xs.length, greaterThan(1), reason: 'nodes follow a wave, not a straight rail');
      expect(find.byKey(const Key('flow_day_path_line')), findsOneWidget);
    });

    testWidgets('dark mode and text scale 1.3 at 360dp render without overflow', (tester) async {
      await tester.pumpWidget(_host(_path(), theme: FlowTheme.darkTheme(), width: 360, textScale: 1.3));
      expect(tester.takeException(), isNull);
    });
  });

  group('History moment sheet', () {
    testWidgets('a completed moment shows what happened, when, and how it felt', (tester) async {
      await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
          onPressed: () => showHistoryMomentSheet(context, item: _items.first, reflection: _gymReflection),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final sheet = find.byKey(const Key('history_moment_sheet'));
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Gym')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('8:05 AM')), findsOneWidget); // completed
      expect(find.descendant(of: sheet, matching: find.text('7:00 AM')), findsOneWidget); // planned
      expect(find.descendant(of: sheet, matching: find.text('52 min · planned 60')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('On fire')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Faster than expected')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Felt strong')), findsOneWidget);
      for (final signal in ['Energy', 'Focus', 'Difficulty', 'Distraction']) {
        expect(find.descendant(of: sheet, matching: find.text(signal)), findsOneWidget);
      }
      expect(find.byKey(const Key('history_signal_energy_4')), findsOneWidget);
      expect(find.byKey(const Key('history_signal_distraction_1')), findsOneWidget);

      final noya = tester.widget<NoyaMotionView>(find.descendant(of: sheet, matching: find.byType(NoyaMotionView)));
      // Gym (physical) finished "on fire": the energetic, cheering Noya.
      expect(noya.pose, NoyaState.cheering);
      // Not an edit dialog.
      expect(find.descendant(of: sheet, matching: find.byType(TextField)), findsNothing);
    });

    testWidgets('without a reflection the sheet says what is not recorded instead of inventing it', (tester) async {
      await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
          onPressed: () => showHistoryMomentSheet(context, item: _items[1], completedAt: DateTime(2026, 10, 3, 9, 10)),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('history_moment_sheet'));
      expect(find.descendant(of: sheet, matching: find.text('9:10 AM')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('60 min planned')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('No reflection recorded')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Energy')), findsNothing);
    });
  });

  group('Path motion', () {
    // NOW is upcoming (not in focus), so no Noya loop competes with the node's own motion.
    final motionItems = [
      _item('comp-gym', 'Gym', '7:00', 'AM', completed: true),
      _item('sched-study', 'Study arrays', '10:00', 'AM'),
      _item('sched-late', 'Late task', '9:00', 'AM', missed: true),
      _item('sched-call', 'Call mom', '6:00', 'PM', fixed: true),
    ];
    FlowDayPath path(String? now) => FlowDayPath(
          items: motionItems,
          nowItemId: now,
          reflectionFor: (_) => null,
          completedAtFor: (_) => null,
          onTap: (_) {},
        );

    tearDown(() => FlowMotion.debugLoopsEnabled = false);

    testWidgets('NOW breathes a few times on arrival, then rests — a bounded state cue, not a loop', (tester) async {
      FlowMotion.debugLoopsEnabled = true;
      await tester.pumpWidget(_host(path('sched-study')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('path_now_breath')), findsOneWidget);
      // Medium marker, not a button: one step above the other stops.
      expect(tester.getSize(find.byKey(const Key('path_now_sched-study'))).width, FlowDayPath.nowNodeSize + 12);

      await tester.pump(const Duration(seconds: 8));
      expect(find.byKey(const Key('path_now_breath')), findsNothing);
      expect(tester.binding.transientCallbackCount, 0, reason: 'nothing keeps ticking after the breaths');
    });

    testWidgets('completed, upcoming, missed and fixed stops never animate', (tester) async {
      FlowMotion.debugLoopsEnabled = true;
      await tester.pumpWidget(_host(path(null)));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byKey(const Key('path_now_breath')), findsNothing);
    });

    testWidgets('reduced motion: NOW is still and the walked line is simply there', (tester) async {
      FlowMotion.debugLoopsEnabled = true;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(412, 900), disableAnimations: true),
          child: Scaffold(body: SingleChildScrollView(child: path('sched-study'))),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('path_now_breath')), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byKey(const Key('path_now_sched-study')), findsOneWidget);
    });

    testWidgets('the route is simply there on entry and morphs when NOW moves', (tester) async {
      await tester.pumpWidget(_host(path('sched-study')));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);

      // NOW moves on: the node states crossfade and the new stretch draws in once.
      await tester.pumpWidget(_host(path('sched-call')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('path_now_sched-call')), findsOneWidget);
      expect(find.byKey(const Key('path_now_sched-study')), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
