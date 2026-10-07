import '../models/task_item.dart';

/// Removes the preview candidate [id] from a Build My Day plan and repairs the order around it.
///
/// Whoever followed the removed task now follows what it followed (A -> B -> C, remove B: C follows A), so no
/// dependency is left pointing at a task that will never be created. Nothing else changes.
List<TaskItem> removeCandidateWithDeps(List<TaskItem> candidates, String id) {
  TaskItem? removed;
  for (final t in candidates) {
    if (t.id == id) removed = t;
  }
  if (removed == null) return List<TaskItem>.from(candidates);
  final inherited = removed.dependsOn.where((d) => d != id).toList();
  return [
    for (final t in candidates)
      if (t.id != id)
        t.dependsOn.contains(id)
            ? t.copyWith(dependsOn: <String>{
                ...t.dependsOn.where((d) => d != id),
                ...inherited.where((d) => d != t.id),
              }.toList())
            : t,
  ];
}
