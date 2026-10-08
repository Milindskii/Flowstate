import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/routine.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

bool _routineSheetOpen = false;

/// "Make Gym a daily routine?" Shown before a routine found in a brain dump is applied.
/// Returns true only when the user taps Confirm; closing the sheet any other way is a cancel and saves nothing.
Future<bool> showRoutineConfirmSheet(BuildContext context, RoutineProposal proposal) async {
  if (_routineSheetOpen) return false;
  _routineSheetOpen = true;
  try {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => RoutineConfirmSheet(proposal: proposal),
    );
    return result == true;
  } finally {
    _routineSheetOpen = false;
  }
}

String routineQuestion(RoutineProposal p) {
  switch (p.kind) {
    case 'avoid':
      return 'Keep ${p.title} out of that window?';
    case 'earliest':
      return 'Remember when ${p.title} can start?';
    default:
      final cadence = p.recurrence == 'weekly' ? 'weekly' : 'daily';
      return 'Make ${p.title} a $cadence routine?';
  }
}

String routineHorizonLine(RoutineProposal p) {
  if (!p.createsTasks) return 'Noya will keep this in mind whenever she plans ${p.title}.';
  if (p.planDates.isEmpty) return 'Nothing is left to plan in the next ${p.horizonDays} days. It will apply from the next one.';
  if (p.recurrence == 'daily') return 'Next ${p.horizonDays} days will be planned.';
  final days = p.planDates.map((d) => DateFormat('EEE d MMM').format(d)).join(', ');
  return 'Within the next ${p.horizonDays} days: $days.';
}

class RoutineConfirmSheet extends StatefulWidget {
  final RoutineProposal proposal;
  const RoutineConfirmSheet({super.key, required this.proposal});

  @override
  State<RoutineConfirmSheet> createState() => _RoutineConfirmSheetState();
}

class _RoutineConfirmSheetState extends State<RoutineConfirmSheet> {
  bool _answered = false;

  void _answer(bool confirmed) {
    if (_answered) return; // a double tap answers exactly once
    _answered = true;
    confirmed ? FlowHaptics.selection() : FlowHaptics.lightTap();
    Navigator.of(context).pop(confirmed);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.proposal;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: FlowColors.border(context), borderRadius: FlowRadii.pillRadius),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              routineQuestion(p),
              key: const Key('routine_confirm_title'),
              style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FlowColors.surfaceContainer(context),
                borderRadius: FlowRadii.cardRadius,
                border: Border.all(color: FlowColors.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.summary,
                    key: const Key('routine_confirm_summary'),
                    style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context))
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    routineHorizonLine(p),
                    key: const Key('routine_confirm_horizon'),
                    style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('routine_cancel_button'),
                    onPressed: () => _answer(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FlowColors.textMutedOf(context),
                      side: BorderSide(color: FlowColors.border(context)),
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Cancel', style: FlowTypography.labelLarge(color: FlowColors.textMutedOf(context))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    key: const Key('routine_confirm_button'),
                    onPressed: () => _answer(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlowColors.accentCyan,
                      foregroundColor: FlowColors.textInverse,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Confirm',
                        style: FlowTypography.labelLarge(color: FlowColors.textInverse)
                            .copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
