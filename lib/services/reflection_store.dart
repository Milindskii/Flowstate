import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/task_reflection.dart';

/// On-device store of task reflections, scoped per signed-in user (or 'local' when signed out).
class ReflectionStore {
  static const int _maxEntries = 400;

  static String keyFor(String scope) => 'flowstate_reflections_v1_$scope';

  Future<Map<String, TaskReflection>> load(String scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(keyFor(scope));
      if (raw == null) return {};
      final list = (jsonDecode(raw) as List).whereType<Map<String, dynamic>>();
      return {for (final r in list.map(TaskReflection.fromJson)) r.taskId: r};
    } catch (_) {
      return {};
    }
  }

  Future<void> save(String scope, Iterable<TaskReflection> reflections) async {
    try {
      final sorted = reflections.toList()..sort((a, b) => b.completedAt.compareTo(a.completedAt));
      final kept = sorted.take(_maxEntries).map((r) => r.toJson()).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyFor(scope), jsonEncode(kept));
    } catch (_) {}
  }
}
