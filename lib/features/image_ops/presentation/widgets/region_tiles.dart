import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../data/region_image.dart';

// The detail layer of a zoomed image (PERF-03, docs/23-LARGE-IMAGES.md §4).
// From afar the caller's rendition shows the image at screen size. Zoomed
// past what that rendition holds, this layer, laid over it in the same box,
// asks [RegionImage] for the tiles in view only, at the coarsest level that
// still gives one image pixel per screen pixel. Tiles of other levels stay
// drawn under the new ones until those arrive, within a fixed cache; tiles
// that left the view before decoding are never decoded. Nothing here grows
// with the image: a 200 MP photo costs what a 12 MP one does.

/// Edge of a decoded tile, in its own pixels.
const int kRegionTileEdge = 512;

/// A tile of the plan: its place in the level's grid and its rectangle in
/// full-size upright pixels (right and bottom exclusive).
class PlannedTile {
  const PlannedTile(this.col, this.row, this.rect);
  final int col;
  final int row;
  final Rect rect;
}

/// The tiles that cover the view and the level they come at.
class TilePlan {
  const TilePlan(this.sample, this.tiles);

  /// Power of two the image is sampled down by.
  final int sample;

  /// Nearest the centre of the view first.
  final List<PlannedTile> tiles;
}

/// The plan for [visible] (logical pixels of the box the image fills, sized
/// [box]) seen at [screenPxPerLocal] physical pixels per logical one. Null
/// when the caller's rendition, [baseLongEdge] pixels on its long edge,
/// already holds that much detail.
TilePlan? planTiles({
  required Size image,
  required Size box,
  required Rect visible,
  required double screenPxPerLocal,
  required int baseLongEdge,
  int tileEdge = kRegionTileEdge,
}) {
  if (image.isEmpty || box.isEmpty || visible.isEmpty) return null;
  if (screenPxPerLocal <= 0) return null;
  final imagePxPerLocal = image.width / box.width;
  // Image pixels per screen pixel: the coarsest power of two at or under it
  // still gives each screen pixel its own image pixel.
  final ratio = imagePxPerLocal / screenPxPerLocal;
  var sample = 1;
  while (sample * 2 <= ratio) {
    sample *= 2;
  }
  if (math.max(image.width, image.height) / sample <= baseLongEdge) {
    return null;
  }
  final view = Rect.fromLTRB(
    visible.left * imagePxPerLocal,
    visible.top * imagePxPerLocal,
    visible.right * imagePxPerLocal,
    visible.bottom * imagePxPerLocal,
  ).intersect(Offset.zero & image);
  if (view.isEmpty) return null;
  final span = (tileEdge * sample).toDouble();
  final cols = (image.width / span).ceil();
  final rows = (image.height / span).ceil();
  final c0 = (view.left / span).floor().clamp(0, cols - 1);
  final c1 = ((view.right / span).ceil() - 1).clamp(0, cols - 1);
  final r0 = (view.top / span).floor().clamp(0, rows - 1);
  final r1 = ((view.bottom / span).ceil() - 1).clamp(0, rows - 1);
  final tiles = <PlannedTile>[
    for (var r = r0; r <= r1; r++)
      for (var c = c0; c <= c1; c++)
        PlannedTile(
          c,
          r,
          Rect.fromLTRB(
            c * span,
            r * span,
            math.min((c + 1) * span, image.width),
            math.min((r + 1) * span, image.height),
          ),
        ),
  ];
  final centre = view.center;
  tiles.sort(
    (a, b) => (a.rect.center - centre).distanceSquared.compareTo(
      (b.rect.center - centre).distanceSquared,
    ),
  );
  return TilePlan(sample, tiles);
}

typedef _Key = (int sample, int col, int row);

/// Draws the tiles of [region] in view over the caller's rendition. Place it
/// in the box the image fills (same aspect). [transform] notifies when the
/// zoom or pan changes; [viewportKey], when given, bounds the view to that
/// widget instead of the screen.
class RegionTiles extends StatefulWidget {
  const RegionTiles({
    required this.region,
    required this.transform,
    required this.baseLongEdge,
    this.viewportKey,
    this.maxTiles = 64,
    super.key,
  });

  final RegionImage region;
  final Listenable transform;
  final int baseLongEdge;
  final GlobalKey? viewportKey;

  /// Decoded tiles kept, about 1 MB each. Tiles in view are never dropped.
  final int maxTiles;

  @override
  State<RegionTiles> createState() => _RegionTilesState();
}

class _RegionTilesState extends State<RegionTiles> {
  /// Insertion order is use order: the first entries go first.
  final _cache = <_Key, (Rect, ui.Image)>{};

  /// The first key of each row in flight; [_rowLoading] all of its keys.
  final _loading = <_Key>{};
  final _rowLoading = <_Key, List<_Key>>{};
  final _failed = <_Key>{};
  final _queue = <(_Key, Rect)>[];
  var _wanted = <_Key>{};
  bool _scheduled = false;
  Size? _laidOut;

  static const _inFlight = 2;

  @override
  void initState() {
    super.initState();
    widget.transform.addListener(_schedule);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule(); // screen size or pixel ratio
  }

  @override
  void didUpdateWidget(RegionTiles old) {
    super.didUpdateWidget(old);
    if (old.transform != widget.transform) {
      old.transform.removeListener(_schedule);
      widget.transform.addListener(_schedule);
    }
    if (old.region != widget.region) {
      _clear();
      _loading.clear(); // their results are dropped on arrival
      _rowLoading.clear();
    }
    _schedule();
  }

  @override
  void dispose() {
    widget.transform.removeListener(_schedule);
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final (_, image) in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _failed.clear();
    _queue.clear();
    _wanted = {};
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _update();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// What is on screen now, in this box's coordinates, and the plan for it.
  void _update() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final toScreen = box.getTransformTo(null);
    final toLocal = Matrix4.tryInvert(toScreen);
    if (toLocal == null) return;
    final view = View.of(context);
    var screen =
        Offset.zero &
        (MediaQuery.maybeSizeOf(context) ??
            view.physicalSize / view.devicePixelRatio);
    final viewport = widget.viewportKey?.currentContext?.findRenderObject();
    if (viewport is RenderBox && viewport.attached && viewport.hasSize) {
      screen = screen.intersect(
        MatrixUtils.transformRect(
          viewport.getTransformTo(null),
          Offset.zero & viewport.size,
        ),
      );
    }
    final visible = MatrixUtils.transformRect(
      toLocal,
      screen,
    ).intersect(Offset.zero & box.size);
    final plan = visible.isEmpty
        ? null
        : planTiles(
            image: Size(
              widget.region.width.toDouble(),
              widget.region.height.toDouble(),
            ),
            box: box.size,
            visible: visible,
            screenPxPerLocal:
                toScreen.getMaxScaleOnAxis() *
                (MediaQuery.maybeDevicePixelRatioOf(context) ??
                    view.devicePixelRatio),
            baseLongEdge: widget.baseLongEdge,
          );
    if (plan == null) {
      // The rendition shows it all: give the memory back.
      if (_cache.isNotEmpty || _wanted.isNotEmpty) setState(_clear);
      return;
    }
    _wanted = {for (final t in plan.tiles) (plan.sample, t.col, t.row)};
    _queue.clear();
    for (final t in plan.tiles) {
      final key = (plan.sample, t.col, t.row);
      final cached = _cache.remove(key);
      if (cached != null) {
        _cache[key] = cached; // most recently used
      } else if (!_isLoading(key) && !_failed.contains(key)) {
        _queue.add((key, t.rect));
      }
    }
    _pump();
    setState(() {});
  }

  /// Decodes the queue a row at a time: the first tile wanted and the other
  /// wanted tiles of its row, in one call (see [RegionImage.tiles]).
  void _pump() {
    while (_loading.length < _inFlight && _queue.isNotEmpty) {
      final (first, _) = _queue.first;
      final row = [
        for (final item in _queue)
          if (item.$1.$1 == first.$1 && item.$1.$3 == first.$3) item,
      ]..sort((a, b) => a.$1.$2.compareTo(b.$1.$2));
      _queue.removeWhere((item) => row.contains(item));
      // The view is a rectangle, so a row's wanted tiles are contiguous.
      row.removeWhere((item) => !_wanted.contains(item.$1));
      if (row.isEmpty) continue;
      final keys = [for (final item in row) item.$1];
      _loading.add(first);
      _rowLoading[first] = keys;
      final region = widget.region;
      final rects = [for (final item in row) item.$2];
      region
          .tiles(
            Rect.fromLTRB(
              rects.first.left,
              rects.first.top,
              rects.last.right,
              rects.first.bottom,
            ),
            [for (final r in rects.skip(1)) r.left],
            first.$1,
          )
          .then((images) {
            _loading.remove(first);
            _rowLoading.remove(first);
            // Dropped when the image changed or the rendition took over again.
            if (!mounted ||
                region != widget.region ||
                _wanted.isEmpty ||
                images == null ||
                images.length != keys.length) {
              for (final image in images ?? const <ui.Image>[]) {
                image.dispose();
              }
              if (mounted && region == widget.region && images == null) {
                _failed.addAll(keys); // not asked again for this image
              }
              if (mounted) _pump();
              return;
            }
            for (var i = 0; i < keys.length; i++) {
              _cache.remove(keys[i])?.$2.dispose();
              _cache[keys[i]] = (rects[i], images[i]);
            }
            _evict();
            setState(() {});
            _pump();
          });
    }
  }

  bool _isLoading(_Key key) => _rowLoading.values.any((k) => k.contains(key));

  void _evict() {
    for (final key in _cache.keys.toList()) {
      if (_cache.length <= widget.maxTiles) return;
      if (_wanted.contains(key)) continue;
      _cache.remove(key)!.$2.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _laidOut) {
          _laidOut = size;
          _schedule();
        }
        final scale = size.width / widget.region.width;
        // Coarse levels first, so finer tiles land on top of them.
        final keys = _cache.keys.toList()..sort((a, b) => b.$1.compareTo(a.$1));
        final draws = [
          for (final key in keys)
            (_scaled(_cache[key]!.$1, scale), _cache[key]!.$2),
        ];
        return CustomPaint(size: size, painter: _TilesPainter(draws));
      },
    );
  }

  static Rect _scaled(Rect r, double s) =>
      Rect.fromLTRB(r.left * s, r.top * s, r.right * s, r.bottom * s);
}

class _TilesPainter extends CustomPainter {
  _TilesPainter(this.draws);
  final List<(Rect, ui.Image)> draws;

  // Tiles share exact edges; anti-aliasing them would show the seams.
  static final _paint = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = false;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (dst, image) in draws) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        dst,
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TilesPainter old) => true;
}
