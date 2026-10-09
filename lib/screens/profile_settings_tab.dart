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
import '../components/shield_popups.dart';
import 'pro_subscription_screen.dart';

/// Screen 10: Profile & Settings Screen with Accent and Theme Mode Selector
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
                style: FlowTypography.headlineMedium(color: textPrimary)
                    .copyWith(fontWeight: FontWeight.w800),
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
                          state.greetingName.isNotEmpty
                              ? state.greetingName[0].toUpperCase()
                              : 'U',
                          style: FlowTypography.headlineMedium(
                                  color: FlowColors.textInverse)
                              .copyWith(
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
                            style:
                                FlowTypography.titleMedium(color: textPrimary)
                                    .copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.email ?? 'personal@flowstate.local',
                            style:
                                FlowTypography.bodyMedium(color: textSecondary),
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

              // Flow Shields Section
              _buildSectionTitle('Flow Shields', textPrimary),
              const SizedBox(height: 12),
              const _ProfileShieldsSection(),
              const SizedBox(height: 24),

              // Appearance: theme and accent share one card
              _buildSectionTitle('Appearance', textPrimary),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPrefLabel('Theme', textPrimary),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final entry in const [
                          (ThemeMode.light, 'Light', Icons.wb_sunny_outlined),
                          (
                            ThemeMode.dark,
                            'Dark',
                            Icons.nightlight_round_outlined
                          ),
                          (
                            ThemeMode.system,
                            'System',
                            Icons.brightness_auto_outlined
                          ),
                        ])
                          _buildThemeOption(
                            context,
                            label: entry.$2,
                            icon: entry.$3,
                            isSelected: themeProvider.themeMode == entry.$1,
                            onTap: () {
                              FlowHaptics.selection();
                              themeProvider.setThemeMode(entry.$1);
                            },
                            accent: accent,
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Divider(height: 1, color: borderColor),
                    ),
                    _buildPrefLabel('Accent color', textPrimary),
                    const SizedBox(height: 10),
                    Row(
                      children: FlowAccent.values.map((option) {
                        final isSelected =
                            themeProvider.selectedAccent == option;
                        return Expanded(
                          child: Semantics(
                            button: true,
                            selected: isSelected,
                            label: '${option.label} accent',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                FlowHaptics.selection();
                                themeProvider.setAccent(option);
                              },
                              child: SizedBox(
                                child: Column(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: option.color,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected
                                              ? textPrimary
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: isSelected
                                          ? const Icon(Icons.check_rounded,
                                              size: 20, color: Colors.white)
                                          : null,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      option.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: FlowTypography.labelSmall(
                                        color: isSelected
                                            ? textPrimary
                                            : textMuted,
                                      ).copyWith(
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
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
              const SizedBox(height: 24),

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
                            MaterialPageRoute(
                                builder: (_) => const FlowScreen()),
                          );
                        },
                        accent: accent,
                      ),
                      _buildSettingTile(
                        context: context,
                        icon: Icons.waves_rounded,
                        title: 'Focus Sounds',
                        subtitle:
                            'Ambient focus soundscapes (${soundService.currentTrack.label})',
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
                subtitle:
                    '${state.personalData.wakeTime} wake up • ${_fmtHours(state.personalData.sleepHours)} hrs',
                onTap: () => _showSleepSheet(context, state),
                accent: accent,
              ),
              _buildSettingTile(
                context: context,
                icon: Icons.bolt_outlined,
                title: 'Peak Focus Window',
                subtitle:
                    '${state.personalData.focusPeak} (calibrated automatically)',
                onTap: () => _showFocusPeakSheet(context, state),
                accent: accent,
              ),
              _buildSettingTile(
                context: context,
                icon: Icons.trending_down_outlined,
                title: 'Energy Dip Time',
                subtitle:
                    '${state.personalData.energyDipTime} (protected light work only)',
                onTap: () => _pickEnergyDip(context, state),
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
                        Icon(Icons.lock_outline_rounded,
                            color: textSecondary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your data belongs to you',
                            style: FlowTypography.bodyLarge(color: textPrimary)
                                .copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Flowstate is a non-medical productivity layer. We never display medical claims or cortisol biomarkers. Your focus and energy rhythm are evaluated strictly for optimal cognitive focus scheduling.',
                      style: FlowTypography.bodySmall(color: textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Legal & Privacy Compliance Section
              _buildSectionTitle('Legal, Privacy & Compliance', textPrimary),
              const SizedBox(height: 12),
              _buildSettingTile(
                context: context,
                icon: Icons.shield_outlined,
                title: 'Legal & Privacy Hub',
                subtitle:
                    'Privacy Policy, Terms, DPDP & Data Rights, Export & Deletion',
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
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(FlowRadii.cardLarge)),
                      title: Text('Sign Out?',
                          style:
                              FlowTypography.titleMedium(color: textPrimary)),
                      content: Text(
                          'Your scheduled tasks and rhythm will be securely saved in your account.',
                          style:
                              FlowTypography.bodyMedium(color: textSecondary)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('Cancel',
                              style:
                                  FlowTypography.labelMedium(color: textMuted)),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: FlowColors.error),
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
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          constraints: const BoxConstraints(minHeight: 56),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.15)
                : FlowColors.surfaceContainer(context),
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

  Widget _buildPrefLabel(String text, Color color) => Text(
        text,
        style: FlowTypography.bodyLarge(color: color)
            .copyWith(fontWeight: FontWeight.w600),
      );

  static String _fmtHours(double h) =>
      h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);

  /// Parses "6:45 AM" or "07:00" into a TimeOfDay (null when unparseable).
  static TimeOfDay? _parseTime(String raw) {
    final m = RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])?').firstMatch(raw);
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final mer = m.group(3)?.toLowerCase();
    if (mer == 'pm' && h < 12) h += 12;
    if (mer == 'am' && h == 12) h = 0;
    if (h > 23 || min > 59) return null;
    return TimeOfDay(hour: h, minute: min);
  }

  /// Writes back in the same style the value was stored in (12h with AM/PM, or 24h).
  static String _formatLike(String original, TimeOfDay t) {
    final mm = t.minute.toString().padLeft(2, '0');
    if (RegExp(r'[AaPp][Mm]').hasMatch(original)) {
      final h12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      return '$h12:$mm ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
    }
    return '${t.hour.toString().padLeft(2, '0')}:$mm';
  }

  Future<void> _pickEnergyDip(
      BuildContext context, AppStateProvider state) async {
    final current = state.personalData.energyDipTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(current) ?? const TimeOfDay(hour: 14, minute: 30),
      helpText: 'Energy dip time',
    );
    if (picked != null) {
      state.updatePersonalData(
        state.personalData.copyWith(
            energyDipTime:
                _formatLike(current.isEmpty ? '2:30 PM' : current, picked)),
      );
    }
  }

  void _showFocusPeakSheet(BuildContext context, AppStateProvider state) {
    const options = ['Morning', 'Afternoon', 'Evening', 'Varies'];
    final accent = Provider.of<ThemeProvider>(context, listen: false)
        .resolveAccent(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              FlowSpacing.pageMargin(ctx), 20, FlowSpacing.pageMargin(ctx), 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Peak focus window',
                  style: FlowTypography.titleMedium(
                      color: FlowColors.textPrimaryOf(ctx))),
              const SizedBox(height: 4),
              Text('When you do your sharpest work.',
                  style: FlowTypography.bodySmall(
                      color: FlowColors.textSecondaryOf(ctx))),
              const SizedBox(height: 12),
              for (final o in options)
                ListTile(
                  minTileHeight: 52,
                  contentPadding: EdgeInsets.zero,
                  title: Text(o,
                      style: FlowTypography.bodyLarge(
                          color: FlowColors.textPrimaryOf(ctx))),
                  trailing: state.personalData.focusPeak == o
                      ? Icon(Icons.check_rounded, color: accent)
                      : null,
                  onTap: () {
                    FlowHaptics.selection();
                    state.updatePersonalData(
                        state.personalData.copyWith(focusPeak: o));
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSleepSheet(BuildContext context, AppStateProvider state) {
    var hours = state.personalData.sleepHours.clamp(4.0, 12.0).toDouble();
    var wake = state.personalData.wakeTime;
    showModalBottomSheet(
      context: context,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(FlowSpacing.pageMargin(ctx), 20,
                FlowSpacing.pageMargin(ctx), 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sleep schedule',
                    style: FlowTypography.titleMedium(
                        color: FlowColors.textPrimaryOf(ctx))),
                const SizedBox(height: 12),
                ListTile(
                  minTileHeight: 52,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Wake up',
                      style: FlowTypography.bodyLarge(
                          color: FlowColors.textPrimaryOf(ctx))),
                  trailing: Text(wake,
                      style: FlowTypography.bodyLarge(
                          color: FlowColors.textSecondaryOf(ctx))),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: _parseTime(wake) ??
                          const TimeOfDay(hour: 7, minute: 0),
                    );
                    if (picked != null) {
                      setSheet(() => wake = _formatLike(wake, picked));
                    }
                  },
                ),
                Row(
                  children: [
                    Text('Sleep',
                        style: FlowTypography.bodyLarge(
                            color: FlowColors.textPrimaryOf(ctx))),
                    const Spacer(),
                    Text('${_fmtHours(hours)} hrs',
                        style: FlowTypography.bodyLarge(
                            color: FlowColors.textSecondaryOf(ctx))),
                  ],
                ),
                Slider(
                  value: hours,
                  min: 4,
                  max: 12,
                  divisions: 16,
                  onChanged: (v) => setSheet(() => hours = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      state.updatePersonalData(state.personalData
                          .copyWith(sleepHours: hours, wakeTime: wake));
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color textColor) {
    return Text(
      title,
      style: FlowTypography.titleMedium(color: textColor)
          .copyWith(fontWeight: FontWeight.w700),
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
                        style: FlowTypography.bodyLarge(color: textPrimary)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: FlowTypography.bodyMedium(color: textMuted),
                      ),
                    ],
                  ),
                ),
                trailing ??
                    Icon(Icons.chevron_right_rounded,
                        color: textMuted, size: 20),
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
                      style: FlowTypography.titleMedium(
                          color: FlowColors.textPrimaryOf(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select calm background audio for deep focus rituals.',
                      style: FlowTypography.bodySmall(
                          color: FlowColors.textSecondaryOf(context)),
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
                          selectedColor:
                              FlowColors.mint.withValues(alpha: 0.25),
                          side: BorderSide(
                            color: isSelected
                                ? FlowColors.mint
                                : FlowColors.border(context),
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
                        Icon(Icons.volume_down_rounded,
                            color: FlowColors.textSecondaryOf(context),
                            size: 20),
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
                        Icon(Icons.volume_up_rounded,
                            color: FlowColors.textSecondaryOf(context),
                            size: 20),
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
          _status = const SubscriptionStatus(
              isPro: false, subscriptionTier: 'free', status: 'inactive');
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
        backgroundColor: FlowColors.surface(context),
        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.cardRadius),
        title: Text('Manage Subscription', style: FlowTypography.titleMedium()),
        content: Text(
          'Your Flowstate Pro subscription is managed securely through Google Play. You can modify, upgrade, or cancel your subscription at any time via the Google Play Store app.',
          style: FlowTypography.bodySmall(
              color: FlowColors.textSecondaryOf(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Got it',
                style:
                    FlowTypography.labelMedium(color: FlowColors.accentCyan)),
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
          border: Border.all(
              color: FlowColors.accentMint.withValues(alpha: 0.4), width: 1.5),
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
                      child: const Icon(Icons.star_rounded,
                          color: FlowColors.accentMint, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'FLOWSTATE PRO',
                      style: FlowTypography.labelLarge(
                              color: FlowColors.accentMint)
                          .copyWith(
                              fontWeight: FontWeight.w800, letterSpacing: 0.5),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: FlowColors.accentMint.withValues(alpha: 0.12),
                    borderRadius: FlowRadii.pillRadius,
                  ),
                  child: Text(
                    'Active',
                    style:
                        FlowTypography.labelSmall(color: FlowColors.accentMint)
                            .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Your plan is active.',
              style: FlowTypography.titleSmall(color: textPrimary)
                  .copyWith(fontWeight: FontWeight.w700),
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
                  shape: const RoundedRectangleBorder(
                      borderRadius: FlowRadii.buttonRadius),
                ),
                child: Text('Manage Subscription',
                    style: FlowTypography.labelMedium(color: textPrimary)),
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
            style: FlowTypography.titleSmall(color: textPrimary)
                .copyWith(fontWeight: FontWeight.w700),
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
                shape: const RoundedRectangleBorder(
                    borderRadius: FlowRadii.buttonRadius),
              ),
              child: Text(
                'Explore Pro',
                style: FlowTypography.labelLarge(color: FlowColors.textInverse)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileShieldsSection extends StatelessWidget {
  const _ProfileShieldsSection();

  @override
  Widget build(BuildContext context) {
    FlowProvider? flow;
    try {
      flow = Provider.of<FlowProvider>(context);
    } catch (_) {}

    final cardBg = FlowColors.surface(context);
    final borderColor = FlowColors.border(context);
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);
    final balance = flow?.shieldBalance ?? 0;

    return Container(
      key: const Key('profile_shields_section'),
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: FlowColors.accentCyan.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: FlowColors.accentCyan,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$balance ${balance == 1 ? 'Shield' : 'Shields'} Available',
                      style: FlowTypography.titleSmall(color: textPrimary).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Powers AI Replan and streak protection',
                      style: FlowTypography.bodySmall(color: textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              key: const Key('profile_get_shields_button'),
              onPressed: () {
                FlowHaptics.lightTap();
                ShieldWalletPopup.show(context);
              },
              icon: const Icon(Icons.add_moderator_outlined, size: 18),
              label: const Text('Get More Shields', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.accentCyan,
                foregroundColor: FlowColors.textInverse,
                shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

