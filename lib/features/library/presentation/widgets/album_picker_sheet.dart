import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AlbumPickerSheet — full-height sheet for switching between albums. Used
// when the inline album strip isn't enough (many albums). Returns the chosen
// album id (null = "All").
// ─────────────────────────────────────────────────────────────────────────────

Future<String?> showAlbumPicker({
  required BuildContext context,
  required List<AssetPathEntity> albums,
  required String? currentId,
}) {
  return showHaynSheet<String?>(
    context: context,
    isScrollControlled: true,
    builder: (_) => AlbumPickerSheet(albums: albums, currentId: currentId),
  );
}

class AlbumPickerSheet extends StatefulWidget {
  const AlbumPickerSheet({
    required this.albums,
    required this.currentId,
    super.key,
  });

  final List<AssetPathEntity> albums;
  final String? currentId;

  @override
  State<AlbumPickerSheet> createState() => _AlbumPickerSheetState();
}

class _AlbumPickerSheetState extends State<AlbumPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;

    // First entry = virtual "All"
    final filtered = <_AlbumRow>[
      _AlbumRow(id: null, name: l.filterAll, path: null),
      for (var i = 1; i < widget.albums.length; i++)
        _AlbumRow(
          id: widget.albums[i].id,
          name: widget.albums[i].name,
          path: widget.albums[i],
        ),
    ].where((row) {
      if (_query.isEmpty) return true;
      return row.name.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(
        child: Column(
          children: [
            HaynSheetHeader(title: l.libraryAlbumsTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, 0, AppSpacing.md, AppSpacing.s3,
              ),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: l.librarySearchAlbums,
                  prefixIcon: Icon(Icons.search_rounded, color: hc.text3),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? HaynEmptyState(
                      icon: Icons.search_off_rounded,
                      title: l.libraryEmptyTitle,
                      message: l.libraryEmptyMessage,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: hc.border, height: 1, thickness: 0.5),
                      itemBuilder: (ctx, i) {
                        final row = filtered[i];
                        return _AlbumRowWidget(
                          row: row,
                          selected: row.id == widget.currentId,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.of(ctx).pop(row.id);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumRow {
  const _AlbumRow({required this.id, required this.name, required this.path});
  final String? id;
  final String name;
  final AssetPathEntity? path;
}

class _AlbumRowWidget extends StatefulWidget {
  const _AlbumRowWidget({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final _AlbumRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AlbumRowWidget> createState() => _AlbumRowWidgetState();
}

class _AlbumRowWidgetState extends State<_AlbumRowWidget> {
  Uint8List? _thumb;
  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = widget.row.path;
    if (path == null) {
      // Virtual "All": skip thumbnail
      return;
    }
    final count = await path.assetCountAsync;
    final list = count > 0
        ? await path.getAssetListRange(start: 0, end: 1)
        : <AssetEntity>[];
    Uint8List? thumb;
    if (list.isNotEmpty) {
      thumb = await list.first.thumbnailDataWithSize(
        const ThumbnailSize.square(160),
      );
    }
    if (mounted) {
      setState(() {
        _thumb = thumb;
        _count = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final isAll = widget.row.path == null;

    return InkWell(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: hc.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              clipBehavior: Clip.antiAlias,
              child: isAll
                  ? Icon(Icons.photo_library_rounded, color: hc.text2, size: 22)
                  : _thumb == null
                      ? null
                      : Image.memory(_thumb!,
                          fit: BoxFit.cover, gaplessPlayback: true),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.row.name,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_count != null)
                    Text(
                      '$_count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: hc.text2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
            if (widget.selected)
              Icon(Icons.check_rounded, color: hc.accent, size: 22),
          ],
        ),
      ),
    );
  }
}
