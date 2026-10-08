import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/pro_subscription_screen.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/theme/flow_theme.dart';

class _OfflineApi extends ApiService {
  final List<String> posts = [];
  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async => throw const ApiException('offline');
  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    posts.add(endpoint);
    return {};
  }
}

void main() {
  Future<_OfflineApi> pump(WidgetTester tester, {Size size = const Size(390, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = _OfflineApi();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>(create: (_) => AppStateProvider(customApi: api)),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: FlowTheme.lightTheme(), home: const ProSubscriptionScreen()),
    ));
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('both plans, yearly preselected and marked best value; selecting switches the CTA and footer', (tester) async {
    await pump(tester);
    expect(find.text('₹2.97/day'), findsOneWidget);
    expect(find.text('₹89 billed monthly'), findsOneWidget);
    expect(find.text('₹2.74/day'), findsOneWidget);
    expect(find.text('₹999 billed yearly'), findsOneWidget);
    expect(find.text('BEST VALUE'), findsOneWidget);
    expect(find.text('Continue with Yearly'), findsOneWidget);
    expect(find.textContaining('₹999 billed yearly. Cancel anytime.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pro_plan_monthly')));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Monthly'), findsOneWidget);
    expect(find.textContaining('₹89 billed monthly. Cancel anytime.'), findsOneWidget);
  });

  testWidgets('the action never pretends a purchase: it says subscribing is not open and sends nothing', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const Key('pro_continue_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pro_not_open_dialog')), findsOneWidget);
    expect(find.textContaining('Nothing was charged'), findsOneWidget);
    expect(find.textContaining('success', findRichText: true), findsNothing);
    expect(api.posts, isEmpty);
  });

  testWidgets('fits a 320 dp phone without overflow, with the disclosure and the action visible', (tester) async {
    await pump(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('pro_continue_button')), findsOneWidget);
    expect(find.byKey(const Key('pro_footer_disclosure')), findsOneWidget);
  });
}
