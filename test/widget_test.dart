import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/main.dart';
import 'package:flowstate/screens/main_shell.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Flowstate smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppStateProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const FlowstateApp(home: MainShell()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FlowstateApp), findsOneWidget);
    expect(find.byType(MainShell), findsOneWidget);
  });
}
