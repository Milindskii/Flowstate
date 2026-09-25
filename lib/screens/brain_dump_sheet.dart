import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/ai_economy_sheets.dart';
import '../models/ai_plan_models.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ai_plan_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'ai_plan_preview_sheet.dart';
import 'pro_subscription_screen.dart';

/// Bottom sheet for brain-dump task input.
///
/// Flow:
/// 1. Natural user text entry (no voice / microphone in V1).
/// 2. Privacy disclosure on first AI use.
/// 3. Server-owned AI economy & shield check.
/// 4. Gemini structured task extraction (non-inventive, strict schema).
/// 5. Compact preview or uncertainty confirmation before deterministic scheduling.
void showBrainDumpSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.darkSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _BrainDumpSheet(),
  );
}

class _BrainDumpSheet extends StatefulWidget {
  const _BrainDumpSheet();
  @override
  State<_BrainDumpSheet> createState() => _BrainDumpSheetState();
}

class _BrainDumpSheetState extends State<_BrainDumpSheet> {
  final _ctrl = TextEditingController();
  bool _isValid = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final v = _ctrl.text.trim().isNotEmpty;
      if (v != _isValid) setState(() => _isValid = v);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    if (!_isValid || _isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final aiService = AIPlanService(api: provider.apiService);

    try {
      // 1. Privacy Disclosure Check (First-time user)
      final acceptedPrivacy = await checkAndShowGeminiPrivacyDisclosure(context);
      if (!acceptedPrivacy) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 2. Server-side AI Usage & Economy Check
      final usageStatus = await aiService.getUsageStatus();
      bool consumeShield = false;

      if (!usageStatus.isPro && !usageStatus.freeUseAvailable) {
        if (usageStatus.shieldsAvailable > 0) {
          // Explicit shield spending confirmation sheet
          if (!mounted) return;
          final confirmedShield = await showShieldConfirmationSheet(
            context,
            shieldsAvailable: usageStatus.shieldsAvailable,
            freeRemaining: 0,
          );
          if (!confirmedShield) {
            if (mounted) setState(() => _isLoading = false);
            return;
          }
          consumeShield = true;
        } else {
          // Quota exhausted & no shields available
          if (!mounted) return;
          setState(() => _isLoading = false);
          showAIExhaustedSheet(
            context,
            onGoPro: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProSubscriptionScreen()),
              );
            },
          );
          return;
        }
      }

      // 3. Generate structured task plan via Gemini with idempotency
      final result = await aiService.generatePlan(
        rawText: _ctrl.text.trim(),
        consumeShield: consumeShield,
      );

      if (!mounted) return;

      if (result.tasks.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Couldn't identify tasks. Try describing what you need to do.";
        });
        return;
      }

      // Close brain dump sheet and present structured confirmation preview
      Navigator.of(context).pop();
      showAIPlanPreviewSheet(context, planResult: result);
    } on AIEconomyException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (e.code == 'SHIELD_REQUIRED') {
        final confirmed = await showShieldConfirmationSheet(
          context,
          shieldsAvailable: e.shieldsAvailable,
          freeRemaining: 0,
        );
        if (confirmed && mounted) {
          _build();
        }
      } else if (e.code == 'QUOTA_EXHAUSTED') {
        showAIExhaustedSheet(
          context,
          onGoPro: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProSubscriptionScreen()),
            );
          },
        );
      } else {
        setState(() => _errorMessage = e.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Planning service unavailable. Please check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

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
            Text(
              "What else is on your plate?",
              style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Just write it out.',
              style: FlowTypography.bodySmall(color: FlowColors.textMuted),
            ),
            const SizedBox(height: 16),

            // Text input container (Microphone completely removed for V1)
            Container(
              decoration: BoxDecoration(
                color: FlowColors.darkCard,
                borderRadius: FlowRadii.cardRadius,
                border: Border.all(
                  color: _errorMessage != null ? FlowColors.warning : FlowColors.darkBorder,
                ),
              ),
              child: TextField(
                key: const Key('brain_dump_text_field'),
                controller: _ctrl,
                autofocus: true,
                maxLines: 5,
                minLines: 3,
                style: FlowTypography.bodyMedium(),
                decoration: InputDecoration(
                  hintText: 'e.g. Finish Python lab tomorrow, study arrays, call the dentist at 4, gym at 6...',
                  hintStyle: FlowTypography.bodySmall(color: FlowColors.textMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: FlowTypography.bodySmall(color: FlowColors.warning),
              ),
            ],

            const SizedBox(height: 16),

            // Build Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                key: const Key('brain_dump_build_button'),
                onPressed: _isValid && !_isLoading ? _build : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isValid ? accent : FlowColors.darkBorder,
                  foregroundColor: _isValid ? FlowColors.textInverse : FlowColors.textMuted,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: FlowColors.textInverse,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Build',
                        style: FlowTypography.labelLarge(
                          color: _isValid ? FlowColors.textInverse : FlowColors.textMuted,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
