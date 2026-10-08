import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/components/ai_economy_sheets.dart';
import 'package:flowstate/engines/plan_candidates.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/brain_dump_sheet.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

/// Build My Day preview: any proposed task can be removed before confirming (manual verification 2026-10-06).
/// It is never saved, nothing else is touched, and whatever followed it now follows what it followed.
TaskItem _t(String id, {List<String> deps = const []}) => TaskItem(
      id: id,
      title: 'Task $id',
      durationMinutes: 30,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'General',
      dependsOn: deps,
    );

class _PlanApi extends ApiService {
  final List<Map<String, dynamic>> batches = [];
  int deletes = 0;

  static Map<String, dynamic> task(String id, String title, Map<String, dynamic> extra) => {
        'candidate_id': id,
        'title': title,
        'estimated_minutes': 45,
        'task_type': 'deep_work',
        'difficulty': 'medium',
        'priority': 'medium',
        'priority_source': 'explicit',
        'duration_source': 'explicit',
        'focus_source': 'inferred',
        'recommended_slot_start': '2026-10-05T14:00:00+05:30',
        'recommended_slot_end': '2026-10-05T14:45:00+05:30',
        'recommended_slot_display': 'Mon · 2:00 PM',
        'planned_date': '2026-10-05',
        ...extra,
      };

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint == '/api/v1/ai/plan') {
      return {
        'tasks': [
          task('c_a', 'Finish ML assignment', {}),
          task('c_b', 'Stick pictures for CN observation', {'depends_on': ['c_a']}),
          task('c_c', 'Email professor', {'depends_on': ['c_b']}),
        ],
        'ambiguities': [],
        'needs_confirmation': false,
      };
    }
    if (endpoint == '/api/v1/tasks/batch-create-and-schedule') {
      batches.add(Map<String, dynamic>.from(body as Map));
      final items = (body['tasks'] as List).cast<Map>();
      var i = 0;
      return {
        'tasks': [
          for (final it in items)
            {
              ...Map<String, dynamic>.from(it),
              'id': 'task-${i++}',
              'status': 'todo',
              'estimated_minutes': it['estimated_minutes'] ?? 45,
              'difficulty': 'medium',
            },
        ],
        'schedule': [],
      };
    }
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> delete(String endpoint) async {
    deletes++;
    return null;
  }

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    if (endpoint == '/api/v1/ai/status') {
      return {
        'is_pro': false,
        'subscription_tier': 'free',
        'free_use_available': true,
        'free_uses_consumed': 0,
        'shields_available': 2,
        'shield_funded_uses': 0,
        'can_use_ai': true,
        'requires_shield': false,
        'hourly_requests_remaining': 5,
      };
    }
    if (endpoint == '/api/v1/tasks') return {'items': [], 'total': 0};
    return <String, dynamic>{};
  }
}

Future<AppStateProvider> _openPreview(WidgetTester tester, _PlanApi api) async {
  const user = AuthUser(id: 'user-rm', email: 'rm@flowstate.local', name: 'R', onboardingCompleted: true);
  final appState = AppStateProvider(customApi: api, initialUser: user);
  if (appState.currentUser == null) appState.onUserAuthenticated(user);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppStateProvider>.value(value: appState),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<FlowProvider>.value(value: FlowProvider(api: api)),
    ],
    child: MaterialApp(
      theme: ThemeData(useMaterial3: false, splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(onPressed: () => showBrainDumpSheet(ctx), child: const Text('Open'))),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('brain_dump_text_field')),
      'Finish ML assignment after that stick pictures for CN observation then email professor');
  await tester.pump();
  await tester.tap(find.byKey(const Key('brain_dump_build_button')));
  await tester.pumpAndSettle();
  expect(find.text('YOUR PLAN'), findsOneWidget);
  return appState;
}

void main() {
  group('removeCandidateWithDeps', () {
    test('A -> B -> C, remove B: C now follows A; nothing else changes', () {
      final out = removeCandidateWithDeps([_t('a'), _t('b', deps: ['a']), _t('c', deps: ['b'])], 'b');
      expect(out.map((t) => t.id), ['a', 'c']);
      expect(out[0].dependsOn, isEmpty);
      expect(out[1].dependsOn, ['a']);
    });

    test('removing the first task leaves its follower with no dangling dependency', () {
      final out = removeCandidateWithDeps([_t('a'), _t('b', deps: ['a'])], 'a');
      expect(out.single.dependsOn, isEmpty);
    });

    test('no duplicate or self dependency after bridging', () {
      final out = removeCandidateWithDeps([_t('a'), _t('b', deps: ['a']), _t('c', deps: ['a', 'b'])], 'b');
      expect(out.last.dependsOn, ['a']);
    });

    test('unknown id: same tasks back', () {
      final list = [_t('a'), _t('b')];
      expect(removeCandidateWithDeps(list, 'zzz').map((t) => t.id), ['a', 'b']);
    });
  });

  group('Build My Day preview Remove', () {
    setUp(() {
      FlowClock.enableAutoTick = false;
      FlowClock().stopTimer();
      SharedPreferences.setMockInitialValues({kGeminiPrivacyAcceptedKey: true});
      TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
    });
    tearDown(() => FlowClock().stopTimer());

    testWidgets('every card has a clear Remove action with a real touch target', (tester) async {
      await _openPreview(tester, _PlanApi());
      for (final id in ['c_a', 'c_b', 'c_c']) {
        final remove = find.byKey(Key('preview_remove_$id'));
        expect(remove, findsOneWidget);
        expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('card controls: an Edit pencil and a dustbin, same size, same row, no text labels', (tester) async {
      await _openPreview(tester, _PlanApi());
      for (final id in ['c_a', 'c_b', 'c_c']) {
        final edit = find.byKey(Key('preview_edit_$id'));
        final remove = find.byKey(Key('preview_remove_$id'));
        expect(edit, findsOneWidget);
        expect(tester.getSize(edit), tester.getSize(remove), reason: 'matching targets');
        expect(tester.getSize(edit).height, greaterThanOrEqualTo(44));
        expect(tester.getCenter(edit).dy, tester.getCenter(remove).dy, reason: 'aligned on one line');
        expect(tester.getTopRight(remove).dx, greaterThan(tester.getTopRight(edit).dx), reason: 'dustbin sits at the far right');
        expect(find.descendant(of: edit, matching: find.byIcon(Icons.edit_outlined)), findsOneWidget);
        expect(find.descendant(of: remove, matching: find.byIcon(Icons.delete_outline_rounded)), findsOneWidget);
        expect(find.descendant(of: edit, matching: find.byType(Text)), findsNothing, reason: 'icon only');
        expect(find.descendant(of: remove, matching: find.byType(Text)), findsNothing, reason: 'icon only');
      }
      expect(find.text('Remove'), findsNothing);
      expect(find.byTooltip('Edit task'), findsNWidgets(3));
      expect(find.byTooltip('Delete task'), findsNWidgets(3));
    });

    testWidgets('the pencil opens the editor for that card', (tester) async {
      await _openPreview(tester, _PlanApi());
      await tester.tap(find.byKey(const Key('preview_edit_c_b')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('structured_task_editor')), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
    });

    testWidgets('remove one task: the others stay, the removed one is never saved, the chain is repaired',
        (tester) async {
      final api = _PlanApi();
      final appState = await _openPreview(tester, api);

      await tester.tap(find.byKey(const Key('preview_remove_c_b')));
      await tester.pumpAndSettle();
      expect(find.text('Stick pictures for CN observation'), findsNothing);
      expect(find.text('Finish ML assignment'), findsOneWidget);
      expect(find.text('Email professor'), findsOneWidget);
      expect(find.byKey(const Key('preview_removed_banner')), findsOneWidget);
      expect(api.deletes, 0, reason: 'a preview candidate is never deleted on the server');

      await tester.tap(find.byKey(const Key('add_and_schedule_button')));
      await tester.pumpAndSettle();

      expect(api.batches.length, 1);
      final items = (api.batches.single['tasks'] as List).cast<Map>();
      expect(items.map((i) => i['title']), ['Finish ML assignment', 'Email professor']);
      final email = items.firstWhere((i) => i['title'] == 'Email professor');
      expect(email['depends_on'], ['c_a'], reason: 'it now follows what the removed task followed');
      expect(appState.tasks.map((t) => t.title), isNot(contains('Stick pictures for CN observation')));
    });

    testWidgets('Undo puts the task back with its dependencies', (tester) async {
      final api = _PlanApi();
      await _openPreview(tester, api);
      await tester.tap(find.byKey(const Key('preview_remove_c_b')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('preview_undo_remove')));
      await tester.pumpAndSettle();
      expect(find.text('Stick pictures for CN observation'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add_and_schedule_button')));
      await tester.pumpAndSettle();
      final items = (api.batches.single['tasks'] as List).cast<Map>();
      expect(items.length, 3);
      expect(items.firstWhere((i) => i['title'] == 'Email professor')['depends_on'], ['c_b']);
    });

    testWidgets('removing every task returns to the dump with the text kept and saves nothing', (tester) async {
      final api = _PlanApi();
      await _openPreview(tester, api);
      for (final id in ['c_a', 'c_b', 'c_c']) {
        await tester.tap(find.byKey(Key('preview_remove_$id')));
        await tester.pumpAndSettle();
      }
      expect(find.text('YOUR PLAN'), findsNothing);
      expect(find.textContaining('Finish ML assignment after that'), findsOneWidget);
      expect(api.batches, isEmpty);
    });
  });
}
