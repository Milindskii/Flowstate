import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/flow_completion_check.dart';
import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/task_card.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/theme/flow_theme.dart';

TaskItem _task({TaskStatus status = TaskStatus.todo, bool completed = false}) => TaskItem(
      id: 't',
      title: 'Walk',
      durationMinutes: 60,
      difficulty: TaskDifficulty.high,
      deadline: 'Due Tomorrow',
      category: 'Work',
      status: completed ? TaskStatus.completed : status,
      isCompleted: completed,
    );

Widget _host(TaskItem task, {ThemeData? theme, double width = 412}) => MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: TaskCard(task: task, onToggleComplete: () {}))),
      ),
    );

BoxDecoration _card(WidgetTester tester) =>
    tester.widget<Container>(find.byKey(const Key('task_card_t'))).decoration! as BoxDecoration;

void main() {
  testWidgets('upcoming task: the task is the focus — light card, one quiet meta line, no decorative Noya', (tester) async {
    await tester.pumpWidget(_host(_task()));
    final d = _card(tester);
    expect(d.boxShadow, anyOf(isNull, isEmpty));
    expect(find.text('Priority not specified'), findsNothing);
    expect(find.byType(NoyaCompanionView), findsNothing);
    // Duration is the row's one number on the right; the meta line carries focus, category, deadline.
    expect(find.text('High Focus · Work · Due Tomorrow'), findsOneWidget);
    expect(find.byKey(const Key('task_card_duration_t')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('task_card_duration_t'))).dx,
        greaterThan(tester.getTopRight(find.text('High Focus · Work · Due Tomorrow')).dx - 1));
    // Check leads the row, before the title.
    expect(tester.getCenter(find.byType(FlowCompletionCheck)).dx, lessThan(tester.getTopLeft(find.text('Walk')).dx));
  });

  testWidgets('in-progress task is emphasized with a focusing Noya', (tester) async {
    await tester.pumpWidget(_host(_task(status: TaskStatus.inProgress)));
    final d = _card(tester);
    expect(d.color!.a, greaterThan(0));
    expect(find.text('In progress'), findsOneWidget);
    expect(tester.widget<NoyaCompanionView>(find.byType(NoyaCompanionView)).state, NoyaState.focusing);
  });

  testWidgets('completed task settles into a calm history state', (tester) async {
    await tester.pumpWidget(_host(_task(completed: true)));
    final d = _card(tester);
    expect(d.color, anyOf(isNull, Colors.transparent));
    expect(d.border, isNull);
    expect(d.boxShadow, anyOf(isNull, isEmpty));
    // No repeated Noya on finished tasks.
    expect(find.byType(NoyaCompanionView), findsNothing);
    expect(tester.widget<Text>(find.text('Walk')).style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('dark mode at 320dp renders without overflow', (tester) async {
    await tester.pumpWidget(_host(_task(status: TaskStatus.inProgress), theme: FlowTheme.darkTheme(), width: 320));
    expect(tester.takeException(), isNull);
  });
}
