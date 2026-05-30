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
  const ResolvedImageFormat(
    this.format, {
    this.requiresAlphaFlatten = false,
  });

  /// The concrete output format — never [DefaultFormat.auto].
  final DefaultFormat format;

  /// True ONLY when the user explicitly forced an opaque format (JPEG) on an
  /// image that has transparency. The UI must warn + get explicit confirmation
  /// before flattening (e.g. onto white). Auto never sets this — it routes
  /// alpha images to an alpha-safe format instead.
  final bool requiresAlphaFlatten;

  @override
  bool operator ==(Object other) =>
      other is ResolvedImageFormat &&
      other.format == format &&
      other.requiresAlphaFlatten == requiresAlphaFlatten;

  @override
  int get hashCode => Object.hash(format, requiresAlphaFlatten);

  @override
  String toString() =>
      'ResolvedImageFormat($format, flatten: $requiresAlphaFlatten)';
}

abstract final class ImageFormatPolicy {
  /// Resolve the concrete target format for an encode.
  ///
  /// * [choice] == auto → the efficiency tree, branched on [hasAlpha]:
  ///   - alpha:    AVIF → HEIC/HEIF → WebP → **PNG**   (never JPEG)
  ///   - no alpha: AVIF → HEIC/HEIF → WebP → JPEG
  /// * [choice] forced → honoured as-is; a forced JPEG on an alpha image is
  ///   returned with [ResolvedImageFormat.requiresAlphaFlatten] = true so the
  ///   caller can warn before flattening (we never drop alpha silently).
  static ResolvedImageFormat resolve({
    required DefaultFormat choice,
    required bool hasAlpha,
    required FormatCapabilities caps,
  }) {
    if (choice != DefaultFormat.auto) {
      final flattens = hasAlpha && !keepsAlpha(choice);
      return ResolvedImageFormat(choice, requiresAlphaFlatten: flattens);
    }

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
      hasAlpha ? DefaultFormat.png : DefaultFormat.jpeg,
    );
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
