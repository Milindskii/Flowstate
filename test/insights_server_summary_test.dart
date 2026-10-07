import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/insights_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';

/// Insights reads the account history from GET /insights/summary (2026-10-07): ready sections show their real
/// numbers and sample sizes; "learning" sections show nothing but what is still needed.
class _Api extends ApiService {
  final Map<String, dynamic> history;
  final List<String> gets = [];

  _Api(this.history);

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    gets.add(endpoint);
    if (endpoint == '/api/v1/insights/summary') return {'history': history};
    if (endpoint == '/api/v1/tasks') return {'items': [], 'total': 0};
    return <String, dynamic>{};
  }
}

const _user = AuthUser(id: 'user-ins', email: 'i@flowstate.local', name: 'I', onboardingCompleted: true);

Map<String, dynamic> _learning(String unit) => {'status': 'learning', 'sample_size': 0, 'needed': 3, 'unit': unit};

Future<_Api> _pump(WidgetTester tester, Map<String, dynamic> history) async {
  tester.view.physicalSize = const Size(412, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _Api(history);
  final state = AppStateProvider(customApi: api, initialUser: _user)..setTasksForTesting(const []);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(412, 3200)),
      child: ChangeNotifierProvider<AppStateProvider>.value(value: state, child: const InsightsTab()),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('learned routine, postponement and week trend come from the server history', (tester) async {
    final api = await _pump(tester, {
      'completion': {'status': 'ready', 'sample_size': 8, 'this_week': 0.75, 'last_week': 0.5, 'change_pts': 25,
                     'completed': 6, 'planned': 8},
      'routines': {'status': 'ready', 'sample_size': 1, 'items': [
        {'title': 'Gym', 'weekday': 'Tuesday', 'start_label': '7:00 PM', 'weeks_seen': 4, 'weeks_span': 5},
      ]},
      'postponement': {'status': 'ready', 'sample_size': 12, 'categories': [
        {'category': 'Admin', 'rate': 0.4, 'sample_size': 10, 'skipped': 1, 'deferred': 3, 'missed': 0},
      ]},
      'focus': _learning('reflections'),
    });
    expect(api.gets, contains('/api/v1/insights/summary'));
    expect(find.byKey(const Key('insights_routines')), findsOneWidget);
    expect(find.textContaining('Gym · Tuesdays around 7:00 PM (4 of the last 5 weeks)'), findsOneWidget);
    expect(find.textContaining('Admin gets pushed back most: 40% of the time'), findsOneWidget);
    expect(find.textContaining('up 25 points from last week'), findsOneWidget);
  });

  testWidgets('a new account: no invented routine, trend or postponement numbers', (tester) async {
    await _pump(tester, {
      'completion': _learning('planned tasks this week'),
      'routines': _learning('weeks of a repeated task'),
      'postponement': _learning('tasks in one category'),
    });
    expect(find.byKey(const Key('insights_routines')), findsNothing);
    expect(find.byKey(const Key('insights_postponement')), findsNothing);
    expect(find.byKey(const Key('insights_week_trend')), findsNothing);
    expect(find.text("We're still learning your rhythm."), findsOneWidget);
  });
}
