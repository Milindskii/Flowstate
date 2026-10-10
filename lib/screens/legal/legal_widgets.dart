import 'package:flutter/material.dart';
import '../../theme/flow_colors.dart';
import '../../theme/flow_haptics.dart';
import '../../theme/flow_radii.dart';
import '../../theme/flow_spacing.dart';
import '../../theme/flow_typography.dart';

/// One titled block of a legal document: a heading and one or more paragraphs / bullet lists.
class LegalSection {
  final String title;
  final List<LegalBlock> blocks;
  const LegalSection(this.title, this.blocks);
}

/// A paragraph, or a bulleted list when [bullets] is set. [lead] is an optional bold lead-in.
class LegalBlock {
  final String? text;
  final List<String>? bullets;
  const LegalBlock.paragraph(String this.text) : bullets = null;
  const LegalBlock.list(List<String> this.bullets) : text = null;
}

/// Shared page shell for the Terms and the Privacy Policy: back button, scrollable body, calm section cards.
class LegalDocumentPage extends StatelessWidget {
  final String appBarTitle;
  final String headline;
  final String intro;
  final String updatedLabel;
  final List<LegalSection> sections;
  final Widget? afterIntro;

  const LegalDocumentPage({
    super.key,
    required this.appBarTitle,
    required this.headline,
    required this.intro,
    required this.updatedLabel,
    required this.sections,
    this.afterIntro,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);
    final cardBg = FlowColors.surface(context);
    final borderColor = FlowColors.border(context);

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      appBar: AppBar(
        title: Text(
          appBarTitle,
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
          padding: EdgeInsets.symmetric(horizontal: FlowSpacing.pageMargin(context), vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: FlowColors.accentCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(FlowRadii.badge),
                ),
                child: Text(
                  updatedLabel,
                  style: FlowTypography.labelSmall(color: FlowColors.accentCyan).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 14),
              Semantics(
                header: true,
                child: Text(
                  headline,
                  style: FlowTypography.headlineMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              Text(intro, style: FlowTypography.bodyMedium(color: textSecondary).copyWith(height: 1.5)),
              if (afterIntro != null) ...[const SizedBox(height: 16), afterIntro!],
              const SizedBox(height: 20),
              for (final s in sections) LegalSectionCard(section: s),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class LegalSectionCard extends StatelessWidget {
  final LegalSection section;
  const LegalSectionCard({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              section.title,
              style: FlowTypography.titleSmall(color: textPrimary).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final b in section.blocks) ...[
            const SizedBox(height: 8),
            if (b.text != null)
              Text(b.text!, style: FlowTypography.bodyMedium(color: textSecondary).copyWith(height: 1.5))
            else
              for (final item in b.bullets!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, right: 10, left: 2),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(color: FlowColors.accentCyan, shape: BoxShape.circle),
                        ),
                      ),
                      Expanded(
                        child: Text(item, style: FlowTypography.bodyMedium(color: textSecondary).copyWith(height: 1.5)),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

/// A quiet inline note (no warning colour) used for "plain-English summary" callouts.
class LegalSummaryNote extends StatelessWidget {
  final String text;
  final IconData icon;
  const LegalSummaryNote({super.key, required this.text, this.icon = Icons.info_outline_rounded});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlowColors.surfaceContainer(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: FlowColors.accentCyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
