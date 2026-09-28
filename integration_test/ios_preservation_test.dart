import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:hayn/app/app.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/image_ops/data/gallery_saver.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/native_image_encoder.dart';
import 'package:hayn/features/image_ops/data/native_image_info.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/library/presentation/library_screen.dart';
import 'package:hayn/features/onboarding/providers/onboarding_provider.dart';
import 'package:hayn/features/settings/presentation/settings_screen.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

// Real iOS services, including the linked Rust library and Photos. Fixtures are
// copied into this disposable simulator by tool/test_ios_preservation.sh; they
// are deliberately not production Flutter assets. Never run on personal media.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(Platform.isIOS, isTrue, reason: 'This suite requires iOS');
    expect(await DarkLibCore.ensureReady(), isTrue);
    final permission = await PhotoManager.requestPermissionExtend();
    expect(
      permission.isAuth,
      isTrue,
      reason: 'Runner must grant Photos access',
    );
  });

  testWidgets('ImageIO distinguishes opaque, alpha and unreadable input', (
    _,
  ) async {
    expect(await NativeImageProbe.probeAlpha(_png(alpha: true)), isTrue);
    expect(await NativeImageProbe.probeAlpha(_png(alpha: false)), isFalse);
    expect(
      await NativeImageProbe.probeAlpha(Uint8List.fromList([1, 2, 3])),
      isNull,
    );
  });

  for (final name in [
    'seine_hdr_rec2020.avif',
    'seine_sdr_gainmap_srgb.avif',
  ]) {
    testWidgets('ImageIO identifies HDR in $name', (_) async {
      final info = await NativeImageProbe.probe(await _fixture(name));
      expect(info, isNotNull);
      expect(info!.isHdr, isTrue);
      expect(info.hasAlpha, isFalse);
    });
  }

  // HDR policy (user decision 2026-09-28): keep where the path exists,
  // otherwise a correct SDR rendition without asking; PQ/HLG via ImageIO.
  // The ImageIO SDR request is platform-dependent (the iOS 26.3 simulator
  // ignores it). Either way no PQ-labelled file may come out, and the PQ
  // original must never reach an engine.
  testWidgets('PQ is refused early or becomes ImageIO SDR', (_) async {
    final source = await _fixture('seine_hdr_rec2020.avif');
    final facts = await SourceInspector.inspect(source);
    expect((facts.directHdr, facts.gainMap), (true, false));
    // The original itself is still refused by Rust across the real FFI.
    await expectLater(
      DarkLibCore.transcode(source, format: DarkLibFormat.webp, quality: 80),
      throwsA(isA<DarkLibPreservationFailure>()),
    );
    final rendition = await NativeImageEncoder.bakeUpright(
      source: source,
      keepMetadata: false,
      keepOriginalTime: true,
      toSdr: true,
    );
    if (rendition == null) {
      await expectLater(
        ImageEncoder.encode(
          source: source,
          target: DefaultFormat.webp,
          quality: 90,
          facts: facts,
          keepMetadata: true,
        ),
        throwsA(
          isA<ImageEncodingFailure>().having(
            (e) => e.diagnostics.map((d) => d.code),
            'refused before any engine',
            allOf(
              contains(MediaDiagnosticCode.hdrToneMapUnavailable),
              isNot(contains(MediaDiagnosticCode.preservationRejected)),
            ),
          ),
        ),
      );
      return;
    }
    await _artifact('pq-imageio-sdr.png', rendition);
    expect((await NativeImageProbe.probeHdr(rendition))!.hdrTransfer, isFalse);
    final result = await ImageEncoder.encode(
      source: source,
      target: DefaultFormat.webp,
      quality: 90,
      facts: facts,
      keepMetadata: true,
    );
    expect(
      result.diagnostics.map((d) => d.code),
      contains(MediaDiagnosticCode.hdrToSdr),
    );
    await _artifact('pq-to-webp.webp', result.bytes);
    expect((await NativeImageProbe.probe(result.bytes))!.isHdr, isFalse);
    _expectSameImage(img.decodePng(rendition)!, img.decodeWebP(result.bytes)!);
  });

  testWidgets('Gain map: SDR base to WebP and AVIF', (_) async {
    final source = await _fixture('seine_sdr_gainmap_srgb.avif');
    final facts = await SourceInspector.inspect(source);
    expect((facts.directHdr, facts.gainMap), (false, true));

    final webp = await ImageEncoder.encode(
      source: source,
      target: DefaultFormat.webp,
      quality: 90,
      facts: facts,
      keepMetadata: true,
    );
    expect(webp.hdr, HdrOutcome.gainMapDropped);
    expect(
      webp.diagnostics.map((d) => d.code),
      contains(MediaDiagnosticCode.hdrToSdr),
    );
    await _artifact('gainmap-to-webp.webp', webp.bytes);
    expect((await NativeImageProbe.probe(webp.bytes))!.isHdr, isFalse);

    final avif = await ImageEncoder.encode(
      source: source,
      target: DefaultFormat.avif,
      quality: 80,
      facts: facts,
      keepMetadata: true,
    );
    // No verified keeping path yet: our rebuilt map was invisible to ImageIO
    // (IMG-10), so AVIF gets the SDR base too.
    expect(avif.hdr, HdrOutcome.gainMapDropped);
    await _artifact('gainmap-to-avif.avif', avif.bytes);
    final after = await NativeImageProbe.probeHdr(avif.bytes);
    expect(after!.gainMap, isFalse);
  });

  for (final target in [
    DefaultFormat.png,
    DefaultFormat.jpeg,
    DefaultFormat.webp,
    DefaultFormat.avif,
  ]) {
    testWidgets('${target.name}: primary encode and Photos original readback', (
      _,
    ) async {
      final alpha = target == DefaultFormat.png || target == DefaultFormat.webp;
      final source = _png(alpha: alpha);
      final facts = await SourceInspector.inspect(source);
      expect(
        (facts.alpha, facts.directHdr, facts.gainMap),
        (alpha, false, false),
      );
      final result = await ImageEncoder.encode(
        source: source,
        target: target,
        quality: 90,
        facts: facts,
        keepMetadata: false,
      );
      expect(result.format, target);
      expect(
        result.backend,
        target == DefaultFormat.png || target == DefaultFormat.jpeg
            ? MediaBackend.imageIO
            : MediaBackend.darklib,
      );
      // Android hardware is probed first by the coordinator even on iOS.
      // Accept only that known capability miss; Rust errors/fallbacks fail.
      expect(
        result.diagnostics.map((d) => d.toString()),
        target == DefaultFormat.avif
            ? ['androidAvif.encode.unavailable']
            : isEmpty,
        reason: 'Unexpected recovery is not primary-path proof',
      );
      await _artifact(
        '${target.name}-encoded.${result.extension}',
        result.bytes,
      );
      await _checkPixels(result.bytes, target, alpha: alpha);

      final saved = await GallerySaver.saveImage(
        result.bytes,
        filename: 'hayn-integration-${target.name}.${result.extension}',
      );
      expect(saved, isNotNull, reason: 'Photos must accept this encoded file');
      expect((saved!.width, saved.height), (16, 12));
      final original = await saved.originBytes;
      expect(original, isNotNull);
      await _artifact('${target.name}-photos.${result.extension}', original!);
      if (target == DefaultFormat.jpeg) {
        _expectJpegReadback(result.bytes, original);
      } else {
        expect(
          original,
          orderedEquals(result.bytes),
          reason: 'Photos original resource must retain these file bytes',
        );
      }
      await _checkPixels(original, target, alpha: alpha);
    });
  }

  testWidgets('Forced JPEG rejects present and unknown alpha', (_) async {
    for (final alpha in <bool?>[true, null]) {
      await expectLater(
        ImageEncoder.encode(
          source: _png(alpha: true),
          target: DefaultFormat.jpeg,
          quality: 80,
          facts: SourceFacts.sdr(alpha: alpha),
          keepMetadata: false,
        ),
        throwsA(isA<ImageEncodingFailure>()),
      );
    }
  });

  testWidgets('Real app opens the library and settings', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingCompletedProvider.overrideWith(
            () => OnboardingNotifier(initial: true),
          ),
        ],
        child: const HaynApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Uint8List _png({required bool alpha}) {
  final input = img.Image(width: 16, height: 12, numChannels: alpha ? 4 : 3);
  img.fill(
    input,
    color: alpha
        ? img.ColorRgba8(80, 120, 160, 64)
        : img.ColorRgb8(80, 120, 160),
  );
  return Uint8List.fromList(img.encodePng(input));
}

Future<Uint8List> _fixture(String name) async {
  final documents = await getApplicationDocumentsDirectory();
  return File('${documents.path}/preservation-fixtures/$name').readAsBytes();
}

Future<void> _checkPixels(
  Uint8List bytes,
  DefaultFormat format, {
  required bool alpha,
}) async {
  final img.Image? decoded;
  if (format == DefaultFormat.avif) {
    final info = await NativeImageProbe.probe(bytes);
    expect(info, isNotNull);
    expect(info!.isHdr, isFalse);
    expect(info.hasAlpha, isFalse);
    final png = await NativeImageEncoder.bakeUpright(
      source: bytes,
      keepMetadata: false,
      keepOriginalTime: false,
    );
    expect(png, isNotNull, reason: 'Independent ImageIO must decode Rust AVIF');
    await _artifact('avif-imageio.png', png!);
    decoded = img.decodePng(png);
  } else {
    decoded = img.decodeImage(bytes);
  }
  expect(decoded, isNotNull);
  expect((decoded!.width, decoded.height), (16, 12));
  final pixel = decoded.getPixel(8, 6);
  await _artifact(
    '${format.name}-pixels.json',
    utf8.encode(
      jsonEncode({
        'channels': decoded.numChannels,
        'format': decoded.format.name,
        'rgba': [pixel.r, pixel.g, pixel.b, pixel.a],
        'hasAlpha': decoded.hasAlpha,
        'maxChannelValue': pixel.maxChannelValue,
      }),
    ),
  );
  // ImageIO can expand 10-bit SDR AVIF into 16-bit RGB PNG. The image package
  // returns alpha=0 for RGB uint16 (no alpha channel), not a transparent pixel.
  expect(decoded.hasAlpha, alpha);
  if (alpha) expect(pixel.aNormalized, closeTo(64 / 255, 1 / 255));
  expect(pixel.rNormalized, closeTo(80 / 255, 8 / 255));
  expect(pixel.gNormalized, closeTo(120 / 255, 8 / 255));
  expect(pixel.bNormalized, closeTo(160 / 255, 8 / 255));
}

/// Same size and near-identical pixels (a lossy re-encode of one rendition).
void _expectSameImage(img.Image a, img.Image b) {
  expect((b.width, b.height), (a.width, a.height));
  var total = 0.0;
  var samples = 0;
  for (var y = 0; y < a.height; y += 7) {
    for (var x = 0; x < a.width; x += 7) {
      final p = a.getPixel(x, y);
      final q = b.getPixel(x, y);
      total +=
          (p.rNormalized - q.rNormalized).abs() +
          (p.gNormalized - q.gNormalized).abs() +
          (p.bNormalized - q.bNormalized).abs();
      samples += 3;
    }
  }
  expect(total / samples, lessThan(4 / 255));
}

Future<void> _artifact(String name, List<int> bytes) async {
  final documents = await getApplicationDocumentsDirectory();
  final directory = Directory('${documents.path}/preservation-results');
  await directory.create(recursive: true);
  await File('${directory.path}/$name').writeAsBytes(bytes);
}

// This is a check for our generated SDR fixture, not a general JPEG sanitizer.
// Photos adds EXIF resolution/version/component fields on import. Keep the
// comparison strict for compressed scans, ICC, XMP, and existing EXIF values.
void _expectJpegReadback(Uint8List before, Uint8List after) {
  expect(
    _withoutExif(after),
    orderedEquals(_withoutExif(before)),
    reason: 'Only the EXIF segment may be rewritten by Photos',
  );
  final first = img.decodeJpg(before)!;
  final second = img.decodeJpg(after)!;
  expect(
    second.getBytes(),
    orderedEquals(first.getBytes()),
    reason: 'Every decoded JPEG pixel must remain identical',
  );
  _expectIfdPreserved(first.exif.imageIfd, second.exif.imageIfd, const {
    0x011a,
    0x011b,
    0x0128,
    0x0213,
  }); // Resolution, unit, and default YCbCr positioning.
  _expectIfdPreserved(first.exif.exifIfd, second.exif.exifIfd, const {
    0x9000,
    0x9101,
    0xa000,
    0xa406,
  }); // Version, components, scene type.
  final positioning = second.exif.imageIfd[0x0213];
  if (positioning != null) {
    expect(
      positioning.toInt(),
      1,
      reason: 'Default centered YCbCr positioning',
    );
  }
}

void _expectIfdPreserved(
  img.IfdDirectory before,
  img.IfdDirectory after,
  Set<int> allowedAdditions,
) {
  expect(after.sub.keys, unorderedEquals(before.sub.keys));
  for (final tag in before.keys) {
    if (tag == 0x8769) {
      continue; // EXIF directory offset moves; compare its data above.
    }
    expect(
      after[tag]?.toString(),
      before[tag]?.toString(),
      reason: 'Existing EXIF tag 0x${tag.toRadixString(16)} changed',
    );
  }
  final allowed = {...before.keys, ...allowedAdditions};
  for (final tag in after.keys) {
    expect(
      allowed.contains(tag),
      isTrue,
      reason: 'Unexpected EXIF tag 0x${tag.toRadixString(16)} added',
    );
  }
}

List<int> _withoutExif(Uint8List jpeg) {
  expect(jpeg.take(2), [0xff, 0xd8]);
  final result = <int>[0xff, 0xd8];
  var offset = 2;
  while (offset + 4 <= jpeg.length) {
    expect(jpeg[offset], 0xff);
    final marker = jpeg[offset + 1];
    if (marker == 0xda) {
      result.addAll(
        jpeg.sublist(offset),
      ); // All scans, restart markers and EOI.
      return result;
    }
    final size = (jpeg[offset + 2] << 8) | jpeg[offset + 3];
    expect(size, greaterThanOrEqualTo(2));
    final end = offset + 2 + size;
    expect(end, lessThanOrEqualTo(jpeg.length));
    final isExif =
        marker == 0xe1 &&
        size >= 8 &&
        String.fromCharCodes(jpeg.sublist(offset + 4, offset + 10)) ==
            'Exif\x00\x00';
    if (!isExif) result.addAll(jpeg.sublist(offset, end));
    offset = end;
  }
  fail('JPEG fixture has no scan');
}
