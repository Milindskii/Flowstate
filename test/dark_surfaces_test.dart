import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/secondary_button.dart';
import 'package:flowstate/theme/flow_colors.dart';
import 'package:flowstate/theme/flow_theme.dart';

/// Dark-mode QA (screenshots 2026-10-03): no light surface may leak into dark mode through
/// light-only aliases or Material's default dark container palette.
void main() {
  ThemeData darkTheme() => FlowTheme.darkTheme();

  testWidgets('dark theme pins dialog, sheet, menu and snackbar surfaces to Flowstate tokens', (tester) async {
    final dark = darkTheme();
    expect(dark.dialogTheme.backgroundColor, FlowColors.surfaceElevatedDark);
    expect(dark.bottomSheetTheme.backgroundColor, FlowColors.surfaceDark);
    expect(dark.bottomSheetTheme.modalBackgroundColor, FlowColors.surfaceDark);
    expect(dark.popupMenuTheme.color, FlowColors.surfaceElevatedDark);
    expect(dark.snackBarTheme.backgroundColor, FlowColors.surfaceElevatedDark);
    expect(dark.colorScheme.surfaceContainerHigh, FlowColors.surfaceElevatedDark);
    expect(dark.colorScheme.surfaceContainer, FlowColors.surfaceDark);
    expect(dark.appBarTheme.backgroundColor, Colors.transparent);
  });

  testWidgets('SecondaryButton uses the dark surface in dark mode', (tester) async {
    final dark = darkTheme();
    await tester.pumpWidget(MaterialApp(
      theme: dark,
      home: Scaffold(body: SecondaryButton(label: 'Edit', onPressed: () {})),
    ));
    final box = tester.widget<Container>(find.ancestor(of: find.text('Edit'), matching: find.byType(Container)).last);
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, FlowColors.surfaceDark);
    expect((decoration.border as Border).top.color, FlowColors.borderDark);
  });
}
