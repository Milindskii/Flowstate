import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'framer_motion_wrapper.dart';

/// The Hero of the Today Screen: "DO THIS NOW"
/// Highest visual weight, minimal clutter, interactive "Why this?" reasons.
class RightNowTaskCard extends StatefulWidget {
  final TaskItem task;
  final VoidCallback onStart;
  final VoidCallback onReschedule;
  final List<String>? reasons;
  final bool isRunning;
  final int elapsedSeconds;
  final VoidCallback? onPause;
  final VoidCallback? onComplete;
  final VoidCallback? onTakeBreak;
  final VoidCallback? onFocusRitual;

  const RightNowTaskCard({
    super.key,
    required this.task,
    required this.onStart,
    required this.onReschedule,
    this.reasons,
    this.isRunning = false,
    this.elapsedSeconds = 0,
    this.onPause,
    this.onComplete,
    this.onTakeBreak,
    this.onFocusRitual,
  });

  @override
  State<RightNowTaskCard> createState() => _RightNowTaskCardState();
}

class _RightNowTaskCardState extends State<RightNowTaskCard> {
  bool _showWhy = false;
  bool _isExpanded = false;

  String _formatElapsed(int totalSecs) {
    final m = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final s = (totalSecs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

    final defaultReasons = [
      'Due tomorrow',
      'Strong focus window',
      'Fits your available time',
    ];
    final activeReasons = (widget.reasons != null && widget.reasons!.isNotEmpty)
        ? widget.reasons!
        : defaultReasons;

    return GestureDetector(
      onTap: () {
        FlowHaptics.lightTap();
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: FlowColors.surface(context),
          borderRadius: FlowRadii.cardLargeRadius,
          border: Border.all(
            color: widget.isRunning ? accent.withValues(alpha: 0.5) : FlowColors.border(context),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: FlowColors.softShadow(context),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header: DO THIS NOW + Expand toggle icon
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'DO THIS NOW',
                      style: FlowTypography.badgeText(color: FlowColors.textSecondary).copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                Icon(
                  _isExpanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                  size: 18,
                  color: FlowColors.textMutedOf(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Task Title (Hero - Dominates through typography & whitespace)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.onComplete != null) ...[
                  Semantics(
                    button: true,
                    label: 'Mark ${widget.task.title} as done',
                    child: InkWell(
                      onTap: () {
                        FlowHaptics.success();
                        widget.onComplete!();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.only(right: 10.0),
                        child: Icon(
                          Icons.radio_button_unchecked_rounded,
                          size: 26,
                          color: FlowColors.mint,
                        ),
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: Text(
                    widget.task.title,
                    style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 22.0,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Clean Metadata: duration · importance · energy
            Text(
              '${widget.task.durationMinutes} min · ${widget.task.importanceLabel} importance · ${widget.task.energyRequired} energy',
              style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),

            // Expandable details: Priority, Window, Deadline
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: _isExpanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: FlowColors.surfaceElevated(context),
                            borderRadius: FlowRadii.cardRadius,
                            border: Border.all(color: FlowColors.border(context)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PRIORITY',
                                    style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.task.difficulty.name.toUpperCase(),
                                    style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              Container(width: 1, height: 24, color: FlowColors.border(context)),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'WINDOW',
                                    style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.task.scheduledTime ?? 'Dynamic Slot',
                                    style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              Container(width: 1, height: 24, color: FlowColors.border(context)),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'DEADLINE',
                                    style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.task.deadline,
                                    style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (widget.onFocusRitual != null) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                FlowHaptics.lightTap();
                                widget.onFocusRitual!();
                              },
                              icon: Icon(Icons.self_improvement_rounded, size: 18, color: accent),
                              label: Text(
                                'Open Focus Ritual with Noya',
                                style: FlowTypography.labelMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: accent.withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  : const SizedBox.shrink(),
            ),

            const SizedBox(height: 16),

            // Action Section: Start + Later + Done
            if (!widget.isRunning) ...[
            Row(
              children: [
                // Primary Start Button with Framer-style press scale
                Expanded(
                  flex: 7,
                  child: FramerMotionPressScale(
                    onTap: () {
                      FlowHaptics.lightTap();
                      widget.onStart();
                    },
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          FlowHaptics.lightTap();
                          widget.onStart();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: FlowColors.textInverse,
                          elevation: 0,
                          shape: const RoundedRectangleBorder(
                            borderRadius: FlowRadii.buttonRadius,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.play_arrow_rounded,
                                color: FlowColors.textInverse,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Start Focus',
                                style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.0,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Secondary Later Button
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () {
                        FlowHaptics.lightTap();
                        widget.onReschedule();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: FlowColors.textSecondaryOf(context),
                        side: BorderSide(color: FlowColors.border(context), width: 1.0),
                        shape: const RoundedRectangleBorder(
                          borderRadius: FlowRadii.buttonRadius,
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Later',
                          style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Running State (Section 11 & Task Transitions)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: FlowColors.surfaceElevated(context),
                borderRadius: FlowRadii.buttonRadius,
                border: Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: FlowColors.successOf(context),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Running · ${_formatElapsed(widget.elapsedSeconds)} elapsed',
                      style: FlowTypography.labelMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.onPause != null)
                    TextButton(
                      onPressed: () {
                        FlowHaptics.lightTap();
                        widget.onPause!();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text('Pause', style: TextStyle(color: FlowColors.textSecondaryOf(context), fontSize: 13)),
                    ),
                  if (widget.onComplete != null)
                    ElevatedButton(
                      onPressed: () {
                        FlowHaptics.success();
                        widget.onComplete!();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FlowColors.successOf(context),
                        foregroundColor: FlowColors.textInverse,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.pillRadius),
                      ),
                      child: const Text('Done', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Optional Subtle "Why this?" Expandable & Take a break trigger
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8.0,
            runSpacing: 4.0,
            children: [
              InkWell(
                onTap: () {
                  FlowHaptics.selection();
                  setState(() => _showWhy = !_showWhy);
                },
                borderRadius: FlowRadii.inputRadius,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Why this?',
                        style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _showWhy ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: FlowColors.textMutedOf(context),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.onTakeBreak != null)
                GestureDetector(
                  onTap: () {
                    FlowHaptics.lightTap();
                    widget.onTakeBreak!();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Take a break',
                      style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          if (_showWhy) ...[
            const SizedBox(height: 6),
            ...activeReasons.take(3).map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text('•', style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r,
                        style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
}
