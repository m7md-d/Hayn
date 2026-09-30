import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart' as avif;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:image/image.dart' as img;
import 'package:hayn/app/app.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/core/isolates/task_progress.dart';
import 'package:hayn/features/image_ops/data/gallery_saver.dart';
import 'package:hayn/features/image_ops/data/image_crop_task.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/image_probe.dart';
import 'package:hayn/features/image_ops/data/native_avif_encoder.dart';
import 'package:hayn/features/image_ops/data/native_image_encoder.dart';
import 'package:hayn/features/image_ops/data/platform_pixels.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/library/presentation/library_screen.dart';
import 'package:hayn/features/onboarding/providers/onboarding_provider.dart';
import 'package:hayn/features/settings/presentation/settings_screen.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

// Real Android services on a physical phone, including the linked Rust library
// and Android's own ImageDecoder, independent of our code: AVIF/HEIC reach it
// through the app's bridge, since Flutter misreads its 10-bit output (IMG-13).
// tool/test_android_device.sh
// runs it in profile mode (optimized Rust), serves the fixtures from the host
// over `adb reverse`, and receives the artifacts through reportData. Nothing
// here reads or writes the phone's storage or gallery.
// See docs/17-TODO.md T-09 and docs/14-ISSUES.md IMG-13.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final device = <String, Object?>{};
  PermissionState? photos;

  setUpAll(() async {
    expect(Platform.isAndroid, isTrue, reason: 'This suite requires Android');
    expect(await DarkLibCore.ensureReady(), isTrue);
    device['hardwareAv1'] = await NativeAvifEncoder.isAvailable();
    // Asked before any test: the request can switch the platform's
    // accessibility on, which a running test reports as a leaked
    // SemanticsHandle.
    if (_galleryTests) photos = await PhotoManager.requestPermissionExtend();
  });

  tearDownAll(
    () => binding.reportData = {
      'device': device,
      'artifacts': {
        for (final e in _artifacts.entries) e.key: base64Encode(e.value),
      },
    },
  );

  // T-08: JPEG for a transparent image composites it onto white
  // (user decision 2026-09-29), whatever the source container.
  for (final kind in ['png', 'webp', 'avif']) {
    testWidgets('Transparent $kind to JPEG flattens onto white', (_) async {
      final source = await _transparent(kind);
      final facts = await SourceInspector.inspect(source);
      expect(facts.alpha, kind == 'avif' ? isNot(false) : isTrue);
      for (final alpha in <bool?>[facts.alpha, null]) {
        final result = await ImageEncoder.encode(
          source: source,
          target: DefaultFormat.jpeg,
          quality: 90,
          facts: SourceFacts(
            alpha: alpha,
            directHdr: facts.directHdr,
            gainMap: facts.gainMap,
          ),
          keepMetadata: false,
        );
        expect(result.format, DefaultFormat.jpeg);
        expect(
          result.diagnostics.map((d) => d.code),
          contains(MediaDiagnosticCode.alphaFlattened),
        );
        device['flatten-$kind'] = result.backend?.name;
        await _artifact('flatten-$kind.jpg', result.bytes);
        final shown = await _platformDecode(result.bytes);
        final p = shown.pixel(8, 6);
        // (80,120,160) at alpha 64/255 over white, never black.
        expect(p[0], closeTo(211, 8));
        expect(p[1], closeTo(221, 8));
        expect(p[2], closeTo(231, 8));
      }
    });
  }

  // T-09 / DEV-01: an SDR source takes hardware AV1 only when the phone has
  // it; otherwise DarkLib. Output must decode in Android's own decoder.
  testWidgets('SDR to AVIF: engine recorded, platform decodes it', (_) async {
    final source = _png(alpha: false);
    final facts = await SourceInspector.inspect(source);
    expect(
      (facts.alpha, facts.directHdr, facts.gainMap),
      (false, false, false),
    );
    final clock = Stopwatch()..start();
    final result = await ImageEncoder.encode(
      source: source,
      target: DefaultFormat.avif,
      quality: 80,
      facts: facts,
      keepMetadata: false,
    );
    device['sdrAvif'] = {
      'backend': result.backend?.name,
      'bytes': result.bytes.length,
      'ms': clock.elapsedMilliseconds,
      'diagnostics': result.diagnostics.map((d) => d.toString()).toList(),
    };
    final hardware = device['hardwareAv1'] == true;
    expect(
      result.backend,
      hardware ? MediaBackend.androidAvif : MediaBackend.darklib,
    );
    await _artifact('sdr.avif', result.bytes);
    // Android's decoder via the bridge, and flutter_avif, which draws the
    // compare preview of an AVIF result.
    final frames = await avif.decodeAvif(result.bytes);
    for (final shown in [
      await _platformDecode(result.bytes),
      await _read(frames.single.image),
    ]) {
      final p = shown.pixel(8, 6);
      expect(p[0], closeTo(80, 8));
      expect(p[1], closeTo(120, 8));
      expect(p[2], closeTo(160, 8));
      expect(p[3], 255);
    }
  });

  // The bridge has no verified tone mapper: PQ as SDR is declined at the
  // header, while a plain preview decode still works.
  testWidgets('Bridge declines PQ as SDR, previews it otherwise', (_) async {
    final pq = await _fixture('seine_hdr_rec2020.avif');
    final (sdr, events) = await MediaDiagnostics.trace((trace) async {
      final r = await NativeImageEncoder.bakeUpright(
        source: pq,
        keepMetadata: false,
        keepOriginalTime: true,
        toSdr: true,
      );
      return (r, trace.events.map((e) => e.toString()).toList());
    });
    expect(sdr, isNull);
    expect(events, ['androidDecoder.bake.emptyOutput']);
    final preview = await PlatformPixels.forDisplay(pq, maxEdge: 0);
    expect(ImageProbe.sniff(preview), SniffedFormat.png);
  });

  // Android has no tone mapper: a PQ original is refused before any engine.
  for (final target in [DefaultFormat.avif, DefaultFormat.webp]) {
    testWidgets('PQ to ${target.name} is refused early', (_) async {
      final source = await _fixture('seine_hdr_rec2020.avif');
      final facts = await SourceInspector.inspect(source);
      expect(facts.directHdr, isTrue);
      await expectLater(
        ImageEncoder.encode(
          source: source,
          target: target,
          quality: 80,
          facts: facts,
          keepMetadata: true,
        ),
        throwsA(
          isA<ImageEncodingFailure>().having(
            (e) => e.diagnostics.map((d) => d.toString()).toList(),
            'refused before any engine',
            // Android has no verified tone mapper; with metadata requested
            // the bridge is not even asked, and no engine is tried.
            [
              'androidDecoder.bake.unavailable',
              'imageEncoder.encode.hdrToneMapUnavailable',
            ],
          ),
        ),
      );
    });
  }

  // HLG has no verified tone mapper on Android either (IMG-14): refused.
  testWidgets('HLG HEIC is refused early', (_) async {
    final source = await _fixture('apple_heic_hlg.heic');
    final facts = await SourceInspector.inspect(source);
    device['hlgFacts'] = [facts.directHdr, facts.gainMap];
    expect(facts.directHdr, isTrue);
    await expectLater(
      ImageEncoder.encode(
        source: source,
        target: DefaultFormat.webp,
        quality: 80,
        facts: facts,
        keepMetadata: false,
      ),
      throwsA(
        isA<ImageEncodingFailure>().having(
          (e) => e.diagnostics.map((d) => d.toString()).toList(),
          'refused at the header, before any engine',
          [
            'androidDecoder.bake.emptyOutput',
            'imageEncoder.encode.hdrToneMapUnavailable',
          ],
        ),
      ),
    );
  });

  // T-08 / IMG-15 for HEIC: Android's HEIF decoder ignores the alpha plane.
  // DarkLib reads the alpha auxiliary from the container, so the plan knows
  // the source is transparent: JPEG is composited onto white by a decoder
  // that reads alpha, or refused as alphaLost; formats that keep alpha either
  // keep it or are refused. Never the hidden colour (80,120,160) as opaque.
  for (final target in [
    DefaultFormat.jpeg,
    DefaultFormat.png,
    DefaultFormat.webp,
  ]) {
    testWidgets('Transparent HEIC to ${target.name}: alpha kept or refused', (
      _,
    ) async {
      final source = await _fixture('apple_heic_alpha.heic');
      final facts = await SourceInspector.inspect(source);
      expect(facts.alpha, isTrue);
      final EncodedImage result;
      try {
        result = await ImageEncoder.encode(
          source: source,
          target: target,
          quality: 95,
          facts: facts,
          keepMetadata: false,
        );
      } on ImageEncodingFailure catch (e) {
        expect(
          e.diagnostics.map((d) => d.code),
          contains(MediaDiagnosticCode.alphaLost),
        );
        device['heic-alpha-${target.name}'] = 'refused: alphaLost';
        return;
      }
      device['heic-alpha-${target.name}'] = result.backend?.name;
      await _artifact('heic-alpha.${result.extension}', result.bytes);
      if (target != DefaultFormat.jpeg) {
        expect(await ImageProbe.hasAlpha(result.bytes), isTrue);
        return;
      }
      final shown = await _platformDecode(result.bytes);
      expect((shown.width, shown.height), (64, 48));
      final translucent = shown.pixel(6, 6);
      expect(translucent[0], closeTo(211, 10));
      expect(translucent[1], closeTo(221, 10));
      expect(translucent[2], closeTo(231, 10));
      final opaque = shown.pixel(32, 24);
      for (var c = 0; c < 3; c++) {
        expect(opaque[c], lessThan(24));
      }
    });
  }

  // T-09: JPEG Ultra HDR (hdrgm XMP + MPF) to formats without its map gives
  // the SDR base, recorded as hdrToSdr.
  for (final target in [DefaultFormat.webp, DefaultFormat.avif]) {
    testWidgets('Ultra HDR JPEG to ${target.name} gives the SDR base', (
      _,
    ) async {
      final source = await _fixture('seine_sdr_gainmap_srgb.jpg');
      final facts = await SourceInspector.inspect(source);
      expect((facts.directHdr, facts.gainMap), (false, true));
      final result = await ImageEncoder.encode(
        source: source,
        target: target,
        quality: 90,
        facts: facts,
        keepMetadata: true,
      );
      device['ultraHdr-${target.name}'] = [
        result.backend?.name,
        result.hdr?.name,
        ...result.diagnostics.map((d) => d.toString()),
      ];
      expect(
        result.diagnostics.map((d) => d.code),
        contains(MediaDiagnosticCode.hdrToSdr),
      );
      expect(
        (await DarkLibCore.inspect(result.bytes))!.gainMap,
        isNot(Presence.present),
      );
      await _artifact(
        'ultrahdr-to-${target.name}.${result.extension}',
        result.bytes,
      );
      _expectSameImage(
        await _platformDecode(source),
        await _platformDecode(result.bytes),
      );
    });
  }

  testWidgets('Gain map: SDR base to WebP, kept AVIF to AVIF', (_) async {
    final source = await _fixture('seine_sdr_gainmap_srgb.avif');
    final facts = await SourceInspector.inspect(source);
    expect((facts.directHdr, facts.gainMap), (false, true));
    final base = await _platformDecode(source);

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
    _expectSameImage(base, await _platformDecode(webp.bytes));

    final avif = await ImageEncoder.encode(
      source: source,
      target: DefaultFormat.avif,
      quality: 80,
      facts: facts,
      keepMetadata: true,
    );
    expect(avif.backend, MediaBackend.darklib);
    expect(avif.hdr, HdrOutcome.gainMapKept);
    await _artifact('gainmap-to-avif.avif', avif.bytes);
    expect((await DarkLibCore.inspect(avif.bytes))!.gainMap, Presence.present);
    // Android's decoder shows the SDR base of the rebuilt file.
    _expectSameImage(base, await _platformDecode(avif.bytes));
  });

  // T-13 (arm64 part): the strip is a container edit, so the phone must give
  // the exact bytes the host test produced, and the shown image must not move.
  for (final name in _orientationNames()) {
    testWidgets('Strip keeps orientation of $name', (_) async {
      final source = await _fixture('strip-sources/$name');
      final expected = await _fixture('strip-expected/$name');
      final out = await DarkLibCore.stripMetadata(source);
      expect(out, isNotNull);
      expect(out, orderedEquals(expected), reason: 'same bytes as the host');
      await _artifact('strip/$name', out!);
      final before = await _platformDecode(source);
      final after = await _platformDecode(out);
      expect((after.width, after.height), (before.width, before.height));
      expect(after.rgba, orderedEquals(before.rgba));
      // Android's PNG output takes the bridge for any source: it must turn
      // the image the same way Flutter shows it.
      final baked = await NativeImageEncoder.bakeUpright(
        source: source,
        keepMetadata: false,
        keepOriginalTime: true,
      );
      final bridged = await _flutterDecode(baked!);
      expect((bridged.width, bridged.height), (before.width, before.height));
      expect(bridged.rgba, orderedEquals(before.rgba));
    });
  }

  for (final target in [
    DefaultFormat.png,
    DefaultFormat.jpeg,
    DefaultFormat.webp,
    DefaultFormat.heic,
  ]) {
    testWidgets('${target.name}: primary Android encode decodes back', (
      _,
    ) async {
      final alpha = target == DefaultFormat.png || target == DefaultFormat.webp;
      final source = _png(alpha: alpha);
      final facts = await SourceInspector.inspect(source);
      final result = await ImageEncoder.encode(
        source: source,
        target: target,
        quality: 90,
        facts: facts,
        keepMetadata: false,
      );
      expect(result.format, target);
      expect(result.backend, switch (target) {
        DefaultFormat.webp => MediaBackend.darklib,
        DefaultFormat.png => MediaBackend.androidDecoder,
        _ => MediaBackend.imageCompress,
      });
      // The iOS-only ImageIO encoder is tried first for JPEG/HEIC; only that
      // miss is accepted, so any engine error or fallback fails the test.
      expect(result.diagnostics.map((d) => d.toString()), switch (target) {
        DefaultFormat.png || DefaultFormat.webp => isEmpty,
        _ => ['imageIO.encode.unavailable'],
      });
      device['encode-${target.name}'] = result.backend?.name;
      await _artifact(
        '${target.name}-encoded.${result.extension}',
        result.bytes,
      );
      final shown = await _platformDecode(result.bytes);
      expect((shown.width, shown.height), (16, 12));
      final p = shown.pixel(8, 6);
      if (alpha) expect(p[3], closeTo(64, 2));
      // Premultiplied read-back of a translucent pixel loses a little.
      final tolerance = alpha ? 12 : 8;
      expect(p[0], closeTo(80, tolerance));
      expect(p[1], closeTo(120, tolerance));
      expect(p[2], closeTo(160, tolerance));
    });
  }

  // T-14/T-15: the real crop task on 10-bit gallery assets. Before IMG-13 it
  // decoded them through Flutter and saved scrambled colours. It writes the
  // sources and results to the gallery, so it runs only with HAYN_GALLERY=1;
  // the files stay for the user to remove.
  final tenBit = <String, Future<Uint8List> Function()>{
    'sdr.avif': () => _tenBitAvif(withGainMap: false),
    'gainmap.avif': () => _tenBitAvif(withGainMap: true),
    'p3.heic': () => _fixture('apple_heic_10bit_p3.heic'),
  };
  for (final MapEntry(key: name, value: load) in tenBit.entries) {
    testWidgets('Crop keeps the colours of a 10-bit $name', (_) async {
      expect(photos?.isAuth, isTrue, reason: 'Photo access was refused');
      final source = await load();
      final asset = await GallerySaver.saveImage(
        source,
        filename: 'hayn-test-crop-source-$name',
      );
      expect(asset, isNotNull);
      final task = ImageCropTask(
        assetId: asset!.id,
        rotationQuarters: 0,
        flipH: false,
        flipV: false,
        cropFraction: const Rect.fromLTWH(0, 0, 1, 1),
      );
      final events = await task.run().toList();
      expect(events.last, isA<TaskSucceeded>());
      final output = await (await AssetEntity.fromId(
        task.outputAssetIds.single,
      ))!.originBytes;
      await _artifact('crop-$name-result', output!);
      _expectSameImage(
        await _platformDecode(source),
        await _platformDecode(output),
      );
    }, skip: !_galleryTests);
  }

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

List<String> _orientationNames() => [
  for (final ext in ['jpg', 'png', 'webp'])
    for (var o = 1; o <= 8; o++) '$ext-o$o.$ext',
];

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

/// The same translucent image in [kind]; WebP and AVIF come from DarkLib.
Future<Uint8List> _transparent(String kind) async {
  final png = _png(alpha: true);
  if (kind == 'png') return png;
  final out = await DarkLibCore.transcode(
    png,
    format: kind == 'webp' ? DarkLibFormat.webp : DarkLibFormat.avif,
    quality: 100,
    keepMetadata: false,
  );
  expect(out, isNotNull);
  return out!.bytes;
}

/// Gallery-writing tests are opt-in (tool/test_android_device.sh documents it).
const _galleryTests = bool.fromEnvironment('HAYN_GALLERY');

/// A 10-bit AVIF from DarkLib (ravif's default depth): the libavif photo with
/// its ISO gain map kept, or its SDR base alone.
Future<Uint8List> _tenBitAvif({required bool withGainMap}) async {
  final photo = await _fixture('seine_sdr_gainmap_srgb.avif');
  final input = withGainMap
      ? photo
      : (await DarkLibCore.transcode(
          photo,
          format: DarkLibFormat.png,
          quality: 100,
          keepMetadata: false,
        ))!.bytes;
  final out = await DarkLibCore.transcode(
    input,
    format: DarkLibFormat.avif,
    quality: 90,
    keepMetadata: false,
  );
  expect(out!.hdr, withGainMap ? HdrOutcome.gainMapKept : HdrOutcome.none);
  return out.bytes;
}

/// Base URL of the host's fixture server, reached through `adb reverse`.
const _fixtures = String.fromEnvironment('HAYN_FIXTURES');

Future<Uint8List> _fixture(String name) async {
  expect(_fixtures, isNotEmpty, reason: 'Run via tool/test_android_device.sh');
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(
      Uri.parse('$_fixtures/$name'),
    )).close();
    expect(response.statusCode, HttpStatus.ok, reason: name);
    return await consolidateHttpClientResponseBytes(response);
  } finally {
    client.close();
  }
}

final _artifacts = <String, List<int>>{};

Future<void> _artifact(String name, List<int> bytes) async =>
    _artifacts[name] = bytes;

class _Shown {
  const _Shown(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;

  List<int> pixel(int x, int y) {
    final i = (y * width + x) * 4;
    return rgba.sublist(i, i + 4);
  }
}

/// Decoded as the app shows it: AVIF/HEIC through Android's ImageDecoder
/// bridge (IMG-13), the rest by Flutter. Orientation applied, straight RGBA.
Future<_Shown> _platformDecode(Uint8List bytes) async =>
    _flutterDecode(await PlatformPixels.forDisplay(bytes, maxEdge: 0));

Future<_Shown> _flutterDecode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final shown = await _read(image);
  codec.dispose();
  return shown;
}

Future<_Shown> _read(ui.Image image) async {
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final shown = _Shown(image.width, image.height, data!.buffer.asUint8List());
  image.dispose();
  return shown;
}

/// Same size and near-identical pixels (a lossy re-encode of one rendition).
void _expectSameImage(_Shown a, _Shown b) {
  expect((b.width, b.height), (a.width, a.height));
  var total = 0;
  var samples = 0;
  for (var y = 0; y < a.height; y += 7) {
    for (var x = 0; x < a.width; x += 7) {
      final p = a.pixel(x, y);
      final q = b.pixel(x, y);
      for (var c = 0; c < 3; c++) {
        total += (p[c] - q[c]).abs();
        samples++;
      }
    }
  }
  expect(total / samples, lessThan(4));
}
