import 'package:flutter/material.dart';
import 'flow_haptics.dart';

/// Centralized Motion & Transition Architecture for Flowstate
///
/// Motion Decision Rules:
/// - Global tab switch → subtle crossfade (180–200ms)
/// - Hierarchical navigation → fade + small directional movement (250–280ms)
/// - Sequential onboarding → PageView horizontal transition (300–340ms)
/// - Bottom sheet → bottom-up sheet transition
/// - State change → inline AnimatedSwitcher (180–220ms)
/// - Recommendation replacement → subtle keyed transition (200–240ms)
/// - First screen entry → one-time stagger only
/// - Returning to an already viewed screen → do NOT replay large entrance animation
/// - Data refresh / provider rebuild → do NOT replay page entrance animation
/// - Reduced motion (`MediaQuery.disableAnimations`) → collapses to instant transitions
class FlowMotion {
  FlowMotion._();

  // Durations
  static const Duration microDuration = Duration(milliseconds: 150);
  static const Duration standardDuration = Duration(milliseconds: 220);
  static const Duration screenDuration = Duration(milliseconds: 280);
  static const Duration onboardingDuration = Duration(milliseconds: 340);

  // Natural Curves
  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;

  /// Returns true if reduced motion is requested by system accessibility settings
  static bool isReducedMotion(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  /// Returns Duration.zero if reduced motion is enabled, otherwise returns [duration]
  static Duration responsiveDuration(BuildContext context, Duration duration) {
    return isReducedMotion(context) ? Duration.zero : duration;
  }
}

/// Flutter-native one-time staggered or direct fade-and-slide entrance.
/// Strictly executes ONCE per widget lifetime and does not replay on rebuilds.
class FlowFadeSlide extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double translateY;

  const FlowFadeSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = FlowMotion.standardDuration,
    this.translateY = 12.0,
  });

  @override
  State<FlowFadeSlide> createState() => _FlowFadeSlideState();
}

class _FlowFadeSlideState extends State<FlowFadeSlide> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: FlowMotion.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, widget.translateY / 100.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: FlowMotion.easeOut),
    );

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (FlowMotion.isReducedMotion(context)) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}

/// Interactive button scale press micro-animation with quick recovery.
class FlowPressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const FlowPressScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
  });

  @override
  State<FlowPressScale> createState() => _FlowPressScaleState();
}

class _FlowPressScaleState extends State<FlowPressScale> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    if (FlowMotion.isReducedMotion(context)) {
      return GestureDetector(
        onTap: widget.onTap != null
            ? () {
                FlowHaptics.lightTap();
                widget.onTap!();
              }
            : null,
        child: widget.child,
      );
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap != null
          ? () {
              FlowHaptics.lightTap();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _isPressed ? widget.pressedScale : 1.0,
        duration: FlowMotion.microDuration,
        curve: Curves.easeOutQuad,
        child: widget.child,
      ),
    );
  }
}

/// Smooth crossfade for IndexedStack tabs.
/// Keeps all child tab states alive while delivering a fast, subtle transition.
/// Avoids duplicate widget tree layout passes.
class FlowFadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FlowFadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 180),
  });

  @override
  State<FlowFadeIndexedStack> createState() => _FlowFadeIndexedStackState();
}

class _FlowFadeIndexedStackState extends State<FlowFadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _animController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.value = 1.0;
  }

  @override
  void didUpdateWidget(FlowFadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      setState(() {
        _currentIndex = widget.index;
      });
      _animController.reset();
      _animController.forward();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (FlowMotion.isReducedMotion(context)) {
      return IndexedStack(
        index: widget.index,
        children: widget.children,
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: IndexedStack(
        index: _currentIndex,
        children: widget.children,
      ),
    );
  }
}

/// Custom Route Transitions matching Flowstate's Motion Architecture
class FlowPageRoute {
  FlowPageRoute._();

  /// Forward hierarchical navigation: fade + slight upward movement (280ms)
  static Route<T> fadeUp<T>({
    required WidgetBuilder builder,
    Duration duration = FlowMotion.screenDuration,
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, _, __) => builder(context),
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (FlowMotion.isReducedMotion(context)) {
          return child;
        }
        final fade = CurvedAnimation(parent: animation, curve: FlowMotion.easeOut);
        final slide = Tween<Offset>(
          begin: const Offset(0.0, 0.04),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: FlowMotion.easeOut));

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: child,
          ),
        );
      },
    );
  }

  /// Same-level or calm navigation: subtle crossfade (220ms)
  static Route<T> fade<T>({
    required WidgetBuilder builder,
    Duration duration = FlowMotion.standardDuration,
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, _, __) => builder(context),
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (FlowMotion.isReducedMotion(context)) {
          return child;
        }
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: FlowMotion.easeOut),
          child: child,
        );
      },
    );
  }

  /// Horizontal shared-axis transition (e.g. Sign In ↔ Sign Up, 250ms)
  static Route<T> sharedAxisHorizontal<T>({
    required WidgetBuilder builder,
    bool forward = true,
    Duration duration = const Duration(milliseconds: 250),
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, _, __) => builder(context),
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (FlowMotion.isReducedMotion(context)) {
          return child;
        }
        final fade = CurvedAnimation(parent: animation, curve: FlowMotion.easeOut);
        final slide = Tween<Offset>(
          begin: Offset(forward ? 0.06 : -0.06, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: FlowMotion.easeOut));

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: child,
          ),
        );
      },
    );
  }
}
