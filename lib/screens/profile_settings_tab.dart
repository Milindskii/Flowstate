import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';

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
      backgroundColor: FlowColors.background(context),
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
                                child: Text(
                                  mode.label,
                                  style: FlowTypography.labelSmall(
                                    color: isSelected ? textPrimary : textMuted,
                                  ).copyWith(
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
}
