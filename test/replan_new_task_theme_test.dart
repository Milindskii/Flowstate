import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flowstate/components/replan_new_task_sheet.dart';
import 'package:flowstate/theme/flow_theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final dark in [false, true]) {
    testWidgets('new-task sheet lays out under the real ${dark ? 'dark' : 'light'} theme', (tester) async {
      final theme = dark ? FlowTheme.darkTheme() : FlowTheme.lightTheme();
      await tester.pumpWidget(MaterialApp(theme: theme, home: const Scaffold(body: ReplanNewTaskSheet())));
      await tester.pump();
      final time = find.byKey(const Key('replan_new_task_time'));
      expect(time, findsOneWidget);
      expect(tester.getSize(time).width.isFinite, isTrue);

      // Verify no harsh checkmark icons exist
      expect(find.byIcon(Icons.check), findsNothing);
    });
  }

  testWidgets('new-task sheet supports title entry, duration selection and submission', (tester) async {
    ReplanNewTaskResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlowTheme.lightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await ReplanNewTaskSheet.show(ctx);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Verify header and hint
    expect(find.text('What came up?'), findsOneWidget);
    expect(find.byKey(const Key('replan_new_task_title')), findsOneWidget);

    // Enter title
    await tester.enterText(find.byKey(const Key('replan_new_task_title')), 'Fix critical auth bug');
    await tester.pump();

    // Select 30 min preset
    await tester.tap(find.byKey(const Key('replan_new_task_min_30')));
    await tester.pump();

    // Submit
    await tester.tap(find.byKey(const Key('replan_new_task_submit')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.title, 'Fix critical auth bug');
    expect(result!.time, isNull);
    expect(result!.isNoyaPick, isTrue);
  });

  testWidgets('editing mode displays Edit task and Save changes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlowTheme.lightTheme(),
        home: const Scaffold(
          body: ReplanNewTaskSheet(
            initialTitle: 'Existing urgent task',
            initialMinutes: 60,
            editing: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Edit task'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });
}
