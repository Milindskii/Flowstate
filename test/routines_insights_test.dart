import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/routines_section.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/routine_service.dart';
import 'package:flowstate/services/timezone_service.dart';

/// A routine server: list / create / patch / delete / continuation, like the real one (weekly cycles).
class _RoutineApi extends ApiService {
  final List<Map<String, dynamic>> routines = [];
  final List<String> calls = [];
  final List<Map<String, dynamic>> bodies = [];

  @override
  bool get isAuthenticated => true;

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    calls.add('GET $endpoint');
    return routines.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    calls.add('POST $endpoint');
    bodies.add(Map<String, dynamic>.from(body as Map));
    if (endpoint == '/api/v1/routines') {
      final b = body;
      final r = {
        'id': 'r${routines.length + 1}',
        'title': b['title'],
        'kind': 'fixed',
        'recurrence': b['recurrence'],
        'weekdays': b['weekdays'],
        'start_hhmm': b['start_hhmm'],
        'estimated_minutes': b['estimated_minutes'],
        'summary': '',
        'confirmed_through': '2026-10-11',
        'continuation_due': false,
      };
      routines.add(r);
      return {'routine': r, 'created_count': 3, 'planned_dates': []};
    }
    if (endpoint.endsWith('/continuation')) {
      final id = endpoint.split('/')[4];
      final r = routines.firstWhere((x) => x['id'] == id);
      if (body['decision'] == 'continue') {
        r['confirmed_through'] = '2026-10-18';
        r['continuation_due'] = false;
        r['paused'] = false;
        return {'routine': r, 'created_count': 3};
      }
      r['continuation_due'] = false;
      return {'routine': r, 'created_count': 0};
    }
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> patch(String endpoint, {dynamic body}) async {
    calls.add('PATCH $endpoint');
    bodies.add(Map<String, dynamic>.from(body as Map));
    final id = endpoint.split('/').last;
    final r = routines.firstWhere((x) => x['id'] == id);
    final b = body;
    if (b['weekdays'] != null) r['weekdays'] = b['weekdays'];
    if (b['start_hhmm'] != null) r['start_hhmm'] = b['start_hhmm'];
    return {'routine': r, 'created_count': 0};
  }

  @override
  Future<dynamic> delete(String endpoint) async {
    calls.add('DELETE $endpoint');
    routines.removeWhere((r) => endpoint.contains('/${r['id']}'));
    return <String, dynamic>{};
  }
}

Map<String, dynamic> _gym({bool due = false}) => {
      'id': 'gym',
      'title': 'Gym',
      'kind': 'fixed',
      'recurrence': 'weekly',
      'weekdays': [0, 2, 4],
      'start_hhmm': '19:00',
      'estimated_minutes': 60,
      'summary': 'Every Mon, Wed, Fri · 7:00 PM',
      'confirmed_through': '2026-10-11',
      'continuation_due': due,
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
  });

  Future<void> pump(WidgetTester tester, _RoutineApi api, {bool autoAsk = true}) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RoutinesSection(key: UniqueKey(), service: RoutineService(api: api), autoAsk: autoAsk),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('create a weekly routine: name, Mon/Wed/Fri, time and duration; shown as days · time · length',
      (tester) async {
    final api = _RoutineApi();
    await pump(tester, api);
    expect(find.byKey(const Key('routines_empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('routine_add_button')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('routine_save_button'))).onPressed, isNull,
        reason: 'a name and at least one day are needed');
    await tester.enterText(find.byKey(const Key('routine_title_field')), 'Gym');
    for (final d in [0, 2, 4]) {
      await tester.tap(find.byKey(Key('routine_day_$d')));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routine_save_button')));
    await tester.pumpAndSettle();

    final created = api.bodies.firstWhere((b) => b.containsKey('idempotency_key'));
    expect(created['weekdays'], [0, 2, 4]);
    expect(created['recurrence'], 'weekly');
    expect(created['start_hhmm'], '19:00');
    expect(created['estimated_minutes'], 60);
    expect(find.text('Mon · Wed · Fri · 7:00 PM · 60 min'), findsOneWidget);
    expect(api.calls.where((c) => c.contains('/ai/')), isEmpty, reason: 'never AI');
    expect(api.calls.where((c) => c.contains('shield')), isEmpty, reason: 'never a Shield');
  });

  testWidgets('edit the days of a routine and remove it', (tester) async {
    final api = _RoutineApi()..routines.add(_gym());
    await pump(tester, api);
    await tester.tap(find.byKey(const Key('routine_tile_gym')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routine_day_4'))); // drop Friday
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routine_save_button')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('PATCH /api/v1/routines/gym'));
    expect(api.bodies.last['weekdays'], [0, 2]);
    expect(find.text('Mon · Wed · 7:00 PM · 60 min'), findsOneWidget);

    await tester.tap(find.byKey(const Key('routine_delete_gym')));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.startsWith('DELETE /api/v1/routines/gym')), hasLength(1));
    expect(find.byKey(const Key('routines_empty')), findsOneWidget);
  });

  testWidgets('end of the week: Noya asks once; Continue plans next week with replay protection', (tester) async {
    final api = _RoutineApi()..routines.add(_gym(due: true));
    await pump(tester, api);
    expect(find.byKey(const Key('routine_continue_dialog')), findsOneWidget);
    expect(find.text('Continue your routine next week?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('routine_dialog_continue')));
    await tester.pumpAndSettle();

    final answer = api.bodies.last;
    expect(answer['decision'], 'continue');
    expect(answer['cycle_end'], '2026-10-11', reason: 'the cycle the app saw: a retry cannot plan twice');
    expect(api.calls.where((c) => c.endsWith('/continuation')), hasLength(1));
    expect(find.byKey(const Key('routine_continue_prompt_gym')), findsNothing);
    expect(api.calls.where((c) => c.contains('shield') || c.contains('/ai/')), isEmpty, reason: 'free');
  });

  testWidgets('Not now plans nothing; the dialog is not repeated on the next open in the same cycle', (tester) async {
    final api = _RoutineApi()..routines.add(_gym(due: true));
    await pump(tester, api);
    await tester.tap(find.byKey(const Key('routine_dialog_not_now')));
    await tester.pumpAndSettle();
    expect(api.bodies.last['decision'], 'not_now');

    // the server would no longer report it due; even if it did, this device already asked for this cycle
    api.routines.first['continuation_due'] = true;
    await pump(tester, api);
    expect(find.byKey(const Key('routine_continue_dialog')), findsNothing);
    expect(find.byKey(const Key('routine_continue_prompt_gym')), findsOneWidget, reason: 'still answerable inline');
  });

  testWidgets('a dismissed question stays inline and a double tap on Continue sends one answer', (tester) async {
    final api = _RoutineApi()..routines.add(_gym(due: true));
    await pump(tester, api);
    await tester.tapAt(const Offset(5, 5)); // dismiss the dialog
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('routine_continue_prompt_gym')), findsOneWidget);
    await tester.tap(find.byKey(const Key('routine_continue_gym')));
    await tester.tap(find.byKey(const Key('routine_continue_gym')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.endsWith('/continuation')), hasLength(1));
  });

  testWidgets('a paused routine can still be continued later from Insights', (tester) async {
    final api = _RoutineApi()..routines.add(_gym(due: true));
    await pump(tester, api, autoAsk: false);
    await tester.tap(find.byKey(const Key('routine_not_now_gym')));
    await tester.pumpAndSettle();
    api.routines.first['paused'] = true;
    await pump(tester, api, autoAsk: false);
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.byKey(const Key('routine_continue_gym')));
    await tester.pumpAndSettle();
    expect(api.bodies.last['decision'], 'continue');
  });
}
