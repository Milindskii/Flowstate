import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../components/flow_logo.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_typography.dart';
import 'auth_screen.dart';

/// Screen 1: Splash Screen
/// Minimal animated breathing splash screen with Flowstate logo and tagline.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.04).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.repeat(reverse: true);

    // Smooth transition to auth after 2.2 seconds
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const AuthScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.darkBackground,
      body: Stack(
        children: [
          // Background ambient subtle glow circles (Cyan and Mint, no purple)
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FlowColors.cyan.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FlowColors.mint.withOpacity(0.05),
              ),
            ),
          ),

          // Center Branding
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),

                  // Floating breathing logo
                  AnimatedBuilder(
                    animation: _scaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: child,
                      );
                    },
                    child: const FlowLogo(size: 88),
                  ),
                  const SizedBox(height: 32),

                  // Brand name
                  Text(
                    'FLOWSTATE',
                    style: FlowTypography.displayMedium().copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tagline
                  Text(
                    'Work with your rhythm.',
                    style: FlowTypography.titleMedium(color: FlowColors.textSecondary),
                  ),

                  const Spacer(flex: 3),

                  // Syncing indicator
                  CircularPercentIndicator(
                    radius: 12.0,
                    lineWidth: 2.5,
                    percent: 0.75,
                    animation: true,
                    progressColor: FlowColors.cyan,
                    backgroundColor: FlowColors.darkBorder,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Syncing your energy...',
                    style: FlowTypography.labelSmall(color: FlowColors.textMuted),
                  ),

                  const Spacer(flex: 1),

                  // Bottom Local Privacy Badge
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            size: 14,
                            color: FlowColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Private & Local',
                            style: FlowTypography.labelSmall(color: FlowColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
