import '../../../core/capabilities/format_capabilities.dart';
import '../../settings/providers/preferences_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ImageFormatPolicy — the single source of truth for "what format do we encode
// this image to", implementing the decision tree in docs/03-FORMATS.md.
//
// Golden rule (CLAUDE.md §2 + 03-FORMATS.md): NEVER silently destroy alpha. An
// image with transparency may only target a format that keeps alpha
// (AVIF / HEIC / WebP / PNG) — never JPEG. PNG is the mandatory alpha-safe
// fallback when no efficient encoder is available.
//
// Pure + dependency-free (no Platform, no IO) so it unit-tests directly. The
// engine layer (Unit B) calls this, then encodes; capability "detection" is
// finalised by the encoder attempting the format and falling back, so this
// stays a clean policy and "اكشف لا تفترض" is honoured end-to-end.
// ─────────────────────────────────────────────────────────────────────────────

class ResolvedImageFormat {
  const ResolvedImageFormat(this.format);

  /// The concrete output format — never [DefaultFormat.auto].
  final DefaultFormat format;

  @override
  bool operator ==(Object other) =>
      other is ResolvedImageFormat && other.format == format;

  @override
  int get hashCode => format.hashCode;

  @override
  String toString() => 'ResolvedImageFormat($format)';
}

/// What the saved file will lack that the source has. Drives a light note on
/// the format, never a warning (user decision, 2026-09-29).
typedef FormatLosses = ({bool alpha, bool hdr});

abstract final class ImageFormatPolicy {
  /// Resolve the concrete target format for an encode.
  ///
  /// * [choice] == auto → the efficiency tree, branched on [hasAlpha]:
  ///   - alpha:    AVIF → HEIC/HEIF → WebP → **PNG**   (never JPEG)
  ///   - no alpha: AVIF → HEIC/HEIF → WebP → JPEG
  /// * [choice] forced → honoured as-is. A forced JPEG on an alpha image is
  ///   the user's permission to flatten it (see [losses]).
  static ResolvedImageFormat resolve({
    required DefaultFormat choice,
    required bool? hasAlpha,
    required FormatCapabilities caps,
  }) {
    if (choice != DefaultFormat.auto) return ResolvedImageFormat(choice);

    // Auto — walk the efficiency tree. AVIF and HEIC/HEIF and WebP all keep
    // alpha, so the only difference the alpha branch makes is the final
    // fallback: PNG (alpha-safe) vs JPEG (opaque).
    if (caps.supportsAvifHardware) {
      return const ResolvedImageFormat(DefaultFormat.avif);
    }
    if (caps.supportsHeic || caps.supportsHeif) {
      return const ResolvedImageFormat(DefaultFormat.heic);
    }
    if (caps.supportsWebp) {
      return const ResolvedImageFormat(DefaultFormat.webp);
    }
    return ResolvedImageFormat(
      hasAlpha != false ? DefaultFormat.png : DefaultFormat.jpeg,
    );
  }

  /// Losses of saving a source with these facts as [format] (resolved). Only
  /// what the source actually has can be lost, so an opaque SDR photo never
  /// gets a note. HDR survives only where ImageIO copies a gain map next to
  /// its base (HEIC/JPEG with metadata, iOS); every other path saves the SDR
  /// image, and no Rust path keeps HDR yet (IMG-10). A flattened JPEG is
  /// re-encoded from SDR pixels, so it drops a gain map too.
  static FormatLosses losses({
    required DefaultFormat format,
    required bool sourceAlpha,
    required bool sourceDirectHdr,
    required bool sourceGainMap,
    required bool keepMetadata,
    required bool platformCopiesGainMap,
  }) {
    final alpha = sourceAlpha && !keepsAlpha(format);
    final hdrKept =
        sourceGainMap &&
        !sourceDirectHdr &&
        !alpha &&
        keepMetadata &&
        platformCopiesGainMap &&
        (format == DefaultFormat.heic || format == DefaultFormat.jpeg);
    return (alpha: alpha, hdr: (sourceDirectHdr || sourceGainMap) && !hdrKept);
  }

  /// Whether a format can carry an alpha channel. JPEG is the only common
  /// output that cannot.
  static bool keepsAlpha(DefaultFormat f) => switch (f) {
    DefaultFormat.avif => true,
    DefaultFormat.heic => true,
    DefaultFormat.webp => true,
    DefaultFormat.png => true,
    DefaultFormat.jpeg => false,
    // "auto" is resolved before this is asked; treat as alpha-safe so a
    // stray call can never green-light flattening.
    DefaultFormat.auto => true,
  };
}
