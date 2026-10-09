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

  /// Default sit with star-sparkle eyes; same framing as idle, so it reads as Noya lighting up
  /// (plan ready). Existing art: `noya_success.png` (spec §2.2).
  delighted,

  /// Default sit with drowsy half-closed eyes for the evening wind-down. Existing art:
  /// `noya_sleeping.png` — despite its name it is the drowsy pose; `sleepy` is the curled one.
  windDown,

  /// Thumbs-up wink: a meaningful finish (the day's plan done, a milestone). Expression sheet art.
  goodJob,

  /// Paw raised under a lightbulb: Flowstate has noticed a pattern (Insights).
  idea,

  /// Holding a checklist: organizing the day.
  planning,

  /// Pom-poms and confetti: a streak or weekly milestone. Use sparingly.
  cheering,
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
      case NoyaState.delighted:
        return 'assets/images/companions/noya_success.png';
      case NoyaState.windDown:
        return 'assets/images/companions/noya_sleeping.png';
      case NoyaState.goodJob:
        return 'assets/images/companions/noya/noya_good_job.png';
      case NoyaState.idea:
        return 'assets/images/companions/noya/noya_idea.png';
      case NoyaState.planning:
        return 'assets/images/companions/noya/noya_planning.png';
      case NoyaState.cheering:
        return 'assets/images/companions/noya/noya_cheering.png';
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
      case NoyaState.delighted:
        return 'Noya beaming with sparkling eyes, delighted with your plan';
      case NoyaState.windDown:
        return 'Noya getting drowsy as the day winds down';
      case NoyaState.goodJob:
        return 'Noya giving a thumbs-up for work well done';
      case NoyaState.idea:
        return 'Noya with a lightbulb, noticing a pattern';
      case NoyaState.planning:
        return 'Noya holding a checklist, organizing the day';
      case NoyaState.cheering:
        return 'Noya cheering with pom-poms for a milestone';
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
      case NoyaState.delighted:
        return 'Delighted';
      case NoyaState.windDown:
        return 'Wind-down';
      case NoyaState.goodJob:
        return 'Good job';
      case NoyaState.idea:
        return 'Idea';
      case NoyaState.planning:
        return 'Planning';
      case NoyaState.cheering:
        return 'Cheering';
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

/// Warms the image cache for the poses a screen can switch to, at the size they will be shown,
/// so a pose change never flashes an undecoded frame (spec §17 P6).
class NoyaAssets {
  NoyaAssets._();

  static Future<void> precache(BuildContext context, Iterable<NoyaState> states, double size) {
    final width = NoyaCompanionView.cacheWidthFor(size, MediaQuery.devicePixelRatioOf(context));
    return Future.wait(states.map(
      (s) => precacheImage(ResizeImage(AssetImage(s.assetPath), width: width), context),
    ));
  }
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

  /// Explicit decode width override in physical pixels to prevent blur during scale animations.
  final int? cacheWidth;

  const NoyaCompanionView({
    super.key,
    required this.state,
    this.size = NoyaSize.normal,
    this.onTap,
    this.showAmbientGlow = false,
    this.semanticLabel,
    this.cacheWidth,
  });

  /// Resolves the optimal, context-aware [NoyaState] based on task domain,
  /// execution status, time of day, and cognitive load.
  ///
  /// Prevents displaying a mismatched studying/laptop desk pose for physical tasks.
  static NoyaState resolveStateForTask(TaskItem task, {DateTime? now}) {
    // 1. Task Completed -> Proud / Celebrating
    if (task.isCompleted || task.status == TaskStatus.completed) {
      return NoyaState.proud;
    }

    final lowerTitle = task.title.toLowerCase();
    final lowerCategory = task.category.toLowerCase();

    // 2. Physical / Fitness / Movement Tasks (Gym, running, workout, yoga, cardio)
    // NEVER show desk/laptop studying pose for physical activities!
    final isPhysical = task.difficulty == TaskDifficulty.physical ||
        task.taskType == TaskType.physical ||
        lowerCategory.contains('fitness') ||
        lowerCategory.contains('gym') ||
        RegExp(r'\b(gym|workout|exercise|running|run|walk|cardio|yoga|stretch|lift|lifting|leg day|training|swim|cycling|sports)\b')
            .hasMatch(lowerTitle);

    if (isPhysical) {
      // Energetic / movement pose
      return NoyaState.encouraging;
    }

    // 3. Bedtime / Night Routine / Sleep
    final isBedtime = RegExp(r'\b(sleep|bedtime|sleepy|night routine|wind down|lights out)\b')
        .hasMatch(lowerTitle);
    if (isBedtime) {
      return NoyaState.sleepy;
    }

    // 4. Planning / Structuring / Brain Dump / Review Tasks
    final isPlanning = RegExp(r'\b(plan|planning|structure|organize|prioritize|brain dump|reflect|review schedule)\b')
        .hasMatch(lowerTitle);
    if (isPlanning) {
      return NoyaState.thinking;
    }

    // 5. Active In-Progress Deep Work, Coding, Study, DSA
    final isInProgress = task.status == TaskStatus.inProgress || task.startedAt != null;
    if (isInProgress) {
      return NoyaState.focusing;
    }

    // 6. Todo / Scheduled: Default calm posture
    return NoyaState.idle;
  }

  /// Factory constructor resolving Noya state data-driven from a [TaskItem].
  factory NoyaCompanionView.fromTask({
    Key? key,
    required TaskItem task,
    double size = NoyaSize.small,
    VoidCallback? onTap,
    bool showAmbientGlow = false,
  }) {
    final state = resolveStateForTask(task);

    return NoyaCompanionView(
      key: key,
      state: state,
      size: size,
      onTap: onTap,
      showAmbientGlow: showAmbientGlow,
    );
  }

  /// Pose for a legacy [CompanionAnimState].
  static NoyaState stateForAnimState(CompanionAnimState animState) {
    switch (animState) {
      case CompanionAnimState.focusing:
        return NoyaState.focusing;
      case CompanionAnimState.success:
      case CompanionAnimState.evolution:
        return NoyaState.celebrating;
      case CompanionAnimState.tired:
        return NoyaState.sleepy;
      case CompanionAnimState.starting:
        return NoyaState.encouraging;
      case CompanionAnimState.idle:
        return NoyaState.idle;
    }
  }

  /// Factory constructor mapping from legacy [CompanionAnimState].
  factory NoyaCompanionView.fromAnimState({
    Key? key,
    required CompanionAnimState animState,
    double size = NoyaSize.normal,
    VoidCallback? onTap,
    bool showAmbientGlow = false,
  }) {
    return NoyaCompanionView(
      key: key,
      state: stateForAnimState(animState),
      size: size,
      onTap: onTap,
      showAmbientGlow: showAmbientGlow,
    );
  }

  /// Decode width in physical pixels. The source art is 1024×1024. Decoding at exactly display
  /// size looked soft (the decoder's downscale is low quality and there is no headroom for scale
  /// animations or fractional DPRs), so decode at 2x display size, capped at the source width.
  /// That is still at most 4 MB per pose, and typically far less for small sizes.
  @visibleForTesting
  static int cacheWidthFor(double size, double devicePixelRatio) =>
      (size * devicePixelRatio * 2).round().clamp(1, 1024);

  @override
  Widget build(BuildContext context) {
    final decodeWidth = cacheWidth ?? cacheWidthFor(size, MediaQuery.devicePixelRatioOf(context));
    Widget characterImage = Image.asset(
      state.assetPath,
      width: size,
      height: size,
      cacheWidth: decodeWidth,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        // Fallback to default canonical sitting Noya if a state asset fails to load
        return Image.asset(
          'assets/images/companions/noya/noya_default.png',
          width: size,
          height: size,
          cacheWidth: decodeWidth,
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
