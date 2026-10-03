import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// The viewer swaps in the original when the user zooms. Decoding it whole
// costs its full pixel count: a 200 MP photo took 3.3 s and 748 MB on a
// Galaxy S25 Edge, past many GPUs' texture limit (RUN-01). Bounded to
// [kFullResMaxEdge], a JPEG decodes already scaled (DCT scaling): a 48 MP
// photo stays whole, a 200 MP one shows at half size in about a second.
// Transitional: Android reads the original by tiles instead (RegionTiles,
// PERF-03). This stays for what has no region decoder yet, iOS (M-07) and
// AVIF on Android, and goes once they have one.

/// Longest edge the viewer decodes the original at.
const int kFullResMaxEdge = 8192;

/// The original's bytes for the zoomed viewer, decoded within
/// [kFullResMaxEdge] on either side and never upscaled.
ImageProvider fullResImage(Uint8List bytes) =>
    boundedImage(bytes, kFullResMaxEdge);

/// [bytes] decoded within [maxEdge] on either side, never upscaled.
ImageProvider boundedImage(Uint8List bytes, int maxEdge) => ResizeImage(
  MemoryImage(bytes),
  width: maxEdge,
  height: maxEdge,
  policy: ResizeImagePolicy.fit,
);
