import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/capabilities/format_capabilities.dart';
import 'package:hayn/features/image_ops/domain/image_format_policy.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

// Capability fixtures for each rung of the efficiency tree.
FormatCapabilities _caps({
  bool avif = false,
  bool heic = false,
  bool heif = false,
  bool webp = true,
}) =>
    FormatCapabilities(
      supportsHeic: heic,
      supportsHeif: heif,
      supportsAvifHardware: avif,
      supportsWebp: webp,
    );

ResolvedImageFormat _auto(bool alpha, FormatCapabilities caps) =>
    ImageFormatPolicy.resolve(
      choice: DefaultFormat.auto,
      hasAlpha: alpha,
      caps: caps,
    );

void main() {
  group('ImageFormatPolicy.resolve — auto efficiency tree', () {
    test('AVIF wins when hardware is present (alpha or not)', () {
      final caps = _caps(avif: true, heic: true);
      expect(_auto(false, caps).format, DefaultFormat.avif);
      expect(_auto(true, caps).format, DefaultFormat.avif);
    });

    test('falls to HEIC when no AVIF', () {
      final caps = _caps(avif: false, heic: true);
      expect(_auto(false, caps).format, DefaultFormat.heic);
      expect(_auto(true, caps).format, DefaultFormat.heic);
    });

    test('HEIF (generic) also satisfies the HEIC rung', () {
      final caps = _caps(avif: false, heif: true);
      expect(_auto(false, caps).format, DefaultFormat.heic);
    });

    test('falls to WebP when no AVIF/HEIC', () {
      final caps = _caps(avif: false, heic: false, webp: true);
      expect(_auto(false, caps).format, DefaultFormat.webp);
      expect(_auto(true, caps).format, DefaultFormat.webp);
    });

    test('final fallback splits on alpha: PNG for alpha, JPEG otherwise', () {
      final none = _caps(avif: false, heic: false, webp: false);
      expect(_auto(false, none).format, DefaultFormat.jpeg);
      expect(_auto(true, none).format, DefaultFormat.png);
    });

    test('auto NEVER routes a transparent image to JPEG (the golden rule)', () {
      for (final caps in [
        _caps(avif: true, heic: true),
        _caps(heic: true),
        _caps(webp: true),
        _caps(avif: false, heic: false, webp: false),
      ]) {
        final r = _auto(true, caps);
        expect(r.format == DefaultFormat.jpeg, isFalse,
            reason: 'alpha → ${r.format} must keep alpha');
        expect(ImageFormatPolicy.keepsAlpha(r.format), isTrue);
        expect(r.requiresAlphaFlatten, isFalse);
      }
    });
  });

  group('ImageFormatPolicy.resolve — forced format', () {
    test('a forced format is honoured verbatim', () {
      final caps = _caps(avif: true);
      expect(
        ImageFormatPolicy.resolve(
                choice: DefaultFormat.webp, hasAlpha: false, caps: caps)
            .format,
        DefaultFormat.webp,
      );
    });

    test('forced JPEG on an alpha image flags a flatten (never silent)', () {
      final r = ImageFormatPolicy.resolve(
        choice: DefaultFormat.jpeg,
        hasAlpha: true,
        caps: _caps(),
      );
      expect(r.format, DefaultFormat.jpeg);
      expect(r.requiresAlphaFlatten, isTrue);
    });

    test('forced JPEG on an opaque image needs no flatten', () {
      final r = ImageFormatPolicy.resolve(
        choice: DefaultFormat.jpeg,
        hasAlpha: false,
        caps: _caps(),
      );
      expect(r.requiresAlphaFlatten, isFalse);
    });

    test('forced alpha-safe format on an alpha image never flattens', () {
      for (final f in [
        DefaultFormat.avif,
        DefaultFormat.heic,
        DefaultFormat.webp,
        DefaultFormat.png,
      ]) {
        final r = ImageFormatPolicy.resolve(
            choice: f, hasAlpha: true, caps: _caps());
        expect(r.requiresAlphaFlatten, isFalse, reason: '$f keeps alpha');
      }
    });
  });

  group('ImageFormatPolicy.keepsAlpha', () {
    test('only JPEG drops alpha', () {
      expect(ImageFormatPolicy.keepsAlpha(DefaultFormat.jpeg), isFalse);
      for (final f in [
        DefaultFormat.avif,
        DefaultFormat.heic,
        DefaultFormat.webp,
        DefaultFormat.png,
      ]) {
        expect(ImageFormatPolicy.keepsAlpha(f), isTrue);
      }
    });
  });
}
