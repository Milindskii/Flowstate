import 'package:flutter/material.dart';

import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_motion.dart';

/// Animated completion check (spec §8.2): the circle fills over 150 ms (easeOutCubic) with a
/// success haptic. A 48 dp hit area surrounds the visual; reduced motion makes it instant.
class FlowCompletionCheck extends StatefulWidget {
  final bool completed;
  final VoidCallback? onToggle;
  final double size;

  /// Overrides the default "Mark complete" / "Completed" semantics label.
  final String? label;
  final Color? color;
  final Color? outlineColor;

  const FlowCompletionCheck({
    super.key,
    required this.completed,
    required this.onToggle,
    this.size = 24,
    this.label,
    this.color,
    this.outlineColor,
  });

  @visibleForTesting
  static const Key fillKey = ValueKey('flow_completion_check_fill');

  @override
  State<FlowCompletionCheck> createState() => _FlowCompletionCheckState();
}

class _FlowCompletionCheckState extends State<FlowCompletionCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: FlowMotion.microDuration,
    value: widget.completed ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _fill, curve: FlowMotion.easeOut);

  @override
  void didUpdateWidget(FlowCompletionCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.completed == oldWidget.completed) return;
    final target = widget.completed ? 1.0 : 0.0;
    if (FlowMotion.isReducedMotion(context)) {
      _fill.value = target;
    } else {
      _fill.animateTo(target);
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.onToggle == null) return;
    if (widget.completed) {
      FlowHaptics.lightTap();
    } else {
      FlowHaptics.success();
    }
    widget.onToggle!();
  }

  @override
  Widget build(BuildContext context) {
    final fillColor = widget.color ?? FlowColors.successOf(context);
    final outline = widget.outlineColor ?? FlowColors.textMutedOf(context);
    final hit = widget.size < 48 ? 48.0 : widget.size;

    return Semantics(
      container: true,
      button: true,
      checked: widget.completed,
      label: widget.label ?? (widget.completed ? 'Completed' : 'Mark complete'),
      onTap: widget.onToggle == null ? null : _toggle,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle == null ? null : _toggle,
        child: SizedBox(
          width: hit,
          height: hit,
          child: Center(
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: AnimatedBuilder(
                animation: _curve,
                builder: (context, _) {
                  final t = _curve.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_fill.value < 1)
                        Icon(Icons.radio_button_unchecked_rounded, size: widget.size, color: outline),
                      if (_fill.value > 0)
                        Opacity(
                          key: FlowCompletionCheck.fillKey,
                          opacity: t.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.8 + 0.2 * t,
                            child: Icon(Icons.check_circle_rounded, size: widget.size, color: fillColor),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
