import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'framer_motion_wrapper.dart';

/// A calm, functional 15-minute recharge break session card.
///
/// Principles:
/// - Real state transition (no fake button)
/// - Countdown timer with auto-completion
/// - Resume / End break early action
/// - Clean white aesthetic with slate typography
/// - Return to next recommended task when finished
class BreakSessionCard extends StatefulWidget {
  final TaskItem? nextTask;
  final VoidCallback onFinish;

  const BreakSessionCard({
    super.key,
    this.nextTask,
    required this.onFinish,
  });

  @override
  State<BreakSessionCard> createState() => _BreakSessionCardState();
}

class _BreakSessionCardState extends State<BreakSessionCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final state = Provider.of<AppStateProvider>(context, listen: false);
      final currentElapsed = state.breakElapsedSeconds + 1;
      final targetSeconds = state.breakDurationMinutes * 60;

      if (currentElapsed >= targetSeconds) {
        _timer?.cancel();
        state.endBreakSession();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.nextTask != null
                  ? 'Recharge complete! Ready for "${widget.nextTask!.title}".'
                  : 'Recharge complete! Ready for your next session.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        widget.onFinish();
      } else {
        state.updateBreakElapsed(currentElapsed);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatRemaining(int remainingSeconds) {
    if (remainingSeconds < 0) remainingSeconds = 0;
    final mins = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (remainingSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);

    final totalTargetSeconds = state.breakDurationMinutes * 60;
    final remainingSeconds = totalTargetSeconds - state.breakElapsedSeconds;
    final double progress = totalTargetSeconds > 0
        ? (state.breakElapsedSeconds / totalTargetSeconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardLargeRadius,
        border: Border.all(
          color: FlowColors.accentMint.withValues(alpha: 0.45),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Tag: ✦ RECHARGE BREAK
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: FlowColors.accentMint,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'RECHARGE BREAK',
                    style: FlowTypography.badgeText(color: FlowColors.accentMint).copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Text(
                '${state.breakDurationMinutes} min',
                style: FlowTypography.labelSmall(color: FlowColors.textMuted).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Title
          Text(
            'Taking a breather',
            style: FlowTypography.headlineMedium().copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 22.0,
              color: FlowColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),

          // Calming prompt
          Text(
            'Step away from the screen, stretch, or hydrate. Flowstate will return to your work when you’re ready.',
            style: FlowTypography.bodyMedium(color: FlowColors.textSecondary).copyWith(
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),

          // Large Timer Display + Progress Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: FlowColors.darkCardElevated,
              borderRadius: FlowRadii.buttonRadius,
              border: Border.all(color: FlowColors.darkBorder, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatRemaining(remainingSeconds),
                      style: FlowTypography.displayLarge().copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: FlowColors.textPrimary,
                      ),
                    ),
                    Text(
                      'remaining',
                      style: FlowTypography.bodySmall(color: FlowColors.textMuted).copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: FlowRadii.pillRadius,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: FlowColors.darkBorder,
                    valueColor: const AlwaysStoppedAnimation<Color>(FlowColors.accentMint),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Next Task Preview
          if (widget.nextTask != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: FlowColors.darkCardElevated,
                borderRadius: FlowRadii.inputRadius,
                border: Border.all(color: FlowColors.darkBorder, width: 1.0),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: FlowColors.textSecondary,
                    size: 15,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Up next: ${widget.nextTask!.title}',
                      style: FlowTypography.labelSmall(color: FlowColors.textSecondary).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${widget.nextTask!.durationMinutes}m',
                    style: FlowTypography.labelSmall(color: FlowColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Action Buttons: Resume Work / +5 min
          Row(
            children: [
              // Primary: End Break & Resume
              Expanded(
                flex: 7,
                child: FramerMotionPressScale(
                  onTap: () {
                    _timer?.cancel();
                    state.endBreakSession();
                    widget.onFinish();
                  },
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        _timer?.cancel();
                        state.endBreakSession();
                        widget.onFinish();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FlowColors.accentMint,
                        foregroundColor: FlowColors.textInverse,
                        elevation: 0,
                        shape: const RoundedRectangleBorder(
                          borderRadius: FlowRadii.buttonRadius,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            color: FlowColors.textInverse,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Resume Work',
                            style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Secondary: +5 min
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () {
                      state.startBreakSession(
                        minutes: state.breakDurationMinutes + 5,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      foregroundColor: FlowColors.textSecondary,
                      side: const BorderSide(color: FlowColors.darkBorder, width: 1.0),
                      shape: const RoundedRectangleBorder(
                        borderRadius: FlowRadii.buttonRadius,
                      ),
                    ),
                    child: Text(
                      '+5 min',
                      style: FlowTypography.labelMedium(color: FlowColors.textSecondary).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
