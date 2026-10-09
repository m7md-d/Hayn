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
  /// More pixels than this make an image giant (user decision 2026-10-02,
  /// RUN-01). 2^26 rather than 64 million, so a 64 MP camera's 9248×6936
  /// (64.1 million) stays below while 108 and 200 MP are above.
  static const int giantPixels = 64 * 1024 * 1024;

  /// Whether a [width]×[height] source is giant; unknown size is not.
  static bool isGiant({int? width, int? height}) =>
      width != null && height != null && width * height > giantPixels;

  /// Whether [format] is offered for a source. A giant one gets JPEG and HEIC,
  /// which run on the platforms' encoders (user decision 2026-10-02): software
  /// AVIF and WebP take minutes at 200 MP. A transparent giant also gets PNG
  /// where HEIC cannot carry alpha (Android, IMG-19), so its alpha has a
  /// format that keeps it. Auto is always offered.
  static bool offers(
    DefaultFormat format, {
    required bool giant,
    required bool? hasAlpha,
    required FormatCapabilities caps,
  }) {
    if (!giant) return true;
    return switch (format) {
      DefaultFormat.auto || DefaultFormat.jpeg || DefaultFormat.heic => true,
      DefaultFormat.png => hasAlpha != false && !caps.heicKeepsAlpha,
      DefaultFormat.avif || DefaultFormat.webp => false,
    };
  }

  /// Whether [format] (resolved) is offered at 10 bits: AVIF always
  /// (DarkLib), HEIC where its encoder writes it (IMG-23).
  static bool offersTenBit(DefaultFormat format, FormatCapabilities caps) =>
      format != DefaultFormat.heic || caps.heicTenBit;

  /// The depth an encode into [format] (resolved) takes for the user's
  /// [chosen] one (0 = match, 8, 10): the choice, within what the format
  /// offers. A 10 picked for AVIF is 8 for a HEIC that has no 10, and 10
  /// again back on AVIF; the encoder holds an output to the depth it is
  /// given, so it must never be given one it cannot write.
  static int depthFor(
    int chosen,
    DefaultFormat format,
    FormatCapabilities caps,
  ) => chosen == 10 && !offersTenBit(format, caps) ? 8 : chosen;

  /// Resolve the concrete target format for an encode.
  ///
  /// * [choice] == auto → the efficiency tree, branched on [hasAlpha]:
  ///   - alpha:    AVIF → HEIC/HEIF → WebP → **PNG**   (never JPEG)
  ///   - no alpha: AVIF → HEIC/HEIF → WebP → JPEG
  /// * [choice] forced → honoured as-is. A forced JPEG on an alpha image is
  ///   the user's permission to flatten it (see [losses]).
  /// * [giant] → only what [offers] allows: a choice it does not offer (a
  ///   batch's WebP, say) resolves as Auto for that image, and Auto prefers
  ///   HEIC, then JPEG, or PNG for alpha HEIC cannot keep.
  static ResolvedImageFormat resolve({
    required DefaultFormat choice,
    required bool? hasAlpha,
    required FormatCapabilities caps,
    bool giant = false,
  }) {
    if (giant) {
      if (choice != DefaultFormat.auto &&
          offers(choice, giant: true, hasAlpha: hasAlpha, caps: caps)) {
        return ResolvedImageFormat(choice);
      }
      final heic = caps.supportsHeic || caps.supportsHeif;
      if (hasAlpha != false) {
        return ResolvedImageFormat(
          heic && caps.heicKeepsAlpha ? DefaultFormat.heic : DefaultFormat.png,
        );
      }
      return ResolvedImageFormat(
        heic ? DefaultFormat.heic : DefaultFormat.jpeg,
      );
    }
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
  /// gets a note. A gain map survives AVIF→AVIF in DarkLib (verified by
  /// ImageIO, IMG-10) and HEIC/JPEG through ImageIO with metadata (iOS);
  /// PQ/HLG always becomes SDR. A flattened JPEG is re-encoded from SDR pixels.
  /// Resize caps and rotated sources can still drop a map; not reflected here.
  static FormatLosses losses({
    required DefaultFormat format,
    required bool sourceAlpha,
    required bool sourceDirectHdr,
    required bool sourceGainMap,
    required bool sourceIsAvif,
    required bool keepMetadata,
    required bool platformCopiesGainMap,
  }) {
    final alpha = sourceAlpha && !keepsAlpha(format);
    final gainMapKept =
        sourceGainMap &&
        !sourceDirectHdr &&
        !alpha &&
        ((format == DefaultFormat.avif && sourceIsAvif) ||
            (keepMetadata &&
                platformCopiesGainMap &&
                (format == DefaultFormat.heic ||
                    format == DefaultFormat.jpeg)));
    return (
      alpha: alpha,
      hdr: (sourceDirectHdr || sourceGainMap) && !gainMapKept,
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
