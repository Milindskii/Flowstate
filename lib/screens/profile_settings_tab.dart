import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Screen 10: Profile & Settings Screen
class ProfileSettingsTab extends StatelessWidget {
  const ProfileSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: FlowColors.darkBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Settings & Profile',
                style: FlowTypography.headlineMedium().copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),

              // Profile Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: FlowColors.darkCard,
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: FlowColors.darkBorder, width: 1.0),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: FlowColors.primaryGradient,
                      ),
                      child: Center(
                        child: Text(
                          'A',
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
                            'Alex Chen',
                            style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'alex.chen@flowstate.local',
                            style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Rhythm Preferences Section
              _buildSectionTitle('Rhythm Preferences'),
              const SizedBox(height: 12),
              _buildSettingTile(
                icon: Icons.bedtime_outlined,
                title: 'Sleep Schedule',
                subtitle: '${state.personalData.wakeTime} wake up • ${state.personalData.sleepHours} hrs',
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.bolt_rounded,
                title: 'Energy Peak Timing',
                subtitle: state.personalData.focusPeak,
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.trending_down_rounded,
                title: 'Energy Dip Window',
                subtitle: state.personalData.energyDipTime,
                onTap: () {},
              ),
              const SizedBox(height: 24),

              // Integrations
              _buildSectionTitle('Integrations'),
              const SizedBox(height: 12),
              _buildSettingTile(
                icon: Icons.calendar_today_rounded,
                title: 'Google Calendar',
                subtitle: 'Connected (Syncs focus blocks)',
                trailing: const Icon(Icons.check_circle_rounded, color: FlowColors.mintLight, size: 20),
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.favorite_outline_rounded,
                title: 'Health Connect / Apple HealthKit',
                subtitle: 'Connected (Sleep & activity hours only)',
                trailing: const Icon(Icons.check_circle_rounded, color: FlowColors.mintLight, size: 20),
                onTap: () {},
              ),
              const SizedBox(height: 24),

              // Appearance & Notifications
              _buildSectionTitle('Preferences'),
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: FlowColors.darkCard,
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: FlowColors.darkBorder, width: 1.0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.dark_mode_outlined, color: FlowColors.cyanLight, size: 22),
                        const SizedBox(width: 14),
                        Text('Dark-First Theme', style: FlowTypography.bodyLarge()),
                      ],
                    ),
                    Switch.adaptive(
                      value: themeProvider.isDarkMode,
                      activeColor: FlowColors.cyanLight,
                      onChanged: (val) => themeProvider.toggleTheme(),
                    ),
                  ],
                ),
              ),
              _buildSettingTile(
                icon: Icons.notifications_none_rounded,
                title: 'Gentle Focus Notifications',
                subtitle: 'Notify 10 min before peak focus window',
                onTap: () {},
              ),
              const SizedBox(height: 24),

              // Clear Trustworthy Privacy Section
              _buildSectionTitle('Data & Privacy'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: FlowColors.darkCard,
                  borderRadius: FlowRadii.cardLargeRadius,
                  border: Border.all(color: FlowColors.darkBorder, width: 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shield_outlined, color: FlowColors.mintLight, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Your data belongs to you.',
                          style: FlowTypography.titleMedium(color: FlowColors.mintLight).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Flowstate works locally on your device. Your sleep and energy patterns are processed privately without transmitting personal biomarkers or medical metrics. We never sell your data.',
                      style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.darkBorder, width: 1.0),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: FlowRadii.cardRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: FlowColors.cyanLight, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: FlowTypography.bodyLarge().copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: FlowTypography.bodyMedium(color: FlowColors.textMuted),
                      ),
                    ],
                  ),
                ),
                trailing ?? const Icon(Icons.chevron_right_rounded, color: FlowColors.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
