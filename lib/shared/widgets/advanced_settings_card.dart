import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/capabilities/format_capabilities.dart';
import '../../features/image_ops/data/native_avif_encoder.dart';
import '../../features/image_ops/domain/image_format_policy.dart';
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
    this.bitDepth,
    this.onBitDepthChanged,
    this.sourceBitDepth,
    this.keepOriginalTime,
    this.onKeepOriginalTimeChanged,
    this.keepTrashBackup,
    this.onKeepTrashChanged,
    this.formatNote,
    this.offered,
    this.autoResolved,
    super.key,
  });

  final DefaultFormat format;
  final double quality;
  final bool keepMetadata;
  final ValueChanged<DefaultFormat> onFormatChanged;
  final ValueChanged<double> onQualityChanged;
  final ValueChanged<bool> onKeepMetaChanged;

  /// Output bit depth: 0 = match the source (keeps HDR), 8 = force SDR, 10 =
  /// deep colour. Null hides the row; it's only shown for deep-colour-capable
  /// formats (HEIC/AVIF) where the choice is meaningful.
  final int? bitDepth;
  final ValueChanged<int>? onBitDepthChanged;

  /// The source image's real bit depth, used to warn when the user picks a
  /// higher depth than the original (no quality gain). Null = unknown.
  final int? sourceBitDepth;

  /// Keep the ORIGINAL capture time on the new copy. Independent of
  /// [keepMetadata] (info/location) so the user can keep location yet have the
  /// copy dated "now". When null the row is hidden (e.g. surgical, which edits
  /// in place and keeps the time inherently).
  final bool? keepOriginalTime;
  final ValueChanged<bool>? onKeepOriginalTimeChanged;

  /// Surgical-only: keep the original in trash for the configured retention
  /// period. When null, the row is hidden (compress doesn't need this).
  final bool? keepTrashBackup;
  final ValueChanged<bool>? onKeepTrashChanged;

  /// Light note for a format choice, e.g. "Without transparency" when it drops
  /// something the current image has. Null or a null result shows nothing.
  final String? Function(DefaultFormat choice)? formatNote;

  /// Which formats the picker lists; null lists every one. A giant image is
  /// offered JPEG and HEIC only (RUN-01).
  final bool Function(DefaultFormat format)? offered;

  /// What Auto becomes for this image, when the caller knows better than the
  /// device default (a giant image's Auto is HEIC or JPEG).
  final DefaultFormat? autoResolved;

  DefaultFormat _auto(FormatCapabilities caps) =>
      autoResolved ?? DefaultFormat.resolveAuto(caps);

  Future<void> _openFormatPicker(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final caps = ref.read(formatCapabilitiesProvider);
    // Probe the REAL hardware AV1 encoder (cached) so capable devices don't see
    // the stale "software/slower" warning. flutter_avif is software, but the
    // native MediaCodec path makes AVIF hardware-accelerated where available.
    final avifHardware =
        caps.supportsAvifHardware || await NativeAvifEncoder.isAvailable();
    final options = <HaynPickerOption<DefaultFormat>>[
      HaynPickerOption(
          value: DefaultFormat.auto,
          note: formatNote?.call(DefaultFormat.auto),
          label: l.formatAuto,
          description: l.formatAutoDesc,
          icon: Icons.auto_awesome_rounded),
      HaynPickerOption(
          value: DefaultFormat.avif,
          note: formatNote?.call(DefaultFormat.avif),
          label: 'AVIF',
          description: l.formatAvifDesc,
          warning: avifHardware ? null : l.formatAvifSoftwareWarning),
      if (caps.supportsHeic)
        HaynPickerOption(
            value: DefaultFormat.heic,
            note: formatNote?.call(DefaultFormat.heic),
            label: 'HEIC',
            description: l.formatHeicDesc)
      else if (caps.supportsHeif)
        HaynPickerOption(
            value: DefaultFormat.heic,
            note: formatNote?.call(DefaultFormat.heic),
            label: 'HEIF',
            description: l.formatHeicDesc),
      if (caps.supportsWebp)
        HaynPickerOption(
            value: DefaultFormat.webp,
            note: formatNote?.call(DefaultFormat.webp),
            label: 'WebP',
            description: l.formatWebpDesc),
      HaynPickerOption(
          value: DefaultFormat.jpeg,
          note: formatNote?.call(DefaultFormat.jpeg),
          label: 'JPEG',
          description: l.formatJpegDesc),
      HaynPickerOption(
          value: DefaultFormat.png,
          note: formatNote?.call(DefaultFormat.png),
          label: 'PNG',
          description: l.formatPngDesc),
    ];

    if (!context.mounted) return;
    await showHaynPickerSheet<DefaultFormat>(
      context: context,
      title: l.compressFormat,
      currentValue: format,
      onChanged: onFormatChanged,
      options: [
        for (final o in options)
          if (offered?.call(o.value) ?? true) o,
      ],
    );
  }

  /// The bit-depth row only makes sense for deep-colour-capable formats
  /// (HEIC/AVIF) and when the caller wired it up. JPEG/WebP/PNG hide it.
  bool _showBitDepth(FormatCapabilities caps) {
    if (bitDepth == null || onBitDepthChanged == null) return false;
    final effective = format == DefaultFormat.auto ? _auto(caps) : format;
    return effective == DefaultFormat.heic || effective == DefaultFormat.avif;
  }

  /// The depth shown, as it is encoded: a 10 the format does not offer is 8.
  int _depth(FormatCapabilities caps) => ImageFormatPolicy.depthFor(
        bitDepth!,
        format == DefaultFormat.auto ? _auto(caps) : format,
        caps,
      );

  /// 10 bits for AVIF always (DarkLib), for HEIC where the encoder writes
  /// it (IMG-23).
  bool _offersTenBit(FormatCapabilities caps) {
    final effective = format == DefaultFormat.auto ? _auto(caps) : format;
    return ImageFormatPolicy.offersTenBit(effective, caps);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final caps = ref.watch(formatCapabilitiesProvider);
    final formatDisplay = format == DefaultFormat.auto
        ? l.formatAutoResolved(DefaultFormat.labelFor(
            _auto(caps),
            supportsHeic: caps.supportsHeic,
            supportsHeif: caps.supportsHeif,
          ))
        : DefaultFormat.labelFor(
            format,
            supportsHeic: caps.supportsHeic,
            supportsHeif: caps.supportsHeif,
          );

    final currentNote = formatNote?.call(format);

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
          if (currentNote != null) ...[
            const SizedBox(height: AppSpacing.s1),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(currentNote,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: hc.text3)),
            ),
          ],

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

          // ── Bit depth (HEIC/AVIF only — where deep colour / HDR applies) ──
          if (_showBitDepth(caps)) ...[
            const Divider(height: AppSpacing.lg),
            Text(l.compressBitDepth, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(l.compressBitDepthDesc,
                style: theme.textTheme.bodySmall?.copyWith(color: hc.text2)),
            const SizedBox(height: AppSpacing.s2),
            HaynSegmentedPill<int>(
              value: _depth(caps),
              onChanged: onBitDepthChanged!,
              items: [
                HaynSegmentItem(value: 0, label: l.compressBitDepthMatch),
                HaynSegmentItem(value: 8, label: l.bitDepthBits(8)),
                if (_offersTenBit(caps))
                  HaynSegmentItem(value: 10, label: l.bitDepthBits(10)),
              ],
            ),
            if (sourceBitDepth != null &&
                _depth(caps) > 0 &&
                _depth(caps) > sourceBitDepth!) ...[
              const SizedBox(height: AppSpacing.s2),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: hc.warningColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.compressBitDepthHigher(sourceBitDepth!),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: hc.warningColor),
                    ),
                  ),
                ],
              ),
            ],
          ],

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

          // ── (Optional) keep-original-time toggle ────────────────────────
          if (keepOriginalTime != null && onKeepOriginalTimeChanged != null) ...[
            const Divider(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.compressKeepTime,
                          style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 2),
                      Text(
                        l.compressKeepTimeDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hc.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: keepOriginalTime!,
                  onChanged: onKeepOriginalTimeChanged,
                ),
              ],
            ),
          ],

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
