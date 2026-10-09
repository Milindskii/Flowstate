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

final _testTheme = FlowTheme.lightTheme();

Widget _host(List<ScheduleItem> items, {bool reduced = false}) => MaterialApp(
      theme: _testTheme,
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
  testWidgets('skipping a task moves no stop: the node changes and the road bends around it, morphing', (tester) async {
    await tester.pumpWidget(_host([_it('a'), _it('b'), _it('c'), _it('d')]));
    await tester.pumpAndSettle();
    final before = List<double>.from(_painter(tester).geometry.sampleXs);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_host([_it('a'), _it('b', skipped: true), _it('c'), _it('d')]));
    await tester.pumpAndSettle();
    final after = _painter(tester).geometry;
    expect(after.sampleXs, isNot(before), reason: 'the route model was regenerated from the new states');
    expect(after.stopById('b').role, StopRouteRole.skipped);
    expect(after.distanceToRoute(after.stopById('b').center), greaterThan(DayRouteGeometry.nodeRadius + 10),
        reason: 'the road goes around the node');
    expect(find.byKey(const Key('path_skipped_b')), findsOneWidget);
    expect(_painter(tester).fromXs, isNull, reason: 'settled: the morph is over');
  });

  testWidgets('completing a stop colours the road in (green creeping down it) over a restrained duration', (tester) async {
    await tester.pumpWidget(_host([_it('a'), _it('b'), _it('c')]));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_host([_it('a'), _it('b', done: true), _it('c')]));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'the new colour is drawing in');
    final mid = _painter(tester);
    expect(mid.fromStates, isNotNull);
    expect(mid.t, inInclusiveRange(0.01, 0.99));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    final g = _painter(tester).geometry;
    expect(g.sampleStates, contains(RouteSegmentState.traveled));
  });

  testWidgets('reduced motion: the road recolours at once, nothing animates', (tester) async {
    await tester.pumpWidget(_host([_it('a'), _it('b'), _it('c')], reduced: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host([_it('a'), _it('b', done: true), _it('c')], reduced: true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(_painter(tester).fromXs, isNull);
    expect(_painter(tester).fromStates, isNull);
    expect(_painter(tester).geometry.sampleStates, contains(RouteSegmentState.traveled));
  });

  testWidgets('recovering a skipped task brings the road back through it, orange, and marks the node recovered',
      (tester) async {
    await tester.pumpWidget(_host([_it('a', done: true), _it('b', skipped: true), _it('c')]));
    await tester.pumpAndSettle();
    final skippedXs = List<double>.from(_painter(tester).geometry.sampleXs);
    expect(_painter(tester).geometry.sampleStates, isNot(contains(RouteSegmentState.recovered)));

    await tester.pumpWidget(_host([_it('a', done: true), _it('b', done: true, recovered: true), _it('c')]));
    await tester.pumpAndSettle();
    final g = _painter(tester).geometry;
    expect(g.sampleStates, contains(RouteSegmentState.recovered));
    expect(g.sampleXs, isNot(skippedXs), reason: 'the detour closes: the road runs through the recovered stop again');
    expect(g.distanceToRoute(g.stopById('b').center), lessThan(0.5));
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
