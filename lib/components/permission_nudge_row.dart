import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Non-intrusive inline permission nudge.
/// Appears inline in the Today page — NOT as a popup.
/// Shows once, can be dismissed permanently.
/// Use for: calendar access, health/battery data, notification opt-in.
class PermissionNudgeRow extends StatefulWidget {
  /// Reason text — must explain the value, not beg.
  /// Example: 'Calendar access helps Flowstate find your free time blocks.'
  final String reason;
  final String actionLabel;
  final VoidCallback onAction;

  const PermissionNudgeRow({
    super.key,
    required this.reason,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  State<PermissionNudgeRow> createState() => _PermissionNudgeRowState();
}

class _PermissionNudgeRowState extends State<PermissionNudgeRow>
    with SingleTickerProviderStateMixin {
  bool _dismissed = false;
  late final AnimationController _ctrl;
  late final Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _heightFactor = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.value = 1.0; // Start open
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _dismiss() {
    _ctrl.reverse().then((_) {
      if (mounted) setState(() => _dismissed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    Color accent = FlowColors.accentCyan;
    try { accent = Provider.of<ThemeProvider>(context).accentColor; } catch (_) {}

    return SizeTransition(
      sizeFactor: _heightFactor,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Container(
          decoration: BoxDecoration(
            color: FlowColors.darkCardElevated,
            borderRadius: FlowRadii.cardRadius,
            border: Border.all(color: FlowColors.darkBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: FlowColors.textMuted, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.reason,
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondary),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  widget.onAction();
                  _dismiss();
                },
                child: Text(
                  widget.actionLabel,
                  style: FlowTypography.labelSmall(color: accent).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _dismiss,
                child: const Icon(Icons.close_rounded, size: 16, color: FlowColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
