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

Future<void> _open(WidgetTester tester, MockClient client) async {
  final provider = AppStateProvider(customApi: ApiService(client: client));
  // the provider sits ABOVE MaterialApp so the modal sheet (a route) can see it
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

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => FlowClock().stopTimer());

  testWidgets('long multiline input grows, stays capped, and the send button stays on screen', (tester) async {
    await _open(tester, MockClient((_) async => http.Response('{}', 200)));
    final field = find.byKey(const Key('replan_composer'));
    final before = tester.getSize(field).height;
    await tester.enterText(field, List.generate(12, (i) => 'line ${i + 1} of a long message').join('\n'));
    await tester.pump();
    await tester.pumpAndSettle();
    final after = tester.getSize(field).height;
    expect(after, greaterThan(before));
    expect(after, lessThan(before * 7)); // capped (maxLines 6), scrolls inside
    expect(find.byKey(const Key('replan_send')), findsOneWidget);
    final send = tester.getRect(find.byKey(const Key('replan_send')));
    expect(send.bottom, lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio));
  });

  testWidgets('a failed replan shows plain language and keeps the draft', (tester) async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'detail': {
            'code': 'invalid_replan_request',
            'errors': [
              {'field': 'user_message', 'code': 'unrecognized_instruction', 'message': 'invalid_replan_request'}
            ]
          }
        }),
        422));
    await _open(tester, client);
    await tester.enterText(find.byKey(const Key('replan_composer')), 'do the thing please');
    await tester.pump();
    await tester.tap(find.byKey(const Key('replan_send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('invalid_replan_request'), findsNothing);
    expect(find.textContaining('field:'), findsNothing);
    expect(find.textContaining('code:'), findsNothing);
    final tf = tester.widget<TextField>(find.byKey(const Key('replan_composer')));
    expect(tf.controller!.text, 'do the thing please');
  });

  testWidgets('send is disabled for an empty draft and a failure offers a calm retry', (tester) async {
    var calls = 0;
    await _open(tester, MockClient((_) async {
      calls++;
      return http.Response('{"detail":"Internal error: model gemini_2 returned status 500 {code: x}"}', 500);
    }));
    final send = find.byKey(const Key('replan_send'));
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('replan_composer')), 'move gym later');
    await tester.pump();
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replan_error_bubble')), findsOneWidget);
    for (final leak in ['gemini', 'status 500', '{', 'code:', 'Internal error']) {
      expect(find.textContaining(leak), findsNothing, reason: leak);
    }
    final callsBefore = calls;
    await tester.tap(find.byKey(const Key('replan_retry')));
    await tester.pumpAndSettle();
    expect(calls, greaterThan(callsBefore));
    expect(find.byKey(const Key('replan_user_message')), findsOneWidget); // not duplicated by the retry
  });

  testWidgets('a very long user message folds behind Show more and unfolds', (tester) async {
    await _open(tester, MockClient((_) async => http.Response('{"detail":"nope"}', 500)));
    final long = List.generate(30, (i) => 'sentence number ${i + 1} explaining my day in detail').join(' ');
    await tester.enterText(find.byKey(const Key('replan_composer')), long);
    await tester.pump();
    await tester.tap(find.byKey(const Key('replan_send')));
    await tester.pumpAndSettle();
    expect(find.text('Show more'), findsOneWidget);
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('Urgent work arrived opens the naming sheet instead of sending immediately', (tester) async {
    var sent = false;
    await _open(tester, MockClient((_) async {
      sent = true;
      return http.Response('{}', 200);
    }));
    await tester.tap(find.text('Urgent work arrived'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replan_new_task_title')), findsOneWidget);
    expect(sent, false);
    // Submit stays disabled until a name is typed
    await tester.enterText(find.byKey(const Key('replan_new_task_title')), 'Finish API security testing');
    await tester.tap(find.byKey(const Key('replan_new_task_min_60')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('replan_new_task_submit')));
    await tester.pumpAndSettle();
    expect(sent, true);
    expect(find.text('Urgent: Finish API security testing · 60 min', skipOffstage: false), findsOneWidget);
  });
}
