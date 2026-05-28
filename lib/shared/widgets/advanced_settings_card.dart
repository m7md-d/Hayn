import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/capabilities/format_capabilities.dart';
import '../../features/settings/providers/preferences_providers.dart';
import 'controls.dart';
import 'sheets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HaynAdvancedSettingsCard — shared "Advanced" panel used by both Compress
// and Surgical. Hosts the format picker, quality slider, keep-metadata
// toggle, and an optional trash-backup toggle (surgical-only).
//
// Designed so that adding a new advanced option to one screen surfaces it
// in the other automatically — encouraging a single mental model for the
// user across both flows.
// ─────────────────────────────────────────────────────────────────────────────

class HaynAdvancedSettingsCard extends ConsumerWidget {
  const HaynAdvancedSettingsCard({
    required this.format,
    required this.quality,
    required this.keepMetadata,
    required this.onFormatChanged,
    required this.onQualityChanged,
    required this.onKeepMetaChanged,
    this.keepTrashBackup,
    this.onKeepTrashChanged,
    super.key,
  });

  final DefaultFormat format;
  final double quality;
  final bool keepMetadata;
  final ValueChanged<DefaultFormat> onFormatChanged;
  final ValueChanged<double> onQualityChanged;
  final ValueChanged<bool> onKeepMetaChanged;

  /// Surgical-only: keep the original in trash for the configured retention
  /// period. When null, the row is hidden (compress doesn't need this).
  final bool? keepTrashBackup;
  final ValueChanged<bool>? onKeepTrashChanged;

  Future<void> _openFormatPicker(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final caps = ref.read(formatCapabilitiesProvider);
    final options = <HaynPickerOption<DefaultFormat>>[
      HaynPickerOption(
          value: DefaultFormat.auto,
          label: l.formatAuto,
          description: l.formatAutoDesc,
          icon: Icons.auto_awesome_rounded),
      HaynPickerOption(
          value: DefaultFormat.avif,
          label: 'AVIF',
          description: l.formatAvifDesc,
          warning:
              caps.supportsAvifHardware ? null : l.formatAvifSoftwareWarning),
      if (caps.supportsHeic)
        HaynPickerOption(
            value: DefaultFormat.heic,
            label: 'HEIC',
            description: l.formatHeicDesc)
      else if (caps.supportsHeif)
        HaynPickerOption(
            value: DefaultFormat.heic,
            label: 'HEIF',
            description: l.formatHeicDesc),
      if (caps.supportsWebp)
        HaynPickerOption(
            value: DefaultFormat.webp,
            label: 'WebP',
            description: l.formatWebpDesc),
      HaynPickerOption(
          value: DefaultFormat.jpeg,
          label: 'JPEG',
          description: l.formatJpegDesc),
    ];

    await showHaynPickerSheet<DefaultFormat>(
      context: context,
      title: l.compressFormat,
      currentValue: format,
      onChanged: onFormatChanged,
      options: options,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final caps = ref.watch(formatCapabilitiesProvider);
    final formatDisplay = format == DefaultFormat.auto
        ? l.formatAutoResolved(DefaultFormat.labelFor(
            DefaultFormat.resolveAuto(caps),
            supportsHeic: caps.supportsHeic,
            supportsHeif: caps.supportsHeif,
          ))
        : DefaultFormat.labelFor(
            format,
            supportsHeic: caps.supportsHeic,
            supportsHeif: caps.supportsHeif,
          );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Format row ──────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                  child: Text(l.compressFormat,
                      style: theme.textTheme.bodyMedium)),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.full),
                onTap: () => _openFormatPicker(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s3, vertical: AppSpacing.s1 + 2),
                  decoration: BoxDecoration(
                    color: hc.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatDisplay,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: hc.accent,
                            fontWeight: FontWeight.w600,
                          )),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded,
                          size: 14, color: hc.accent),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const Divider(height: AppSpacing.lg),

          // ── Quality slider ──────────────────────────────────────────────
          HaynValueSlider(
            label: l.compressQuality,
            valueLabel: '${quality.round()}',
            value: quality,
            min: 30,
            max: 100,
            divisions: 14,
            onChanged: onQualityChanged,
            helper: quality < 60
                ? l.compressLowQ
                : quality > 90
                    ? l.compressHighQ
                    : l.compressMidQ,
          ),

          const Divider(height: AppSpacing.lg),

          // ── Keep metadata toggle ────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.compressKeepMeta,
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      l.compressKeepMetaDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hc.text2,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: keepMetadata,
                onChanged: onKeepMetaChanged,
              ),
            ],
          ),

          // ── (Optional) trash-backup toggle ──────────────────────────────
          if (keepTrashBackup != null && onKeepTrashChanged != null) ...[
            const Divider(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.surgicalKeepBackup,
                          style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 2),
                      Text(
                        l.surgicalKeepBackupDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hc.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: keepTrashBackup!,
                  onChanged: onKeepTrashChanged,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
