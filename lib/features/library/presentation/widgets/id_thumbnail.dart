import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/asset_entity_cache.dart';
import '../providers/thumbnail_cache.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IdThumbnail — paints a media thumbnail for an asset id WITHOUT being handed
// an AssetEntity. It materialises the entity lazily (AssetEntityCache) only
// when it's actually on screen, then loads the thumbnail bytes through the
// shared, bounded ThumbnailCache. Both steps are cancellable, so a fast fling
// past thousands of cells never floods the platform bridge or holds entities
// the user already scrolled past.
//
// This is the single rendering primitive behind the virtualized library grid,
// the detail filmstrip, and the batch/preview grids in the tool screens — none
// of them keep a list of AssetEntities in memory anymore.
// ─────────────────────────────────────────────────────────────────────────────

class IdThumbnail extends StatefulWidget {
  const IdThumbnail({
    required this.id,
    this.fit = BoxFit.cover,
    this.placeholderColor,
    super.key,
  });

  final String id;
  final BoxFit fit;
  final Color? placeholderColor;

  @override
  State<IdThumbnail> createState() => _IdThumbnailState();
}

class _IdThumbnailState extends State<IdThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(IdThumbnail old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _bytes = ThumbnailCache.get(widget.id);
      if (_bytes == null) _resolve();
    }
  }

  Future<void> _resolve() async {
    final id = widget.id;
    final cached = ThumbnailCache.get(id);
    if (cached != null) {
      _bytes = cached;
      return;
    }
    bool stale() => !mounted || widget.id != id;
    final entity = await AssetEntityCache.load(id, cancelled: stale);
    if (entity == null || stale()) return;
    final data = await ThumbnailCache.load(entity, cancelled: stale);
    if (data == null || stale()) return;
    setState(() => _bytes = data);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return ColoredBox(
        color: widget.placeholderColor ?? const Color(0x14000000),
      );
    }
    return Image.memory(
      bytes,
      fit: widget.fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}
