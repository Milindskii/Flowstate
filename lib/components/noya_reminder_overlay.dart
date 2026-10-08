import 'dart:async';
import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../services/smart_reminder_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'noya_companion_view.dart';

/// Small, polished Noya companion popup/overlay displayed when a scheduled task
/// becomes due while the user is inside the app.
///
/// Designed as a contextual companion notification, NOT a full-screen blocking modal.
class NoyaReminderOverlay extends StatefulWidget {
  final SmartReminderService? service;

  const NoyaReminderOverlay({super.key, this.service});

  @override
  State<NoyaReminderOverlay> createState() => _NoyaReminderOverlayState();
}

class _NoyaReminderOverlayState extends State<NoyaReminderOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _autoDismissTimer;
  TaskItem? _displayedTask;

  SmartReminderService get _service => widget.service ?? SmartReminderService.instance;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 240),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInQuad,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _service.currentInAppReminder.addListener(_onReminderChanged);
    _onReminderChanged();
  }

  @override
  void dispose() {
    _service.currentInAppReminder.removeListener(_onReminderChanged);
    _autoDismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _onReminderChanged() {
    final task = _service.currentInAppReminder.value;
    if (task != null) {
      setState(() => _displayedTask = task);
      _animController.forward();
      _autoDismissTimer?.cancel();
      _autoDismissTimer = Timer(const Duration(seconds: 14), () {
        if (mounted) {
          _dismiss();
        }
      });
    } else if (_displayedTask != null) {
      _animController.reverse().then((_) {
        if (mounted) {
          setState(() => _displayedTask = null);
        }
      });
    }
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    _service.dismissInAppReminder();
  }

  @override
  Widget build(BuildContext context) {
    if (_displayedTask == null) {
      return const SizedBox.shrink();
    }

    final task = _displayedTask!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IgnorePointer(
      ignoring: false,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Material(
              color: Colors.transparent,
              child: Container(
                key: const Key('noya_reminder_overlay'),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E232A) : Colors.white,
                  borderRadius: BorderRadius.circular(FlowRadii.card),
                  border: Border.all(
                    color: FlowColors.mint.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  children: [
                    const NoyaCompanionView(
                      state: NoyaState.encouraging,
                      size: 42,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '\u{1F98A} Noya',
                                style: FlowTypography.labelMedium(
                                  color: const Color(0xFFFF7A00),
                                ).copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Time for ${task.title}',
                            style: FlowTypography.bodyMedium(
                              color: FlowColors.textPrimaryOf(context),
                            ).copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Ready to start?',
                            style: FlowTypography.bodySmall(
                              color: FlowColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('noya_reminder_start_button'),
                      style: FilledButton.styleFrom(
                        backgroundColor: FlowColors.mint,
                        foregroundColor: FlowColors.textInverse,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(FlowRadii.button),
                        ),
                      ),
                      onPressed: () {
                        _service.handleInAppAction(context, task);
                      },
                      child: const Text(
                        'Start',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const Key('noya_reminder_dismiss_button'),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: FlowColors.textSecondaryOf(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: _dismiss,
                      tooltip: 'Dismiss',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
