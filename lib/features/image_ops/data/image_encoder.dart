import 'dart:typed_data';

import '../../../core/diagnostics/media_diagnostics.dart';

import 'package:flutter_avif/flutter_avif.dart' as avif;
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;

import '../../../core/darklib/darklib.dart';
import '../../settings/providers/preferences_providers.dart';
import '../../../core/isolates/heavy_work.dart';
import 'alpha_flatten.dart';
import 'native_avif_encoder.dart';
import 'native_image_encoder.dart';
import 'image_probe.dart';
import 'source_facts.dart';

// Coordinates the existing backends from facts about the ORIGINAL source, read
// before any engine runs (IMG-05). HDR policy (user decision, 2026-09-28): keep
// HDR where the path exists, otherwise save a correct SDR rendition without
// asking; PQ/HLG needs the platform tone mapper or is refused. JPEG for a
// transparent source composites it onto white (user decision, 2026-09-29).
// Non-empty output
// is NOT proof that colour, orientation or metadata survived. Backend, format
// and HDR outcomes are recorded in bounded release diagnostics.

class EncodedImage {
  const EncodedImage(
    this.bytes,
    this.format, {
    this.backend,
    this.requestedFormat,
    this.diagnostics = const [],
    this.hdr,
  });

  final MediaBackend? backend;

  /// What DarkLib reported about a gain map; null for other engines.
  final HdrOutcome? hdr;
  final DefaultFormat? requestedFormat;
  final List<MediaDiagnostic> diagnostics;

  final Uint8List bytes;

  /// The format actually produced — may differ from the request if a fallback
  /// kicked in (surface this to the user).
  final DefaultFormat format;

  String get extension => switch (format) {
    DefaultFormat.avif => 'avif',
    DefaultFormat.heic => 'heic',
    DefaultFormat.webp => 'webp',
    DefaultFormat.png => 'png',
    DefaultFormat.jpeg => 'jpg',
    DefaultFormat.auto => 'jpg',
  };
}

abstract final class ImageEncoder {
  /// Encode [source] to [target] at [quality] (0–100). On encoder failure walks
  /// [fallbackChain]. Returns the bytes + the format actually produced. Throws
  /// if all permitted encoders fail. Format changes require explicit permission;
  /// backend recovery within the requested format remains allowed. A preservation
  /// rejection is terminal. Diagnostics accompany success or failure. What the
  /// chosen format cannot hold (alpha in JPEG, HDR) is dropped without asking.
  ///
  /// Runs through [HeavyWork] (RUN-02) with [memoryEstimate]: it waits its
  /// turn, fails with `insufficientMemory` when it can never fit, and throws
  /// [HeavyWorkWithdrawn] when [ticket] is withdrawn before it starts.
  static Future<EncodedImage> encode({
    required Uint8List source,
    required DefaultFormat target,
    required int quality,
    required SourceFacts facts,
    required bool keepMetadata,
    bool allowFormatFallback = false,
    bool keepOriginalTime = true,
    int bitDepth = 0,
    int? maxWidth,
    int? maxHeight,
    HeavyWorkTicket? ticket,
  }) => MediaDiagnostics.trace((trace) async {
    if (target == DefaultFormat.auto) {
      // Auto must be resolved by ImageFormatPolicy before encoding.
      MediaDiagnostics.record(
        MediaBackend.imageEncoder,
        MediaOperation.encode,
        MediaDiagnosticCode.preservationRejected,
      );
      throw ImageEncodingFailure(target, trace.events);
    }
    try {
      return await HeavyWork.instance.run(
        estimateBytes: memoryEstimate(facts, target, source.length),
        ticket: ticket,
        body: () => _admitted(
          trace: trace,
          source: source,
          target: target,
          quality: quality,
          facts: facts,
          keepMetadata: keepMetadata,
          allowFormatFallback: allowFormatFallback,
          keepOriginalTime: keepOriginalTime,
          bitDepth: bitDepth,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
      );
    } on InsufficientMemory {
      MediaDiagnostics.record(
        MediaBackend.imageEncoder,
        MediaOperation.encode,
        MediaDiagnosticCode.insufficientMemory,
      );
      throw ImageEncodingFailure(target, trace.events);
    }
  });

  static Future<EncodedImage> _admitted({
    required MediaDiagnosticTrace trace,
    required Uint8List source,
    required DefaultFormat target,
    required int quality,
    required SourceFacts facts,
    required bool keepMetadata,
    required bool allowFormatFallback,
    required bool keepOriginalTime,
    required int bitDepth,
    required int? maxWidth,
    required int? maxHeight,
  }) async {
    // PQ/HLG samples read as sRGB are a wrong image, so no engine receives the
    // original: only ImageIO's tone-mapped SDR rendition may continue (the
    // Android bridge has no verified tone mapper and declines).
    var input = source;
    var plan = facts;
    if (facts.directHdr == true) {
      final sdr = await NativeImageEncoder.bakeUpright(
        source: source,
        keepMetadata: keepMetadata,
        keepOriginalTime: keepOriginalTime,
        toSdr: true,
      );
      if (sdr == null) {
        MediaDiagnostics.record(
          MediaBackend.imageEncoder,
          MediaOperation.encode,
          MediaDiagnosticCode.hdrToneMapUnavailable,
        );
        throw ImageEncodingFailure(target, trace.events);
      }
      MediaDiagnostics.record(
        NativeImageEncoder.bakeBackend,
        MediaOperation.bake,
        MediaDiagnosticCode.hdrToSdr,
      );
      input = sdr;
      // The rendition keeps the size: a giant source stays giant.
      plan = SourceFacts.sdr(
        alpha: facts.alpha,
        width: facts.width,
        height: facts.height,
      );
    } else if (facts.directHdr == null || facts.gainMap == null) {
      MediaDiagnostics.record(
        MediaBackend.imageEncoder,
        MediaOperation.probe,
        MediaDiagnosticCode.hdrUnverified,
      );
    }

    // JPEG cannot hold alpha: flatten onto white first, the same on every
    // platform. Metadata is carried over from the original afterwards.
    var flattened = false;
    if (target == DefaultFormat.jpeg && plan.alpha != false) {
      Uint8List? flat;
      try {
        flat = await AlphaFlatten.toOpaquePng(
          input,
          toSdr: plan.hasHdr,
          alpha: plan.alpha,
        );
      } on DarkLibPreservationFailure {
        flat = null;
      }
      if (flat == null) {
        MediaDiagnostics.record(
          MediaBackend.imageEncoder,
          MediaOperation.encode,
          MediaDiagnosticCode.unavailable,
        );
        throw ImageEncodingFailure(target, trace.events);
      }
      MediaDiagnostics.record(
        MediaBackend.imageEncoder,
        MediaOperation.encode,
        MediaDiagnosticCode.alphaFlattened,
      );
      if (plan.gainMap == true) {
        MediaDiagnostics.record(
          MediaBackend.imageEncoder,
          MediaOperation.encode,
          MediaDiagnosticCode.hdrToSdr,
        );
      }
      input = flat;
      plan = const SourceFacts.sdr(alpha: false);
      flattened = true;
    }
    final hasAlpha = plan.alpha;

    final candidates = allowFormatFallback
        ? fallbackChain(target, hasAlpha, giant: facts.giant)
        : [target];
    for (final fmt in candidates) {
      if (fmt != target) {
        MediaDiagnostics.record(
          MediaBackend.imageEncoder,
          MediaOperation.encode,
          MediaDiagnosticCode.formatFallback,
        );
      }
      EncodedImage? encoded;
      try {
        encoded = await _tryEncode(
          source: input,
          format: fmt,
          quality: quality,
          facts: plan,
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
          bitDepth: bitDepth,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        );
      } on DarkLibPreservationFailure {
        // Retrying another codec must not turn a preservation veto into success.
        throw ImageEncodingFailure(target, trace.events);
      }
      if (encoded != null) {
        if (!_matchesFormat(encoded.bytes, fmt)) {
          MediaDiagnostics.record(
            encoded.backend ?? MediaBackend.imageEncoder,
            MediaOperation.encode,
            MediaDiagnosticCode.outputFormatMismatch,
          );
          continue;
        }
        if (hasAlpha == true) {
          // Alpha values, not channel presence: a platform decode can return
          // a channel that is opaque everywhere (IMG-15).
          if (!await ImageProbe.keepsAlpha(
            source: input,
            output: encoded.bytes,
            backend: encoded.backend ?? MediaBackend.imageEncoder,
          )) {
            continue;
          }
        } else if (hasAlpha == null) {
          MediaDiagnostics.record(
            MediaBackend.imageEncoder,
            MediaOperation.probe,
            MediaDiagnosticCode.alphaUnverified,
          );
        }
        if (plan.gainMap == true) await _recordGainMap(encoded);
        var bytes = encoded.bytes;
        // The flattened PNG came out of package:image with no profile at all:
        // carry the original's back, the colour profile even without metadata.
        if (flattened) {
          final carried = await carryMetadata(
            source,
            bytes,
            keepMetadata: keepMetadata,
          );
          if (carried == null) {
            MediaDiagnostics.record(
              MediaBackend.darklib,
              MediaOperation.transplant,
              MediaDiagnosticCode.preservationUnverified,
            );
          } else {
            bytes = carried;
          }
        }
        return EncodedImage(
          bytes,
          encoded.format,
          backend: encoded.backend,
          requestedFormat: target,
          diagnostics: trace.events,
          hdr: encoded.hdr,
        );
      }
    }
    throw ImageEncodingFailure(target, trace.events);
  }

  /// Peak memory an encode of [facts]' image into [target] needs, for
  /// [HeavyWork]: bytes per pixel above what the app held before, measured on
  /// a 195 MP source on the Galaxy S25 Edge (2026-10-09, docs/18-PERFORMANCE.md:
  /// HEIC 0.6, PNG 5.7, JPEG 6.8, AVIF 7.2, WebP 17 where it failed) and
  /// rounded up, plus twice the source bytes (Dart's copy and the
  /// platform's). HEIC goes in bands (RUN-01), the rest decode whole. Unknown
  /// size: 0, so only the count limits it.
  static int memoryEstimate(
    SourceFacts facts,
    DefaultFormat target,
    int sourceBytes,
  ) {
    final w = facts.width, h = facts.height;
    if (w == null || h == null) return 0;
    final perPixel = switch (target) {
      DefaultFormat.heic => 1,
      DefaultFormat.jpeg => 9,
      DefaultFormat.avif => 8,
      DefaultFormat.png => 9,
      DefaultFormat.webp || DefaultFormat.auto => 17,
    };
    return w * h * perPixel + 2 * sourceBytes;
  }

  /// Ordered formats to attempt: requested first, then alpha-aware fallbacks.
  /// PNG is the final alpha-capable candidate; JPEG is opaque. An
  /// alpha image never lists JPEG. A [giant] source falls back only within
  /// JPEG, HEIC and, for alpha, PNG (RUN-01): software WebP and AVIF take
  /// minutes at 200 MP. Pure + unit-testable.
  static List<DefaultFormat> fallbackChain(
    DefaultFormat target,
    bool? hasAlpha, {
    bool giant = false,
  }) {
    final out = <DefaultFormat>[];
    void add(DefaultFormat f) {
      if (f == DefaultFormat.auto) return;
      if (hasAlpha != false && f == DefaultFormat.jpeg) {
        return; // never flatten on fallback
      }
      if (giant &&
          out.isNotEmpty &&
          (f == DefaultFormat.webp || f == DefaultFormat.avif)) {
        return;
      }
      if (!out.contains(f)) out.add(f);
    }

    add(target);
    add(DefaultFormat.webp); // mid fallback (cheap, wide support on Android)
    if (hasAlpha != false) {
      add(DefaultFormat.png); // alpha-safe floor, always available
    } else {
      add(DefaultFormat.jpeg); // opaque floor, always available
      add(DefaultFormat.png); // last resort
    }
    return out;
  }

  /// Gain-map sources: DarkLib reports the outcome; for other engines read
  /// the output back. Presence is not proof its meaning survived (IMG-10).
  static Future<void> _recordGainMap(EncodedImage out) async {
    final outcome = out.hdr;
    if (outcome == HdrOutcome.gainMapKept) return;
    if (outcome == HdrOutcome.gainMapKeepFailed) {
      MediaDiagnostics.record(
        MediaBackend.darklib,
        MediaOperation.encode,
        MediaDiagnosticCode.hdrKeepFailed,
      );
    }
    final after = outcome == null || outcome == HdrOutcome.none
        ? (await DarkLibCore.inspect(out.bytes))?.gainMap
        : Presence.absent;
    if (after == Presence.present) return;
    MediaDiagnostics.record(
      out.backend ?? MediaBackend.imageEncoder,
      MediaOperation.encode,
      after == Presence.absent
          ? MediaDiagnosticCode.hdrToSdr
          : MediaDiagnosticCode.hdrUnverified,
    );
  }

  static Future<EncodedImage?> _tryEncode({
    required Uint8List source,
    required DefaultFormat format,
    required int quality,
    required SourceFacts facts,
    required bool keepMetadata,
    bool keepOriginalTime = true,
    int bitDepth = 0,
    int? maxWidth,
    int? maxHeight,
  }) async {
    final hasAlpha = facts.alpha;
    // An SDR rendition of any HDR source; below iOS 17 a gain map's SDR base.
    final toSdr = facts.hasHdr;
    var backend = MediaBackend.androidAvif;
    try {
      if (format == DefaultFormat.avif) {
        // Hardware output is followed by a best-effort metadata transplant.
        // This path still needs independent preservation verification.
        // Android's bitmap/YUV path has no alpha plane and no tone mapper, so
        // it runs only on sources known to be neither transparent nor PQ/HLG.
        // A gain-map AVIF goes to DarkLib, which keeps the map (IMG-10).
        final keepsGainMap =
            facts.gainMap == true &&
            ImageProbe.sniff(source) == SniffedFormat.avif;
        // The hardware encoder takes 8-bit YUV: not for a 10-bit choice.
        final hw =
            hasAlpha == false &&
                facts.directHdr == false &&
                !keepsGainMap &&
                bitDepth != 10
            ? await NativeAvifEncoder.encode(source: source, quality: quality)
            : null;
        if (hw != null && hw.isNotEmpty) {
          final withMetadata = await carryMetadata(
            source,
            hw,
            keepMetadata: keepMetadata,
          );
          if (withMetadata == null || withMetadata.isEmpty) {
            MediaDiagnostics.record(
              MediaBackend.darklib,
              MediaOperation.transplant,
              MediaDiagnosticCode.preservationUnverified,
            );
          }
          return EncodedImage(
            withMetadata == null || withMetadata.isEmpty ? hw : withMetadata,
            format,
            backend: backend,
          );
        }

        // DarkLib software AVIF. Preservation limitations remain in phase B.
        backend = MediaBackend.darklib;
        final dark = await DarkLibCore.transcode(
          source,
          format: DarkLibFormat.avif,
          quality: quality,
          keepMetadata: keepMetadata,
          maxEdge: maxWidth ?? 0,
          bitDepth: bitDepth,
        );
        if (dark != null) {
          return EncodedImage(
            dark.bytes,
            format,
            backend: backend,
            hdr: dark.hdr,
          );
        }

        // Platform decode bridge for sources DarkLib cannot decode directly.
        // PNG encoding does not prove preservation of source HDR or colour.
        final baked = await NativeImageEncoder.bakeUpright(
          source: source,
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
          toSdr: toSdr,
        );
        if (baked != null && baked.isNotEmpty) {
          final bridged = await DarkLibCore.transcode(
            baked,
            format: DarkLibFormat.avif,
            quality: quality,
            keepMetadata: keepMetadata,
            maxEdge: maxWidth ?? 0,
            bitDepth: bitDepth,
          );
          if (bridged != null) {
            return EncodedImage(
              bridged.bytes,
              format,
              backend: backend,
              hdr: bridged.hdr,
            );
          }
        }

        // Lower quantizer = higher quality. Map 0–100 → ~[55..12].
        final maxQ = (63 - quality * 0.5).round().clamp(12, 55);
        final minQ = (maxQ - 12).clamp(0, maxQ);
        // Transitional software fallback; its EXIF handling is limited.
        final input = baked ?? source;
        backend = MediaBackend.flutterAvif;
        final out = await avif.encodeAvif(
          input,
          minQuantizer: minQ,
          maxQuantizer: maxQ,
          minQuantizerAlpha: minQ,
          maxQuantizerAlpha: maxQ,
          // flutter_avif is SOFTWARE libaom (no hardware path), so encoding is
          // CPU-bound — use more threads + a faster speed to cut the wait.
          maxThreads: 8,
          speed: 8,
          keepExif: baked != null && keepMetadata,
        );
        return _result(out, format, backend);
      }

      final cf = switch (format) {
        DefaultFormat.heic => fic.CompressFormat.heic,
        DefaultFormat.webp => fic.CompressFormat.webp,
        DefaultFormat.png => fic.CompressFormat.png,
        DefaultFormat.jpeg => fic.CompressFormat.jpeg,
        DefaultFormat.avif || DefaultFormat.auto => null,
      };
      if (cf == null) return null;

      // WebP: DarkLib first — it encodes WebP on EVERY platform (the plugin's
      // WebP encode is Android-only, so an iOS WebP request used to silently
      // fall away to another format) and it carries EXIF/XMP/ICC inside the
      // file, which the plugin never did for WebP. A HEIC source fails the
      // direct transcode and goes over the same platform-decode bridge as AVIF
      // (bakeUpright → DarkLib). Android's bridge answers only without
      // metadata; otherwise the plugin below handles HEIC platform-side.
      if (format == DefaultFormat.webp) {
        backend = MediaBackend.darklib;
        final dark = await DarkLibCore.transcode(
          source,
          format: DarkLibFormat.webp,
          quality: quality,
          keepMetadata: keepMetadata,
          maxEdge: maxWidth ?? 0,
        );
        if (dark != null) {
          return EncodedImage(
            dark.bytes,
            format,
            backend: backend,
            hdr: dark.hdr,
          );
        }
        final baked = await NativeImageEncoder.bakeUpright(
          source: source,
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
          toSdr: toSdr,
        );
        if (baked != null && baked.isNotEmpty) {
          final bridged = await DarkLibCore.transcode(
            baked,
            format: DarkLibFormat.webp,
            quality: quality,
            keepMetadata: keepMetadata,
            maxEdge: maxWidth ?? 0,
          );
          if (bridged != null) {
            return EncodedImage(
              bridged.bytes,
              format,
              backend: backend,
              hdr: bridged.hdr,
            );
          }
        }
      }

      final noCap = maxWidth == null && maxHeight == null;

      // Prefer upright platform pixels for PNG; source preservation remains
      // subject to the colour/HDR limitations in the stabilization plan.
      if (noCap && format == DefaultFormat.png) {
        final baked = await NativeImageEncoder.bakeUpright(
          source: source,
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
          toSdr: toSdr,
        );
        if (baked != null && baked.isNotEmpty) {
          return EncodedImage(
            baked,
            format,
            backend: NativeImageEncoder.bakeBackend,
          );
        }
      }

      // Android HEIC: bands and tiles (RUN-01), at every size since IMG-24.
      // The plugin's HeifWriter took RGB_565 through a GL texture: banding,
      // and a crash in the GPU driver at an odd width (user report
      // 2026-10-09). The source's profile and, on request, its metadata
      // carried by DarkLib. No alpha plane: a transparent source has no HEIC
      // on Android (IMG-19).
      if (noCap &&
          format == DefaultFormat.heic &&
          NativeImageEncoder.androidHeic &&
          hasAlpha != true &&
          facts.directHdr != true) {
        backend = MediaBackend.androidHeic;
        final tiles = await NativeImageEncoder.encodeHeicTiles(
          source: source,
          quality: quality.clamp(1, 100),
          orientation: facts.orientation,
          depth: await _androidHeicDepth(bitDepth, facts),
        );
        if (tiles != null) {
          return EncodedImage(
            await _withMetadata(source, tiles.bytes, keepMetadata, backend),
            format,
            backend: backend,
          );
        }
      }

      // Android JPEG (IMG-24): 8-bit pixels from the platform decoder and
      // libjpeg-turbo, the source's profile and metadata carried by DarkLib.
      if (noCap && format == DefaultFormat.jpeg && NativeImageEncoder.android) {
        backend = MediaBackend.androidJpeg;
        final jpeg = await NativeImageEncoder.encodeJpeg(
          source: source,
          quality: quality,
          toSdr: toSdr,
        );
        if (jpeg != null) {
          return EncodedImage(
            await _withMetadata(source, jpeg, keepMetadata, backend),
            format,
            backend: backend,
          );
        }
      }

      // Never flutter_image_compress on Android: it decodes into RGB_565
      // (IMG-24). What the paths above could not encode fails here.
      if (NativeImageEncoder.android) return null;

      // Prefer our own ImageIO encoder for HEIC/JPEG: it avoids the plugin's
      // "opaque image with AlphaLast" warning and carries real camera metadata
      // (the plugin only did EXIF for JPEG), keeping the orientation TAG (which
      // HEIC/JPEG viewers honour). Native returns null off-iOS / on failure, so
      // the plugin below stays the safety net.
      const nativeFormats = {DefaultFormat.heic, DefaultFormat.jpeg};
      if (noCap && nativeFormats.contains(format)) {
        final native = await NativeImageEncoder.encode(
          source: source,
          format: format == DefaultFormat.heic ? 'heic' : 'jpeg',
          quality: quality.clamp(1, 100),
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
          // Only HEIC honours a forced depth; JPEG is 8-bit anyway.
          bitDepth: format == DefaultFormat.heic ? bitDepth : 0,
          // With metadata, ImageIO copies a gain map next to its base; without
          // it the map is dropped, so decode the SDR rendition instead.
          toSdr: toSdr && !keepMetadata,
        );
        if (native != null && native.isNotEmpty) {
          return EncodedImage(native, format, backend: MediaBackend.imageIO);
        }
      }

      // Huge default bounds = "keep original dimensions"; a real cap only when
      // the caller asks for one. flutter_image_compress scales DOWN to fit.
      backend = MediaBackend.imageCompress;
      final out = await fic.FlutterImageCompress.compressWithList(
        source,
        format: cf,
        quality: quality.clamp(1, 100),
        minWidth: maxWidth ?? 1000000,
        minHeight: maxHeight ?? 1000000,
        keepExif: keepMetadata && _supportsKeepExif(format),
      );
      return _result(out, format, backend);
    } on DarkLibPreservationFailure {
      rethrow;
    } catch (_) {
      MediaDiagnostics.record(
        backend,
        MediaOperation.encode,
        MediaDiagnosticCode.exception,
      );
      return null;
    }
  }

  // Container identity only, not proof of complete decoding or HDR fidelity.
  static bool _matchesFormat(Uint8List bytes, DefaultFormat format) =>
      ImageProbe.sniff(bytes) ==
      switch (format) {
        DefaultFormat.avif => SniffedFormat.avif,
        DefaultFormat.heic => SniffedFormat.heic,
        DefaultFormat.webp => SniffedFormat.webp,
        DefaultFormat.png => SniffedFormat.png,
        DefaultFormat.jpeg => SniffedFormat.jpeg,
        DefaultFormat.auto => SniffedFormat.unknown,
      };

  static EncodedImage? _result(
    Uint8List bytes,
    DefaultFormat format,
    MediaBackend backend,
  ) {
    if (bytes.isEmpty) {
      MediaDiagnostics.record(
        backend,
        MediaOperation.encode,
        MediaDiagnosticCode.emptyOutput,
      );
      return null;
    }
    return EncodedImage(bytes, format, backend: backend);
  }

  /// [carryMetadata] onto a platform encoder's output; when DarkLib fails,
  /// the output as it is, with a diagnostic (as for hardware AVIF).
  static Future<Uint8List> _withMetadata(
    Uint8List source,
    Uint8List out,
    bool keepMetadata,
    MediaBackend backend,
  ) async {
    final carried = await carryMetadata(
      source,
      out,
      keepMetadata: keepMetadata,
    );
    if (carried != null && carried.isNotEmpty) return carried;
    MediaDiagnostics.record(
      MediaBackend.darklib,
      MediaOperation.transplant,
      MediaDiagnosticCode.preservationUnverified,
    );
    return out;
  }

  /// The HEIC depth on Android (IMG-23): the user's 8 or 10, or the
  /// source's ("match": 10 for a deeper source). 10 needs HEVC Main10; a
  /// device without it writes 8, recorded (the picker offers 10 only where
  /// it exists, so this is a "match" of a deep source).
  static Future<int> _androidHeicDepth(int bitDepth, SourceFacts facts) async {
    final want = bitDepth == 8 || bitDepth == 10
        ? bitDepth
        : ((facts.bitDepth ?? 8) > 8 ? 10 : 8);
    if (want == 8 || await NativeImageEncoder.heicTenBit()) return want;
    MediaDiagnostics.record(
      MediaBackend.androidHeic,
      MediaOperation.encode,
      MediaDiagnosticCode.depthReduced,
    );
    return 8;
  }

  /// The plugin can request JPEG EXIF copying. This is not a full metadata,
  /// orientation, colour or HDR preservation contract.
  static bool _supportsKeepExif(DefaultFormat f) => f == DefaultFormat.jpeg;

  /// The source's metadata onto [target]: all of it, or with [keepMetadata]
  /// off only the colour profile. It says what the pixel values mean, so
  /// dropping it recolours a P3 image as sRGB (IMG-08); DarkLib's strip keeps
  /// it and removes EXIF/XMP/IPTC. Null when either step failed.
  static Future<Uint8List?> carryMetadata(
    Uint8List source,
    Uint8List target, {
    required bool keepMetadata,
  }) async {
    final carried = await DarkLibCore.transplantMetadata(
      source: source,
      target: target,
    );
    if (carried == null || carried.isEmpty || keepMetadata) return carried;
    return DarkLibCore.stripMetadata(carried);
  }
}

class ImageEncodingFailure implements Exception {
  ImageEncodingFailure(this.requestedFormat, List<MediaDiagnostic> diagnostics)
    : diagnostics = List.unmodifiable(diagnostics);
  final DefaultFormat requestedFormat;
  final List<MediaDiagnostic> diagnostics;

  @override
  String toString() => 'No image encoder succeeded for ${requestedFormat.name}';
}
