import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/profile_settings_tab.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/theme/flow_colors.dart';
import 'package:flowstate/services/flow_clock.dart';

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => FlowClock().stopTimer());

  Future<AppStateProvider> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final appState = AppStateProvider();
    appState.setCurrentUserForTesting(const AuthUser(
      id: 'u1',
      email: 'tester@flowstate.local',
      name: 'Tester',
      onboardingCompleted: true,
    ));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: appState),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<FlowProvider>.value(value: FlowProvider()),
      ],
      child: const MaterialApp(home: ProfileSettingsTab()),
    ));
    await tester.pumpAndSettle();
    return appState;
  }

  testWidgets('Peak Focus Window tile opens a picker and saves the choice', (tester) async {
    final state = await pumpProfile(tester);
    await tester.ensureVisible(find.text('Peak Focus Window'));
    await tester.tap(find.text('Peak Focus Window'));
    await tester.pumpAndSettle();
    expect(find.text('Evening'), findsOneWidget);
    await tester.tap(find.text('Evening'));
    await tester.pumpAndSettle();
    expect(state.personalData.focusPeak, 'Evening');
  });

  testWidgets('Sleep Schedule tile opens an editor that saves sleep hours', (tester) async {
    final state = await pumpProfile(tester);
    await tester.ensureVisible(find.text('Sleep Schedule'));
    await tester.tap(find.text('Sleep Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Wake up'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(state.personalData.sleepHours, 4.0);
  });

  testWidgets('Energy Dip Time tile opens the time picker', (tester) async {
    await pumpProfile(tester);
    await tester.ensureVisible(find.text('Energy Dip Time'));
    await tester.tap(find.text('Energy Dip Time'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('Appearance controls change theme mode, accent and density', (tester) async {
    await pumpProfile(tester);
    final theme = Provider.of<ThemeProvider>(tester.element(find.byType(ProfileSettingsTab)), listen: false);
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(theme.themeMode, ThemeMode.dark);
    final accent = FlowAccent.values.last;
    await tester.tap(find.text(accent.label));
    await tester.pump();
    expect(theme.selectedAccent, accent);
    final density = DensityMode.values.last;
    await tester.tap(find.text(density.label));
    await tester.pump();
    expect(theme.densityMode, density);
  });
}
