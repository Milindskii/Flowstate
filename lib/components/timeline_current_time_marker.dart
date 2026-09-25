import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/flow_clock.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_typography.dart';

/// Real-time indicator line: ──── 10:42 AM NOW ────
/// Automatically updates on minute rollover via FlowClock.
class TimelineCurrentTimeMarker extends StatelessWidget {
  final DateTime? time;

  const TimelineCurrentTimeMarker({
    super.key,
    this.time,
  });

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

    return ListenableBuilder(
      listenable: FlowClock(),
      builder: (context, _) {
        final now = time ?? FlowClock().now;
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
                      Container(
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
                      const SizedBox(width: 6),
                      Text(
                        '$formattedTime NOW',
                        style: FlowTypography.labelSmall(color: accent).copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          fontSize: 11,
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
