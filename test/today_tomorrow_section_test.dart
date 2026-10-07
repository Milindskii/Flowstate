import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/models/today_model.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/today_dashboard_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';

/// Today stays today's execution view; tomorrow's open tasks are a separate TOMORROW section
/// (manual verification 2026-10-06). The backend owns the list; the app only renders it.
class _TodayApi extends ApiService {
  final Map<String, dynamic> today;
  _TodayApi(this.today);

  @override
  Future<dynamic> get(String endpoint, {Map<String, String>? queryParams}) async {
    if (endpoint == '/api/v1/today') return Map<String, dynamic>.from(today);
    return <dynamic>[];
  }
}

Map<String, dynamic> _todayJson({List<Map<String, dynamic>> tomorrow = const []}) => {
      'lifecycle_state': 'calibrated',
      'state': 'calibrated',
      'has_actionable_tasks': true,
      'upcoming_timeline': [
        {
          'id': 'sched-today-1',
          'time': '4:00',
          'period': 'PM',
          'title': 'Today only task',
          'type': 'admin',
          'tag_text': 'LIGHT',
          'duration_minutes': 30,
        },
      ],
      'tomorrow_tasks': tomorrow,
    };

Future<void> _pumpToday(WidgetTester tester, Map<String, dynamic> today) async {
  final appState = AppStateProvider(customApi: _TodayApi(today));
  appState.setCalibratedStateForTesting();
  await tester.runAsync(() => appState.refreshTodayData());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: appState),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const TodayDashboardTab(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => FlowClock().stopTimer());

  group('TodayResponseModel.tomorrowTasks', () {
    test('absent key -> empty list (older backend)', () {
      expect(TodayResponseModel.fromJson(_todayJson()).tomorrowTasks, isEmpty);
    });

    test('round-trips through toJson, so the offline cache keeps it across a restart', () {
      final model = TodayResponseModel.fromJson(_todayJson(tomorrow: [
        {
          'id': 't1',
          'title': 'Dentist',
          'start_time': '2026-10-07T04:30:00+00:00',
          'duration_minutes': 45,
          'is_commitment': true,
        },
        {'id': 't2', 'title': 'Laundry', 'start_time': null, 'duration_minutes': 30, 'is_commitment': false},
      ]));
      expect(model.tomorrowTasks.map((t) => t.title), ['Dentist', 'Laundry']);
      expect(model.tomorrowTasks[0].isCommitment, isTrue);
      expect(model.tomorrowTasks[1].startTime, isNull);

      final again = TodayResponseModel.fromJson(model.toJson());
      expect(again.tomorrowTasks.map((t) => (t.id, t.title, t.durationMinutes, t.isCommitment)),
          model.tomorrowTasks.map((t) => (t.id, t.title, t.durationMinutes, t.isCommitment)));
      expect(again.tomorrowTasks[0].startTime, model.tomorrowTasks[0].startTime);
    });
  });

  group('TOMORROW section on Today', () {
    testWidgets('shows tomorrow tasks in their own section, not in today\'s timeline', (tester) async {
      await _pumpToday(tester, _todayJson(tomorrow: [
        {'id': 't1', 'title': 'Tomorrow slot', 'start_time': '2026-10-07T04:30:00+00:00', 'duration_minutes': 45},
        {'id': 't2', 'title': 'Tomorrow anytime', 'start_time': null, 'duration_minutes': 30},
      ]));
      await tester.scrollUntilVisible(find.byKey(const Key('today_tomorrow_section')), 300,
          scrollable: find.byType(Scrollable).first);

      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('Tomorrow slot'), findsOneWidget);
      expect(find.text('Tomorrow anytime'), findsOneWidget);
      expect(find.text('Anytime'), findsOneWidget);
      expect(find.text('45m'), findsOneWidget);
      // today's own view is untouched
      expect(find.text('Today only task'), findsWidgets);
    });

    testWidgets('no section when tomorrow has no tasks', (tester) async {
      await _pumpToday(tester, _todayJson());
      expect(find.text('TOMORROW'), findsNothing);
      expect(find.byKey(const Key('today_tomorrow_section')), findsNothing);
    });

    testWidgets('long lists are capped with a "+N more" line', (tester) async {
      await _pumpToday(tester, _todayJson(tomorrow: [
        for (var i = 1; i <= 7; i++) {'id': 't$i', 'title': 'Tomorrow task $i', 'duration_minutes': 20},
      ]));
      await tester.scrollUntilVisible(find.byKey(const Key('today_tomorrow_section')), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('+2 more'), findsOneWidget);
      expect(find.text('Tomorrow task 6'), findsNothing);
    });
  });
}
