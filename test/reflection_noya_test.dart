import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/noya_motion_view.dart';
import 'package:flowstate/screens/task_feedback_sheet.dart';
import 'package:flowstate/services/flow_clock.dart';

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
  });

  testWidgets('Noya reflects with the user: her pose follows the chosen feeling', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TaskFeedbackContent(taskId: 't', actualMinutes: 30)),
    ));

    NoyaMotionView noya() => tester.widget<NoyaMotionView>(find.byKey(const Key('reflection_noya')));
    expect(noya().pose, NoyaState.encouraging, reason: 'listening before an answer');

    const expected = {1: NoyaState.sleepy, 2: NoyaState.idle, 3: NoyaState.proud, 4: NoyaState.celebrating};
    for (final entry in expected.entries) {
      await tester.tap(find.bySemanticsLabel(RegExp('^Rate feeling')).at(entry.key - 1));
      await tester.pump();
      expect(noya().pose, entry.value, reason: 'feeling ${entry.key}');
    }
    await tester.pump(const Duration(seconds: 9)); // let the 8 s auto-close timer run out
  });
}
