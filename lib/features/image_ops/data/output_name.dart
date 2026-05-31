import 'package:photo_manager/photo_manager.dart';

/// Builds a safe gallery filename from a source asset.
///
/// iOS [AssetEntity.title] is frequently EMPTY (not just null), which produced
/// names like ".avif" — the base vanished. So we use [AssetEntity.titleAsync]
/// (the real filename), strip any path + old extension, fall back to a
/// timestamped IMG_ name when there's nothing usable, and append an optional
/// suffix before the new extension. e.g. `IMG_1234` + heic/"clean" →
/// `IMG_1234_clean.heic`.
Future<String> outputFilename(
  AssetEntity entity,
  String ext, {
  String suffix = '',
}) async {
  var base = (await entity.titleAsync).trim();
  final slash = base.lastIndexOf('/');
  if (slash >= 0) base = base.substring(slash + 1);
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  if (base.isEmpty) {
    base = 'IMG_${DateTime.now().millisecondsSinceEpoch}';
  }
  return suffix.isEmpty ? '$base.$ext' : '${base}_$suffix.$ext';
}
