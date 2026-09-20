import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../services/task_parse_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'parsed_plan_confirm_sheet.dart';

/// Bottom sheet for brain-dump task input post-onboarding.
/// Calls the backend parser, then shows a ParsedPlanConfirmSheet.
/// Production: POST /api/v1/tasks/parse → backend.
/// Offline fallback: static demo stub (same as onboarding).
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

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final v = _ctrl.text.trim().length >= 10;
      if (v != _isValid) setState(() => _isValid = v);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _onVoiceTap() {
    // DEMO PLACEHOLDER — replace with real STT (e.g., speech_to_text package)
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Voice input coming soon', style: FlowTypography.bodySmall(color: FlowColors.textPrimary)),
      backgroundColor: FlowColors.darkCardElevated,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _build() async {
    if (!_isValid || _isLoading) return;
    setState(() => _isLoading = true);

    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final parseService = TaskParseService(api: provider.apiService);

    try {
      final results = await parseService.parseBrainDump(
        _ctrl.text.trim(),
        isDemoMode: provider.isDemoMode,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // Close brain dump sheet
      showParsedPlanConfirmSheet(context, candidates: results);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try { accent = Provider.of<ThemeProvider>(context).accentColor; } catch (_) {}

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 36, height: 4,
              decoration: const BoxDecoration(color: FlowColors.darkBorder, borderRadius: FlowRadii.pillRadius),
            )),
            const SizedBox(height: 20),
            Text("What else is on your plate?", style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Just write it out.', style: FlowTypography.bodySmall(color: FlowColors.textMuted)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: FlowColors.darkCard,
                borderRadius: FlowRadii.cardRadius,
                border: Border.all(color: FlowColors.darkBorder),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    maxLines: 5, minLines: 3,
                    style: FlowTypography.bodyMedium(),
                    decoration: InputDecoration(
                      hintText: 'e.g. Finish Python lab, attend meeting at 3, buy groceries...',
                      hintStyle: FlowTypography.bodySmall(color: FlowColors.textMuted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: FlowColors.darkBorder))),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: _onVoiceTap,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: FlowColors.darkCardElevated, borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.mic_none_rounded, color: FlowColors.textMuted, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: _isValid && !_isLoading ? _build : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isValid ? accent : FlowColors.darkBorder,
                  foregroundColor: _isValid ? FlowColors.textInverse : FlowColors.textMuted,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                ),
                child: _isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: FlowColors.textInverse, strokeWidth: 2))
                  : Text('Build', style: FlowTypography.labelLarge(color: _isValid ? FlowColors.textInverse : FlowColors.textMuted).copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
