import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'noya_companion_view.dart';
import 'noya_motion_view.dart';

/// A polished, friendly failure state featuring sleeping Noya.
///
/// Used consistently across Build My Day and Replan whenever AI planning
/// encounters quota exhaustion, provider failures, timeouts, or unexpected errors.
/// Reassures the user that their tasks and draft are safe.
class NoyaFailureState extends StatelessWidget {
  /// The main headline. Defaults to "Noya's taking a little nap".
  final String title;

  /// The reassuring body copy explaining tasks/text are safe.
  final String body;

  /// Secondary action callback (e.g. "Try again").
  final VoidCallback? onRetry;

  /// Primary or alternative action callback (e.g. "Plan it myself" or "Sign in").
  final VoidCallback? onAlternative;

  /// Label for the retry button. Defaults to "Try again".
  final String retryLabel;

  /// Label for the alternative button (e.g. "Plan it myself").
  final String? alternativeLabel;

  /// Custom key for the retry button (e.g. for test compatibility).
  final Key? retryKey;

  /// Custom key for the alternative button.
  final Key? alternativeKey;

  /// Whether a retry/operation is currently in progress.
  final bool isLoading;

  /// If true, renders a slightly more compact layout suitable for chat streams.
  final bool compact;

  const NoyaFailureState({
    super.key,
    this.title = "Noya's taking a little nap",
    this.body =
        'Something went wrong while planning your day. Your existing tasks are safe.',
    this.onRetry,
    this.onAlternative,
    this.retryLabel = 'Try again',
    this.alternativeLabel,
    this.retryKey,
    this.alternativeKey,
    this.isLoading = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

    final cardBg = FlowColors.surfaceElevated(context);
    final borderColor = FlowColors.border(context);

    final noyaSize = compact ? 44.0 : 60.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14.0 : 18.0,
        vertical: compact ? 10.0 : 14.0,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: FlowColors.isDark(context)
                ? Colors.black.withValues(alpha: 0.20)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Visual Focus: Sleeping Noya with subtle breathing loop and warm glow
          Center(
            child: Semantics(
              label: 'Sleeping Noya taking a nap',
              child: NoyaMotionView(
                mood: NoyaMood.asleep,
                pose: NoyaState.sleepy,
                size: noyaSize,
                showAmbientGlow: true,
              ),
            ),
          ),
          SizedBox(height: compact ? 6.0 : 8.0),

          // Title
          Text(
            title,
            textAlign: TextAlign.center,
            style: (compact
                    ? FlowTypography.titleSmall()
                    : FlowTypography.titleMedium())
                .copyWith(
              fontWeight: FontWeight.w700,
              color: FlowColors.textPrimaryOf(context),
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 4.0),

          // Reassuring Body
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 4.0 : 12.0),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: FlowTypography.bodySmall(
                color: FlowColors.textSecondaryOf(context),
              ).copyWith(
                height: 1.35,
              ),
            ),
          ),
          SizedBox(height: compact ? 10.0 : 14.0),

          // Action Buttons: debounced and guarded against repeated taps
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (onRetry != null)
                OutlinedButton(
                  key: retryKey ?? const Key('retry_ai_button'),
                  onPressed: isLoading ? null : onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FlowColors.textPrimaryOf(context),
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    minimumSize: const Size(48, 44),
                    shape: const RoundedRectangleBorder(
                      borderRadius: FlowRadii.pillRadius,
                    ),
                  ),
                  child: Text(
                    retryLabel,
                    style: FlowTypography.labelMedium(
                      color: FlowColors.textPrimaryOf(context),
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              if (onAlternative != null && alternativeLabel != null)
                FilledButton(
                  key: alternativeKey ?? const Key('use_basic_planner_button'),
                  onPressed: isLoading ? null : onAlternative,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    minimumSize: const Size(48, 44),
                    shape: const RoundedRectangleBorder(
                      borderRadius: FlowRadii.pillRadius,
                    ),
                  ),
                  child: Text(
                    alternativeLabel!,
                    style: FlowTypography.labelMedium(
                      color: Colors.white,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
