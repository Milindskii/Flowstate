import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/companion/companion_graphic.dart';
import '../components/companion/flow_companion_view.dart';
import '../components/flow_ambient_background.dart';
import '../components/shield_recovery_dialog.dart';
import '../models/flow_achievement.dart';
import '../models/flow_companion.dart';
import '../models/flow_daily_quest.dart';
import '../providers/flow_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';
import 'focus_ritual_screen.dart';

/// FLOWSTATE — LIVING FLOW COMPANION HUB
///
/// Mental Model:
///              🦊 NOYA
///                 │
///        ┌────────┼────────┐
///        ↓        ↓        ↓
///      FOCUS    JOURNEY   QUESTS
///        │        │        │
///        └────────┼────────┘
///                 ↓
///              PROGRESS
///                 ↓
///           CUSTOMIZATION
class FlowScreen extends StatefulWidget {
  const FlowScreen({super.key});

  @override
  State<FlowScreen> createState() => _FlowScreenState();
}

class _FlowScreenState extends State<FlowScreen> {
  int _selectedTab = 0; // 0: Journey, 1: Quests, 2: Achievements, 3: Customize
  String? _speechBubble;
  int _speechCounter = 0;

  static const _noyaPhrases = [
    'Ready when you are!',
    'Let’s build that streak together!',
    'You are in the flow zone.',
    'I am right here with you!',
    'Deep work feels good together.',
  ];

  void _handleNoyaTap(FlowProvider flow) {
    FlowHaptics.lightTap();
    setState(() {
      _speechBubble = _noyaPhrases[_speechCounter % _noyaPhrases.length];
      _speechCounter++;
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _speechBubble != null) {
        setState(() => _speechBubble = null);
      }
    });
  }

  void _showEvolutionDialog(BuildContext context, FlowProvider provider) {
    FlowHaptics.success();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlowColors.surface(context),
        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.cardLargeRadius),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFFEAB308), size: 48),
            const SizedBox(height: 16),
            Text(
              'Evolution Ready!',
              style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Noya has absorbed enough focus energy to reach the next stage of development.',
              style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final success = await provider.evolveCompanion();
                  if (context.mounted && success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Noya evolved into the ${provider.companion.stage} stage!'),
                        backgroundColor: FlowColors.mint,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEAB308),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                ),
                child: const Text('Evolve Noya', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _claimQuest(BuildContext context, FlowProvider flow, FlowDailyQuest quest) async {
    FlowHaptics.success();
    final success = await flow.claimDailyQuest(quest.id);
    if (context.mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Claimed +${quest.rewardFlow} Flow!'),
            backgroundColor: FlowColors.mint,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quest reward already claimed or unavailable.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = Provider.of<FlowProvider>(context);
    final companion = flow.companion;
    final profile = flow.profile;
    final overview = flow.overview;

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: FlowColors.textPrimaryOf(context),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          'Living Flow Hub',
          style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: FlowColors.surfaceElevated(context),
              borderRadius: BorderRadius.circular(FlowRadii.pill),
              border: Border.all(color: FlowColors.mint.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars_rounded, color: Color(0xFFEAB308), size: 16),
                const SizedBox(width: 4),
                Text(
                  '${profile.flowBalance} Flow',
                  style: FlowTypography.labelSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: FlowAmbientBackground(
        visualState: companion.isEvolutionReady
            ? OnboardingVisualState.focusActive
            : OnboardingVisualState.morningBright,
        child: RefreshIndicator(
          onRefresh: () => flow.loadOverview(),
          color: FlowColors.mint,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: FlowSpacing.pageMargin(context),
              vertical: 12.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top Quick Stats: Streak & Shields
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: FlowColors.mint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(FlowRadii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department_rounded, color: Color(0xFFF97316), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '${profile.currentStreak} Day Streak',
                            style: FlowTypography.labelMedium(color: FlowColors.mint).copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => ShieldRecoveryDialog.show(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: FlowColors.surfaceElevated(context),
                          borderRadius: BorderRadius.circular(FlowRadii.pill),
                          border: Border.all(color: FlowColors.border(context)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.shield_rounded, color: Color(0xFF0284C7), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${profile.shieldsAvailable} / 3 Shields',
                              style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 20),

              // Speech Bubble if Noya was tapped
              if (_speechBubble != null) ...[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    key: ValueKey(_speechBubble),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: FlowColors.surfaceElevated(context),
                      borderRadius: BorderRadius.circular(FlowRadii.card),
                      border: Border.all(color: FlowColors.mint.withValues(alpha: 0.4)),
                      boxShadow: [
                        BoxShadow(
                          color: FlowColors.mint.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      _speechBubble!,
                      style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],

              // Noya Interactive Scene
              FlowCompanionView(
                companion: companion,
                controller: flow.animController,
                size: 156,
                onTap: () => _handleNoyaTap(flow),
                showStageBadge: true,
                showStatusText: true,
              ),
              const SizedBox(height: 16),

              // Primary CTA: [ Focus with Noya ]
              SizedBox(
                width: 230,
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF047857),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FlowRadii.pill),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
                  label: Text(
                    'Focus with Noya',
                    style: FlowTypography.labelLarge(color: Colors.white).copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  onPressed: () {
                    FlowHaptics.lightTap();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FocusRitualScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Rhythm Intelligence Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: FlowColors.surfaceElevated(context),
                  borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
                  border: Border.all(color: FlowColors.border(context)),
                ),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/companions/fox_winking.png',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.pets_rounded, size: 20, color: Color(0xFFF97316)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        overview.rhythmAcknowledgement,
                        style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 4 Segmented Tabs: Journey | Quests | Badges | Customize
              Container(
                decoration: BoxDecoration(
                  color: FlowColors.surfaceElevated(context),
                  borderRadius: BorderRadius.circular(FlowRadii.pill),
                  border: Border.all(color: FlowColors.border(context)),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _buildHubTabItem(0, 'Journey', Icons.alt_route_rounded),
                    _buildHubTabItem(1, 'Quests', Icons.check_rounded),
                    _buildHubTabItem(2, 'Badges', Icons.emoji_events_outlined),
                    _buildHubTabItem(3, 'Customize', Icons.pets_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tab View Content
              if (_selectedTab == 0) _buildJourneyTab(context, flow, companion, overview),
              if (_selectedTab == 1) _buildQuestsTab(context, flow, overview.dailyQuests),
              if (_selectedTab == 2) _buildAchievementsTab(context, overview.achievements),
              if (_selectedTab == 3) _buildCustomizeTab(context, companion),

              const SizedBox(height: 28),

              // Personal Progress ("Me vs Myself")
              _buildPersonalRecordsCard(context, overview),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildHubTabItem(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          FlowHaptics.selection();
          setState(() => _selectedTab = index);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected ? FlowColors.mint : Colors.transparent,
            borderRadius: BorderRadius.circular(FlowRadii.pill),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: isSelected ? Colors.black : FlowColors.textSecondaryOf(context),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: FlowTypography.labelSmall(
                    color: isSelected ? Colors.black : FlowColors.textSecondaryOf(context),
                  ).copyWith(
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// TAB 0: JOURNEY
  Widget _buildJourneyTab(
    BuildContext context,
    FlowProvider flow,
    FlowCompanion companion,
    dynamic overview,
  ) {
    final progressFrac = companion.progressFraction;
    final totalBand = companion.companionXp + companion.xpToNextLevel;
    final wp = overview.weeklyProgress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Level & Evolution Progress Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: FlowColors.surfaceElevated(context),
            borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
            border: Border.all(color: FlowColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Level ${companion.level} Evolution Line',
                      style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${companion.companionXp} / $totalBand XP',
                      style: FlowTypography.labelMedium(color: FlowColors.mint).copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(FlowRadii.pill),
                child: LinearProgressIndicator(
                  value: progressFrac,
                  minHeight: 10,
                  backgroundColor: FlowColors.border(context),
                  valueColor: const AlwaysStoppedAnimation<Color>(FlowColors.mint),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                companion.isEvolutionReady
                    ? 'Evolution Ready! Noya is ready to transform.'
                    : '${companion.xpToNextLevel} XP needed to reach next stage.',
                style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
              ),
              if (companion.isEvolutionReady) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEAB308),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Evolve Noya Now', style: TextStyle(fontWeight: FontWeight.w800)),
                    onPressed: () => _showEvolutionDialog(context, flow),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Weekly Grind Progress Card ─────────────────────────────────────
        if (wp != null) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: wp.weeklyGoalHit
                  ? FlowColors.mint.withValues(alpha: 0.08)
                  : FlowColors.surfaceElevated(context),
              borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
              border: Border.all(
                color: wp.weeklyGoalHit
                    ? FlowColors.mint.withValues(alpha: 0.5)
                    : FlowColors.border(context),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'WEEKLY GRIND',
                        style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (wp.weeklyGoalHit)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: FlowColors.mint.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(FlowRadii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_fire_department_rounded,
                              size: 12,
                              color: FlowColors.mint,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'GOAL HIT',
                              style: FlowTypography.labelSmall(color: FlowColors.mint).copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        '${wp.sessionsCompleted} / ${wp.adaptiveSessionTarget} sessions',
                        style: FlowTypography.labelSmall(color: FlowColors.mint).copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(FlowRadii.pill),
                  child: LinearProgressIndicator(
                    value: wp.sessionProgressFraction,
                    minHeight: 8,
                    backgroundColor: FlowColors.border(context),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      wp.weeklyGoalHit ? FlowColors.mint : const Color(0xFF6366F1),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildWeeklyMiniStat(context, '${wp.focusMinutesLogged}m', 'Focus'),
                    _buildWeeklyMiniStat(context, '${wp.priorityTasksCompleted}', 'Priority Tasks'),
                    _buildWeeklyMiniStat(context, '+${wp.flowPointsEarned}', 'Flow Earned'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Weekly Challenge Card
        if (overview.activeChallenge != null) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: FlowColors.surfaceElevated(context),
              borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
              border: Border.all(color: FlowColors.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'WEEKLY CHALLENGE',
                        style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAB308).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(FlowRadii.pill),
                      ),
                      child: Text(
                        '+${overview.activeChallenge!.rewardFlow} Flow',
                        style: FlowTypography.labelSmall(color: const Color(0xFFEAB308)).copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  overview.activeChallenge!.title,
                  style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Progress: ${overview.activeChallenge!.progressLabel}',
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(FlowRadii.pill),
                  child: LinearProgressIndicator(
                    value: overview.activeChallenge!.progressFraction,
                    minHeight: 8,
                    backgroundColor: FlowColors.border(context),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEAB308)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWeeklyMiniStat(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// TAB 1: QUESTS (Progress-driven with explicit user claim)
  Widget _buildQuestsTab(
    BuildContext context,
    FlowProvider flow,
    List<FlowDailyQuest> dailyQuests,
  ) {
    if (dailyQuests.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(
          'Daily quests refresh at midnight.',
          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'TODAY’S QUESTS',
                style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Claim before midnight',
              style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...dailyQuests.map((quest) {
          final isClaimable = quest.isCompleted && !quest.isClaimed;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FlowColors.surfaceElevated(context),
              borderRadius: BorderRadius.circular(FlowRadii.card),
              border: Border.all(
                color: isClaimable ? FlowColors.mint : FlowColors.border(context),
                width: isClaimable ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            quest.title,
                            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            quest.description,
                            style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Action button: CLAIM / In Progress / Claimed
                    if (quest.isClaimed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: FlowColors.mint.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(FlowRadii.pill),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 14, color: FlowColors.mint),
                            const SizedBox(width: 4),
                            Text(
                              'Claimed',
                              style: FlowTypography.labelSmall(color: FlowColors.mint).copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (isClaimable)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: FlowColors.mint,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.pill)),
                        ),
                        onPressed: () => _claimQuest(context, flow, quest),
                        child: Text(
                          'CLAIM +${quest.rewardFlow}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: FlowColors.border(context).withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(FlowRadii.pill),
                        ),
                        child: Text(
                          quest.progressLabel,
                          style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(FlowRadii.pill),
                  child: LinearProgressIndicator(
                    value: quest.progressFraction,
                    minHeight: 6,
                    backgroundColor: FlowColors.border(context),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      quest.isCompleted ? FlowColors.mint : FlowColors.textMutedOf(context),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// TAB 2: ACHIEVEMENTS (12 Meaningful Milestones)
  Widget _buildAchievementsTab(
    BuildContext context,
    List<FlowAchievement> achievements,
  ) {
    if (achievements.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(
          'Achieve milestones to earn permanent Flow rewards.',
          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
        ),
      );
    }

    final unlockedCount = achievements.where((a) => a.isUnlocked).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'ACHIEVEMENTS ($unlockedCount / ${achievements.length})',
                style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '12 Milestones',
              style: FlowTypography.labelSmall(color: FlowColors.mint).copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...achievements.map((item) {
          final isUnlocked = item.isUnlocked;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: FlowColors.surfaceElevated(context),
              borderRadius: BorderRadius.circular(FlowRadii.card),
              border: Border.all(
                color: isUnlocked ? FlowColors.mint.withValues(alpha: 0.5) : FlowColors.border(context),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isUnlocked ? FlowColors.mint.withValues(alpha: 0.15) : FlowColors.border(context).withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isUnlocked ? Icons.emoji_events_rounded : Icons.lock_outline_rounded,
                    color: isUnlocked ? FlowColors.mint : FlowColors.textMutedOf(context),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.description,
                        style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '+${item.rewardFlow} Flow',
                  style: FlowTypography.labelSmall(
                    color: isUnlocked ? const Color(0xFFEAB308) : FlowColors.textMutedOf(context),
                  ).copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// TAB 3: CUSTOMIZE — Companion Sanctuary with real shop + purchase flow
  Widget _buildCustomizeTab(
    BuildContext context,
    FlowCompanion companion,
  ) {
    final flow = Provider.of<FlowProvider>(context);
    final catalog = flow.shopCatalog;
    final currentBalance = flow.profile.flowBalance;

    // Fallback static list if catalog not yet loaded
    final displayCatalog = catalog.isNotEmpty ? catalog : [
      {'species': 'fox', 'name': 'Noya', 'description': 'Curious & Energizing', 'is_owned': true, 'flow_cost': 0, 'perk': 'Sprint Mastery', 'accent_color': '#F97316'},
      {'species': 'otter', 'name': 'Ludo', 'description': 'Playful & Resilient', 'is_owned': false, 'flow_cost': 250, 'perk': 'Deep Current', 'accent_color': '#06B6D4'},
      {'species': 'owl', 'name': 'Aria', 'description': 'Calm & Wise', 'is_owned': false, 'flow_cost': 350, 'perk': 'Night Owl', 'accent_color': '#8B5CF6'},
      {'species': 'capybara', 'name': 'Boba', 'description': 'Patient & Steady', 'is_owned': false, 'flow_cost': 500, 'perk': 'Stress Immunity', 'accent_color': '#10B981'},
      {'species': 'cat', 'name': 'Mochi', 'description': 'Playful & Curious', 'is_owned': false, 'flow_cost': 600, 'perk': 'Creative Flow', 'accent_color': '#F472B6'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'COMPANION SANCTUARY',
                style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, size: 14, color: Color(0xFFEAB308)),
                const SizedBox(width: 3),
                Text(
                  '$currentBalance',
                  style: FlowTypography.labelSmall(color: const Color(0xFFEAB308)).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
          children: displayCatalog.map((item) {
            final species = item['species'] as String? ?? '';
            final name = item['name'] as String? ?? '';
            final isOwned = item['is_owned'] as bool? ?? false;
            final cost = item['flow_cost'] as int? ?? 0;
            final perk = item['perk'] as String? ?? '';
            final isCurrent = companion.species == species;
            final canAfford = currentBalance >= cost;

            return GestureDetector(
              onTap: () => _handleCompanionTap(context, flow, species, name, isOwned, cost, canAfford, isCurrent),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FlowColors.surfaceElevated(context),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isCurrent
                        ? FlowColors.mint
                        : isOwned
                            ? FlowColors.mint.withValues(alpha: 0.35)
                            : FlowColors.border(context),
                    width: isCurrent ? 2.0 : 1.0,
                  ),
                  boxShadow: isCurrent
                      ? [BoxShadow(color: FlowColors.mint.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CompanionGraphic(species: species, size: 64),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      perk,
                      style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                        fontSize: 9,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: FlowColors.mint,
                          borderRadius: BorderRadius.circular(FlowRadii.pill),
                        ),
                        child: Text(
                          'ACTIVE',
                          style: FlowTypography.labelSmall(color: Colors.black).copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 9,
                          ),
                        ),
                      )
                    else if (isOwned)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: FlowColors.mint.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(FlowRadii.pill),
                          border: Border.all(color: FlowColors.mint.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          'TAP TO SWITCH',
                          style: FlowTypography.labelSmall(color: FlowColors.mint).copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: canAfford
                              ? const Color(0xFFEAB308).withValues(alpha: 0.12)
                              : FlowColors.border(context).withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(FlowRadii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 11,
                              color: canAfford
                                  ? const Color(0xFFEAB308)
                                  : FlowColors.textMutedOf(context),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$cost',
                              style: FlowTypography.labelSmall(
                                color: canAfford
                                    ? const Color(0xFFEAB308)
                                    : FlowColors.textMutedOf(context),
                              ).copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: FlowColors.surfaceElevated(context),
            borderRadius: BorderRadius.circular(FlowRadii.card),
            border: Border.all(color: FlowColors.border(context)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF6366F1)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Earn Flow Points by completing focus sessions, quests, and challenges.',
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleCompanionTap(
    BuildContext context,
    FlowProvider flow,
    String species,
    String name,
    bool isOwned,
    int cost,
    bool canAfford,
    bool isCurrent,
  ) {
    if (isCurrent) return; // Already active, nothing to do

    if (isOwned) {
      // Switch companion
      FlowHaptics.lightTap();
      flow.selectCompanion(species);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name is now your active companion!'),
          backgroundColor: FlowColors.mint,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Show purchase confirmation dialog
    FlowHaptics.lightTap();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlowColors.surface(context),
        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.cardLargeRadius),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CompanionGraphic(species: species, size: 56),
            const SizedBox(height: 12),
            Text(
              'Unlock $name?',
              style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                fontWeight: FontWeight.w800, fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (!canAfford)
              Text(
                'You need $cost Flow Points but only have ${flow.profile.flowBalance}.\nKeep focusing to earn more!',
                style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                textAlign: TextAlign.center,
              )
            else
              Text(
                'This will deduct $cost Flow Points from your balance.',
                style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                textAlign: TextAlign.center,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: FlowColors.textSecondaryOf(context))),
          ),
          if (canAfford)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEAB308),
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await flow.purchaseCompanion(species);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$name joined your roster!'),
                        backgroundColor: FlowColors.mint,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.toString().replaceFirst('Exception: ', '')),
                        backgroundColor: Colors.red.shade700,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
              child: Text('Unlock for $cost ⭐', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }


  /// Personal Records ("Me vs Myself")
  Widget _buildPersonalRecordsCard(BuildContext context, dynamic overview) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
        border: Border.all(color: FlowColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart_rounded, size: 20, color: FlowColors.mint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PERSONAL RECORDS · ME VS MYSELF',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildMetricColumn(
                context,
                overview.personalBestFocusMinutes > 0
                    ? '${overview.personalBestFocusMinutes}m'
                    : '—',
                'Best Session',
              ),
              Container(width: 1, height: 28, color: FlowColors.border(context)),
              _buildMetricColumn(
                context,
                overview.bestFocusDayMinutes > 0
                    ? '${overview.bestFocusDayMinutes}m'
                    : '—',
                'Best Day',
              ),
              Container(width: 1, height: 28, color: FlowColors.border(context)),
              _buildMetricColumn(
                context,
                overview.totalFocusMinutes > 0
                    ? (overview.totalFocusMinutes < 60
                        ? '${overview.totalFocusMinutes}m'
                        : (overview.totalFocusMinutes % 60 == 0
                            ? '${overview.totalFocusMinutes ~/ 60}h'
                            : '${(overview.totalFocusMinutes / 60).toStringAsFixed(1)}h'))
                    : '0m',
                'Total Focus',
              ),
              Container(width: 1, height: 28, color: FlowColors.border(context)),
              _buildMetricColumn(
                context,
                overview.consistencyScore.isNotEmpty
                    ? overview.consistencyScore
                    : 'Building',
                'Rhythm',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
