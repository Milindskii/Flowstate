import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/flow_provider.dart';
import '../providers/theme_provider.dart';
import '../services/focus_soundscape_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';
import 'flow_screen.dart';
import 'auth_screen.dart';
import 'legal/legal_hub_screen.dart';
import '../models/ai_plan_models.dart';
import '../services/ai_plan_service.dart';
import 'pro_subscription_screen.dart';

/// Screen 10: Profile & Settings Screen with Accent, Density, and Theme Mode Selector
class ProfileSettingsTab extends StatelessWidget {
  const ProfileSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final accent = themeProvider.resolveAccent(context);
    final user = state.currentUser;
    final pageMargin = FlowSpacing.pageMargin(context);

    final cardBg = FlowColors.surface(context);
    final borderColor = FlowColors.border(context);
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);
    final textMuted = FlowColors.textMutedOf(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: pageMargin, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Settings & Profile',
                style: FlowTypography.headlineMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),

              // Dynamic Profile Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent,
                      ),
                      child: Center(
                        child: Text(
                          state.greetingName.isNotEmpty ? state.greetingName[0].toUpperCase() : 'U',
                          style: FlowTypography.headlineMedium(color: FlowColors.textInverse).copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? 'Flowstate Explorer',
                            style: FlowTypography.titleMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.email ?? 'personal@flowstate.local',
                            style: FlowTypography.bodyMedium(color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Go Pro Section
              const _GoProProfileSection(),
              const SizedBox(height: 24),

              // Appearance & Theme Preferences
              _buildSectionTitle('Theme & Appearance', textPrimary),
              const SizedBox(height: 12),

              // Theme Mode Selector (Light / Dark / System)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.brightness_medium_outlined, color: accent, size: 20),
                        const SizedBox(width: 10),
                        Text('Theme Mode', style: FlowTypography.bodyLarge(color: textPrimary).copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Select Light (pure white default), Dark, or device System.',
                      style: FlowTypography.labelSmall(color: textSecondary),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _buildThemeOption(
                          context,
                          label: 'Light',
                          icon: Icons.wb_sunny_outlined,
                          isSelected: themeProvider.themeMode == ThemeMode.light,
                          onTap: () {
                            FlowHaptics.selection();
                            themeProvider.setThemeMode(ThemeMode.light);
                          },
                          accent: accent,
                        ),
                        _buildThemeOption(
                          context,
                          label: 'Dark',
                          icon: Icons.nightlight_round_outlined,
                          isSelected: themeProvider.themeMode == ThemeMode.dark,
                          onTap: () {
                            FlowHaptics.selection();
                            themeProvider.setThemeMode(ThemeMode.dark);
                          },
                          accent: accent,
                        ),
                        _buildThemeOption(
                          context,
                          label: 'System',
                          icon: Icons.brightness_auto_outlined,
                          isSelected: themeProvider.themeMode == ThemeMode.system,
                          onTap: () {
                            FlowHaptics.selection();
                            themeProvider.setThemeMode(ThemeMode.system);
                          },
                          accent: accent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Accent Color Customization
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.palette_outlined, color: accent, size: 20),
                        const SizedBox(width: 10),
                        Text('Accent Color', style: FlowTypography.bodyLarge(color: textPrimary).copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Personalize your CTA, navigation, and focus highlights.',
                      style: FlowTypography.labelSmall(color: textSecondary),
                    ),
                    const SizedBox(height: 16),
                    // Accent Color Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: FlowAccent.values.map((option) {
                        final isSelected = themeProvider.selectedAccent == option;
                        return GestureDetector(
                          onTap: () {
                            FlowHaptics.selection();
                            themeProvider.setAccent(option);
                          },
                          child: Column(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: option.color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.transparent,
                                    width: 2.5,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: option.color.withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check_rounded, size: 20, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                option.label,
                                style: FlowTypography.labelSmall(
                                  color: isSelected ? textPrimary : textMuted,
                                ).copyWith(
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              // Visual Density Selector
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.view_agenda_outlined, color: accent, size: 20),
                        const SizedBox(width: 10),
                        Text('Visual Density', style: FlowTypography.bodyLarge(color: textPrimary).copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Control timeline spacing and information richness.',
                      style: FlowTypography.labelSmall(color: textSecondary),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: DensityMode.values.map((mode) {
                        final isSelected = themeProvider.densityMode == mode;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              FlowHaptics.selection();
                              themeProvider.setDensityMode(mode);
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? accent.withValues(alpha: 0.15) : FlowColors.surfaceContainer(context),
                                borderRadius: FlowRadii.inputRadius,
                                border: Border.all(
                                  color: isSelected ? accent : borderColor,
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      mode.label,
                                      maxLines: 1,
                                      style: FlowTypography.labelSmall(
                                        color: isSelected ? textPrimary : textMuted,
                                      ).copyWith(
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Flow & Progression Section
              _buildSectionTitle('Flow & Progression', textPrimary),
              const SizedBox(height: 12),
              Builder(
                builder: (ctx) {
                  FlowProvider? flowProvider;
                  try {
                    flowProvider = Provider.of<FlowProvider>(ctx);
                  } catch (_) {}
                  final companion = flowProvider?.companion;
                  final soundService = FocusSoundscapeService();

                  return Column(
                    children: [
                      _buildSettingTile(
                        context: context,
                        icon: Icons.pets_rounded,
                        title: 'Noya & Companion',
                        subtitle: companion != null
                            ? '${companion.stage} · Level ${companion.level} · Open Flow Hub'
                            : 'View living fox companion & progression',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const FlowScreen()),
                          );
                        },
                        accent: accent,
                      ),
                      _buildSettingTile(
                        context: context,
                        icon: Icons.waves_rounded,
                        title: 'Focus Sounds',
                        subtitle: 'Ambient focus soundscapes (${soundService.currentTrack.label})',
                        onTap: () => _showSoundscapeSheet(context),
                        accent: accent,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),

              // Rhythm Preferences Section
              _buildSectionTitle('Rhythm Preferences', textPrimary),
              const SizedBox(height: 12),
              _buildSettingTile(
                context: context,
                icon: Icons.bedtime_outlined,
                title: 'Sleep Schedule',
                subtitle: '${state.personalData.wakeTime} wake up • ${state.personalData.sleepHours} hrs',
                onTap: () {},
                accent: accent,
              ),
              _buildSettingTile(
                context: context,
                icon: Icons.bolt_outlined,
                title: 'Peak Focus Window',
                subtitle: '${state.personalData.focusPeak} (calibrated automatically)',
                onTap: () {},
                accent: accent,
              ),
              _buildSettingTile(
                context: context,
                icon: Icons.trending_down_outlined,
                title: 'Energy Dip Time',
                subtitle: '${state.personalData.energyDipTime} (protected light work only)',
                onTap: () {},
                accent: accent,
              ),
              const SizedBox(height: 20),

              // Honest Transparency Notice
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: FlowColors.surfaceContainer(context),
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shield_outlined, color: FlowColors.positive, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Your data belongs to you.',
                          style: FlowTypography.titleMedium(color: FlowColors.positive).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Flowstate is a non-medical productivity layer. We never display medical claims or cortisol biomarkers. Your focus and energy rhythm are evaluated strictly for optimal cognitive focus scheduling.',
                      style: FlowTypography.bodyMedium(color: textSecondary),
                    ),
                  ],
                ),
              ),
              // Legal & Privacy Compliance Section
              _buildSectionTitle('Legal, Privacy & Compliance', textPrimary),
              const SizedBox(height: 12),
              _buildSettingTile(
                context: context,
                icon: Icons.shield_outlined,
                title: 'Legal & Privacy Hub',
                subtitle: 'Privacy Policy, Terms, DPDP & Data Rights, Export & Deletion',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LegalHubScreen()),
                  );
                },
                accent: accent,
              ),
              const SizedBox(height: 20),

              // Account & Session Section
              _buildSectionTitle('Account & Security', textPrimary),
              const SizedBox(height: 12),
              _buildSettingTile(
                context: context,
                icon: Icons.logout_rounded,
                title: 'Sign Out',
                subtitle: state.currentUser?.email ?? 'End active session',
                onTap: () async {
                  final shouldSignOut = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: cardBg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.cardLarge)),
                      title: Text('Sign Out?', style: FlowTypography.titleMedium(color: textPrimary)),
                      content: Text('Your scheduled tasks and rhythm will be securely saved in your account.', style: FlowTypography.bodyMedium(color: textSecondary)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('Cancel', style: FlowTypography.labelMedium(color: textMuted)),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: FlowColors.error),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  );
                  if (shouldSignOut == true && context.mounted) {
                    await state.logout();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const AuthScreen()),
                        (route) => false,
                      );
                    }
                  }
                },
                accent: FlowColors.error,
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required Color accent,
  }) {
    final borderColor = FlowColors.border(context);
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textMuted = FlowColors.textMutedOf(context);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? accent.withValues(alpha: 0.15) : FlowColors.surfaceContainer(context),
            borderRadius: FlowRadii.inputRadius,
            border: Border.all(
              color: isSelected ? accent : borderColor,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? accent : textMuted,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: FlowTypography.labelSmall(
                  color: isSelected ? textPrimary : textMuted,
                ).copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color textColor) {
    return Text(
      title,
      style: FlowTypography.titleMedium(color: textColor).copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _buildSettingTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
    required Color accent,
  }) {
    final cardBg = FlowColors.surface(context);
    final borderColor = FlowColors.border(context);
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textMuted = FlowColors.textMutedOf(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: FlowRadii.cardRadius,
          onTap: () {
            FlowHaptics.lightTap();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: accent, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: FlowTypography.bodyLarge(color: textPrimary).copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: FlowTypography.bodyMedium(color: textMuted),
                      ),
                    ],
                  ),
                ),
                trailing ?? Icon(Icons.chevron_right_rounded, color: textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSoundscapeSheet(BuildContext context) {
    FlowHaptics.lightTap();
    final soundService = FocusSoundscapeService();
    showModalBottomSheet(
      context: context,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: FlowSpacing.pageMargin(context),
                  vertical: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 16),
                    Text(
                      'Focus Soundscapes',
                      style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select calm background audio for deep focus rituals.',
                      style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: SoundscapeTrack.values.map((track) {
                        final isSelected = soundService.currentTrack == track;
                        return ChoiceChip(
                          label: Text(track.label),
                          selected: isSelected,
                          selectedColor: FlowColors.mint.withValues(alpha: 0.25),
                          side: BorderSide(
                            color: isSelected ? FlowColors.mint : FlowColors.border(context),
                          ),
                          onSelected: (_) {
                            soundService.selectTrack(track);
                            setModalState(() {});
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(Icons.volume_down_rounded, color: FlowColors.textSecondaryOf(context), size: 20),
                        Expanded(
                          child: Slider(
                            value: soundService.volume,
                            activeColor: FlowColors.mint,
                            onChanged: (val) {
                              soundService.setVolume(val);
                              setModalState(() {});
                            },
                          ),
                        ),
                        Icon(Icons.volume_up_rounded, color: FlowColors.textSecondaryOf(context), size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GoProProfileSection extends StatefulWidget {
  const _GoProProfileSection();

  @override
  State<_GoProProfileSection> createState() => _GoProProfileSectionState();
}

class _GoProProfileSectionState extends State<_GoProProfileSection> {
  SubscriptionStatus? _status;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    try {
      final state = Provider.of<AppStateProvider>(context, listen: false);
      final aiService = AIPlanService(api: state.apiService);
      final status = await aiService.getSubscriptionStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = const SubscriptionStatus(isPro: false, subscriptionTier: 'free', status: 'inactive');
          _isLoading = false;
        });
      }
    }
  }

  void _openProScreen() async {
    FlowHaptics.lightTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProSubscriptionScreen()),
    );
    _fetchStatus();
  }

  void _manageSubscription() {
    FlowHaptics.selection();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlowColors.darkCard,
        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.cardRadius),
        title: Text('Manage Subscription', style: FlowTypography.titleMedium()),
        content: Text(
          'Your Flowstate Pro subscription is managed securely through Google Play. You can modify, upgrade, or cancel your subscription at any time via the Google Play Store app.',
          style: FlowTypography.bodySmall(color: FlowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Got it', style: FlowTypography.labelMedium(color: FlowColors.accentCyan)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final accent = themeProvider.resolveAccent(context);
    final cardBg = FlowColors.surface(context);
    final borderColor = FlowColors.border(context);
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);

    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: FlowRadii.cardRadius,
          border: Border.all(color: borderColor),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final isPro = _status?.isPro ?? false;

    if (isPro) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: FlowRadii.cardRadius,
          border: Border.all(color: FlowColors.accentMint.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: FlowColors.accentMint.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.star_rounded, color: FlowColors.accentMint, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'FLOWSTATE PRO',
                      style: FlowTypography.labelLarge(color: FlowColors.accentMint)
                          .copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: FlowColors.accentMint.withValues(alpha: 0.12),
                    borderRadius: FlowRadii.pillRadius,
                  ),
                  child: Text(
                    'Active',
                    style: FlowTypography.labelSmall(color: FlowColors.accentMint)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Your plan is active.',
              style: FlowTypography.titleSmall(color: textPrimary).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Plan: ${_status?.subscriptionTier.toUpperCase() ?? 'PRO'} · Google Play Subscription',
              style: FlowTypography.bodySmall(color: textSecondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton(
                onPressed: _manageSubscription,
                style: OutlinedButton.styleFrom(
                  foregroundColor: textPrimary,
                  side: BorderSide(color: borderColor),
                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                ),
                child: Text('Manage Subscription', style: FlowTypography.labelMedium(color: textPrimary)),
              ),
            ),
          ],
        ),
      );
    }

    // Free User Card
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.bolt_rounded, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'GO PRO',
                style: FlowTypography.labelLarge(color: accent)
                    .copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'More planning power for your Flow.',
            style: FlowTypography.titleSmall(color: textPrimary).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Unlock generous AI Brain Dump planning, advanced personalization, and more flexibility.',
            style: FlowTypography.bodySmall(color: textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              key: const Key('explore_pro_button'),
              onPressed: _openProScreen,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: FlowColors.textInverse,
                elevation: 0,
                shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
              ),
              child: Text(
                'Explore Pro',
                style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

