import 'package:flutter/material.dart';

/// Logical states for the companion character presentation.
/// Exactly maps to the external Rive / Lottie state machine contract:
/// idle, starting, focusing, success, tired, evolution.
enum CompanionAnimState {
  idle,
  starting,
  focusing,
  success,
  tired,
  evolution,
}

/// Decoupled animation controller coordinating companion presentation.
/// Business logic and game engines communicate solely with this controller,
/// remaining fully decoupled from whether the renderer is Rive, Lottie, or a placeholder.
class FlowCompanionAnimationController extends ChangeNotifier {
  CompanionAnimState _state = CompanionAnimState.idle;
  String? _statusText;

  CompanionAnimState get state => _state;
  String? get statusText => _statusText;

  bool get isIdle => _state == CompanionAnimState.idle;
  bool get isStarting => _state == CompanionAnimState.starting;
  bool get isFocusing => _state == CompanionAnimState.focusing;
  bool get isSuccess => _state == CompanionAnimState.success;
  bool get isTired => _state == CompanionAnimState.tired;
  bool get isEvolving => _state == CompanionAnimState.evolution;

  void setState(CompanionAnimState newState, {String? statusText}) {
    if (_state != newState || _statusText != statusText) {
      _state = newState;
      _statusText = statusText;
      notifyListeners();
    }
  }

  void setIdle() => setState(CompanionAnimState.idle, statusText: null);

  void setStarting({String? taskTitle}) {
    setState(CompanionAnimState.starting, statusText: taskTitle != null ? 'Starting $taskTitle' : 'Preparing focus');
  }

  void setFocusing({String? taskTitle, int? elapsedMinutes}) {
    final text = taskTitle != null
        ? 'Focusing on $taskTitle${elapsedMinutes != null ? ' (+$elapsedMinutes XP)' : ''}'
        : 'Focusing with you';
    setState(CompanionAnimState.focusing, statusText: text);
  }

  void triggerSuccess({String? message}) {
    setState(CompanionAnimState.success, statusText: message ?? 'Session complete!');
  }

  void triggerMilestone(int minutes) {
    setState(CompanionAnimState.focusing, statusText: '$minutes min milestone reached!');
  }

  void triggerLevelUp(int level) {
    setState(CompanionAnimState.evolution, statusText: 'Noya reached Level $level!');
  }

  void setGreeting(String message) {
    setState(CompanionAnimState.idle, statusText: message);
  }

  void setTired({String? message}) {
    setState(CompanionAnimState.tired, statusText: message ?? 'Resting. Protect your streak tomorrow.');
  }

  void triggerEvolution() {
    setState(CompanionAnimState.evolution, statusText: 'Ready to evolve!');
  }
}
