import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/primary_button.dart';
import '../components/secondary_button.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Screen 7: "What Should I Do Now?"
/// Confident, single-minded focus decision screen.
class WhatShouldIDoScreen extends StatefulWidget {
  final TaskItem task;

  const WhatShouldIDoScreen({
    super.key,
    required this.task,
  });

  @override
  State<WhatShouldIDoScreen> createState() => _WhatShouldIDoScreenState();
}

class _WhatShouldIDoScreenState extends State<WhatShouldIDoScreen> {
  bool _isSessionActive = false;
  int _remainingSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.task.durationMinutes * 60;
  }

  void _startFocusSession() {
    setState(() {
      _isSessionActive = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer?.cancel();
        _completeSession();
      }
    });
  }

  void _pauseFocusSession() {
    _timer?.cancel();
    setState(() {
      _isSessionActive = false;
    });
  }

  void _completeSession() {
    _timer?.cancel();
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    provider.toggleTaskCompletion(widget.task.id);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlowColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: FlowRadii.cardRadius),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: FlowColors.mintLight),
            const SizedBox(width: 10),
            Text('Session Completed', style: FlowTypography.titleMedium()),
          ],
        ),
        content: Text(
          'Great focus block! Your performance feedback has been fed back into your personal rhythm model.',
          style: FlowTypography.bodyMedium(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text('Done', style: FlowTypography.labelLarge(color: FlowColors.cyanLight)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: FlowColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // Title
              Text(
                'What should you do now?',
                style: FlowTypography.displayMedium().copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),

              // Main Highlighted Card
              Container(
                decoration: BoxDecoration(
                  color: FlowColors.darkCard,
                  borderRadius: FlowRadii.cardLargeRadius,
                  border: Border.all(color: FlowColors.cyan.withOpacity(0.4), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: FlowColors.cyan.withOpacity(0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: FlowColors.tagDeepWorkBg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.bolt_rounded,
                            color: FlowColors.cyanLight,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            widget.task.title,
                            style: FlowTypography.headlineMedium().copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Countdown Timer / Duration
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: FlowColors.darkSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: FlowColors.darkBorder, width: 1.0),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _isSessionActive
                                ? _formatTime(_remainingSeconds)
                                : 'Estimated time: ${widget.task.durationMinutes} min',
                            style: FlowTypography.numberHero(
                              color: _isSessionActive ? FlowColors.mintLight : FlowColors.cyanLight,
                            ),
                          ),
                          if (_isSessionActive) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Focus session in progress',
                              style: FlowTypography.labelSmall(color: FlowColors.mintLight),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Why this task?
                    Text(
                      'Why this task?',
                      style: FlowTypography.labelLarge().copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    _buildReasonBullet(Icons.check_circle_outline_rounded, 'High priority & aligned with goals'),
                    _buildReasonBullet(Icons.auto_awesome_rounded, 'Matches current 9:30 AM peak focus window'),
                    _buildReasonBullet(Icons.calendar_today_rounded, widget.task.deadline),
                    _buildReasonBullet(Icons.timelapse_rounded, 'Fits your available cognitive energy slot'),
                  ],
                ),
              ),

              const Spacer(),

              // Primary Actions
              if (!_isSessionActive) ...[
                PrimaryButton(
                  label: 'Start Focus Session',
                  icon: const Icon(Icons.play_arrow_rounded, color: FlowColors.textInverse),
                  onPressed: _startFocusSession,
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Choose something else',
                  onPressed: () => Navigator.pop(context),
                ),
              ] else ...[
                PrimaryButton(
                  label: 'Complete Task & Record Feedback',
                  icon: const Icon(Icons.check_circle_rounded, color: FlowColors.textInverse),
                  onPressed: _completeSession,
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Pause Session',
                  onPressed: _pauseFocusSession,
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReasonBullet(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: FlowColors.cyanLight),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
