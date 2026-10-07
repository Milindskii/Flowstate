import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/flow_date_strip.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';

// Friday 2 October 2026. The default strip runs 1 → 14 October; a strip starting
// 25 October crosses into November for the month-label test.
final _today = DateTime(2026, 10, 2);

List<DateTime> _daysFrom(DateTime start) => List.generate(14, (i) => start.add(Duration(days: i)));

Widget _host(Widget child, {double width = 412, double textScale = 1.0}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => FlowClock().stopTimer());

  group('FlowDateStrip', () {
    testWidgets('chip shows weekday abbreviation and day number', (tester) async {
      await tester.pumpWidget(_host(FlowDateStrip(
        days: _daysFrom(_today.subtract(const Duration(days: 1))),
        selected: _today,
        today: _today,
        onSelect: (_) {},
      )));

      final chip = find.byKey(const Key('calendar_day_chip_today'));
      expect(find.descendant(of: chip, matching: find.text('Fri')), findsOneWidget);
      expect(find.descendant(of: chip, matching: find.text('2')), findsOneWidget);
      // Relative labels no longer replace the weekday.
      expect(find.text('Today'), findsNothing);
      expect(find.text('Tmrw'), findsNothing);
      expect(find.text('Yest'), findsNothing);
    });

    testWidgets('today marker visible when another day selected', (tester) async {
      DateTime? picked;
      await tester.pumpWidget(_host(FlowDateStrip(
        days: _daysFrom(_today.subtract(const Duration(days: 1))),
        selected: _today.add(const Duration(days: 1)),
        today: _today,
        onSelect: (d) => picked = d,
      )));

      final marker = find.byKey(const Key('calendar_today_marker'));
      expect(marker, findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_day_chip_today')), matching: marker), findsOneWidget);

      await tester.tap(find.byKey(const Key('calendar_day_chip_yesterday')));
      expect(picked, _today.subtract(const Duration(days: 1)));
    });

    testWidgets('today marker also visible when today is selected', (tester) async {
      await tester.pumpWidget(_host(FlowDateStrip(
        days: _daysFrom(_today.subtract(const Duration(days: 1))),
        selected: _today,
        today: _today,
        onSelect: (_) {},
      )));
      expect(
        find.descendant(of: find.byKey(const Key('calendar_day_chip_today')), matching: find.byKey(const Key('calendar_today_marker'))),
        findsOneWidget,
      );
    });

    testWidgets('month label above first chip of a new month', (tester) async {
      final start = DateTime(2026, 10, 25);
      await tester.pumpWidget(_host(FlowDateStrip(
        days: _daysFrom(start),
        selected: start,
        today: _today,
        onSelect: (_) {},
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('calendar_month_label_2026-10')), findsOneWidget);
      final nov = find.byKey(const Key('calendar_month_label_2026-11'));
      await tester.dragUntilVisible(nov, find.byType(Scrollable).first, const Offset(-120, 0));
      expect(nov, findsOneWidget);
      expect(tester.widget<Text>(nov).data, 'Nov');

      // The label sits directly above the 1 November chip.
      final labelRect = tester.getRect(nov);
      final chipRect = tester.getRect(find.byKey(const Key('calendar_day_chip_2026-11-01')));
      expect(labelRect.bottom, lessThanOrEqualTo(chipRect.top));
      expect((labelRect.left - chipRect.left).abs(), lessThan(1.0));
    });

    testWidgets('selected chip scrolled fully into view after selecting day 12', (tester) async {
      final days = _daysFrom(_today.subtract(const Duration(days: 1)));
      final target = _today.add(const Duration(days: 11)); // 13 October, chip index 12
      // Selection arrives from outside (Calendar passes state.selectedCalendarDate).
      final selected = ValueNotifier<DateTime>(_today);
      await tester.pumpWidget(ValueListenableBuilder<DateTime>(
        valueListenable: selected,
        builder: (context, value, _) => _host(
          FlowDateStrip(days: days, selected: value, today: _today, onSelect: (d) => selected.value = d),
          width: 360,
        ),
      ));
      await tester.pumpAndSettle();

      selected.value = target;
      await tester.pumpAndSettle();

      final viewport = tester.getRect(find.byType(Scrollable).first);
      final chip = tester.getRect(find.byKey(Key('calendar_day_chip_${DateFormat('yyyy-MM-dd').format(target)}')));
      expect(chip.left, greaterThanOrEqualTo(viewport.left - 0.5));
      expect(chip.right, lessThanOrEqualTo(viewport.right + 0.5));
    });

    testWidgets('existing keys and semantics preserved', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(FlowDateStrip(
        days: _daysFrom(_today.subtract(const Duration(days: 1))),
        selected: _today,
        today: _today,
        onSelect: (_) {},
      )));

      expect(find.byKey(const Key('calendar_day_chip_yesterday')), findsOneWidget);
      expect(find.byKey(const Key('calendar_day_chip_today')), findsOneWidget);
      expect(find.byKey(const Key('calendar_day_chip_tomorrow')), findsOneWidget);
      expect(find.byKey(const Key('calendar_day_chip_2026-10-04')), findsOneWidget);

      expect(
        tester.getSemantics(find.byKey(const Key('calendar_day_chip_today'))),
        matchesSemantics(label: 'Today October 2', isButton: true, hasSelectedState: true, isSelected: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('calendar_day_chip_tomorrow'))),
        matchesSemantics(label: 'Tomorrow October 3', isButton: true, hasSelectedState: true, isSelected: false, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('calendar_day_chip_yesterday'))),
        matchesSemantics(label: 'Yesterday October 1', isButton: true, hasSelectedState: true, isSelected: false, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('calendar_day_chip_2026-10-04'))),
        matchesSemantics(label: 'Sunday October 4', isButton: true, hasSelectedState: true, isSelected: false, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('six full chips fit at 360dp', (tester) async {
      await tester.pumpWidget(_host(
        FlowDateStrip(
          days: _daysFrom(_today.subtract(const Duration(days: 1))),
          selected: _today.subtract(const Duration(days: 1)),
          today: _today,
          onSelect: (_) {},
        ),
        width: 360,
      ));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(Scrollable).first);
      final sixth = tester.getRect(find.byKey(const Key('calendar_day_chip_2026-10-06')));
      expect(sixth.right, lessThanOrEqualTo(viewport.right + 0.5));
    });

    testWidgets('textScaler 1.3 at 360dp: no overflow', (tester) async {
      await tester.pumpWidget(_host(
        FlowDateStrip(
          days: _daysFrom(DateTime(2026, 10, 25)),
          selected: DateTime(2026, 10, 25),
          today: _today,
          onSelect: (_) {},
        ),
        width: 360,
        textScale: 1.3,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('header shows full selected date', (tester) async {
    final mockClient = MockClient((request) async => http.Response(
          jsonEncode({
            'date': request.url.queryParameters['date'],
            'is_today': false,
            'is_past': false,
            'timeline': [],
            'fixed_commitments': [],
            'completed_tasks': [],
            'remaining_tasks': [],
            'unscheduled_tasks': [],
            'conflicts': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ));
    final provider = AppStateProvider(customApi: ApiService(client: mockClient));

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<AppStateProvider>.value(value: provider, child: const CalendarTab()),
    ));
    await tester.pumpAndSettle();

    final now = FlowClock().now;
    final todayLabel = DateFormat('EEEE, MMMM d').format(now);
    expect(find.text(todayLabel), findsOneWidget);
    expect(find.text('Energy-aligned schedule & focus blocks'), findsNothing);

    await tester.tap(find.byKey(const Key('calendar_day_chip_tomorrow')));
    await tester.pumpAndSettle();
    expect(find.text(DateFormat('EEEE, MMMM d').format(now.add(const Duration(days: 1)))), findsOneWidget);
    expect(find.text(todayLabel), findsNothing);
  });
}
