import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/components/ai_economy_sheets.dart';
import 'package:flowstate/screens/brain_dump_sheet.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';

import 'gemini_brain_dump_pro_test.dart' show MockAISubscriptionApiService, createTestApp;

const int kLimit = 12; // the server tells the app its limit; a small one keeps these tests readable

String words(int n) => List.filled(n, 'word').join(' ');

class LimitApi extends MockAISubscriptionApiService {
  bool tooLongFromServer = false;

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    final base = await super.get(endpoint, queryParams: queryParams);
    if (endpoint == '/api/v1/ai/status' && base is Map) return <String, dynamic>{...base, 'max_input_words': kLimit};
    return base;
  }

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint == '/api/v1/ai/plan' && tooLongFromServer) {
      aiPlanCallCount++;
      throw const ApiException('too long', statusCode: 422, data: {
        'detail': 'That is a bit long for one plan. Please trim it to 12 words or fewer. Nothing was charged.',
        'failure_code': 'input_too_long',
        'limit_words': kLimit,
        'words': kLimit + 3,
      });
    }
    return super.post(endpoint, body: body);
  }
}

Future<void> openSheet(WidgetTester tester, LimitApi api, {String? initialText}) async {
  await tester.pumpWidget(createTestApp(
    api: api,
    child: Builder(
      builder: (ctx) => ElevatedButton(
        onPressed: () => showBrainDumpSheet(ctx, initialText: initialText),
        child: const Text('Open'),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder get field => find.byKey(const Key('brain_dump_text_field'));
Finder get counter => find.byKey(const Key('brain_dump_word_counter'));
String counterText(WidgetTester tester) => tester.widget<Text>(counter).data!;

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({kGeminiPrivacyAcceptedKey: true});
  });
  tearDown(() => FlowClock().stopTimer());

  testWidgets('shows a live "words / limit" counter that follows typing', (tester) async {
    await openSheet(tester, LimitApi());
    expect(counterText(tester), '0 / $kLimit words');
    await tester.enterText(field, words(5));
    await tester.pump();
    expect(counterText(tester), '5 / $kLimit words');
    await tester.enterText(field, '  ${words(3)}\n\n${words(2)},  ');
    await tester.pump();
    expect(counterText(tester), '5 / $kLimit words');
  });

  testWidgets('typing past the limit is blocked and the text is kept', (tester) async {
    await openSheet(tester, LimitApi());
    await tester.enterText(field, words(kLimit));
    await tester.pump();
    await tester.enterText(field, '${words(kLimit)} extra');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, words(kLimit));
    expect(counterText(tester), '$kLimit / $kLimit words');
  });

  testWidgets('a paste that does not fit is rejected whole, kept as it was, and explained', (tester) async {
    await openSheet(tester, LimitApi());
    await tester.enterText(field, words(4));
    await tester.pump();
    await tester.enterText(field, '${words(4)} ${words(30)}');
    await tester.pump();
    await tester.pump(); // the note lands on the frame after the refusal
    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, words(4), reason: 'never silently truncated');
    expect(find.textContaining('over the limit'), findsOneWidget);
  });

  testWidgets('a paste that fits is accepted', (tester) async {
    await openSheet(tester, LimitApi());
    await tester.enterText(field, words(4));
    await tester.pump();
    await tester.enterText(field, '${words(4)} ${words(6)}');
    await tester.pump();
    expect(counterText(tester), '10 / $kLimit words');
  });

  testWidgets('prefilled text over the limit keeps its text, blocks Build and says how much to trim', (tester) async {
    await openSheet(tester, LimitApi(), initialText: words(kLimit + 5));
    expect(tester.widget<TextField>(field).controller!.text, words(kLimit + 5));
    final button = tester.widget<ElevatedButton>(find.byKey(const Key('brain_dump_build_button')));
    expect(button.onPressed, isNull);
    expect(find.text('Trim 5 words to continue'), findsOneWidget);
  });

  testWidgets('the Build button works at exactly the limit', (tester) async {
    await openSheet(tester, LimitApi());
    await tester.enterText(field, words(kLimit));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.byKey(const Key('brain_dump_build_button'))).onPressed, isNotNull);
  });

  testWidgets('a server "input_too_long" answer is shown inline with the text kept, not as a Noya failure', (tester) async {
    final api = LimitApi()..tooLongFromServer = true;
    await openSheet(tester, api);
    await tester.enterText(field, 'Finish lab. Call dentist. Plan trip. Buy gifts. Pack bags.'); // 10 words: fits, but still needs AI
    await tester.pump();
    await tester.tap(find.byKey(const Key('brain_dump_build_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Please trim it to 12 words or fewer'), findsOneWidget);
    expect(find.text('Noya is resting'), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, contains('Finish lab'));
  });
}
