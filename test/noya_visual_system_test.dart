import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/components/companion/flow_companion_animation_controller.dart';
import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/task_card.dart';
import 'package:flowstate/models/task_item.dart';

void main() {
  group('Noya Canonical Visual System - Unit & State Tests', () {
    test('1. Verify all 13 canonical Noya states exist and map to correct assets', () {
      expect(NoyaState.values.length, 13);

      expect(NoyaState.idle.assetPath, 'assets/images/companions/noya/noya_default.png');
      expect(NoyaState.focusing.assetPath, 'assets/images/companions/noya/noya_focusing.png');
      expect(NoyaState.celebrating.assetPath, 'assets/images/companions/noya/noya_celebrating.png');
      expect(NoyaState.thinking.assetPath, 'assets/images/companions/noya/noya_thinking.png');
      expect(NoyaState.sleepy.assetPath, 'assets/images/companions/noya/noya_sleepy.png');
      expect(NoyaState.proud.assetPath, 'assets/images/companions/noya/noya_proud.png');
      expect(NoyaState.encouraging.assetPath, 'assets/images/companions/noya/noya_encouraging.png');
      // Existing art in the root companions folder (spec §2.2), registered in Rev 2 (D2).
      expect(NoyaState.delighted.assetPath, 'assets/images/companions/noya_success.png');
      expect(NoyaState.windDown.assetPath, 'assets/images/companions/noya_sleeping.png');
      // Cut from the expression sheet (docs/ui-qa/screenshots), transparent 384 px.
      expect(NoyaState.goodJob.assetPath, 'assets/images/companions/noya/noya_good_job.png');
      expect(NoyaState.idea.assetPath, 'assets/images/companions/noya/noya_idea.png');
      expect(NoyaState.planning.assetPath, 'assets/images/companions/noya/noya_planning.png');
      expect(NoyaState.cheering.assetPath, 'assets/images/companions/noya/noya_cheering.png');
    });

    test('1b. New states carry their spec labels', () {
      expect(NoyaState.delighted.semanticLabel, 'Noya beaming with sparkling eyes, delighted with your plan');
      expect(NoyaState.windDown.semanticLabel, 'Noya getting drowsy as the day winds down');
      expect(NoyaState.delighted.displayName, 'Delighted');
      expect(NoyaState.windDown.displayName, 'Wind-down');
    });

    test('2. Verify all 9 canonical Noya asset files physically exist on disk', () {
      for (final state in NoyaState.values) {
        final file = File(state.assetPath);
        expect(file.existsSync(), isTrue, reason: 'Missing asset file: ${state.assetPath}');
        expect(file.lengthSync(), greaterThan(10000), reason: 'Asset file too small: ${state.assetPath}');
      }
    });

    test('3. Verify Android launcher icon assets exist in all density buckets', () {
      final densities = ['mipmap-mdpi', 'mipmap-hdpi', 'mipmap-xhdpi', 'mipmap-xxhdpi', 'mipmap-xxxhdpi'];
      for (final density in densities) {
        final iconFile = File('android/app/src/main/res/$density/ic_launcher.png');
        final roundIconFile = File('android/app/src/main/res/$density/ic_launcher_round.png');
        expect(iconFile.existsSync(), isTrue, reason: 'Missing launcher icon in $density');
        expect(roundIconFile.existsSync(), isTrue, reason: 'Missing round launcher icon in $density');
      }

      final masterIcon = File('assets/images/app_icon.png');
      expect(masterIcon.existsSync(), isTrue, reason: 'Missing master app icon source artwork');
    });

    test('4. Verify Data-Driven TaskItem mapping to NoyaState', () {
      const todoTask = TaskItem(
        id: 'task-1',
        title: 'Draft Project Specs',
        durationMinutes: 45,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
        status: TaskStatus.todo,
        isCompleted: false,
      );
      final todoView = NoyaCompanionView.fromTask(task: todoTask);
      expect(todoView.state, NoyaState.idle);

      const inProgressTask = TaskItem(
        id: 'task-2',
        title: 'Deep Coding Session',
        durationMinutes: 60,
        difficulty: TaskDifficulty.high,
        deadline: 'Today',
        category: 'Work',
        status: TaskStatus.inProgress,
        isCompleted: false,
      );
      final inProgressView = NoyaCompanionView.fromTask(task: inProgressTask);
      expect(inProgressView.state, NoyaState.focusing);

      const completedTask = TaskItem(
        id: 'task-3',
        title: 'Gym Workout',
        durationMinutes: 60,
        difficulty: TaskDifficulty.physical,
        deadline: 'Today',
        category: 'Fitness',
        status: TaskStatus.completed,
        isCompleted: true,
      );
      final completedView = NoyaCompanionView.fromTask(task: completedTask);
      expect(completedView.state, NoyaState.proud);
    });

    test('5. Verify Data-Driven CompanionAnimState mapping to NoyaState', () {
      expect(
        NoyaCompanionView.fromAnimState(animState: CompanionAnimState.idle).state,
        NoyaState.idle,
      );
      expect(
        NoyaCompanionView.fromAnimState(animState: CompanionAnimState.focusing).state,
        NoyaState.focusing,
      );
      expect(
        NoyaCompanionView.fromAnimState(animState: CompanionAnimState.success).state,
        NoyaState.celebrating,
      );
      expect(
        NoyaCompanionView.fromAnimState(animState: CompanionAnimState.evolution).state,
        NoyaState.celebrating,
      );
      expect(
        NoyaCompanionView.fromAnimState(animState: CompanionAnimState.tired).state,
        NoyaState.sleepy,
      );
      expect(
        NoyaCompanionView.fromAnimState(animState: CompanionAnimState.starting).state,
        NoyaState.encouraging,
      );
    });

    test('6. Verify semantic accessibility labels for all 9 states', () {
      for (final state in NoyaState.values) {
        expect(state.semanticLabel.isNotEmpty, isTrue);
        expect(state.displayName.isNotEmpty, isTrue);
      }
    });

    test('7. Verify sizing presets adhere to guidelines', () {
      expect(NoyaSize.small, inInclusiveRange(36.0, 44.0));
      expect(NoyaSize.normal, inInclusiveRange(44.0, 56.0));
      expect(NoyaSize.hero, inInclusiveRange(80.0, 160.0));
    });
  });

  group('Noya Widget & UI Integration Tests', () {
    testWidgets('8. NoyaCompanionView renders cleanly with correct semantic label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NoyaCompanionView(
              state: NoyaState.focusing,
              size: 44,
            ),
          ),
        ),
      );

      final nViewFinder = find.byType(NoyaCompanionView);
      expect(nViewFinder, findsOneWidget);

      final semanticsFinder = find.bySemanticsLabel(NoyaState.focusing.semanticLabel);
      expect(semanticsFinder, findsOneWidget);
    });

    testWidgets('9. Completed TaskCard shows a clear checkmark [✓] and no repeated Noya', (tester) async {
      bool toggleCalled = false;
      const completedTask = TaskItem(
        id: 'test-card-1',
        title: 'Review System Specs',
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
        status: TaskStatus.completed,
        isCompleted: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCard(
              task: completedTask,
              onToggleComplete: () => toggleCalled = true,
            ),
          ),
        ),
      );

      // Finished tasks are calm history: Noya is not repeated beside each one.
      expect(find.byType(NoyaCompanionView), findsNothing);

      // Verify clear completion indicator [✓] is rendered
      final checkIconFinder = find.byIcon(Icons.check_circle_rounded);
      expect(checkIconFinder, findsOneWidget);

      // Verify strike-through title
      final textWidget = tester.widget<Text>(find.text('Review System Specs'));
      expect(textWidget.style?.decoration, TextDecoration.lineThrough);

      // Tap toggle
      await tester.tap(checkIconFinder);
      expect(toggleCalled, isTrue);
    });
  });

  group('Noya decode size (spec §17 P5)', () {
    test('cacheWidthFor rounds size x dpr', () {
      expect(NoyaCompanionView.cacheWidthFor(40, 2.625), 105);
      expect(NoyaCompanionView.cacheWidthFor(156, 3.0), 468);
    });

    testWidgets('NoyaCompanionView decodes at size x DPR, not 1024x1024', (tester) async {
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: NoyaCompanionView(state: NoyaState.idle, size: 40)),
      ));
      final image = tester.widget<Image>(find.byType(Image).first).image;
      expect(image, isA<ResizeImage>());
      expect((image as ResizeImage).width, 120);
    });
  });
}
