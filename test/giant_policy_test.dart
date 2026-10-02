import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/capabilities/format_capabilities.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/image_ops/domain/image_format_policy.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

// RUN-01 (user decisions 2026-10-02): images over 64 MP are served at full
// size, in JPEG and HEIC only, which run on the platforms' encoders; a
// transparent one keeps PNG where HEIC cannot carry alpha (IMG-19). Replaces
// the 8192 px cap that silently shrank them.

const _android = FormatCapabilities(
  supportsHeic: false,
  supportsHeif: true,
  supportsAvifHardware: false,
  supportsWebp: true,
);
const _ios = FormatCapabilities(
  supportsHeic: true,
  supportsHeif: false,
  supportsAvifHardware: false,
  supportsWebp: true,
  heicKeepsAlpha: true,
);

void main() {
  test('the threshold leaves a 64 MP camera below and 108 MP above', () {
    expect(ImageFormatPolicy.isGiant(width: 9248, height: 6936), isFalse);
    expect(ImageFormatPolicy.isGiant(width: 8064, height: 6048), isFalse);
    expect(ImageFormatPolicy.isGiant(width: 12000, height: 9000), isTrue);
    expect(ImageFormatPolicy.isGiant(width: 16320, height: 12240), isTrue);
    expect(ImageFormatPolicy.isGiant(width: null, height: 9000), isFalse);
    const facts = SourceFacts(
      alpha: false,
      directHdr: false,
      gainMap: false,
      width: 16128,
      height: 12096,
    );
    expect(facts.giant, isTrue);
  });

  test('a giant image is offered JPEG and HEIC, PNG only for alpha', () {
    bool offers(DefaultFormat f, bool? alpha, FormatCapabilities caps) =>
        ImageFormatPolicy.offers(f, giant: true, hasAlpha: alpha, caps: caps);
    for (final caps in [_android, _ios]) {
      for (final f in [
        DefaultFormat.auto,
        DefaultFormat.jpeg,
        DefaultFormat.heic,
      ]) {
        expect(offers(f, false, caps), isTrue, reason: '$f');
      }
      for (final f in [DefaultFormat.webp, DefaultFormat.avif]) {
        expect(offers(f, true, caps), isFalse, reason: '$f');
      }
      expect(offers(DefaultFormat.png, false, caps), isFalse);
    }
    expect(offers(DefaultFormat.png, true, _android), isTrue);
    expect(offers(DefaultFormat.png, true, _ios), isFalse);
    // Not giant: everything as before.
    for (final f in DefaultFormat.values) {
      expect(
        ImageFormatPolicy.offers(f, giant: false, hasAlpha: true, caps: _ios),
        isTrue,
      );
    }
  });

  test('a giant image resolves within what it is offered', () {
    DefaultFormat resolve(DefaultFormat choice, bool? alpha, caps) =>
        ImageFormatPolicy.resolve(
          choice: choice,
          hasAlpha: alpha,
          caps: caps,
          giant: true,
        ).format;
    // A batch's WebP becomes Auto for the giant image.
    expect(resolve(DefaultFormat.webp, false, _android), DefaultFormat.heic);
    expect(resolve(DefaultFormat.avif, false, _ios), DefaultFormat.heic);
    expect(resolve(DefaultFormat.jpeg, false, _android), DefaultFormat.jpeg);
    // Alpha: HEIC where it keeps alpha, otherwise PNG; a forced JPEG is the
    // user's permission to flatten.
    expect(resolve(DefaultFormat.auto, true, _ios), DefaultFormat.heic);
    expect(resolve(DefaultFormat.auto, true, _android), DefaultFormat.png);
    expect(resolve(DefaultFormat.jpeg, true, _android), DefaultFormat.jpeg);
  });

  test('a giant image never falls back to software WebP or AVIF', () {
    expect(ImageEncoder.fallbackChain(DefaultFormat.heic, false, giant: true), [
      DefaultFormat.heic,
      DefaultFormat.jpeg,
      DefaultFormat.png,
    ]);
    expect(ImageEncoder.fallbackChain(DefaultFormat.heic, true, giant: true), [
      DefaultFormat.heic,
      DefaultFormat.png,
    ]);
    expect(
      ImageEncoder.fallbackChain(DefaultFormat.heic, false),
      contains(DefaultFormat.webp),
    );
  });
}
