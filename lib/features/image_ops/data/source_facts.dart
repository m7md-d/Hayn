import 'dart:typed_data';

import '../../../core/darklib/darklib.dart';
import '../domain/image_format_policy.dart';
import 'image_probe.dart';
import 'native_image_info.dart';

// Facts about the ORIGINAL source, gathered once before any engine runs, so a
// platform encoder can never succeed on bytes the plan would refuse (IMG-05).
// Every field is tri-state: null = unknown, never a guessed false.

class SourceFacts {
  const SourceFacts({
    required this.alpha,
    required this.directHdr,
    required this.gainMap,
    this.width,
    this.height,
  });

  /// Pixels this app produced itself in SDR (crop output, an SDR rendition).
  const SourceFacts.sdr({required this.alpha, this.width, this.height})
    : directHdr = false,
      gainMap = false;

  /// Transparency present (true), confirmed absent (false) or unknown (null).
  final bool? alpha;

  /// PQ/HLG primary image: only a tone mapper turns it into a correct SDR image.
  final bool? directHdr;

  /// An HDR gain map next to the base image.
  final bool? gainMap;

  /// Stored size from the header, before orientation; null when unknown.
  final int? width;
  final int? height;

  bool get hasHdr => directHdr == true || gainMap == true;

  /// Over the giant threshold: JPEG and HEIC only (RUN-01). Unknown size is
  /// not giant.
  bool get giant => ImageFormatPolicy.isGiant(width: width, height: height);
}

abstract final class SourceInspector {
  /// DarkLib reads the container; ImageIO (iOS) adds what it decodes. Either
  /// one reporting HDR wins, so a missing probe can only leave a fact unknown.
  static Future<SourceFacts> inspect(Uint8List bytes) async {
    final alpha = await ImageProbe.hasAlpha(bytes);
    final container = await DarkLibCore.inspect(bytes);
    final native = await NativeImageProbe.probeHdr(bytes);
    return SourceFacts(
      alpha: alpha,
      width: (container?.width ?? 0) > 0 ? container!.width : null,
      height: (container?.height ?? 0) > 0 ? container!.height : null,
      directHdr: _merge(switch (container?.transfer) {
        Transfer.pq || Transfer.hlg => true,
        Transfer.noHdrSignal => false,
        Transfer.unknown || null => null,
      }, native?.hdrTransfer),
      gainMap: _merge(switch (container?.gainMap) {
        Presence.present => true,
        Presence.absent => false,
        Presence.unknown || null => null,
      }, native?.gainMap),
    );
  }

  static bool? _merge(bool? a, bool? b) {
    if (a == true || b == true) return true;
    if (a == false || b == false) return false;
    return null;
  }
}
