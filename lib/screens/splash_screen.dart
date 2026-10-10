import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/noya_companion_view.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_typography.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'main_shell.dart';
import 'onboarding_flow_screen.dart';

/// Screen 1: Splash Screen
/// Minimal animated breathing splash screen with Flowstate logo and tagline.
/// Restores persistent Supabase session and routes cleanly to appropriate screen.
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

    _checkInitialAuth();
  }

  Future<void> _checkInitialAuth() async {
    final startTime = DateTime.now();
    final appState = Provider.of<AppStateProvider>(context, listen: false);

    // Attempt restoring existing session from Supabase
    AuthUser? user = await appState.authService.restoreSession();
    if (user != null) {
      // Navigate once identity + onboarding are known; tasks / Today / Calendar keep loading in parallel
      // behind the first screen (its own loading state), instead of holding the splash for every request.
      await appState.onUserAuthenticated(user, awaitData: false);
    }

    // A short brand moment, not a wait: the splash used to hold for 1.6 s on top of the network.
    final elapsed = DateTime.now().difference(startTime);
    final remaining = const Duration(milliseconds: 900) - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (!mounted) return;

    // Double-check session restoration in case async storage completed during splash animation
    if (user == null) {
      user = await appState.authService.restoreSession();
      if (user != null) {
        await appState.onUserAuthenticated(user, awaitData: false);
      }
    }

    if (!mounted) return;

    Widget targetScreen;
    if (user != null) {
      if (appState.onboardingComplete) {
        targetScreen = const MainShell();
      } else {
        targetScreen = const OnboardingFlowScreen();
      }
    } else {
      targetScreen = const AuthScreen();
    }

    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => targetScreen,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FlowColors.isDark(context);

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      body: Stack(
        children: [
          // Background ambient subtle glow cards (Cyan and Mint, no purple)
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(64),
                color: FlowColors.cyan.withValues(alpha: isDark ? 0.08 : 0.04),
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
                borderRadius: BorderRadius.circular(64),
                color: FlowColors.mint.withValues(alpha: isDark ? 0.06 : 0.03),
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
                    child: const NoyaCompanionView(
                      state: NoyaState.idle,
                      size: 96,
                      cacheWidth: 512,
                      showAmbientGlow: true,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Brand name
                  Text(
                    'FLOWSTATE',
                    style: FlowTypography.displayMedium(
                      color: FlowColors.textPrimaryOf(context),
                    ).copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tagline
                  Text(
                    'Work with your rhythm.',
                    style: FlowTypography.titleMedium(
                      color: FlowColors.textSecondaryOf(context),
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Syncing indicator
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: 0.75,
                      strokeWidth: 2.5,
                      color: FlowColors.cyan,
                      backgroundColor: FlowColors.border(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Syncing your energy...',
                    style: FlowTypography.labelSmall(
                      color: FlowColors.textMutedOf(context),
                    ),
                  ),

                  const Spacer(flex: 1),

                  // Bottom Local Privacy Badge
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 14,
                            color: FlowColors.textMutedOf(context),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Your data stays yours',
                            style: FlowTypography.labelSmall(
                              color: FlowColors.textMutedOf(context),
                            ),
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
