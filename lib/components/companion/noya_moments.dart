import '../../models/task_reflection.dart';
import '../noya_companion_view.dart';

/// Noya's pose for a remembered moment of the day: a state indicator, not decoration.
///
/// The pose follows how the user said the task felt (the reflection sheet). A task finished
/// without a reflection reads as quietly done.
NoyaState noyaStateForMoment(TaskReflection? reflection) {
  if (reflection == null) return NoyaState.proud;
  switch (reflection.feeling) {
    case 1:
      return NoyaState.sleepy; // drained
    case 2:
      return NoyaState.idle; // okay
    case 3:
      return NoyaState.proud; // good
    default:
      return NoyaState.celebrating; // on fire
  }
}

/// The kind of work a task is, read from its category and schedule type words.
enum WorkKind { physical, study, planning, deepWork, other }

WorkKind workKindOf({String? category, String? type, String? title}) {
  final words = '${category ?? ''} ${type ?? ''} ${title ?? ''}'.toLowerCase();
  // Word-start matches, so "run" finds "running" but not "brunch".
  bool any(List<String> keys) => RegExp('\\b(${keys.join('|')})').hasMatch(words);
  if (any(const ['fitness', 'gym', 'workout', 'run', 'walk', 'yoga', 'physical', 'health', 'sport', 'swim', 'exercise'])) {
    return WorkKind.physical;
  }
  if (any(const ['plan', 'review', 'organi', 'schedule', 'retro'])) return WorkKind.planning;
  if (any(const ['study', 'college', 'class', 'lecture', 'learn', 'read', 'homework', 'exam'])) return WorkKind.study;
  if (any(const ['deep', 'high focus', 'focus', 'write', 'code', 'design'])) return WorkKind.deepWork;
  return WorkKind.other;
}

/// Noya's pose when a task is opened from the day's history: what the work was, and — once it
/// is done — how it went. Drained or hard-and-flat sessions get the recovery pose; a strong
/// finish gets the celebration; a planned task shows the pose of the work ahead.
NoyaState noyaStateForTask({required WorkKind kind, required bool done, TaskReflection? reflection}) {
  if (done) {
    final r = reflection;
    if (r == null) return kind == WorkKind.physical ? NoyaState.cheering : NoyaState.goodJob;
    if (r.feeling == 1 || (r.feeling == 2 && r.difficulty >= 4)) return NoyaState.sleepy;
    if (r.feeling >= 4) return kind == WorkKind.physical ? NoyaState.cheering : NoyaState.celebrating;
    if (r.feeling == 3) return NoyaState.proud;
    return NoyaState.idle;
  }
  switch (kind) {
    case WorkKind.physical:
      return NoyaState.cheering;
    case WorkKind.study:
    case WorkKind.deepWork:
      return NoyaState.focusing;
    case WorkKind.planning:
      return NoyaState.planning;
    case WorkKind.other:
      return NoyaState.encouraging;
  }
}

/// Plain-language reading of the duration answer on the reflection sheet.
String? durationFeedbackLabel(String? code) {
  switch (code) {
    case 'shorter':
      return 'Faster than expected';
    case 'about_right':
      return 'About as planned';
    case 'longer':
      return 'Took longer than planned';
  }
  return null;
}
