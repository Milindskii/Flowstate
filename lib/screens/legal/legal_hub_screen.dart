import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/app_state_provider.dart';
import '../../theme/flow_colors.dart';
import '../../theme/flow_haptics.dart';
import '../../theme/flow_radii.dart';
import '../../theme/flow_spacing.dart';
import '../../theme/flow_typography.dart';
import '../auth_screen.dart';
import 'cookie_policy_screen.dart';
import 'privacy_policy_screen.dart';
import 'refund_policy_screen.dart';
import 'terms_of_service_screen.dart';

/// Central Legal, Compliance & GDPR Rights Hub
class LegalHubScreen extends StatefulWidget {
  const LegalHubScreen({super.key});

  @override
  State<LegalHubScreen> createState() => _LegalHubScreenState();
}

class _LegalHubScreenState extends State<LegalHubScreen> {
  bool _isExporting = false;
  bool _isDeleting = false;
  bool _isDeactivating = false;

  Future<void> _handleEmailContact(String email, String subject) async {
    FlowHaptics.lightTap();
    final uri = Uri(scheme: 'mailto', path: email, queryParameters: {'subject': subject});
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await Clipboard.setData(ClipboardData(text: email));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied $email to clipboard.'),
              backgroundColor: FlowColors.accentCyan,
            ),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: email));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied $email to clipboard.'),
            backgroundColor: FlowColors.accentCyan,
          ),
        );
      }
    }
  }

  void _handleViewMyData() {
    FlowHaptics.lightTap();
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final user = appState.currentUser;
    final rhythm = appState.personalData;
    final tasksCount = appState.tasks.length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlowColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.cardLarge)),
        title: Row(
          children: [
            const Icon(Icons.person_outline_rounded, color: FlowColors.mint, size: 24),
            const SizedBox(width: 8),
            Text('My Stored Personal Data', style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Account Details', style: FlowTypography.labelLarge(color: FlowColors.mint).copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Email: ${user?.email ?? 'Not signed in'}', style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
              Text('Name: ${user?.name ?? 'Friend'}', style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
              const SizedBox(height: 12),
              Text('Circadian Rhythm Calibration', style: FlowTypography.labelLarge(color: FlowColors.mint).copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Wake Time: ${rhythm.wakeTime}', style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
              Text('Sleep Hours: ${rhythm.sleepHours} hrs', style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
              Text('Focus Peak Window: ${rhythm.focusPeak}', style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
              Text('Energy Dip Time: ${rhythm.energyDipTime}', style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
              const SizedBox(height: 12),
              Text('Productivity & Companion Data', style: FlowTypography.labelLarge(color: FlowColors.mint).copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Active Tasks: $tasksCount tasks', style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
              Text('Companion Mascot: Noya (Fox)', style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
              const SizedBox(height: 12),
              Text(
                'Note: All task parsing is performed locally in-memory. No task text is sent to third-party public AI models.',
                style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _handleSubmitGrievance() {
    FlowHaptics.lightTap();
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final emailCtrl = TextEditingController(text: appState.currentUser?.email ?? '');
    final msgCtrl = TextEditingController();
    String selectedType = 'general_grievance';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Submit Privacy Grievance or Request', style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))),
              const SizedBox(height: 4),
              Text(
                'Under the DPDP Act 2023, you have the right to request clarification, correction, or submit grievances regarding your personal data.',
                style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedType,
                dropdownColor: FlowColors.surface(context),
                decoration: const InputDecoration(labelText: 'Request Type', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'general_grievance', child: Text('General Privacy Grievance')),
                  DropdownMenuItem(value: 'access', child: Text('Data Access / Information')),
                  DropdownMenuItem(value: 'correction', child: Text('Data Correction')),
                  DropdownMenuItem(value: 'erasure_inquiry', child: Text('Erasure Inquiry')),
                  DropdownMenuItem(value: 'objection', child: Text('Processing Objection')),
                ],
                onChanged: (val) => setSheetState(() => selectedType = val ?? 'general_grievance'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Your Contact Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: msgCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Describe your request or concern',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (emailCtrl.text.trim().isEmpty || msgCtrl.text.trim().isEmpty) return;
                          setSheetState(() => isSubmitting = true);
                          try {
                            await appState.apiService.post('/api/v1/auth/grievance', body: {
                              'request_type': selectedType,
                              'email': emailCtrl.text.trim(),
                              'message': msgCtrl.text.trim(),
                            });
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  backgroundColor: FlowColors.surface(context),
                                  title: const Text('Grievance Received'),
                                  content: const Text(
                                    'Your request has been logged. We will review your request and respond as required by applicable law to your provided email address.',
                                  ),
                                  actions: [
                                    FilledButton(onPressed: () => Navigator.pop(_), child: const Text('OK')),
                                  ],
                                ),
                              );
                            }
                          } catch (e) {
                            setSheetState(() => isSubmitting = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Submission notice: $e')));
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Submit Request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleDeactivateAccount() async {
    FlowHaptics.lightTap();
    final appState = Provider.of<AppStateProvider>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlowColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.cardLarge)),
        title: Row(
          children: [
            const Icon(Icons.pause_circle_outline_rounded, color: FlowColors.warning, size: 24),
            const SizedBox(width: 8),
            Text('Deactivate Account?', style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))),
          ],
        ),
        content: Text(
          'Deactivating temporarily suspends your account and stops all notifications.\n\n'
          'Unlike permanent deletion, your saved tasks, rhythm calibrations, and Noya companion progression remain safely preserved.\n\n'
          'You can reactivate your account at any time by simply logging back in.',
          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: FlowTypography.labelMedium(color: FlowColors.textMutedOf(context))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FlowColors.warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isDeactivating = true);
      try {
        await appState.apiService.post('/api/v1/auth/deactivate');
        await appState.logout();
        if (mounted) {
          setState(() => _isDeactivating = false);
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isDeactivating = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deactivation note: $e'),
              backgroundColor: FlowColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleExportData() async {
    FlowHaptics.lightTap();
    setState(() => _isExporting = true);
    final appState = Provider.of<AppStateProvider>(context, listen: false);

    try {
      final res = await appState.apiService.post('/api/v1/auth/export-data');
      final jsonPretty = const JsonEncoder.withIndent('  ').convert(res);
      await Clipboard.setData(ClipboardData(text: jsonPretty));

      if (mounted) {
        setState(() => _isExporting = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: FlowColors.surface(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.cardLarge)),
            title: Row(
              children: [
                const Icon(Icons.download_done_rounded, color: FlowColors.positive, size: 24),
                const SizedBox(width: 8),
                Text('Data Export Ready', style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))),
              ],
            ),
            content: Text(
              'Your exported data archive has been copied to your clipboard as a formatted JSON document. You can paste it into any text editor.',
              style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export notice: $e'),
            backgroundColor: FlowColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    FlowHaptics.lightTap();
    final appState = Provider.of<AppStateProvider>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlowColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.cardLarge)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: FlowColors.error, size: 26),
            const SizedBox(width: 8),
            Text('Permanently Delete Account?', style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))),
          ],
        ),
        content: Text(
          'This action is permanent and irreversible.\n\n'
          'All your tasks, performance logs, rhythm calibrations, Flow Points, and companion progression (Noya) will be permanently purged from our servers.\n\n'
          'An external web account deletion request page will also be available prior to production launch.',
          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: FlowTypography.labelMedium(color: FlowColors.textMutedOf(context))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FlowColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isDeleting = true);
      try {
        await appState.apiService.delete('/api/v1/auth/me');
        await appState.logout();
        if (mounted) {
          setState(() => _isDeleting = false);
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isDeleting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account deletion notice: $e'),
              backgroundColor: FlowColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);
    final cardBg = FlowColors.surface(context);
    final borderColor = FlowColors.border(context);
    final pageMargin = FlowSpacing.pageMargin(context);

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      appBar: AppBar(
        title: Text(
          'Legal & Compliance Hub',
          style: FlowTypography.titleMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w700),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          tooltip: 'Back',
          onPressed: () {
            FlowHaptics.lightTap();
            Navigator.of(context).pop();
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: borderColor, height: 1.0),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: pageMargin, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Trust & Legal Transparency',
                style: FlowTypography.headlineMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Access our legal agreements, privacy disclosures, and exercise data portability and account erasure rights.',
                style: FlowTypography.bodyMedium(color: textSecondary),
              ),
              const SizedBox(height: 20),

              // Legal Policies Section
              Text('Legal Policies', style: FlowTypography.titleSmall(color: textPrimary).copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),

              _buildNavTile(
                context,
                icon: Icons.shield_outlined,
                title: 'Privacy & Data Policy',
                subtitle: 'Data collection, AI parsing disclosures, and user rights',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                ),
              ),
              _buildNavTile(
                context,
                icon: Icons.description_outlined,
                title: 'Terms of Service',
                subtitle: 'Fair usage, acceptable conduct, non-medical disclaimer',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()),
                ),
              ),
              _buildNavTile(
                context,
                icon: Icons.price_check_rounded,
                title: 'Refund Policy & Free Guarantee',
                subtitle: '100% free progression, 14-day refund guarantee',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RefundPolicyScreen()),
                ),
              ),
              _buildNavTile(
                context,
                icon: Icons.storage_rounded,
                title: 'Local Storage & Data Preferences',
                subtitle: 'Essential app storage, offline caching, zero ad trackers',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CookiePolicyScreen()),
                ),
              ),
              _buildNavTile(
                context,
                icon: Icons.source_outlined,
                title: 'Open Source Licenses',
                subtitle: 'Attributions for Flutter, Google Fonts (OFL), and packages',
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: 'Flowstate',
                    applicationVersion: '2.0.0',
                    applicationLegalese: '© 2026 Milind Krishnan. All rights reserved.',
                  );
                },
              ),

              const SizedBox(height: 24),

              // Developer Details Card
              Text('Developer Identity & Contact', style: FlowTypography.titleSmall(color: textPrimary).copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
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
                    Text('Milind Krishnan, Independent Developer', style: FlowTypography.titleSmall(color: textPrimary).copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Location: Chennai, Tamil Nadu, India\n'
                      'Developer Status: Solo / Independent Developer project (not an incorporated company or registered entity).\n'
                      'External Web Deletion URL: TBD (will be hosted at the verified web domain before production launch)',
                      style: FlowTypography.bodySmall(color: textSecondary).copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _handleEmailContact('Milindkrishnan24@gmail.com', 'Privacy & General Inquiry'),
                          icon: const Icon(Icons.email_outlined, size: 16),
                          label: const Text('Milindkrishnan24@gmail.com'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _handleSubmitGrievance,
                          icon: const Icon(Icons.feedback_outlined, size: 16),
                          label: const Text('Submit Grievance / Inquiry'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Data Rights Actions
              Text('Data Access, Portability & Erasure', style: FlowTypography.titleSmall(color: textPrimary).copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),

              _buildNavTile(
                context,
                icon: Icons.visibility_outlined,
                title: 'View My Stored Data',
                subtitle: 'Inspect personal credentials, circadian calibration, and companion stats',
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                accentColor: FlowColors.mint,
                onTap: _handleViewMyData,
              ),

              _buildNavTile(
                context,
                icon: Icons.download_rounded,
                title: 'Data Portability & Export (JSON Archive)',
                subtitle: _isExporting ? 'Generating JSON bundle...' : 'Data export functionality supporting applicable portability/access rights',
                trailing: _isExporting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.copy_rounded, size: 20),
                onTap: _isExporting ? () {} : _handleExportData,
              ),

              _buildNavTile(
                context,
                icon: Icons.pause_circle_outline_rounded,
                title: 'Deactivate Account (Temporary Pause)',
                subtitle: _isDeactivating ? 'Deactivating account...' : 'Pause notifications & access; tasks and Noya progression are preserved',
                trailing: _isDeactivating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: FlowColors.warning))
                    : const Icon(Icons.chevron_right_rounded, color: FlowColors.warning, size: 20),
                accentColor: FlowColors.warning,
                onTap: _isDeactivating ? () {} : _handleDeactivateAccount,
              ),

              _buildNavTile(
                context,
                icon: Icons.delete_forever_rounded,
                title: 'Permanent Account & Data Deletion',
                subtitle: _isDeleting ? 'Purging account...' : 'Permanently erase all personal data from Flowstate servers',
                trailing: _isDeleting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: FlowColors.error))
                    : const Icon(Icons.chevron_right_rounded, color: FlowColors.error, size: 20),
                accentColor: FlowColors.error,
                onTap: _isDeleting ? () {} : _handleDeleteAccount,
              ),

              // External deletion info note
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'Google Play Policy Note: An external web-based account deletion route will be provided before launch. The URL will be confirmed and linked here.',
                  style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    Color? accentColor,
    required VoidCallback onTap,
  }) {
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textMuted = FlowColors.textMutedOf(context);
    final cardBg = FlowColors.surface(context);
    final borderColor = FlowColors.border(context);
    final iconColor = accentColor ?? FlowColors.accentCyan;

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: FlowTypography.bodyLarge(color: accentColor ?? textPrimary).copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: FlowTypography.bodySmall(color: textMuted),
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
