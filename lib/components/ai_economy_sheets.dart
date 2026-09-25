import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

const String kGeminiPrivacyAcceptedKey = 'flowstate_gemini_privacy_accepted_v1';

/// Checks if user has accepted the Gemini privacy disclosure. If not, shows disclosure modal.
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
    backgroundColor: FlowColors.darkSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _GeminiPrivacyDisclosureSheet(),
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

class _GeminiPrivacyDisclosureSheet extends StatelessWidget {
  const _GeminiPrivacyDisclosureSheet();

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
                decoration: const BoxDecoration(
                  color: FlowColors.darkBorder,
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
                  child: Text(
                    'Privacy & AI Notice',
                    style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FlowColors.darkCard,
                borderRadius: FlowRadii.cardRadius,
                border: Border.all(color: FlowColors.darkBorder),
              ),
              child: Text(
                'Flowstate uses Google Gemini to organize your task list.\nThe text you submit is sent to Google to process your request.',
                style: FlowTypography.bodyMedium(color: FlowColors.textPrimary).copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Only raw task notes, current date, and timezone are transmitted. Credentials, passwords, and private profile records are never sent.',
              style: FlowTypography.bodySmall(color: FlowColors.textMuted),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FlowColors.textMuted,
                      side: const BorderSide(color: FlowColors.darkBorder),
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Not now', style: FlowTypography.labelLarge(color: FlowColors.textMuted)),
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

/// Confirmation sheet when spending 1 Flowstate Shield for an additional AI planning session
Future<bool> showShieldConfirmationSheet(
  BuildContext context, {
  required int shieldsAvailable,
  int freeRemaining = 0,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.darkSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ShieldConfirmationSheet(
      shieldsAvailable: shieldsAvailable,
      freeRemaining: freeRemaining,
    ),
  );
  return result == true;
}

class _ShieldConfirmationSheet extends StatelessWidget {
  final int shieldsAvailable;
  final int freeRemaining;

  const _ShieldConfirmationSheet({
    required this.shieldsAvailable,
    this.freeRemaining = 0,
  });

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
                decoration: const BoxDecoration(
                  color: FlowColors.darkBorder,
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
                    'Use a Shield?',
                    style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FlowColors.darkCard,
                borderRadius: FlowRadii.cardRadius,
                border: Border.all(color: FlowColors.darkBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You have $freeRemaining free AI plans remaining.',
                    style: FlowTypography.bodyMedium(color: FlowColors.textPrimary)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Using a Shield will give you another AI planning session.\nShields can also protect your Flow streak.',
                    style: FlowTypography.bodySmall(color: FlowColors.textSecondary).copyWith(height: 1.4),
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
                    onPressed: () {
                      FlowHaptics.lightTap();
                      Navigator.of(context).pop(false);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FlowColors.textMuted,
                      side: const BorderSide(color: FlowColors.darkBorder),
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Not now', style: FlowTypography.labelLarge(color: FlowColors.textMuted)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    key: const Key('use_1_shield_button'),
                    onPressed: () {
                      FlowHaptics.selection();
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
                      'Use 1 Shield',
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
    backgroundColor: FlowColors.darkSurface,
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
                decoration: const BoxDecoration(
                  color: FlowColors.darkBorder,
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
                    style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Use a Shield for another plan or upgrade to Pro.',
              style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FlowColors.textMuted,
                      side: const BorderSide(color: FlowColors.darkBorder),
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Close', style: FlowTypography.labelLarge(color: FlowColors.textMuted)),
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
