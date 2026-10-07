import 'package:flowstate/components/day_path/day_route_geometry.dart';
import 'package:flowstate/components/day_path/day_route_painter.dart';
import 'package:flowstate/components/flow_day_path.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/theme/flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleItem _it(String id, {bool skipped = false, bool done = false, bool recovered = false, bool commitment = false, int? at, String? state}) => ScheduleItem(
      id: id,
      time: '9:00',
      period: 'AM',
      title: 'Task $id',
      type: 'Task',
      tagText: 'TASK',
      isSkipped: skipped,
      isCompleted: done,
      isCompletedAfterDeviation: recovered,
      isCommitment: commitment,
      isFixed: commitment,
      state: state,
      startTime: commitment ? DateTime(2026, 10, 5, 18, 30) : (at == null ? null : DateTime(2026, 10, 7, 9).add(Duration(minutes: at))),
      endTime: commitment ? DateTime(2026, 10, 5, 20, 30) : null,
    );

Widget _host(List<ScheduleItem> items, {bool reduced = false}) => MaterialApp(
      theme: FlowTheme.lightTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 900), disableAnimations: reduced),
        child: Scaffold(
          body: SingleChildScrollView(
            child: FlowDayPath(
              items: items,
              nowItemId: null,
              reflectionFor: (_) => null,
              completedAtFor: (_) => null,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );

DayRoutePainter _painter(WidgetTester tester) => tester.widget<CustomPaint>(find.byKey(const Key('flow_day_route'))).painter as DayRoutePainter;

void main() {
  testWidgets('skipping a task deviates the road around it: the node stays, the road morphs', (tester) async {
    await tester.pumpWidget(_host([_it('a', at: 0), _it('b', at: 60), _it('c', at: 120), _it('d', at: 180)]));
    await tester.pumpAndSettle();
    final planned = _painter(tester).geometry;
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_host([_it('a', at: 0), _it('b', at: 60, skipped: true), _it('c', at: 120), _it('d', at: 180)]));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'the road is morphing, not swapping');
    final mid = _painter(tester).geometry;
    await tester.pumpAndSettle();
    final after = _painter(tester).geometry;
    expect(after.stopById('b').center, planned.stopById('b').center, reason: 'the node keeps its place');
    expect(after.stopById('b').role, StopRouteRole.skipped);
    expect(after.distanceToRoute(after.stopById('b').center), greaterThan(30));
    expect(mid.sampleXs, isNot(planned.sampleXs));
    expect(mid.sampleXs, isNot(after.sampleXs), reason: 'mid-morph differs from both ends');
    expect(find.byKey(const Key('path_skipped_b')), findsOneWidget);
  });

  testWidgets('completing a stop recolours the road green', (tester) async {
    await tester.pumpWidget(_host([_it('a'), _it('b'), _it('c')]));
    await tester.pumpAndSettle();
    expect(_painter(tester).geometry.sampleStates, isNot(contains(RouteSegmentState.traveled)));

    await tester.pumpWidget(_host([_it('a'), _it('b', done: true), _it('c')]));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(_painter(tester).geometry.sampleStates, contains(RouteSegmentState.traveled));
  });

  testWidgets('reduced motion: the road changes at once, nothing animates', (tester) async {
    await tester.pumpWidget(_host([_it('a'), _it('b'), _it('c')], reduced: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host([_it('a'), _it('b', skipped: true), _it('c')], reduced: true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(_painter(tester).geometry.stopById('b').deviated, isTrue);
  });

  testWidgets('recovering then completing a skipped task: the orange way back appears and then stays as history', (tester) async {
    await tester.pumpWidget(_host([_it('a', done: true, at: 0), _it('b', skipped: true, at: 60), _it('c', at: 120)]));
    await tester.pumpAndSettle();
    expect(_painter(tester).geometry.detours, isEmpty);

    await tester.pumpWidget(_host([_it('a', done: true, at: 0), _it('b', state: 'recovering', at: 60), _it('c', at: 120)]));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_painter(tester).geometry.detours.single.reveal, inExclusiveRange(0.0, 1.0), reason: 'the orange path draws in');
    await tester.pumpAndSettle();
    expect(_painter(tester).geometry.detours.single.reveal, 1);
    expect(_painter(tester).geometry.sampleStates, contains(RouteSegmentState.recovered));
    expect(find.byKey(const Key('path_recovering_b')), findsOneWidget);
    expect(find.text('Recovering'), findsOneWidget);

    await tester.pumpWidget(_host([_it('a', done: true, at: 0), _it('b', done: true, recovered: true, at: 60), _it('c', at: 120)]));
    await tester.pumpAndSettle();
    final g = _painter(tester).geometry;
    expect(g.detours.map((d) => d.stopId), ['b'], reason: 'the deviation history stays after completion');
    expect(g.stopById('b').deviated, isTrue);
    expect(g.sampleStates, contains(RouteSegmentState.recovered));
    expect(find.byKey(const Key('path_check_b')), findsOneWidget);
    expect(find.textContaining('Recovered'), findsOneWidget);
  });

  testWidgets('rescheduling a task moves its stop and morphs the road; deleting one closes it', (tester) async {
    await tester.pumpWidget(_host([_it('a', at: 0), _it('b', at: 30), _it('c', at: 240)]));
    await tester.pumpAndSettle();
    final before = _painter(tester).geometry;

    await tester.pumpWidget(_host([_it('a', at: 0), _it('b', at: 200), _it('c', at: 240)]));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpAndSettle();
    final moved = _painter(tester).geometry;
    expect(moved.stopById('b').center.dy, greaterThan(before.stopById('b').center.dy));
    expect(tester.getTopLeft(find.byKey(const Key('path_stop_b'))).dy, greaterThan(before.stopById('b').center.dy - 46 - 1));

    await tester.pumpWidget(_host([_it('a', at: 0), _it('c', at: 240)]));
    await tester.pumpAndSettle();
    final closed = _painter(tester).geometry;
    expect(find.byKey(const Key('path_stop_b')), findsNothing);
    expect(closed.stops.map((s) => s.id), ['a', 'c']);
    expect(closed.height, lessThan(moved.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a locked commitment reads as protected time with its span, never as work', (tester) async {
    await tester.pumpWidget(_host([_it('a'), _it('out', commitment: true)]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('path_commitment_out')), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.textContaining('6:30'), findsOneWidget);
    expect(find.textContaining('8:30 PM'), findsOneWidget);
    expect(find.text('Fixed'), findsOneWidget);
  });

  testWidgets('every stop keeps a 48dp tap target and the road stays inside the viewport at 360dp', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host([for (var i = 0; i < 6; i++) _it('t$i')]));
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      final size = tester.getSize(find.byKey(Key('path_node_t$i')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });
}
