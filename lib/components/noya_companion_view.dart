import 'package:flutter/material.dart';
import '../models/task_item.dart';
import 'companion/flow_companion_animation_controller.dart';

/// Canonical Noya Companion States.
///
/// Noya is Flowstate's singular companion fox.
/// The character identity (species, fur color, collar, proportions) remains
/// identical across all states, while the pose, expression, and action change.
enum NoyaState {
  /// Canonical default sitting upright, calm, friendly expression.
  idle,

  /// At desk with laptop, headband, and focused determined expression.
  focusing,

  /// Jumping with raised paws and joyful sparkles celebrating completed work.
  celebrating,

  /// Paw near chin with thoughtful, intelligent planning expression.
  thinking,

  /// Curled up peacefully on belly with eyes closed and subtle zzz.
  sleepy,

  /// Confident gentle smile / wink with small sparkle after task completion.
  proud,

  /// Upbeat waving gesture encouraging user to begin.
  encouraging,
}

extension NoyaStateExtension on NoyaState {
  /// Canonical asset path for this state.
  String get assetPath {
    switch (this) {
      case NoyaState.idle:
        return 'assets/images/companions/noya/noya_default.png';
      case NoyaState.focusing:
        return 'assets/images/companions/noya/noya_focusing.png';
      case NoyaState.celebrating:
        return 'assets/images/companions/noya/noya_celebrating.png';
      case NoyaState.thinking:
        return 'assets/images/companions/noya/noya_thinking.png';
      case NoyaState.sleepy:
        return 'assets/images/companions/noya/noya_sleepy.png';
      case NoyaState.proud:
        return 'assets/images/companions/noya/noya_proud.png';
      case NoyaState.encouraging:
        return 'assets/images/companions/noya/noya_encouraging.png';
    }
  }

  /// Screen-reader accessible label describing Noya's current appearance.
  String get semanticLabel {
    switch (this) {
      case NoyaState.idle:
        return 'Noya sitting calmly and ready to accompany your flow';
      case NoyaState.focusing:
        return 'Noya working intently at desk with laptop and headband';
      case NoyaState.celebrating:
        return 'Noya jumping with joy, celebrating your completed flow';
      case NoyaState.thinking:
        return 'Noya resting chin on paw, thoughtfully structuring your day';
      case NoyaState.sleepy:
        return 'Noya curled up peacefully asleep, recharging';
      case NoyaState.proud:
        return 'Noya winking proudly with a gentle smile and sparkles';
      case NoyaState.encouraging:
        return 'Noya waving energetically, encouraging you to begin';
    }
  }

  /// Short display label for diagnostics / tooling.
  String get displayName {
    switch (this) {
      case NoyaState.idle:
        return 'Default';
      case NoyaState.focusing:
        return 'Focusing';
      case NoyaState.celebrating:
        return 'Celebrating';
      case NoyaState.thinking:
        return 'Thinking';
      case NoyaState.sleepy:
        return 'Sleepy';
      case NoyaState.proud:
        return 'Proud';
      case NoyaState.encouraging:
        return 'Encouraging';
    }
  }
}

/// Standard responsive sizing presets for Noya presentation across Flowstate.
class NoyaSize {
  /// Small contextual representation inside task rows, chips, and meta headers (36–44 px).
  static const double small = 40.0;

  /// Normal companion representation for banners, sheets, and headers (44–56 px).
  static const double normal = 50.0;

  /// Hero presentation for Flow Hub, Focus Ritual, and Flow Complete (80–140 px).
  static const double hero = 120.0;
}

/// Canonical Noya Companion Presentation Widget.
///
/// Enforces:
/// 1. Aspect ratio preservation (1:1 containment, zero distortion or stretching).
/// 2. Frameless integration (no nested square-on-square white boxes or clipping).
/// 3. Transparent RGBA asset rendering that shines on both Dark and Light themes.
/// 4. Data-driven state resolution from [TaskItem] or [CompanionAnimState].
class NoyaCompanionView extends StatelessWidget {
  /// Current canonical state of Noya.
  final NoyaState state;

  /// Rendered dimension in logical pixels (width and height maintain 1:1 aspect ratio).
  final double size;

  /// Optional tap handler.
  final VoidCallback? onTap;

  /// Optional subtle ambient warm glow behind the character (useful for Hero displays).
  final bool showAmbientGlow;

  /// Custom semantic label override.
  final String? semanticLabel;

  const NoyaCompanionView({
    super.key,
    required this.state,
    this.size = NoyaSize.normal,
    this.onTap,
    this.showAmbientGlow = false,
    this.semanticLabel,
  });

  /// Factory constructor resolving Noya state data-driven from a [TaskItem].
  ///
  /// - Completed task -> [NoyaState.proud]
  /// - In progress task -> [NoyaState.focusing]
  /// - Todo task -> [NoyaState.idle]
  factory NoyaCompanionView.fromTask({
    Key? key,
    required TaskItem task,
    double size = NoyaSize.small,
    VoidCallback? onTap,
    bool showAmbientGlow = false,
  }) {
    NoyaState state;
    if (task.isCompleted || task.status == TaskStatus.completed) {
      state = NoyaState.proud;
    } else if (task.status == TaskStatus.inProgress || task.startedAt != null) {
      state = NoyaState.focusing;
    } else {
      state = NoyaState.idle;
    }

    return NoyaCompanionView(
      key: key,
      state: state,
      size: size,
      onTap: onTap,
      showAmbientGlow: showAmbientGlow,
    );
  }

  /// Factory constructor mapping from legacy [CompanionAnimState].
  factory NoyaCompanionView.fromAnimState({
    Key? key,
    required CompanionAnimState animState,
    double size = NoyaSize.normal,
    VoidCallback? onTap,
    bool showAmbientGlow = false,
  }) {
    NoyaState state;
    switch (animState) {
      case CompanionAnimState.focusing:
        state = NoyaState.focusing;
        break;
      case CompanionAnimState.success:
      case CompanionAnimState.evolution:
        state = NoyaState.celebrating;
        break;
      case CompanionAnimState.tired:
        state = NoyaState.sleepy;
        break;
      case CompanionAnimState.starting:
        state = NoyaState.encouraging;
        break;
      case CompanionAnimState.idle:
        state = NoyaState.idle;
        break;
    }

    return NoyaCompanionView(
      key: key,
      state: state,
      size: size,
      onTap: onTap,
      showAmbientGlow: showAmbientGlow,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget characterImage = Image.asset(
      state.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        // Fallback to default canonical sitting Noya if a state asset fails to load
        return Image.asset(
          'assets/images/companions/noya/noya_default.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.pets_rounded,
            size: size * 0.7,
            color: const Color(0xFFF97316),
          ),
        );
      },
    );

    Widget content = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (showAmbientGlow)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFF97316).withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          characterImage,
        ],
      ),
    );

    if (onTap != null) {
      content = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    return Semantics(
      label: semanticLabel ?? state.semanticLabel,
      image: true,
      button: onTap != null,
      child: content,
    );
  }
}
