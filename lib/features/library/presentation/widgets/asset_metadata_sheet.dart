import 'dart:io';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AssetMetadataSheet — read-only details shown from the (i) action in the Asset
// Detail app bar.
//
// Two tiers, basics first then "the nerdy bits" further down (the user scrolls
// to them): a clean header section everyone cares about (format, dimensions,
// size, duration, location) and a Technical section for stills (resolution in
// MP + the camera/lens/exposure pulled from EXIF). The media KIND (photo/video)
// is intentionally NOT a row — the header icon already says it.
// ─────────────────────────────────────────────────────────────────────────────

class AssetMetadataSheet extends StatefulWidget {
  const AssetMetadataSheet({required this.asset, super.key});
  final AssetEntity asset;

  @override
  State<AssetMetadataSheet> createState() => _AssetMetadataSheetState();
}

class _AssetMetadataSheetState extends State<AssetMetadataSheet> {
  late Future<_FileFacts> _facts;

  @override
  void initState() {
    super.initState();
    _facts = _loadFacts();
  }

  Future<_FileFacts> _loadFacts() async {
    final asset = widget.asset;
    final file = await asset.file;
    final title = await asset.titleAsync;
    int? size;
    if (file != null && await file.exists()) {
      size = await file.length();
    }

    // EXIF (stills only) — camera, lens, exposure. Defensive: any failure just
    // means the Technical section stays minimal.
    _Exif? exifFacts;
    if (asset.type == AssetType.image && file != null) {
      exifFacts = await _readExif(file);
    }

    return _FileFacts(
      filename: title,
      sizeBytes: size,
      format: _formatLabel(title, asset.title),
      exif: exifFacts,
    );
  }

  Future<_Exif?> _readExif(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) return null;

      Ratio? ratio(String key) {
        final v = tags[key]?.values.toList();
        if (v != null && v.isNotEmpty && v.first is Ratio) {
          return v.first as Ratio;
        }
        return null;
      }

      final make = tags['Image Make']?.printable.trim();
      final model = tags['Image Model']?.printable.trim();
      final camera = [make, model]
          .where((s) => s != null && s.isNotEmpty)
          .join(' ')
          .trim();

      // Exposure line: ƒ2.8 · 1/120s · 26mm — only the parts that exist.
      final parts = <String>[];
      final fnum = ratio('EXIF FNumber')?.toDouble();
      if (fnum != null && fnum > 0) parts.add('ƒ${_trim(fnum)}');
      final shutter = tags['EXIF ExposureTime']?.printable.trim();
      if (shutter != null && shutter.isNotEmpty) parts.add('${shutter}s');
      final focal = ratio('EXIF FocalLength')?.toDouble();
      if (focal != null && focal > 0) parts.add('${focal.round()}mm');

      return _Exif(
        camera: camera.isEmpty ? null : camera,
        lens: tags['EXIF LensModel']?.printable.trim(),
        exposure: parts.isEmpty ? null : parts.join(' · '),
        iso: tags['EXIF ISOSpeedRatings']?.printable.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  // Hand off to the device's maps app at the photo's coordinates. This is a
  // user-initiated OS handoff (the app makes no network call itself); the maps
  // app is local. iOS opens Apple Maps; Android uses the geo: scheme.
  Future<void> _openMaps(double lat, double lng) async {
    final uri = Platform.isIOS
        ? Uri.parse('https://maps.apple.com/?ll=$lat,$lng&q=$lat,$lng')
        : Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No maps handler / not permitted — silently ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final l = AppLocalizations.of(context);
    final asset = widget.asset;
    final isVideo = asset.type == AssetType.video;
    final mp = (asset.width * asset.height) / 1e6;

    return SafeArea(
      child: FutureBuilder<_FileFacts>(
        future: _facts,
        builder: (ctx, snap) {
          final facts = snap.data;
          final exif = facts?.exif;
          final hasLocation = asset.latitude != null &&
              asset.longitude != null &&
              asset.latitude != 0 &&
              asset.longitude != 0;

          // Bit rate (video) — derived from size + duration; a real technical
          // fact without needing to probe codecs.
          final durSecs = asset.videoDuration.inSeconds;
          String? bitrate;
          if (isVideo && durSecs > 0 && (facts?.sizeBytes ?? 0) > 0) {
            final mbps = (facts!.sizeBytes! * 8) / durSecs / 1e6;
            bitrate = '${mbps.toStringAsFixed(mbps >= 10 ? 0 : 1)} Mbps';
          }

          // Technical section: resolution + EXIF (stills) or bit rate (video).
          final technical = <Widget>[
            if (mp >= 0.1)
              _MetaRow(
                icon: Icons.high_quality_outlined,
                label: l.metaMegapixels,
                value: '${_trim(mp)} MP',
              ),
            if (bitrate != null)
              _MetaRow(
                icon: Icons.speed_rounded,
                label: l.metaBitrate,
                value: bitrate,
              ),
            if (exif?.camera != null)
              _MetaRow(
                icon: Icons.photo_camera_outlined,
                label: l.metaCamera,
                value: exif!.camera!,
              ),
            if (exif?.lens != null && exif!.lens!.isNotEmpty)
              _MetaRow(
                icon: Icons.center_focus_weak_outlined,
                label: l.metaLens,
                value: exif.lens!,
              ),
            if (exif?.exposure != null)
              _MetaRow(
                icon: Icons.shutter_speed_outlined,
                label: l.metaExposure,
                value: exif!.exposure!,
              ),
            if (exif?.iso != null && exif!.iso!.isNotEmpty)
              _MetaRow(
                icon: Icons.iso_outlined,
                label: l.metaIso,
                value: exif.iso!,
              ),
          ];

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HaynSheetHeader(
                    title: facts?.filename ?? asset.id,
                    subtitle: _formatDate(asset.createDateTime,
                        Localizations.localeOf(context).languageCode),
                  ),

                  // ── Basics ───────────────────────────────────────────────
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: HaynListSection(
                      children: [
                        if (facts?.format != null)
                          _MetaRow(
                            icon: Icons.image_outlined,
                            label: l.metaFormat,
                            value: facts!.format!,
                          ),
                        _MetaRow(
                          icon: Icons.aspect_ratio_rounded,
                          label: l.metaDimensions,
                          value: '${asset.width} × ${asset.height}',
                        ),
                        if (facts?.sizeBytes != null)
                          _MetaRow(
                            icon: Icons.sd_storage_outlined,
                            label: l.metaSize,
                            value: _formatBytes(facts!.sizeBytes!),
                          ),
                        if (isVideo)
                          _MetaRow(
                            icon: Icons.schedule_rounded,
                            label: l.metaDuration,
                            value: _formatDuration(asset.videoDuration),
                          ),
                        if (hasLocation)
                          _MetaRow(
                            icon: Icons.location_on_outlined,
                            label: l.metaLocation,
                            value:
                                '${asset.latitude!.toStringAsFixed(4)}, ${asset.longitude!.toStringAsFixed(4)}',
                            onTap: () =>
                                _openMaps(asset.latitude!, asset.longitude!),
                          ),
                      ],
                    ),
                  ),

                  // ── Technical (nerdy bits, scrolled to) ──────────────────
                  if (technical.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                          AppSpacing.md, AppSpacing.md, AppSpacing.s2),
                      child: Text(
                        l.metaTechnical,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: hc.text3),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md),
                      child: HaynListSection(children: technical),
                    ),
                  ],

                  if (snap.connectionState == ConnectionState.waiting)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: hc.accent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Formatters ──────────────────────────────────────────────────────────

  /// Uppercased file extension (HEIC, JPG, MOV…), falling back to nothing.
  static String? _formatLabel(String? titleAsync, String? title) {
    final name = (titleAsync?.isNotEmpty ?? false) ? titleAsync! : (title ?? '');
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      return name.substring(dot + 1).toUpperCase();
    }
    return null;
  }

  /// Trim a double to at most one decimal, dropping a trailing ".0".
  static String _trim(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  static String _formatDate(DateTime d, String locale) {
    return DateFormat.yMMMd(locale).add_Hm().format(d);
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _FileFacts {
  const _FileFacts({this.filename, this.sizeBytes, this.format, this.exif});
  final String? filename;
  final int? sizeBytes;
  final String? format;
  final _Exif? exif;
}

class _Exif {
  const _Exif({this.camera, this.lens, this.exposure, this.iso});
  final String? camera;
  final String? lens;
  final String? exposure;
  final String? iso;
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;

  /// When set the row is tappable (e.g. location → maps) and shows an accent
  /// value + a chevron.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final tappable = onTap != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.s3,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tappable ? hc.accent : hc.text2),
          const SizedBox(width: AppSpacing.s3),
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tappable ? hc.accent : hc.text2,
                fontWeight: tappable ? FontWeight.w600 : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (tappable) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 18, color: hc.accent),
          ],
        ],
      ),
    );
    if (!tappable) return row;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: row,
    );
  }
}
