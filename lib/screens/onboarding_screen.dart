import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/primary_button.dart';
import '../components/progress_header.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'main_shell.dart';

/// Screen 3: 5-step Onboarding Experience
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 1;
  static const int _totalSteps = 5;

  // Selected values
  String _wakeTime = '6:30 AM - 7:30 AM';
  String _focusPeak = 'Morning';
  String _energyDip = 'Midday slump (1:00 PM - 2:30 PM)';
  String _sleepDuration = '7 - 8 hours';
  String _primaryGoal = 'College';

  void _nextStep() {
    if (_currentStep < _totalSteps) {
      setState(() {
        _currentStep++;
      });
    } else {
      _finishOnboarding();
    }
  }

  void _prevStep() {
    if (_currentStep > 1) {
      setState(() {
        _currentStep--;
      });
    }
  }

  void _finishOnboarding() {
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final current = provider.personalData;

    double sleepHours = 7.5;
    if (_sleepDuration.contains('< 6')) sleepHours = 5.5;
    if (_sleepDuration.contains('6 - 7')) sleepHours = 6.5;
    if (_sleepDuration.contains('8+')) sleepHours = 8.5;

    provider.updatePersonalData(
      current.copyWith(
        wakeTime: _wakeTime,
        focusPeak: _focusPeak,
        sleepHours: sleepHours,
        primaryGoal: _primaryGoal,
      ),
    );

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MainShell(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.darkBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Step Progress Header
              ProgressHeader(
                currentStep: _currentStep,
                totalSteps: _totalSteps,
                onBack: _prevStep,
              ),
              const SizedBox(height: 28),

              // Title and Subtitle based on active step
              ..._buildStepHeader(),
              const SizedBox(height: 24),

              // Options List
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: _buildStepOptions(),
                  ),
                ),
              ),

              // Sticky Bottom Actions
              Column(
                children: [
                  PrimaryButton(
                    label: _currentStep == _totalSteps ? 'Enter Flowstate' : 'Continue',
                    onPressed: _nextStep,
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _finishOnboarding,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        "I'll do this later",
                        style: FlowTypography.bodyMedium(color: FlowColors.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStepHeader() {
    String title = '';
    String subtitle = '';

    switch (_currentStep) {
      case 1:
        title = 'What time do you usually wake up?';
        subtitle = 'This helps calibrate your circadian rise time and morning focus ramp.';
        break;
      case 2:
        title = 'When do you usually feel most focused?';
        subtitle = 'This helps us align your deep work windows with your natural energy peaks.';
        break;
      case 3:
        title = 'When do you usually feel your energy dip?';
        subtitle = 'We schedule lighter tasks or recovery periods during your natural slump.';
        break;
      case 4:
        title = 'How much sleep do you usually get?';
        subtitle = 'Sleep duration is a key foundation for your daily readiness score.';
        break;
      case 5:
        title = 'What are you mainly using Flowstate for?';
        subtitle = 'Customize your default task categories and scheduling templates.';
        break;
    }

    return [
      Text(
        title,
        style: FlowTypography.headlineLarge().copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      Text(
        subtitle,
        style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
      ),
    ];
  }

  List<Widget> _buildStepOptions() {
    switch (_currentStep) {
      case 1:
        return [
          _buildOptionCard('5:30 AM - 6:30 AM', 'Early riser', _wakeTime == '5:30 AM - 6:30 AM', () {
            setState(() => _wakeTime = '5:30 AM - 6:30 AM');
          }),
          _buildOptionCard('6:30 AM - 7:30 AM', 'Standard morning rhythm', _wakeTime == '6:30 AM - 7:30 AM', () {
            setState(() => _wakeTime = '6:30 AM - 7:30 AM');
          }),
          _buildOptionCard('7:30 AM - 8:30 AM', 'Moderate start', _wakeTime == '7:30 AM - 8:30 AM', () {
            setState(() => _wakeTime = '7:30 AM - 8:30 AM');
          }),
          _buildOptionCard('8:30 AM or later', 'Late starter', _wakeTime == '8:30 AM or later', () {
            setState(() => _wakeTime = '8:30 AM or later');
          }),
        ];
      case 2:
        return [
          _buildOptionCard('Morning', "I'm sharpest right after waking up", _focusPeak == 'Morning', () {
            setState(() => _focusPeak = 'Morning');
          }),
          _buildOptionCard('Afternoon', 'I need a bit of time to warm up', _focusPeak == 'Afternoon', () {
            setState(() => _focusPeak = 'Afternoon');
          }),
          _buildOptionCard('Evening', 'My best work happens at night', _focusPeak == 'Evening', () {
            setState(() => _focusPeak = 'Evening');
          }),
          _buildOptionCard('It varies', 'My energy is unpredictable', _focusPeak == 'It varies', () {
            setState(() => _focusPeak = 'It varies');
          }),
        ];
      case 3:
        return [
          _buildOptionCard('Midday slump (1:00 PM - 2:30 PM)', 'Post-lunch dip', _energyDip.contains('Midday'), () {
            setState(() => _energyDip = 'Midday slump (1:00 PM - 2:30 PM)');
          }),
          _buildOptionCard('Late afternoon (3:30 PM - 5:00 PM)', 'Pre-evening slowdown', _energyDip.contains('Late afternoon'), () {
            setState(() => _energyDip = 'Late afternoon (3:30 PM - 5:00 PM)');
          }),
          _buildOptionCard('Evening (after dinner)', 'Wind down dip', _energyDip.contains('Evening'), () {
            setState(() => _energyDip = 'Evening (after dinner)');
          }),
          _buildOptionCard('Consistent rhythm', 'No major perceptible dip', _energyDip.contains('Consistent'), () {
            setState(() => _energyDip = 'Consistent rhythm');
          }),
        ];
      case 4:
        return [
          _buildOptionCard('Less than 6 hours', 'Usually tired in the afternoon', _sleepDuration.contains('< 6'), () {
            setState(() => _sleepDuration = '< 6 hours');
          }),
          _buildOptionCard('6 - 7 hours', 'Moderate rest', _sleepDuration.contains('6 - 7'), () {
            setState(() => _sleepDuration = '6 - 7 hours');
          }),
          _buildOptionCard('7 - 8 hours', 'Recommended restful zone', _sleepDuration.contains('7 - 8'), () {
            setState(() => _sleepDuration = '7 - 8 hours');
          }),
          _buildOptionCard('8+ hours', 'High recovery', _sleepDuration.contains('8+'), () {
            setState(() => _sleepDuration = '8+ hours');
          }),
        ];
      case 5:
        return [
          _buildOptionCard('College', 'Lectures, revisions, exams, projects', _primaryGoal == 'College', () {
            setState(() => _primaryGoal = 'College');
          }),
          _buildOptionCard('Work', 'Deep work sessions, deliverables, meetings', _primaryGoal == 'Work', () {
            setState(() => _primaryGoal = 'Work');
          }),
          _buildOptionCard('Personal projects', 'Side projects, writing, creation', _primaryGoal == 'Personal projects', () {
            setState(() => _primaryGoal = 'Personal projects');
          }),
          _buildOptionCard('Fitness & Wellness', 'Training, recovery, habits', _primaryGoal == 'Fitness', () {
            setState(() => _primaryGoal = 'Fitness');
          }),
          _buildOptionCard('General productivity', 'Daily balance and task flow', _primaryGoal == 'General productivity', () {
            setState(() => _primaryGoal = 'General productivity');
          }),
        ];
      default:
        return [];
    }
  }

  Widget _buildOptionCard(
    String title,
    String subtitle,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(
          color: isSelected ? FlowColors.cyanLight : FlowColors.darkBorder,
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: FlowColors.cyan.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: FlowRadii.cardRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                // Radio indicator
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? FlowColors.cyanLight : FlowColors.textMuted,
                      width: 2.0,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: FlowColors.primaryGradient,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                // Text Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: FlowTypography.titleMedium().copyWith(
                          fontWeight: FontWeight.w700,
                          color: isSelected ? FlowColors.textPrimary : FlowColors.textPrimary,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
