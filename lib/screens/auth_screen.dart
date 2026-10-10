import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/flow_ambient_background.dart';
import '../components/noya_companion_view.dart';
import '../components/primary_button.dart';
import '../components/secondary_button.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_motion.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'onboarding_flow_screen.dart';
import 'main_shell.dart';
import 'legal/legal_constants.dart';
import 'legal/privacy_policy_screen.dart';
import 'legal/terms_of_service_screen.dart';
import 'legal/refund_policy_screen.dart';
import '../utils/friendly_error.dart';

/// Screen 2: Login & Sign Up
/// Calm, alive, tactile entry screen with soft ambient breathing motion.
class AuthScreen extends StatefulWidget {
  final bool returnToBuildMyDay;
  final VoidCallback? onAuthenticated;

  const AuthScreen({
    super.key,
    this.returnToBuildMyDay = false,
    this.onAuthenticated,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoginMode = false;

  void _navigateToOnboarding() {
    FlowHaptics.lightTap();
    Navigator.of(context).pushAndRemoveUntil(
      FlowPageRoute.fade(
        builder: (_) => const OnboardingFlowScreen(),
        duration: const Duration(milliseconds: 320),
      ),
      (route) => false,
    );
  }

  void _navigateToDashboard() {
    FlowHaptics.lightTap();
    Navigator.of(context).pushAndRemoveUntil(
      FlowPageRoute.fade(
        builder: (_) => const MainShell(),
        duration: const Duration(milliseconds: 320),
      ),
      (route) => false,
    );
  }

  void _finishAuthentication(AppStateProvider appState) {
    if (widget.returnToBuildMyDay) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        _navigateToDashboard();
      }
      widget.onAuthenticated?.call();
      return;
    }
    if (appState.onboardingComplete) {
      _navigateToDashboard();
    } else {
      _navigateToOnboarding();
    }
  }

  void _showEmailSheet() {
    FlowHaptics.lightTap();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool sheetIsLogin = _isLoginMode;
    bool isSubmitting = false;
    bool acceptedTermsAndAge = false;
    String? errorMessage;

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
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: FlowColors.border(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(
                      key: ValueKey(sheetIsLogin),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            sheetIsLogin ? 'Welcome back' : 'Create your account',
                            style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            sheetIsLogin
                                ? 'Sign in to access your rhythm and daily plan.'
                                : 'Enter your email to sync your rhythm preferences.',
                            style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)),
                    decoration: InputDecoration(
                      hintText: 'name@domain.com',
                      hintStyle: FlowTypography.bodyMedium(color: FlowColors.textMutedOf(context)),
                      prefixIcon: Icon(Icons.email_outlined, color: FlowColors.textMutedOf(context)),
                      filled: true,
                      fillColor: FlowColors.surfaceContainer(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: FlowColors.border(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: FlowColors.border(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: FlowColors.cyan, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      hintStyle: FlowTypography.bodyMedium(color: FlowColors.textMutedOf(context)),
                      prefixIcon: Icon(Icons.lock_outline_rounded, color: FlowColors.textMutedOf(context)),
                      filled: true,
                      fillColor: FlowColors.surfaceContainer(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: FlowColors.border(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: FlowColors.border(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: FlowColors.cyan, width: 1.5),
                      ),
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Text(
                        errorMessage!,
                        style: FlowTypography.bodySmall(color: const Color(0xFFB91C1C)),
                      ),
                    ),
                  ],
                  if (!sheetIsLogin) ...[
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: acceptedTermsAndAge,
                            activeColor: FlowColors.accentCyan,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                            onChanged: (val) {
                              setSheetState(() => acceptedTermsAndAge = val ?? false);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'I agree to the ',
                                style: FlowTypography.bodySmall(color: const Color(0xFF64748B)),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsOfServiceScreen())),
                                child: Text(
                                  'Terms of Service',
                                  style: FlowTypography.bodySmall(color: FlowColors.accentCyan).copyWith(
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              Text(
                                ' & ',
                                style: FlowTypography.bodySmall(color: const Color(0xFF64748B)),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                                child: Text(
                                  'Privacy Policy',
                                  style: FlowTypography.bodySmall(color: FlowColors.accentCyan).copyWith(
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              Text(
                                ', and confirm I am $kMinimumAge or older.',
                                style: FlowTypography.bodySmall(color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: isSubmitting
                        ? 'Processing...'
                        : (sheetIsLogin ? 'Log In' : 'Get Started'),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final email = emailController.text.trim();
                            final password = passwordController.text;
                            if (email.isEmpty || !email.contains('@')) {
                              setSheetState(() => errorMessage = 'Please enter a valid email address.');
                              return;
                            }
                            if (password.length < 6) {
                              setSheetState(() => errorMessage = 'Password must be at least 6 characters.');
                              return;
                            }
                            if (!sheetIsLogin && !acceptedTermsAndAge) {
                              setSheetState(() => errorMessage = 'Please accept the Terms and Privacy Policy and confirm you are $kMinimumAge or older.');
                              return;
                            }

                            setSheetState(() {
                              isSubmitting = true;
                              errorMessage = null;
                            });

                            try {
                              final appState = Provider.of<AppStateProvider>(context, listen: false);
                              if (sheetIsLogin) {
                                final user = await appState.authService.loginWithEmail(email, password);
                                await appState.onUserAuthenticated(user);
                                if (ctx.mounted) Navigator.pop(ctx);
                                _finishAuthentication(appState);
                              } else {
                                final user = await appState.authService.signUpWithEmail(email, password);
                                await appState.onUserAuthenticated(user);
                                try {
                                  await appState.apiService.post('/api/v1/auth/consent', body: {
                                    'terms_accepted': true,
                                    'privacy_accepted': true,
                                    'age_confirmed': true,
                                  });
                                } catch (_) {}
                                if (ctx.mounted) Navigator.pop(ctx);
                                _finishAuthentication(appState);
                              }
                            } catch (e) {
                              final msg = friendlyAuthMessage(e);
                              setSheetState(() {
                                isSubmitting = false;
                                errorMessage = msg;
                              });
                            }
                          },
                  ),

                  const SizedBox(height: 8),
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        FlowHaptics.lightTap();
                        setSheetState(() {
                          sheetIsLogin = !sheetIsLogin;
                          errorMessage = null;
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
                          style: FlowTypography.labelMedium(color: FlowColors.cyanDark).copyWith(
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

  void _enterGuestMode({bool startWithOnboarding = true}) async {
    FlowHaptics.lightTap();
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    await appState.enterGuestMode(startWithOnboarding: startWithOnboarding);
    if (startWithOnboarding) {
      _navigateToOnboarding();
    } else {
      _navigateToDashboard();
    }
  }

  void _handleGoogleSignIn() async {
    FlowHaptics.lightTap();
    await _performGoogleSignIn();
  }

  Future<void> _performGoogleSignIn() async {
    try {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      final user = await appState.authService.loginWithGoogle();
      await appState.onUserAuthenticated(user);
      if (mounted) {
        _finishAuthentication(appState);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyAuthMessage(e, fallback: "Google sign-in didn't finish. Please try again.")),
            backgroundColor: const Color(0xFFB91C1C),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      body: FlowAmbientBackground(
        visualState: OnboardingVisualState.neutral,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: screenHeight > 700 ? 36 : 16),

                    // Simple Flowstate Mark & Title
                    Center(
                      child: FlowFadeSlide(
                        duration: const Duration(milliseconds: 450),
                        translateY: 10.0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const NoyaCompanionView(
                              state: NoyaState.idle,
                              size: 64,
                              showAmbientGlow: false,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'FLOWSTATE',
                              style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: screenHeight > 700 ? 56 : 36),

                    // Headline
                    FlowFadeSlide(
                      delay: const Duration(milliseconds: 80),
                      duration: const Duration(milliseconds: 450),
                      translateY: 10.0,
                      child: Text(
                        'Plan around your energy.',
                        style: FlowTypography.displayMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Grounded Description
                    FlowFadeSlide(
                      delay: const Duration(milliseconds: 140),
                      duration: const Duration(milliseconds: 450),
                      translateY: 10.0,
                      child: Text(
                        'Flowstate learns how you work best and helps you put the right task at the right time.',
                        style: FlowTypography.bodyLarge(color: FlowColors.textSecondaryOf(context)).copyWith(
                          height: 1.45,
                        ),
                      ),
                    ),

                    SizedBox(height: screenHeight > 700 ? 44 : 28),

                    // Primary Action: Continue with Email
                    FlowFadeSlide(
                      delay: const Duration(milliseconds: 200),
                      duration: const Duration(milliseconds: 450),
                      translateY: 10.0,
                      child: PrimaryButton(
                        label: 'Continue with Email',
                        icon: const Icon(Icons.mail_outline_rounded, size: 22, color: Colors.white),
                        onPressed: _showEmailSheet,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Secondary Action: Continue with Google
                    FlowFadeSlide(
                      delay: const Duration(milliseconds: 250),
                      duration: const Duration(milliseconds: 450),
                      translateY: 10.0,
                      child: SecondaryButton(
                        label: 'Continue with Google',
                        icon: Icon(Icons.g_mobiledata_rounded, size: 28, color: FlowColors.textPrimaryOf(context)),
                        onPressed: _handleGoogleSignIn,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Instant Guest / Demo Mode
                    FlowFadeSlide(
                      delay: const Duration(milliseconds: 300),
                      duration: const Duration(milliseconds: 450),
                      translateY: 10.0,
                      child: OutlinedButton.icon(
                        onPressed: _enterGuestMode,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: FlowColors.textPrimaryOf(context),
                          side: BorderSide(color: FlowColors.border(context), width: 1.2),
                          backgroundColor: FlowColors.surface(context).withValues(alpha: 0.85),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.bolt_rounded, size: 20, color: FlowColors.cyan),
                        label: const Text(
                          'Explore as Guest (Instant Demo)',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Switch Mode Toggle
                    FlowFadeSlide(
                      delay: const Duration(milliseconds: 320),
                      duration: const Duration(milliseconds: 450),
                      translateY: 10.0,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _isLoginMode ? "New to Flowstate?" : "Already have an account?",
                            style: FlowTypography.bodyMedium(color: const Color(0xFF64748B)),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              FlowHaptics.lightTap();
                              setState(() {
                                _isLoginMode = !_isLoginMode;
                              });
                            },
                            child: Text(
                              _isLoginMode ? 'Create account' : 'Log in',
                              style: FlowTypography.labelMedium(color: FlowColors.cyanDark).copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),
                    // Legal Policy Links
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            FlowHaptics.lightTap();
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
                          },
                          child: Text('Privacy Policy', style: FlowTypography.labelSmall(color: const Color(0xFF64748B))),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('·', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                        ),
                        GestureDetector(
                          onTap: () {
                            FlowHaptics.lightTap();
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()));
                          },
                          child: Text('Terms of Service', style: FlowTypography.labelSmall(color: const Color(0xFF64748B))),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('·', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                        ),
                        GestureDetector(
                          onTap: () {
                            FlowHaptics.lightTap();
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const RefundPolicyScreen()));
                          },
                          child: Text('Refund Policy', style: FlowTypography.labelSmall(color: const Color(0xFF64748B))),
                        ),
                      ],
                    ),

                    SizedBox(height: screenHeight > 700 ? 32 : 16),
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
