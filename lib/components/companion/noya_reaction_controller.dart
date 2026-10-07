import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../services/flow_clock.dart';

/// One-shot Noya reactions (spec §5.2). Each plays once over the current mood, then returns to it.
enum NoyaReaction { greet, taskDone, planReady, celebrate, recover }

extension NoyaReactionRules on NoyaReaction {
  /// Spec §5.3: celebrate > taskDone > planReady > recover > greet.
  int get priority {
    switch (this) {
      case NoyaReaction.celebrate:
        return 4;
      case NoyaReaction.taskDone:
        return 3;
      case NoyaReaction.planReady:
        return 2;
      case NoyaReaction.recover:
        return 1;
      case NoyaReaction.greet:
        return 0;
    }
  }

  /// How long the reaction occupies Noya, including its hold (spec §6).
  Duration get activeWindow {
    switch (this) {
      case NoyaReaction.greet:
        return const Duration(milliseconds: 1500);
      case NoyaReaction.taskDone:
        return const Duration(milliseconds: 1700);
      case NoyaReaction.planReady:
        return const Duration(milliseconds: 1400);
      case NoyaReaction.celebrate:
        return const Duration(milliseconds: 3100);
      case NoyaReaction.recover:
        return const Duration(milliseconds: 500);
    }
  }
}

@immutable
class NoyaReactionEvent {
  final int id;
  final NoyaReaction reaction;
  final DateTime at;

  const NoyaReactionEvent({required this.id, required this.reaction, required this.at});
}

/// The single place where Noya's reaction rules live (spec §5.3): priority, `taskDone` coalescing,
/// the daily celebration cap, the tap rate limit and greet-once bookkeeping. Views only play what
/// this emits; an event that is dropped here never animates anywhere.
class NoyaReactionController extends ChangeNotifier implements ValueListenable<NoyaReactionEvent?> {
  NoyaReactionController({DateTime Function()? clock}) : _clock = clock ?? (() => FlowClock().now);

  static const Duration _taskDoneCoalesce = Duration(milliseconds: 1500);
  static const Duration _tapInterval = Duration(seconds: 2);
  static const int _celebrationsPerDay = 3;

  final DateTime Function() _clock;
  final Set<String> _greeted = <String>{};
  NoyaReactionEvent? _current;
  DateTime? _lastTaskDoneAt;
  DateTime? _lastTapAt;
  String? _celebrationDay;
  int _celebrationsToday = 0;
  int _nextId = 1;

  @override
  NoyaReactionEvent? get value => _current;

  /// Emits [reaction] unless the rules drop it. Returns the emitted event (whose reaction may be a
  /// downgrade) or null.
  NoyaReactionEvent? react(NoyaReaction reaction) {
    final now = _clock();
    var r = reaction;

    if (r == NoyaReaction.celebrate) {
      final day = _dayKey(now);
      if (_celebrationDay != day) {
        _celebrationDay = day;
        _celebrationsToday = 0;
      }
      if (_celebrationsToday >= _celebrationsPerDay) r = NoyaReaction.taskDone;
    }

    if (r == NoyaReaction.taskDone &&
        _lastTaskDoneAt != null &&
        now.difference(_lastTaskDoneAt!) < _taskDoneCoalesce) {
      return null;
    }

    final current = _current;
    if (current != null &&
        now.difference(current.at) < current.reaction.activeWindow &&
        r.priority < current.reaction.priority) {
      return null;
    }

    final event = NoyaReactionEvent(id: _nextId++, reaction: r, at: now);
    _current = event;
    if (r == NoyaReaction.taskDone) _lastTaskDoneAt = now;
    if (r == NoyaReaction.celebrate) _celebrationsToday++;
    notifyListeners();
    return event;
  }

  /// A tap on Noya greets back, at most once per 2 s.
  NoyaReactionEvent? reactToTap() {
    final now = _clock();
    if (_lastTapAt != null && now.difference(_lastTapAt!) < _tapInterval) return null;
    final event = react(NoyaReaction.greet);
    if (event != null) _lastTapAt = now;
    return event;
  }

  /// True the first time [screenKey] asks this session (or this local day when [perDay]).
  bool greetOnce(String screenKey, {bool perDay = false}) {
    final key = perDay ? '$screenKey@${_dayKey(_clock())}' : screenKey;
    return _greeted.add(key);
  }

  static String _dayKey(DateTime t) => DateFormat('yyyy-MM-dd').format(t);
}
