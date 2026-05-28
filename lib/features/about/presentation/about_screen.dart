import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AboutScreen — brief identity, philosophy, source code link, license info,
// and the system licenses page (embedded — no duplicate cell in Settings).
// No donation prompts anywhere.
// ─────────────────────────────────────────────────────────────────────────────

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _appVersion = '1.0.0';
  static const _repoUrl = 'https://github.com/m7md-d/hayn';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);

    return HaynScaffold(
      appBar: HaynDetailAppBar(title: l.aboutTitle),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.lg,
        ),
        children: [
          // ── Identity ──────────────────────────────────────────────────
          Column(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: hc.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.auto_awesome_rounded,
                    size: 48, color: hc.accent),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(l.appName, style: theme.textTheme.displaySmall),
              const SizedBox(height: AppSpacing.s1),
              Text(
                '${l.settingsVersion} $_appVersion',
                style: theme.textTheme.labelMedium?.copyWith(color: hc.text2),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l.aboutTagline,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: hc.text2,
                  height: 1.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Philosophy ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Text(
              l.aboutPhilosophy,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.7,
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Source code + licenses (one section) ──────────────────────
          HaynListSection(
            footer: l.aboutLicenseLine,
            children: [
              HaynListCell(
                leadingIcon: Icons.code_rounded,
                label: l.aboutSourceCode,
                description: l.aboutSourceCodeDesc,
                onTap: () => _openUrl(context, _repoUrl),
              ),
              HaynListCell(
                leadingIcon: Icons.description_outlined,
                label: l.settingsLicenses,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: l.appName,
                  applicationVersion: _appVersion,
                  applicationLegalese: l.aboutLicenseLine,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    HapticFeedback.selectionClick();
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      HaynSnack.error(context, AppLocalizations.of(context).errorUnknown);
    }
  }
}
