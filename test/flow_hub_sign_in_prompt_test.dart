import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/auth_screen.dart';
import 'package:flowstate/screens/flow_screen.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  test('isAuthRequired is true only for the signed-out state', () async {
    final api = ApiService(client: MockClient((_) async => http.Response(jsonEncode({}), 401)));
    final flow = FlowProvider(api: api);
    expect(flow.isAuthRequired, isFalse);
    await flow.loadOverview();
    expect(flow.isAuthRequired, isTrue);
  });

  testWidgets('signed out, Flow Hub shows a friendly sign-in prompt instead of a raw auth error', (tester) async {
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = ApiService(client: MockClient((_) async => http.Response(jsonEncode({}), 401)));
    final flow = FlowProvider(api: api);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: AppStateProvider(customApi: api)),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ChangeNotifierProvider<FlowProvider>.value(value: flow),
      ],
      child: const MaterialApp(home: FlowScreen()),
    ));
    await flow.loadOverview();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Sign in to sync your progress'), findsOneWidget);
    expect(find.text('Authentication required. Please sign in.'), findsNothing);
    expect(find.text('Retry'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(AuthScreen), findsOneWidget);
  });
}
