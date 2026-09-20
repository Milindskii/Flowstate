import 'package:flutter/material.dart';
import '../components/flow_logo.dart';
import '../components/primary_button.dart';
import '../components/secondary_button.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_motion.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'onboarding_flow_screen.dart'; // New 7-step aha-moment flow
import 'main_shell.dart';

/// Screen 2: Login & Sign Up
/// Beautiful onboarding screen with flowing energy rhythm graphic.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoginMode = false;

  void _navigateToOnboarding() {
    Navigator.of(context).push(
      FlowPageRoute.fadeUp(
        builder: (_) => const OnboardingFlowScreen(),
        duration: const Duration(milliseconds: 280),
      ),
    );
  }

  void _navigateToDashboard() {
    Navigator.of(context).pushReplacement(
      FlowPageRoute.fade(
        builder: (_) => const MainShell(),
        duration: const Duration(milliseconds: 220),
      ),
    );
  }

  void _showEmailSheet() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool sheetIsLogin = _isLoginMode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: FlowColors.border(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) {
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: Offset(sheetIsLogin ? 0.05 : -0.05, 0),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(sheetIsLogin),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            sheetIsLogin ? 'Welcome back' : 'Create your account',
                            style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            sheetIsLogin
                                ? 'Sign in to access your energy rhythm and daily plan.'
                                : 'Enter your email to sync your rhythm preferences.',
                            style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)),
                    decoration: InputDecoration(
                      hintText: 'name@domain.com',
                      prefixIcon: Icon(Icons.email_outlined, color: FlowColors.textMutedOf(context)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline_rounded, color: FlowColors.textMutedOf(context)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: sheetIsLogin ? 'Log In' : 'Get Started',
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (sheetIsLogin) {
                        _navigateToDashboard();
                      } else {
                        _navigateToOnboarding();
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        setSheetState(() {
                          sheetIsLogin = !sheetIsLogin;
                        });
                        setState(() {
                          _isLoginMode = sheetIsLogin;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          sheetIsLogin
                              ? "Don't have an account? Sign up"
                              : 'Already have an account? Log in',
                          style: FlowTypography.labelMedium(color: FlowColors.cyanLight).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final headerHeight = screenHeight > 300 ? (screenHeight * 0.36).clamp(180.0, 280.0) : 200.0;

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight > 0 ? screenHeight : 600,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  // Top Section: Abstract flowing energy waves
                  Container(
                    height: headerHeight,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFE0F2FE),
                          Color(0xFFFFFFFF),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Smooth layered ambient energy circles (Cyan and Mint, no purple)
                        Positioned(
                          top: 40,
                          left: -30,
                          child: Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: FlowColors.cyan.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 20,
                          right: -20,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: FlowColors.mint.withValues(alpha: 0.08),
                            ),
                          ),
                        ),

                        // Center Logo Emblem
                        Positioned.fill(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const FlowLogo(size: 76),
                                    const SizedBox(height: 16),
                                    Text(
                                      'FLOWSTATE',
                                      style: FlowTypography.titleMedium(color: FlowColors.textPrimaryLight).copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: 32,
                                      height: 3,
                                      decoration: const BoxDecoration(
                                        color: FlowColors.cyan,
                                        borderRadius: FlowRadii.pillRadius,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Section: Messaging & Authentication
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 24),

                          // Headline
                          Text(
                            'Plan around your energy.',
                            style: FlowTypography.displayMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Supporting description
                          Text(
                            'Flowstate learns how you work best and helps you put the right task at the right time.',
                            style: FlowTypography.bodyLarge(color: FlowColors.textSecondaryOf(context)),
                          ),

                          const SizedBox(height: 32),

                          // Primary Button: Continue with Google
                          PrimaryButton(
                            label: 'Continue with Google',
                            icon: const Icon(Icons.g_mobiledata_rounded, size: 28, color: FlowColors.textInverse),
                            onPressed: _navigateToOnboarding,
                          ),
                          const SizedBox(height: 14),

                          // Secondary Button: Continue with Email
                          SecondaryButton(
                            label: 'Continue with Email',
                            icon: Icon(Icons.mail_outline_rounded, size: 20, color: FlowColors.textPrimaryOf(context)),
                            onPressed: _showEmailSheet,
                          ),

                          const SizedBox(height: 20),

                          // Login / Sign Up Toggle
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isLoginMode ? "New to Flowstate?" : "Already have an account?",
                                style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isLoginMode = !_isLoginMode;
                                  });
                                },
                                child: Text(
                                  _isLoginMode ? 'Create account' : 'Log in',
                                  style: FlowTypography.labelMedium(color: FlowColors.cyanLight).copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
