import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/replan_day_sheet.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';

/// AI Replan economy, client side: the Shield is asked for BEFORE the model is used (the server says
/// `ai_required`, nothing is charged), cancelling costs nothing, the confirmed resend reuses the request id, and a
/// missing Shield is a resting Noya with the message kept. Authoritative accounting: backend/tests/test_replan_shield_economy.py.
const _message = 'scrap the evening plans with friends';

Map<String, dynamic> _diff({Map<String, dynamic>? aiRequired}) => {
      'success': true,
      'plan_diff': {
        'plan_id': 'p1',
        'selected_date': '2026-10-05',
        'before_schedule': [],
        'after_schedule': [],
        'moved_tasks': [],
        'cancelled_tasks': [],
        'conflicts': [],
        'explanation': 'ok',
      },
      'user_intent_summary': _message,
      if (aiRequired != null) 'ai_required': aiRequired,
    };

class _Server {
  final List<Map<String, dynamic>> bodies = [];
  final Map<String, dynamic> Function(Map<String, dynamic> body) answer;
  _Server(this.answer);

  MockClient get client => MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        bodies.add(body);
        return http.Response(jsonEncode(answer(body)), 200);
      });
}

Future<void> _open(WidgetTester tester, MockClient client) async {
  final provider = AppStateProvider(customApi: ApiService(client: client));
  await tester.pumpWidget(ChangeNotifierProvider<AppStateProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showReplanDaySheet(context, selectedDate: DateTime(2026, 10, 5)),
            child: const Text('Open Replan'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open Replan'));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, [String text = _message]) async {
  await tester.enterText(find.byKey(const Key('replan_composer')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('replan_send')));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Map<String, dynamic> _need({bool canAfford = true, int shields = 2}) =>
    {'kind': 'shield', 'shield_cost': 1, 'shields_available': shields, 'can_afford': canAfford};

String _draft(WidgetTester tester) => tester.widget<TextField>(find.byKey(const Key('replan_composer'))).controller!.text;

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => FlowClock().stopTimer());

  testWidgets('a rules-only replan never shows the Shield sheet and sends no consent', (tester) async {
    final server = _Server((_) => _diff());
    await _open(tester, server.client);
    await _send(tester, 'skip gym');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shield_reason_text')), findsNothing);
    expect(server.bodies, hasLength(1));
    expect(server.bodies.single.containsKey('ai_consent'), isFalse);
  });

  testWidgets('AI needed: Noya asks first with the exact copy, and nothing else is sent until the user confirms',
      (tester) async {
    final server = _Server((b) => b['ai_consent'] == true ? _diff() : _diff(aiRequired: _need()));
    await _open(tester, server.client);
    await _send(tester);

    expect(find.text('Noya can reshape your day using 1 Shield.'), findsOneWidget);
    expect(find.text('Use 1 Shield to let Noya reshape your day?'), findsOneWidget);
    expect(find.text('Use 1 Shield'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(server.bodies, hasLength(1), reason: 'the first request carried no consent');
    expect(server.bodies.first.containsKey('ai_consent'), isFalse);

    await tester.tap(find.byKey(const Key('use_shields_button')));
    await tester.pumpAndSettle();
    expect(server.bodies, hasLength(2));
    expect(server.bodies[1]['ai_consent'], isTrue);
    expect(server.bodies[1]['idempotency_key'], server.bodies[0]['idempotency_key'],
        reason: 'the confirmed resend reuses the request id: the server can never charge twice');
    expect(find.byKey(const Key('shield_reason_text')), findsNothing);
  });

  testWidgets('Cancel: no second request, no charge, the message stays, nothing scary shown', (tester) async {
    final server = _Server((_) => _diff(aiRequired: _need()));
    await _open(tester, server.client);
    await _send(tester);
    await tester.tap(find.byKey(const Key('shield_not_now_button')));
    await tester.pumpAndSettle();

    expect(server.bodies, hasLength(1));
    expect(find.textContaining('no Shield was used'), findsOneWidget);
    expect(_draft(tester), _message);
    expect(find.textContaining('HTTP'), findsNothing);
  });

  testWidgets('double tapping Use 1 Shield sends exactly one confirmed request', (tester) async {
    final server = _Server((b) => b['ai_consent'] == true ? _diff() : _diff(aiRequired: _need()));
    await _open(tester, server.client);
    await _send(tester);
    final confirm = find.byKey(const Key('use_shields_button'));
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(server.bodies.where((b) => b['ai_consent'] == true), hasLength(1));
  });

  testWidgets('no Shield to pay: no sheet, no second request, a resting Noya, the message is kept', (tester) async {
    final server = _Server((_) => _diff(aiRequired: _need(canAfford: false, shields: 0)));
    await _open(tester, server.client);
    await _send(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shield_reason_text')), findsNothing);
    expect(server.bodies, hasLength(1));
    expect(find.textContaining("Noya can't use AI for this one right now"), findsOneWidget);
    expect(_draft(tester), _message);
  });

  testWidgets('losing a race for the last Shield after confirming is a calm message, not an error', (tester) async {
    final server = _Server((_) => _diff(aiRequired: _need()));
    await _open(tester, server.client);
    await _send(tester);
    await tester.tap(find.byKey(const Key('use_shields_button')));
    await tester.pumpAndSettle();

    expect(server.bodies, hasLength(2));
    expect(find.textContaining('no Shield was used'), findsOneWidget);
    expect(_draft(tester), _message);
  });
}
