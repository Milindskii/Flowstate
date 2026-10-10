import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/screens/brain_dump_sheet.dart';
import 'package:flowstate/screens/legal/privacy_policy_screen.dart';
import 'package:flowstate/services/flow_clock.dart';

import 'gemini_brain_dump_pro_test.dart' show MockAISubscriptionApiService, createTestApp;

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => FlowClock().stopTimer());

  testWidgets('Build My Day shows a privacy entry point before the first dump, with no provider name', (tester) async {
    await tester.pumpWidget(createTestApp(
      api: MockAISubscriptionApiService(),
      child: Builder(
        builder: (ctx) => ElevatedButton(onPressed: () => showBrainDumpSheet(ctx), child: const Text('Open')),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bmd_privacy_info_link')), findsOneWidget);
    expect(find.textContaining('Gemini'), findsNothing);
    expect(find.textContaining('Google'), findsNothing);

    await tester.tap(find.byKey(const Key('bmd_privacy_info_link')));
    await tester.pumpAndSettle();
    expect(find.text('How Build My Day uses your notes'), findsOneWidget);
    expect(find.textContaining('Gemini'), findsNothing);
    expect(find.textContaining('Google'), findsNothing);

    await tester.tap(find.byKey(const Key('privacy_policy_link')));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
  });
}
