import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/capabilities/format_capabilities.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Preference providers — UI-state today, persisted (SharedPreferences) once
// the storage layer arrives. Kept thin so the picker sheets stay consistent.
// ─────────────────────────────────────────────────────────────────────────────

enum NumeralsStyle { latin, arabicIndic }

final numeralsProvider =
    StateProvider<NumeralsStyle>((ref) => NumeralsStyle.latin);

// Image / video output format default. Technical names (AVIF, HEIC/HEIF,
// WebP, JPEG) are proper nouns. The `heic` enum value represents the HEIF
// container — labelled HEIC on Apple, HEIF on Android. "Auto" is localised
// upstream via AppLocalizations.formatAuto.
enum DefaultFormat {
  auto,
  avif,
  heic,
  webp,
  jpeg;

  /// Static name (Apple-flavoured). Use [labelFor] when you have the device
  /// capabilities so the HEIC/HEIF naming follows the platform.
  String get techName => switch (this) {
        DefaultFormat.auto => 'Auto',
        DefaultFormat.avif => 'AVIF',
        DefaultFormat.heic => 'HEIC',
        DefaultFormat.webp => 'WebP',
        DefaultFormat.jpeg => 'JPEG',
      };

  /// Display name swapped for platform: HEIC on Apple, HEIF elsewhere.
  /// Pass in the capabilities so this layer stays decoupled from Platform.
  static String labelFor(
    DefaultFormat f, {
    required bool supportsHeic,
    required bool supportsHeif,
  }) {
    if (f != DefaultFormat.heic) return f.techName;
    if (supportsHeic) return 'HEIC';
    if (supportsHeif) return 'HEIF';
    return 'HEIC';
  }

  /// Resolves the "Auto" choice using the priority chain:
  ///   AVIF (with hw)  →  HEIC / HEIF  →  WebP  →  JPEG.
  /// JPEG is the universal fallback when nothing else fits.
  static DefaultFormat resolveAuto(FormatCapabilities caps) {
    if (caps.supportsAvifHardware) return DefaultFormat.avif;
    if (caps.supportsHeic || caps.supportsHeif) return DefaultFormat.heic;
    if (caps.supportsWebp) return DefaultFormat.webp;
    return DefaultFormat.jpeg;
  }
}

final defaultFormatProvider =
    StateProvider<DefaultFormat>((ref) => DefaultFormat.auto);

// Quality / speed target.
enum DefaultQuality { lightning, balanced, highest }

final defaultQualityProvider =
    StateProvider<DefaultQuality>((ref) => DefaultQuality.balanced);

// Trash retention in days.
final trashRetentionProvider = StateProvider<int>((ref) => 14);
