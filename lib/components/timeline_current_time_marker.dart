import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/flow_clock.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_motion.dart';
import '../theme/flow_typography.dart';

/// Real-time indicator line: ──── 10:42 AM NOW ────
/// Automatically updates on minute rollover via FlowClock.
///
/// On today's date the dot pulses 1.0 ↔ 0.55 opacity for three 2,400 ms cycles after the screen
/// is shown, then rests (spec §8.7). No pulse under reduced motion or with loops disabled.
class TimelineCurrentTimeMarker extends StatefulWidget {
  final DateTime? time;
  final bool isToday;

  const TimelineCurrentTimeMarker({
    super.key,
    this.time,
    this.isToday = true,
  });

  static const Duration pulsePeriod = Duration(milliseconds: 2400);
  static const int pulseCycles = 3;

  @override
  State<TimelineCurrentTimeMarker> createState() => _TimelineCurrentTimeMarkerState();
}

class _TimelineCurrentTimeMarkerState extends State<TimelineCurrentTimeMarker> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: TimelineCurrentTimeMarker.pulsePeriod * TimelineCurrentTimeMarker.pulseCycles,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed = widget.isToday && FlowMotion.loopsEnabled(context);
    if (!allowed) {
      // Reduced motion switched on mid-pulse: stop at the rest frame.
      if (_pulse.isAnimating) _pulse.stop();
      _pulse.value = 0;
    } else if (!_started) {
      _started = true;
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// 1.0 at rest, dipping to 0.55 mid-cycle; every cycle starts and ends at 1.0.
  double get _dotOpacity {
    if (_pulse.value == 0 || _pulse.isCompleted) return 1.0;
    final t = (_pulse.value * TimelineCurrentTimeMarker.pulseCycles) % 1.0;
    final dip = (1 - math.cos(2 * math.pi * t)) / 2;
    return 1.0 - 0.45 * dip;
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

    return ListenableBuilder(
      listenable: FlowClock(),
      builder: (context, _) {
        final now = widget.time ?? FlowClock().now;
        final formattedTime = DateFormat('h:mm a').format(now);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  color: accent.withValues(alpha: 0.35),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) => Opacity(
                          key: const Key('timeline_now_marker_dot'),
                          opacity: _dotOpacity,
                          child: child,
                        ),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.6),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$formattedTime NOW',
                        style: FlowTypography.labelSmall(color: accent).copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1,
                  color: accent.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
