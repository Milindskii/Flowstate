import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'noya_companion_view.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_typography.dart';

/// Honest "Building Your Starting Rhythm" View
///
/// Avoids fake-scientific AI theatre.
/// Transparently steps through:
///   Reading your schedule
///   Understanding your work preferences
///   Finding your strongest starting window
///   Creating your first plan
///
/// Then reveals the Starting Rhythm Hypothesis (labeled explicitly as Starting estimate).
class RoutineBuildingView extends StatefulWidget {
  final Map<String, dynamic> userAnswers;
  final VoidCallback onComplete;

  const RoutineBuildingView({
    super.key,
    required this.userAnswers,
    required this.onComplete,
  });

  @override
  State<RoutineBuildingView> createState() => _RoutineBuildingViewState();
}

class _RoutineBuildingViewState extends State<RoutineBuildingView>
    with SingleTickerProviderStateMixin {
  int _activeStep = 0;
  bool _isBuilt = false;
  late AnimationController _circleAnimController;
  Timer? _stepTimer;

  final List<String> _steps = [
    'Reading your schedule',
    'Understanding your work preferences',
    'Finding your strongest starting window',
    'Creating your first plan',
  ];

  @override
  void initState() {
    super.initState();
    _circleAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _startHonestProgression();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _circleAnimController.stop();
    } else if (!_circleAnimController.isAnimating) {
      _circleAnimController.repeat();
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _circleAnimController.dispose();
    super.dispose();
  }

  void _startHonestProgression() {
    // Progress through each step every 600ms, then show the starting rhythm card
    _stepTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted) return;
      if (_activeStep < _steps.length - 1) {
        FlowHaptics.selection();
        setState(() {
          _activeStep++;
        });
      } else {
        timer.cancel();
        _circleAnimController.stop();
        FlowHaptics.success();
        setState(() {
          _isBuilt = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isBuilt ? _buildStartingRhythmCard() : _buildBuildingStep(),
    );
  }

  // ---------------------------------------------------------------------------
  // Step A: Calm Circular Loading & Step Progression
  // ---------------------------------------------------------------------------
  Widget _buildBuildingStep() {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth < 360 ? 16.0 : (screenWidth < 400 ? 24.0 : 32.0);

    return Center(
      key: const ValueKey('building_step'),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPad),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Subtle looping Noya animation appropriate for building rhythm
            _buildNoyaLoadingAnimation(),

            const SizedBox(height: 36),

            Text(
              'BUILDING YOUR STARTING RHYTHM',
              style: FlowTypography.labelMedium(color: const Color(0xFF64748B)).copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 28),

            // Honest Steps List
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                children: List.generate(_steps.length, (index) {
                  final isCurrent = index == _activeStep;
                  final isDone = index < _activeStep;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDone
                                ? FlowColors.cyan
                                : (isCurrent
                                    ? FlowColors.cyan.withValues(alpha: 0.2)
                                    : const Color(0xFFE2E8F0)),
                          ),
                          child: isDone
                              ? const Icon(Icons.check, size: 12, color: Colors.white)
                              : (isCurrent
                                  ? Center(
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: FlowColors.cyanDark,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    )
                                  : null),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _steps[index],
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                              color: isDone || isCurrent
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoyaLoadingAnimation() {
    NoyaState currentNoyaState;
    if (_activeStep <= 1) {
      currentNoyaState = NoyaState.thinking;
    } else if (_activeStep == 2) {
      currentNoyaState = NoyaState.idle;
    } else {
      currentNoyaState = NoyaState.encouraging;
    }

    return AnimatedBuilder(
      animation: _circleAnimController,
      builder: (context, child) {
        final t = _circleAnimController.value;
        // Subtle horizontal pacing: smooth ease back and forth (-8 to +8 px)
        final dx = math.sin(t * 2 * math.pi) * 8.0;
        // Subtle vertical walking/stepping bob (0 to -2.5 px)
        final dy = -math.sin(t * 4 * math.pi).abs() * 2.5;
        // Ground shadow breathes slightly with step
        final shadowScale = 0.93 + 0.07 * (1.0 - (dy / -2.5).clamp(0.0, 1.0));

        return SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Grounded soft oval shadow beneath Noya
              Positioned(
                bottom: 12,
                child: Transform.scale(
                  scaleX: shadowScale,
                  scaleY: shadowScale * 0.9,
                  child: Container(
                    width: 72,
                    height: 10,
                    decoration: BoxDecoration(
                      color: FlowColors.softShadow(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              // Noya pacing thoughtfully with gentle stepping
              Positioned(
                bottom: 18,
                child: Transform.translate(
                  offset: Offset(dx, dy),
                  child: NoyaCompanionView(
                    state: currentNoyaState,
                    size: 100,
                    showAmbientGlow: true,
                    semanticLabel: 'Noya structuring and building your starting rhythm',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Step B: Starting Rhythm Hypothesis (No Fake 24-Hour Curves)
  // ---------------------------------------------------------------------------
  Widget _buildStartingRhythmCard() {
    final peak = widget.userAnswers['peak_window'] as String? ?? 'morning';

    // Format peak window label
    String peakWindowDesc = '9:00 AM – 11:30 AM';
    double morningWeight = 0.90;
    double afternoonWeight = 0.55;
    double eveningWeight = 0.40;

    if (peak == 'midday') {
      peakWindowDesc = '11:30 AM – 2:00 PM';
      morningWeight = 0.65;
      afternoonWeight = 0.85;
      eveningWeight = 0.40;
    } else if (peak == 'afternoon') {
      peakWindowDesc = '2:00 PM – 5:00 PM';
      morningWeight = 0.50;
      afternoonWeight = 0.90;
      eveningWeight = 0.50;
    } else if (peak == 'evening') {
      peakWindowDesc = '6:30 PM – 9:30 PM';
      morningWeight = 0.40;
      afternoonWeight = 0.60;
      eveningWeight = 0.90;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth < 360 ? 16.0 : (screenWidth < 400 ? 20.0 : 28.0);
    final cardPad = screenWidth < 360 ? 14.0 : 20.0;

    return Padding(
      key: const ValueKey('starting_rhythm_card'),
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),

          // Gentle checkmark pill
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FlowColors.cyan.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: FlowColors.cyan, size: 24),
          ),
          const SizedBox(height: 20),

          Text(
            'Your rhythm has a starting point.',
            style: FlowTypography.displayMedium(color: const Color(0xFF0F172A)).copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "We'll refine it as you work.",
            style: FlowTypography.titleMedium(color: const Color(0xFF475569)),
          ),

          const SizedBox(height: 28),

          // Starting Rhythm Hypothesis Container
          Container(
            padding: EdgeInsets.all(cardPad),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'YOUR STARTING RHYTHM',
                        style: FlowTypography.labelSmall(color: const Color(0xFF64748B)).copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Starting estimate',
                        style: FlowTypography.labelSmall(color: const Color(0xFF475569)).copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Relative Weight Bars (Honest starting hypothesis)
                _buildHypothesisBar(
                  label: 'Morning',
                  weight: morningWeight,
                  tag: morningWeight >= 0.85 ? 'Strongest ($peakWindowDesc)' : 'Moderate',
                  isStrongest: morningWeight >= 0.85,
                ),
                const SizedBox(height: 12),
                _buildHypothesisBar(
                  label: 'Afternoon',
                  weight: afternoonWeight,
                  tag: afternoonWeight >= 0.85 ? 'Strongest ($peakWindowDesc)' : 'Lighter',
                  isStrongest: afternoonWeight >= 0.85,
                ),
                const SizedBox(height: 12),
                _buildHypothesisBar(
                  label: 'Evening',
                  weight: eveningWeight,
                  tag: eveningWeight >= 0.85 ? 'Strongest ($peakWindowDesc)' : 'Secondary',
                  isStrongest: eveningWeight >= 0.85,
                ),

                const SizedBox(height: 16),
                const Divider(color: Color(0xFFF1F5F9), height: 1),
                const SizedBox(height: 12),

                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Flowstate learns from your actual completions, not assumptions.',
                        style: FlowTypography.bodySmall(color: const Color(0xFF64748B)).copyWith(
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Spacer(flex: 3),

          // Final CTA
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () {
                FlowHaptics.lightTap();
                widget.onComplete();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                'Take me to Today',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildHypothesisBar({
    required String label,
    required double weight,
    required String tag,
    required bool isStrongest,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isStrongest ? FontWeight.w700 : FontWeight.w500,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                tag,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isStrongest ? FlowColors.cyanDark : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: weight,
            minHeight: 8,
            backgroundColor: const Color(0xFFF1F5F9),
            valueColor: AlwaysStoppedAnimation<Color>(
              isStrongest ? FlowColors.cyan : const Color(0xFFCBD5E1),
            ),
          ),
        ),
      ],
    );
  }
}
