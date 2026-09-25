import 'package:flutter/material.dart';
import '../../models/flow_companion.dart';
import '../../theme/flow_colors.dart';
import '../../theme/flow_radii.dart';
import '../../theme/flow_typography.dart';
import 'companion_graphic.dart';
import 'flow_companion_animation_controller.dart';

/// Reusable Companion Presentation View.
///
/// Implements the Rive/Lottie-ready animation contract:
/// - idle
/// - starting
/// - focusing
/// - success
/// - tired
/// - evolution
///
/// Uses an elegant, restrained vector glyph placeholder that adapts
/// to light/dark themes and respects reduced motion settings.
class FlowCompanionView extends StatefulWidget {
  final FlowCompanion companion;
  final FlowCompanionAnimationController? controller;
  final double size;
  final VoidCallback? onTap;
  final bool showStageBadge;
  final bool showStatusText;

  const FlowCompanionView({
    super.key,
    required this.companion,
    this.controller,
    this.size = 140,
    this.onTap,
    this.showStageBadge = true,
    this.showStatusText = true,
  });

  @override
  State<FlowCompanionView> createState() => _FlowCompanionViewState();
}

class _FlowCompanionViewState extends State<FlowCompanionView>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    widget.controller?.addListener(_onControllerChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _pulseController.stop();
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(FlowCompanionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChange);
      widget.controller?.addListener(_onControllerChange);
    }
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChange);
    _pulseController.dispose();
    super.dispose();
  }

  Color _getStateAccent(BuildContext context, CompanionAnimState state) {
    switch (state) {
      case CompanionAnimState.focusing:
        return FlowColors.mint;
      case CompanionAnimState.success:
        return FlowColors.positive;
      case CompanionAnimState.tired:
        return FlowColors.warning;
      case CompanionAnimState.evolution:
        return const Color(0xFFEAB308); // Golden amber
      case CompanionAnimState.starting:
      case CompanionAnimState.idle:
        return widget.companion.animalInfo.accentColor;
    }
  }

  IconData _getStateIcon(CompanionAnimState state) {
    switch (state) {
      case CompanionAnimState.focusing:
        return Icons.lens_blur_rounded;
      case CompanionAnimState.success:
        return Icons.auto_awesome_rounded;
      case CompanionAnimState.tired:
        return Icons.nights_stay_rounded;
      case CompanionAnimState.evolution:
        return Icons.stars_rounded;
      case CompanionAnimState.starting:
        return Icons.play_arrow_rounded;
      case CompanionAnimState.idle:
        return Icons.pets_rounded;
    }
  }

  String _getStateDescription(CompanionAnimState state) {
    switch (state) {
      case CompanionAnimState.focusing:
        return 'Focusing with you';
      case CompanionAnimState.success:
        return 'Session complete! Growth recorded';
      case CompanionAnimState.tired:
        return 'Resting. Ready for tomorrow';
      case CompanionAnimState.evolution:
        return 'Evolution ready! Tap to evolve';
      case CompanionAnimState.starting:
        return 'Starting focus window';
      case CompanionAnimState.idle:
        return 'Ready to focus';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller?.state ??
        (widget.companion.isEvolutionReady
            ? CompanionAnimState.evolution
            : CompanionAnimState.idle);

    final bool reduceMotion = MediaQuery.of(context).disableAnimations;
    final stateAccent = _getStateAccent(context, state);
    final size = widget.size;

    return Semantics(
      label: '${widget.companion.name}, ${widget.companion.stage}, level ${widget.companion.level}. Current state: ${state.name}.',
      button: widget.onTap != null,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Character Container
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                final scale = reduceMotion ? 1.0 : (state == CompanionAnimState.focusing ? _pulseAnimation.value : 1.0);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: FlowColors.surfaceElevated(context),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0xFFFED7AA),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF97316).withValues(alpha: FlowColors.isDark(context) ? 0.2 : 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // Companion Graphic (Big and prominently displayed!)
                        CompanionGraphic(
                          species: widget.companion.species,
                          size: size * 0.88,
                          state: state,
                        ),

                        // Paw Badge at bottom right of card (Matching Image 2)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xFFFB923C),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFB923C).withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.pets_rounded,
                              size: size * 0.12,
                              color: const Color(0xFFEA580C),
                            ),
                          ),
                        ),

                        // Evolution Ready Badge at top right (Retained as icon badge)
                        if (widget.companion.isEvolutionReady || state == CompanionAnimState.evolution)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFEAB308),
                              ),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 14,
                                color: Colors.black,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),

            if (widget.showStageBadge) ...[
              const SizedBox(height: 12),
              // Companion Identity & Stage
              Text(
                widget.companion.name.toUpperCase(),
                style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${widget.companion.stage} · Level ${widget.companion.level}',
                style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            if (widget.showStatusText) ...[
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  widget.controller?.statusText ?? _getStateDescription(state),
                  key: ValueKey(widget.controller?.statusText ?? state.name),
                  style: FlowTypography.labelMedium(
                    color: state == CompanionAnimState.evolution ? const Color(0xFFEAB308) : stateAccent,
                  ).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
