import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AssetMetadataSheet — read-only details panel shown from the (i) action in
// the Asset Detail app bar. Reads sync properties from AssetEntity and async
// file size from the underlying file.
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
    final file = await widget.asset.file;
    final title = await widget.asset.titleAsync;
    int? size;
    if (file != null && await file.exists()) {
      size = await file.length();
    }
    return _FileFacts(filename: title, sizeBytes: size, file: file);
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final l = AppLocalizations.of(context);
    final asset = widget.asset;

    return SafeArea(
      child: FutureBuilder<_FileFacts>(
        future: _facts,
        builder: (ctx, snap) {
          final facts = snap.data;
          return Padding(
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md),
                  child: HaynListSection(
                    children: [
                      _MetaRow(
                        icon: asset.type == AssetType.video
                            ? Icons.movie_outlined
                            : Icons.photo_outlined,
                        label: l.selectionInfo,
                        value: asset.type == AssetType.video
                            ? l.filterVideos
                            : l.filterPhotos,
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
                      if (asset.type == AssetType.video)
                        _MetaRow(
                          icon: Icons.schedule_rounded,
                          label: l.metaDuration,
                          value: _formatDuration(asset.videoDuration),
                        ),
                      if (asset.latitude != null &&
                          asset.longitude != null &&
                          asset.latitude != 0 &&
                          asset.longitude != 0)
                        _MetaRow(
                          icon: Icons.location_on_outlined,
                          label: l.metaLocation,
                          value:
                              '${asset.latitude!.toStringAsFixed(4)}, ${asset.longitude!.toStringAsFixed(4)}',
                        ),
                    ],
                  ),
                ),
                if (snap.connectionState == ConnectionState.waiting)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Center(
                      child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: hc.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Formatters ──────────────────────────────────────────────────────────

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
  const _FileFacts({this.filename, this.sizeBytes, this.file});
  final String? filename;
  final int? sizeBytes;
  final File? file;
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, vertical: AppSpacing.s3,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: hc.text2),
          const SizedBox(width: AppSpacing.s3),
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: hc.text2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
