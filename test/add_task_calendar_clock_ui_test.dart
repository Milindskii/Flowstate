import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/add_task_sheet.dart';
import 'package:flowstate/theme/flow_colors.dart';
import 'package:flowstate/theme/flow_theme.dart';

void main() {
  group('Add Task Calendar & Clock Polished UI Tests', () {
    testWidgets('1. AddTaskSheet date and time buttons render with polished themed styles', (tester) async {
      final appState = AppStateProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AddTaskSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find Date and Time buttons
      final dateBtnFinder = find.byKey(const Key('add_task_date_button'));
      final timeBtnFinder = find.byKey(const Key('add_task_time_button'));
      expect(dateBtnFinder, findsOneWidget);
      expect(timeBtnFinder, findsOneWidget);

      // Verify preset chips render cleanly
      expect(find.byKey(const Key('add_task_preset_today')), findsOneWidget);
      expect(find.byKey(const Key('add_task_preset_tomorrow')), findsOneWidget);

      // Tapping preset activates subtle checkmark & glow
      await tester.tap(find.byKey(const Key('add_task_preset_today')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byKey(const Key('add_task_clear_date')), findsOneWidget);
    });

    testWidgets('2. Date picker dialog opens with unified theme and can be confirmed', (tester) async {
      final appState = AppStateProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AddTaskSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Date picker button
      await tester.tap(find.byKey(const Key('add_task_date_button')));
      await tester.pumpAndSettle();

      // Verify DatePickerDialog is rendered
      expect(find.byType(DatePickerDialog), findsOneWidget);

      // Confirm with 'Done'
      final doneBtn = find.text('Done').hitTestable().first;
      await tester.tap(doneBtn);
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsNothing);
    });

    testWidgets('3. Time picker clock dialog opens with unified theme and can be confirmed', (tester) async {
      final appState = AppStateProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AddTaskSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Time picker button
      await tester.tap(find.byKey(const Key('add_task_time_button')));
      await tester.pumpAndSettle();

      // Verify TimePickerDialog is rendered
      expect(find.byType(TimePickerDialog), findsOneWidget);

      // Confirm with 'Done'
      final doneBtn = find.text('Done').hitTestable().first;
      await tester.tap(doneBtn);
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
    });

    testWidgets('4. FlowTheme configures datePickerTheme and timePickerTheme for both light and dark mode', (tester) async {
      final light = FlowTheme.lightTheme();
      final dark = FlowTheme.darkTheme();

      expect(light.datePickerTheme.backgroundColor, FlowColors.surfaceLight);
      expect(dark.datePickerTheme.backgroundColor, FlowColors.surfaceElevatedDark);
      expect(light.datePickerTheme.surfaceTintColor, Colors.transparent);
      expect(dark.datePickerTheme.surfaceTintColor, Colors.transparent);

      expect(light.timePickerTheme.backgroundColor, FlowColors.surfaceLight);
      expect(dark.timePickerTheme.backgroundColor, FlowColors.surfaceElevatedDark);
      expect(light.timePickerTheme.dialBackgroundColor, FlowColors.surfaceContainerLight);
      expect(dark.timePickerTheme.dialBackgroundColor, FlowColors.surfaceContainerDark);
    });
  });
}
