import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_plan_models.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../screens/legal/privacy_policy_screen.dart';
import '../theme/flow_typography.dart';

/// Stored key keeps its original name so existing acceptances remain valid; it is never shown to users.
const String kGeminiPrivacyAcceptedKey = 'flowstate_gemini_privacy_accepted_v1';

/// Checks if the user has seen the Build My Day privacy notice. If not, shows it before anything is sent.
/// Choosing Cancel sends nothing; the caller then offers the basic planner.
Future<bool> checkAndShowGeminiPrivacyDisclosure(BuildContext context) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(kGeminiPrivacyAcceptedKey) ?? false;
    if (accepted) return true;
  } catch (_) {}

  if (!context.mounted) return false;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const BuildMyDayPrivacySheet(requireChoice: true),
  );

  if (result == true) {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kGeminiPrivacyAcceptedKey, true);
    } catch (_) {}
    return true;
  }
  return false;
}

/// Read-only version of the same notice, opened from the small "How your notes are used" link in Build My Day.
Future<void> showBuildMyDayPrivacyInfo(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const BuildMyDayPrivacySheet(requireChoice: false),
  );
}

/// Short, product-voiced notice about how Build My Day handles notes. Names no provider; the Privacy Policy does.
/// [requireChoice] shows Cancel / Continue (the pre-send gate); otherwise a single Done button.
class BuildMyDayPrivacySheet extends StatelessWidget {
  final bool requireChoice;
  const BuildMyDayPrivacySheet({super.key, required this.requireChoice});

  @override
  Widget build(BuildContext context) {
    final textPrimary = FlowColors.textPrimaryOf(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: FlowColors.border(context),
                  borderRadius: FlowRadii.pillRadius,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: FlowColors.accentCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.privacy_tip_outlined, color: FlowColors.accentCyan, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'How Build My Day uses your notes',
                      style: FlowTypography.titleMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FlowColors.surfaceContainer(context),
                borderRadius: FlowRadii.cardRadius,
                border: Border.all(color: FlowColors.border(context)),
              ),
              child: Text(
                'Build My Day turns your notes into a practical plan. To do that, your text is sent to Flowstate\'s '
                'servers and to an external AI service that organizes it into tasks. You review everything before it is added.',
                style: FlowTypography.bodyMedium(color: textPrimary).copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Only your notes, today\'s date and your time zone are sent. Your email, password and sign-in details are not. '
              'Simple lists can be organized on your device without being sent.',
              style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(height: 1.45),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('privacy_policy_link'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                foregroundColor: FlowColors.accentCyan,
              ),
              onPressed: () {
                FlowHaptics.lightTap();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
              },
              child: Text(
                'Read the Privacy Policy',
                style: FlowTypography.labelLarge(color: FlowColors.accentCyan).copyWith(
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (requireChoice)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
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
                      key: const Key('privacy_continue_button'),
                      onPressed: () {
                        FlowHaptics.lightTap();
                        Navigator.of(context).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FlowColors.accentCyan,
                        foregroundColor: FlowColors.textInverse,
                        elevation: 0,
                        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Continue',
                        style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('privacy_done_button'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textPrimary,
                    side: BorderSide(color: FlowColors.border(context)),
                    shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Done', style: FlowTypography.labelLarge(color: textPrimary)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

bool _shieldSheetOpen = false;

String _shieldCount(int n) => '$n Shield${n == 1 ? '' : 's'}';

/// Confirmation sheet shown BEFORE the AI request when an AI plan is paid with Shields.
/// Only one can be open at a time: a second call while one is showing returns false without stacking another.
Future<bool> showShieldConfirmationSheet(
  BuildContext context, {
  required int shieldsAvailable,
  int shieldCost = AIUsageStatus.defaultShieldCost,
  int freeRemaining = 0,
}) async {
  if (_shieldSheetOpen) return false;
  _shieldSheetOpen = true;
  final bool? result;
  try {
    result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ShieldConfirmationSheet(
      shieldsAvailable: shieldsAvailable,
      shieldCost: shieldCost,
      freeRemaining: freeRemaining,
    ),
    );
  } finally {
    _shieldSheetOpen = false;
  }
  return result == true;
}

class _ShieldConfirmationSheet extends StatefulWidget {
  final int shieldsAvailable;
  final int shieldCost;
  final int freeRemaining;

  const _ShieldConfirmationSheet({
    required this.shieldsAvailable,
    this.shieldCost = AIUsageStatus.defaultShieldCost,
    this.freeRemaining = 0,
  });

  @override
  State<_ShieldConfirmationSheet> createState() =>
      _ShieldConfirmationSheetState();
}

class _ShieldConfirmationSheetState extends State<_ShieldConfirmationSheet> {
  bool _answered = false;

  @override
  void dispose() {
    _shieldSheetOpen = false; // however the sheet goes away (answer, back swipe, teardown), the guard is released
    super.dispose();
  }

  /// A double tap (or Confirm + Not now) answers exactly once.
  void _answer(bool confirmed) {
    if (_answered) return;
    _answered = true;
    if (confirmed) {
      FlowHaptics.selection();
    } else {
      FlowHaptics.lightTap();
    }
    Navigator.of(context).pop(confirmed);
  }

  @override
  Widget build(BuildContext context) {
    final shieldsAvailable = widget.shieldsAvailable;
    final cost = widget.shieldCost;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: FlowColors.border(context),
                  borderRadius: FlowRadii.pillRadius,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: FlowColors.accentCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shield_outlined, color: FlowColors.accentCyan, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Use ${_shieldCount(cost)}?',
                    style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
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
                    'Noya can plan this for you using ${_shieldCount(cost)}.',
                    key: const Key('shield_reason_text'),
                    style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context))
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your free AI plan is used up. Nothing is charged if Noya can\'t finish the plan.\nShields also protect your Flow streak if you ever miss a day.',
                    style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.security_rounded, size: 14, color: FlowColors.accentCyan),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Available: $shieldsAvailable Shield${shieldsAvailable == 1 ? '' : 's'}',
                          style: FlowTypography.labelSmall(color: FlowColors.accentCyan)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('shield_not_now_button'),
                    onPressed: () => _answer(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FlowColors.textMutedOf(context),
                      side: BorderSide(color: FlowColors.border(context)),
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Not now', style: FlowTypography.labelLarge(color: FlowColors.textMutedOf(context))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    key: const Key('use_shields_button'),
                    onPressed: () => _answer(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlowColors.accentCyan,
                      foregroundColor: FlowColors.textInverse,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Use ${_shieldCount(cost)}',
                      style: FlowTypography.labelLarge(color: FlowColors.textInverse)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
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

/// Bottom sheet when free AI uses and shields are exhausted
void showAIExhaustedSheet(
  BuildContext context, {
  required VoidCallback onGoPro,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AIExhaustedSheet(onGoPro: onGoPro),
  );
}

class _AIExhaustedSheet extends StatelessWidget {
  final VoidCallback onGoPro;

  const _AIExhaustedSheet({required this.onGoPro});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: FlowColors.border(context),
                  borderRadius: FlowRadii.pillRadius,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: FlowColors.accentMint.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: FlowColors.accentMint, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "You've used your free AI plan.",
                    style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Use a Shield for another plan or upgrade to Pro for unlimited AI planning.',
              style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FlowColors.textMutedOf(context),
                      side: BorderSide(color: FlowColors.border(context)),
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Close', style: FlowTypography.labelLarge(color: FlowColors.textMutedOf(context))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    key: const Key('go_pro_exhausted_button'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onGoPro();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlowColors.accentCyan,
                      foregroundColor: FlowColors.textInverse,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Go Pro',
                      style: FlowTypography.labelLarge(color: FlowColors.textInverse)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
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
