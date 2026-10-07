import 'package:flowstate/components/day_path/day_route_geometry.dart';
import 'package:flowstate/components/day_path/day_route_painter.dart';
import 'package:flowstate/components/flow_day_path.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/theme/flow_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleItem _it(String id, {bool skipped = false, bool done = false, bool recovered = false, bool commitment = false}) => ScheduleItem(
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
      startTime: commitment ? DateTime(2026, 10, 5, 18, 30) : null,
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
  testWidgets('skipping a task morphs the route itself (not a recolor) over a restrained duration', (tester) async {
    await tester.pumpWidget(_host([_it('a'), _it('b'), _it('c'), _it('d')]));
    await tester.pumpAndSettle();
    final before = List<double>.from(_painter(tester).geometry.sampleXs);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_host([_it('a'), _it('b', skipped: true), _it('c'), _it('d')]));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'the route is morphing');
    final mid = _painter(tester);
    expect(mid.fromXs, isNotNull);
    expect(mid.t, inInclusiveRange(0.01, 0.99));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    final after = _painter(tester).geometry;
    final yB = after.stopById('b').center.dy;
    expect((after.routeXAt(yB) - before[((yB - after.sampleYs.first) / DayRouteGeometry.sampleStep).round()]).abs(), greaterThan(1),
        reason: 'the route really moved around B');
    expect(after.distanceToRoute(after.stopById('b').center), greaterThanOrEqualTo(DayRouteGeometry.bypassClearance - 3));
  });

  testWidgets('reduced motion: the route changes at once, nothing animates', (tester) async {
    await tester.pumpWidget(_host([_it('a'), _it('b'), _it('c')], reduced: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host([_it('a'), _it('b', skipped: true), _it('c')], reduced: true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(_painter(tester).fromXs, isNull);
    final g = _painter(tester).geometry;
    expect(g.distanceToRoute(g.stopById('b').center), greaterThanOrEqualTo(DayRouteGeometry.bypassClearance - 3));
  });

  testWidgets('recovering a skipped task adds a real orange detour and keeps the node marked recovered', (tester) async {
    await tester.pumpWidget(_host([_it('a', done: true), _it('b', skipped: true), _it('c')]));
    await tester.pumpAndSettle();
    expect(_painter(tester).geometry.detours, isEmpty);

    await tester.pumpWidget(_host([_it('a', done: true), _it('b', done: true, recovered: true), _it('c')]));
    await tester.pumpAndSettle();
    final g = _painter(tester).geometry;
    expect(g.detours.single.stopId, 'b');
    expect(find.byKey(const Key('path_check_b')), findsOneWidget);
    expect(find.textContaining('Recovered'), findsOneWidget);
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
