import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart' as avif;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:image/image.dart' as img;
import 'package:hayn/features/image_ops/domain/image_format_policy.dart';
import 'package:hayn/core/capabilities/format_capabilities.dart';
import 'package:hayn/app/app.dart';
import 'package:hayn/app/l10n/app_localizations.dart';
import 'package:hayn/app/theme/app_theme.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/core/isolates/heavy_work.dart';
import 'package:hayn/core/isolates/task_progress.dart';
import 'package:hayn/core/isolates/task_runner.dart';
import 'package:hayn/features/image_ops/data/gallery_saver.dart';
import 'package:hayn/features/image_ops/data/image_compress_task.dart';
import 'package:hayn/features/image_ops/data/image_crop_task.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/image_probe.dart';
import 'package:hayn/features/image_ops/data/native_avif_encoder.dart';
import 'package:hayn/features/image_ops/data/native_image_encoder.dart';
import 'package:hayn/features/image_ops/data/original_rendition.dart';
import 'package:hayn/features/image_ops/data/platform_pixels.dart';
import 'package:hayn/features/image_ops/data/region_image.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/image_ops/presentation/compress_screen.dart';
import 'package:hayn/features/image_ops/presentation/widgets/region_tiles.dart';
import 'package:hayn/features/library/presentation/asset_detail_screen.dart';
import 'package:hayn/features/library/presentation/full_res_image.dart';
import 'package:hayn/features/library/presentation/library_screen.dart';
import 'package:hayn/features/onboarding/providers/onboarding_provider.dart';
import 'package:hayn/features/settings/presentation/settings_screen.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/shared/widgets/buttons.dart';
import 'package:hayn/shared/widgets/comparison_viewer.dart';
import 'package:hayn/src/rust/api/metadata.dart' as dl;

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
    photos = await PhotoManager.requestPermissionExtend();
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
            // Android has no verified tone mapper: the bridge declines the
            // SDR rendition at the header, and no engine is tried.
            [
              'androidDecoder.bake.emptyOutput',
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

  // T-08 / IMG-15 for HEIC: Android's HEIF decoder ignores the alpha plane,
  // which Apple codes as monochrome HEVC. DarkLib extracts it, the FFmpeg the
  // app ships decodes it, and DarkLib puts it back (HeifAlpha). Every target
  // must now succeed with the real transparency: JPEG composited onto white,
  // the others keeping alpha 64. Never the hidden colour (80,120,160).
  // With metadata (the compress screen's default) the bridge decodes without
  // it and DarkLib carries the source's onto the result.
  for (final keepMetadata in [false, true]) {
    for (final target in [
      DefaultFormat.jpeg,
      DefaultFormat.png,
      DefaultFormat.webp,
      DefaultFormat.avif,
    ]) {
      _transparentHeic(target, keepMetadata, device);
    }
  }

  // IMG-08 through the Android bridge: a P3 HEIC to WebP and PNG, with and
  // without metadata. The bridge keeps P3 and its profile; DarkLib carries the
  // source's. Before, the bridge turned pixels to sRGB while the source's P3
  // profile was carried onto them, oversaturating the result. JPEG and HEIC
  // (IMG-24) keep the decoder's raw values and carry the profile that names
  // them.
  for (final keepMetadata in [false, true]) {
    for (final target in [
      DefaultFormat.webp,
      DefaultFormat.png,
      DefaultFormat.jpeg,
      DefaultFormat.heic,
    ]) {
      final label = '${target.name}${keepMetadata ? ' with metadata' : ''}';
      testWidgets('P3 HEIC to $label keeps its colours', (_) async {
        final source = await _fixture('apple_heic_10bit_p3.heic');
        final result = await ImageEncoder.encode(
          source: source,
          target: target,
          quality: 95,
          facts: await SourceInspector.inspect(source),
          keepMetadata: keepMetadata,
        );
        device['p3heic-$label'] = result.backend?.name;
        await _artifact(
          'p3heic/${target.name}${keepMetadata ? '-meta' : ''}.${result.extension}',
          result.bytes,
        );
        Future<_Shown> managed(Uint8List bytes) async => _flutterDecode(
          (await NativeImageEncoder.bakeUpright(
            source: bytes,
            keepMetadata: false,
            keepOriginalTime: true,
            colours: BakeColours.srgb,
          ))!,
        );
        _expectSameImage(await managed(source), await managed(result.bytes));
      });
    }
  }

  // IMG-15 in the viewer and previews: the display path gets the plane back
  // too, scaled to a preview sampled down.
  for (final maxEdge in [0, 32]) {
    testWidgets('Transparent HEIC shows its transparency (maxEdge $maxEdge)', (
      _,
    ) async {
      final source = await _fixture('apple_heic_alpha.heic');
      final shown = img.decodePng(
        await PlatformPixels.forDisplay(source, maxEdge: maxEdge),
      )!;
      final scale = shown.width / 64;
      expect(shown.height, (48 * scale).round());
      expect(
        shown.getPixel((6 * scale).round(), (6 * scale).round()).a,
        closeTo(64, 12),
      );
      expect(shown.getPixel((32 * scale).round(), (24 * scale).round()).a, 255);
    });
  }

  // IMG-08 on Android: without metadata, a P3 source must keep its colour
  // meaning in each target, through whichever engine Android picks (JPEG and
  // HEIC from the platform decoder's raw values, IMG-24). Both sides are read
  // by Android's colour-managed decoder into sRGB. The patches move 10 to 24
  // levels between P3 and sRGB (ImageCms), so a dropped profile shows; the
  // control proves it.
  for (final target in [
    DefaultFormat.jpeg,
    DefaultFormat.png,
    DefaultFormat.heic,
  ]) {
    testWidgets('P3 to ${target.name} without metadata keeps its colours', (
      _,
    ) async {
      final p3 = img.decodePng(await _fixture('apple_png_p3_icc.png'))!;
      final patches = img.Image(width: 64, height: 64)
        ..iccProfile = p3.iccProfile;
      const colours = [
        (200, 100, 50),
        (60, 170, 90),
        (180, 60, 140),
        (230, 200, 60),
      ];
      for (var i = 0; i < 4; i++) {
        final (r, g, b) = colours[i];
        img.fillRect(
          patches,
          x1: (i % 2) * 32,
          y1: (i ~/ 2) * 32,
          x2: (i % 2) * 32 + 31,
          y2: (i ~/ 2) * 32 + 31,
          color: img.ColorRgb8(r, g, b),
        );
      }
      final source = Uint8List.fromList(img.encodePng(patches));
      final result = await ImageEncoder.encode(
        source: source,
        target: target,
        quality: 95,
        facts: await SourceInspector.inspect(source),
        keepMetadata: false,
      );
      device['p3-${target.name}'] = result.backend?.name;
      await _artifact('p3.${result.extension}', result.bytes);

      Future<img.Image> managed(Uint8List bytes) async => img.decodePng(
        (await NativeImageEncoder.bakeUpright(
          source: bytes,
          keepMetadata: false,
          keepOriginalTime: true,
          colours: BakeColours.srgb,
        ))!,
      )!;
      double meanShift(img.Image a, img.Image b) {
        var total = 0.0;
        for (var i = 0; i < 4; i++) {
          final x = (i % 2) * 32 + 16, y = (i ~/ 2) * 32 + 16;
          final p = a.getPixel(x, y), q = b.getPixel(x, y);
          total += (p.r - q.r).abs() + (p.g - q.g).abs() + (p.b - q.b).abs();
        }
        return total / 12;
      }

      final want = await managed(source);
      // The decoder manages colour: P3 (200,100,50) reads as sRGB (215,93,31).
      final first = want.getPixel(16, 16);
      expect(
        [first.r, first.g, first.b],
        [closeTo(215, 4), closeTo(93, 4), closeTo(31, 4)],
      );
      final shift = meanShift(want, await managed(result.bytes));
      device['p3-${target.name}-shift'] = shift.toStringAsFixed(1);
      expect(shift, lessThan(4));
      // Control: the same output without a profile reads visibly different,
      // unless the engine converted the pixels to sRGB already.
      final bare = await DarkLibCore.stripMetadata(
        result.bytes,
        stripIcc: true,
      );
      if (bare != null) {
        device['p3-${target.name}-bare-shift'] = meanShift(
          want,
          await managed(bare),
        ).toStringAsFixed(1);
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

  // RUN-01 step 5: HEIC from bands and 512 tiles. The stored pixels stay as
  // decoded and the orientation goes into the container, so what Android
  // shows must match the source as shown: size, the four quadrants (a turn
  // or a mirror swaps them) and the pixels overall. 1100×700 spans 3×2
  // tiles with partial ones on the right and bottom edges.
  for (final (w, h, orientations) in [
    (64, 48, [1, 2, 3, 4, 5, 6, 7, 8]),
    (1100, 700, [1, 2, 5, 6]),
  ]) {
    for (final o in orientations) {
      testWidgets('HEIC tiles: ${w}x$h with orientation $o shows upright', (
        _,
      ) async {
        final source = _quadrants(w, h, orientation: o);
        final facts = await SourceInspector.inspect(source);
        expect(facts.orientation, o);
        final sw = Stopwatch()..start();
        final out = await NativeImageEncoder.encodeHeicTiles(
          source: source,
          quality: 95,
          orientation: facts.orientation,
        );
        expect(out, isNotNull);
        device['heic-tiles-${w}x$h-o$o-ms'] = sw.elapsedMilliseconds;
        device['heic-tiles-codec'] = out!.codec;
        device['heic-tiles-rateMode'] = out.rateMode;
        await _artifact('heic-tiles/${w}x$h-o$o.heic', out.bytes);
        final before = await _platformDecode(source);
        final after = await _platformDecode(out.bytes);
        _expectSameQuadrants(before, after);
        _expectSameImage(before, after);
      });
    }
  }

  // The tiles keep the decoded colour space and write no profile; the
  // source's is carried after (DarkLib, into the idat grid). Without it a P3
  // image would be read as sRGB.
  // Formats without random access are decoded once, whole, then tiled the
  // same way (a region re-reads every row above it).
  for (final kind in [
    DarkLibFormat.png,
    DarkLibFormat.webp,
    DarkLibFormat.avif,
  ]) {
    testWidgets('HEIC tiles: a ${kind.name} source decodes back', (_) async {
      final source = (await DarkLibCore.transcode(
        _quadrants(1100, 700, orientation: 1),
        format: kind,
        quality: 100,
        keepMetadata: false,
      ))!.bytes;
      final out = await NativeImageEncoder.encodeHeicTiles(
        source: source,
        quality: 95,
        orientation: 0,
      );
      expect(out, isNotNull);
      await _artifact('heic-tiles/from-${kind.name}.heic', out!.bytes);
      final before = await _platformDecode(source);
      final after = await _platformDecode(out.bytes);
      _expectSameQuadrants(before, after);
      _expectSameImage(before, after);
    });
  }

  // Android's decoder ignores the colour profile of every HEIC on this phone
  // (an Apple P3 HEIC included: its pixels come as sRGB, IMG-21), so it
  // cannot judge colour here. On the phone: the stored values are the
  // source's and its profile travels with them. The colour itself is judged
  // on the host by libheif with colour management
  // (test_native/check_heic_tiles.py).
  testWidgets('HEIC tiles: a Display P3 source keeps its values and profile', (
    _,
  ) async {
    // Saturated quadrants named P3 by the fixture's own profile.
    final source = await DarkLibCore.transplantMetadata(
      source: await _fixture('apple_png_p3_icc.png'),
      target: _quadrants(256, 192, orientation: 1),
    );
    expect(dl.readMetadataSummary(bytes: source!).hasIcc, isTrue);
    final out = await NativeImageEncoder.encodeHeicTiles(
      source: source,
      quality: 95,
      orientation: 0,
    );
    expect(out, isNotNull);
    final carried = await ImageEncoder.carryMetadata(
      source,
      out!.bytes,
      keepMetadata: false,
    );
    expect(carried, isNotNull);
    await _artifact('heic-tiles/p3.heic', carried!);
    await _artifact('heic-tiles/p3-source.jpg', source);
    expect(dl.readMetadataSummary(bytes: carried).hasIcc, isTrue);
    // Values as stored, unconverted: the region decoder kept P3.
    Future<_Shown> raw(Uint8List bytes) async => _flutterDecode(
      img.encodePng(
        img.decodePng(
          (await NativeImageEncoder.bakeUpright(
            source: bytes,
            keepMetadata: false,
            keepOriginalTime: true,
          ))!,
        )!,
      ),
    );
    _expectSameImage(await raw(source), await raw(carried));
  });

  // A HEIC source goes through the region decoder too (Apple, 10-bit P3).
  testWidgets('HEIC tiles: an Apple HEIC source decodes back', (_) async {
    final source = await _fixture('apple_heic_10bit_p3.heic');
    final facts = await SourceInspector.inspect(source);
    final out = await NativeImageEncoder.encodeHeicTiles(
      source: source,
      quality: 95,
      orientation: facts.orientation,
    );
    expect(out, isNotNull);
    final carried = await ImageEncoder.carryMetadata(
      source,
      out!.bytes,
      keepMetadata: false,
    );
    await _artifact('heic-tiles/apple-10bit.heic', carried!);
    _expectSameImage(
      await _platformDecode(source),
      await _platformDecode(carried),
    );
  });

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
      // Never flutter_image_compress on Android (IMG-24).
      expect(result.backend, switch (target) {
        DefaultFormat.webp => MediaBackend.darklib,
        DefaultFormat.png => MediaBackend.androidDecoder,
        DefaultFormat.jpeg => MediaBackend.androidJpeg,
        _ => MediaBackend.androidHeic,
      });
      // Any engine error or fallback fails the test.
      expect(result.diagnostics, isEmpty);
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

  // IMG-21: Android's decoder ignores a HEIC's colour profile and calls its
  // values sRGB. The display path names them with the profile's space from
  // DarkLib, and Android converts. The expected colours are LittleCMS's, on
  // the host, for the libheif files (fixtures/README).
  for (final name in ['libheif_p3_icc.heic', 'libheif_p3_nclx.heic']) {
    testWidgets('A P3 HEIC shows its colours: $name', (_) async {
      final shown = await _flutterDecode(
        await PlatformPixels.forDisplay(await _fixture(name), maxEdge: 0),
      );
      _expectP3Quadrants(shown);
    });
  }

  // IMG-21: the crop keeps the stored values and carries the source's
  // profile (P3 stays P3), where it saved a HEIC's P3 values as sRGB. Judged
  // through the display path against the same LittleCMS colours.
  final p3Crops = <String, Future<Uint8List> Function()>{
    'p3-icc.heic': () => _fixture('libheif_p3_icc.heic'),
    'p3-nclx.heic': () => _fixture('libheif_p3_nclx.heic'),
    'p3.jpg': () async => (await DarkLibCore.transplantMetadata(
      source: await _fixture('apple_png_p3_icc.png'),
      target: _quadrants(64, 48, orientation: 1),
    ))!,
  };
  for (final MapEntry(key: name, value: load) in p3Crops.entries) {
    testWidgets('Crop keeps the P3 colours of $name', (_) async {
      expect(photos?.isAuth, isTrue, reason: 'Photo access was refused');
      final asset = await GallerySaver.saveImage(
        await load(),
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
      await _artifact('crop-p3/$name-result', output!);
      expect(dl.readMetadataSummary(bytes: output).hasIcc, isTrue);
      _expectP3Quadrants(
        await _flutterDecode(
          await PlatformPixels.forDisplay(output, maxEdge: 0),
        ),
      );
    });
  }

  // T-14/T-15: the real crop task on 10-bit gallery assets. Before IMG-13 it
  // decoded them through Flutter and saved scrambled colours. It writes the
  // sources and results to the gallery (`hayn-test-crop-*`), every run; the
  // files stay for the user to remove.
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
    });
  }

  // PERF-03: the zoomed views read tiles through BitmapRegionDecoder, which
  // ignores the orientation; the bridge maps each upright rectangle to the
  // stored pixels and turns the tile. Put back together, the tiles must be
  // the image as the app shows it whole: size, quadrants and pixels.
  for (final o in [1, 2, 3, 4, 5, 6, 7, 8]) {
    testWidgets('Region tiles: a JPEG with orientation $o shows upright', (
      _,
    ) async {
      final source = _quadrants(1100, 700, orientation: o);
      final whole = await _regionWhole(source);
      final before = await _platformDecode(source);
      _expectSameQuadrants(before, whole);
      _expectSameImage(before, whole);
    });
  }

  // The tiled HEIC writes the orientation as irot/imir in the container.
  for (final o in [1, 2, 5, 6]) {
    testWidgets('Region tiles: a HEIC with orientation $o shows upright', (
      _,
    ) async {
      final out = await NativeImageEncoder.encodeHeicTiles(
        source: _quadrants(1100, 700, orientation: o),
        quality: 95,
        orientation: o,
      );
      expect(out, isNotNull);
      final whole = await _regionWhole(out!.bytes);
      final before = await _platformDecode(out.bytes);
      _expectSameQuadrants(before, whole);
      _expectSameImage(before, whole);
    });
  }

  // IMG-21 holds for tiles too: a HEIC's profile names its values, a JPEG's
  // is applied; the colours are LittleCMS's (fixtures/README).
  final p3Regions = <String, Future<Uint8List> Function()>{
    'libheif_p3_icc.heic': () => _fixture('libheif_p3_icc.heic'),
    'libheif_p3_nclx.heic': () => _fixture('libheif_p3_nclx.heic'),
    'P3 JPEG': () async => (await DarkLibCore.transplantMetadata(
      source: await _fixture('apple_png_p3_icc.png'),
      target: _quadrants(64, 48, orientation: 1),
    ))!,
  };
  for (final MapEntry(key: name, value: load) in p3Regions.entries) {
    testWidgets('Region tiles: $name shows its colours', (_) async {
      _expectP3Quadrants(await _regionWhole(await load()));
    });
  }

  testWidgets('Region tiles: an Apple 10-bit HEIC matches the whole decode', (
    _,
  ) async {
    final source = await _fixture('apple_heic_10bit_p3.heic');
    final sw = Stopwatch()..start();
    final whole = await _regionWhole(source);
    device['region-apple-heic-ms'] = sw.elapsedMilliseconds;
    _expectSameImage(await _platformDecode(source), whole);
  });

  // Android's ARGB_8888 is premultiplied, which Flutter's rgba8888 expects:
  // read back straight, a translucent pixel keeps its colour and alpha.
  testWidgets('Region tiles: a translucent PNG keeps colour and alpha', (
    _,
  ) async {
    final whole = await _regionWhole(_png(alpha: true));
    final p = whole.pixel(8, 6);
    expect(p[3], 64);
    for (final (c, want) in [(0, 80), (1, 120), (2, 160)]) {
      expect(p[c], closeTo(want, 4), reason: '$p');
    }
  });

  testWidgets('Region tiles: a sampled tile is smaller; none after close', (
    _,
  ) async {
    final region = await RegionImage.open(
      _quadrants(1100, 700, orientation: 6),
    );
    expect(region, isNotNull);
    expect((region!.width, region.height), (700, 1100));
    final half = await region.tile(const Rect.fromLTRB(0, 0, 700, 1024), 2);
    expect((half!.width, half.height), (350, 512));
    half.dispose();
    await region.close();
    expect(await region.tile(const Rect.fromLTRB(0, 0, 64, 64), 1), isNull);
  });

  // AVIF reads through DarkLib on every platform: one item decoded once into
  // raw files in the cache directory, a grid cell by cell. Put back
  // together, the tiles must be what Android's own decoder shows.
  testWidgets('Region tiles: an AVIF of one item matches the whole decode', (
    _,
  ) async {
    final source = (await DarkLibCore.transcode(
      _quadrants(1100, 700, orientation: 1),
      format: DarkLibFormat.avif,
      quality: 100,
      keepMetadata: false,
    ))!.bytes;
    final whole = await _regionWhole(source);
    final before = await _platformDecode(source);
    _expectSameQuadrants(before, whole);
    _expectSameImage(before, whole);
  });

  testWidgets('Region tiles: an AVIF grid matches the whole decode', (_) async {
    final source = await _fixture('sofa_grid1x5_420.avif');
    _expectSameImage(await _platformDecode(source), await _regionWhole(source));
  });

  // The AVIF's profile converts to sRGB in DarkLib (LittleCMS's values).
  testWidgets('Region tiles: a P3 AVIF shows its colours', (_) async {
    final p3 = (await DarkLibCore.transplantMetadata(
      source: await _fixture('apple_png_p3_icc.png'),
      target: _quadrants(64, 48, orientation: 1),
    ))!;
    final avif = (await DarkLibCore.transcode(
      p3,
      format: DarkLibFormat.avif,
      quality: 100,
      keepMetadata: true,
    ))!.bytes;
    _expectP3Quadrants(await _regionWhole(avif));
  });

  // PQ has no SDR display here: refused, recorded, the bounded decode shows
  // it. And a closed reader leaves no file in the cache directory.
  testWidgets('Region tiles: a PQ AVIF is refused; nothing is left behind', (
    _,
  ) async {
    final trace = await MediaDiagnostics.trace((trace) async {
      expect(
        await RegionImage.open(await _fixture('seine_hdr_rec2020.avif')),
        isNull,
      );
      return trace;
    });
    expect(
      trace.events.map((d) => d.toString()),
      contains('darklib.display.exception'),
    );
    final region = await RegionImage.open(
      (await DarkLibCore.transcode(
        _quadrants(300, 200, orientation: 1),
        format: DarkLibFormat.avif,
        quality: 90,
        keepMetadata: false,
      ))!.bytes,
    );
    expect(region, isNotNull);
    final dir = await getTemporaryDirectory();
    bool cached(FileSystemEntity f) =>
        f.path.split('/').last.startsWith('darklib-region-');
    expect(dir.listSync().where(cached), isNotEmpty);
    await region!.close();
    expect(dir.listSync().where(cached), isEmpty);
  });

  // PERF-03 end to end: a 3600×2700 checkerboard of 4 px squares under a
  // ×10 zoom near its centre, where four tiles meet (2048, 1536). The squares
  // straddle the 4 px blocks the 1000 px rendition averages, so it shows
  // them grey: the same view without the tile layer is the control. With
  // it, each square must show where it belongs (a viewport pixel is one
  // image pixel here).
  testWidgets('Region tiles draw the zoomed part at full detail', (
    tester,
  ) async {
    final source = _checkerboard(3600, 2700);
    final region = await tester.runAsync(() => RegionImage.open(source));
    expect(region, isNotNull);
    final ctrl = TransformationController(
      Matrix4.identity()
        ..translateByDouble(-1800, -1350, 0, 1)
        ..scaleByDouble(10, 10, 1, 1),
    );
    final viewport = GlobalKey();
    Widget view({required bool tiles}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: viewport,
          child: SizedBox(
            width: 360,
            height: 270,
            child: InteractiveViewer(
              transformationController: ctrl,
              maxScale: 64,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image(image: boundedImage(source, 1000), fit: BoxFit.fill),
                  if (tiles)
                    RegionTiles(
                      region: region!,
                      transform: ctrl,
                      baseLongEdge: 1000,
                      viewportKey: viewport,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Future<(int, int)> score() async =>
        _checkerScore(await _capture(tester, viewport));

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    await tester.pumpWidget(view(tiles: false));
    for (var i = 0; i < 10; i++) {
      await settle(); // the rendition decodes
    }
    final (control, total) = await score();
    await tester.pumpWidget(view(tiles: true));
    final sw = Stopwatch()..start();
    var right = 0;
    for (var i = 0; i < 60 && right < total * 0.98; i++) {
      if (i > 0) await settle(); // tiles arrive asynchronously
      (right, _) = await score();
    }
    device['region-draw-ms'] = sw.elapsedMilliseconds;
    device['region-draw-right'] = 'control $control, tiles $right of $total';
    expect(control / total, lessThan(0.75), reason: 'the rendition shows it');
    expect(right / total, greaterThan(0.98), reason: '$right of $total');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(region!.close);
    ctrl.dispose();
  });

  // The compare screen's panes: "before" inside the InteractiveViewer,
  // "after" under the same matrix in a Transform, each read by its own
  // decoder. Both halves must show the squares where they belong; the
  // labels, the split line and its handle are left out of the count.
  testWidgets('Compare panes draw the zoomed part at full detail', (
    tester,
  ) async {
    final source = _checkerboard(3600, 2700);
    final regions = await tester.runAsync(
      () => Future.wait([RegionImage.open(source), RegionImage.open(source)]),
    );
    expect(regions, everyElement(isNotNull));
    final ctrl = TransformationController(
      Matrix4.identity()
        ..translateByDouble(-1800, -1350, 0, 1)
        ..scaleByDouble(10, 10, 1, 1),
    );
    final viewport = GlobalKey();
    Widget pane(RegionImage region) => AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(image: boundedImage(source, 1000), fit: BoxFit.fill),
          RegionTiles(
            region: region,
            transform: ctrl,
            baseLongEdge: 1000,
            viewportKey: viewport,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            height: 270,
            child: RepaintBoundary(
              key: viewport,
              child: HaynComparisonViewer(
                controller: ctrl,
                beforeLabel: 'before',
                afterLabel: 'after',
                before: pane(regions![0]!),
                after: pane(regions[1]!),
              ),
            ),
          ),
        ),
      ),
    );
    bool chrome(int x, int y) => y < 32 || y > 230 || (x - 180).abs() < 26;
    var left = (0, 0), right = (0, 0);
    for (var i = 0; i < 60; i++) {
      if (i > 0) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      final shot = await _capture(tester, viewport);
      left = _checkerScore(shot, skip: (x, y) => x >= 180 || chrome(x, y));
      right = _checkerScore(shot, skip: (x, y) => x < 180 || chrome(x, y));
      if (left.$1 >= left.$2 * 0.98 && right.$1 >= right.$2 * 0.98) break;
    }
    device['compare-draw-right'] = 'before $left, after $right';
    expect(left.$1 / left.$2, greaterThan(0.98), reason: 'before $left');
    expect(right.$1 / right.$2, greaterThan(0.98), reason: 'after $right');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      for (final r in regions) {
        await r!.close();
      }
    });
    ctrl.dispose();
  });

  // IMG-23: bit depth is the user's choice, 8 or 10, and "match" is the
  // depth of the picked image (user decision 2026-10-09; it was DarkLib's
  // default, 10): here an 8-bit PNG. The output must say the depth it was
  // asked for, decode, and keep its colours.
  testWidgets('AVIF at 8 and 10 bits, and the default', (_) async {
    final source = _gradient(301, 97);
    final facts = await SourceInspector.inspect(source);
    expect(facts.bitDepth, 8);
    for (final (chosen, want) in [(0, 8), (8, 8), (10, 10)]) {
      final result = await ImageEncoder.encode(
        source: source,
        target: DefaultFormat.avif,
        quality: 90,
        facts: facts,
        keepMetadata: false,
        bitDepth: chosen,
      );
      expect((await DarkLibCore.inspect(result.bytes))!.bitDepth, want);
      final error = _channelError(source, await _platformDecode(result.bytes));
      device['avif-depth-$chosen'] = {
        'bytes': result.bytes.length,
        'meanError': error,
      };
      for (final e in error) {
        expect(e, lessThan(2), reason: 'depth $chosen: $error');
      }
    }
  });

  testWidgets('HEIC at 10 bits where the encoder has Main10', (_) async {
    final tenBit = await NativeImageEncoder.heicTenBit();
    device['heicTenBit'] = tenBit;
    if (!tenBit) {
      // Then the picker offers no 10 for HEIC; "match" writes 8 (route test).
      return;
    }
    final source = _gradient(1179, 97);
    final result = await ImageEncoder.encode(
      source: source,
      target: DefaultFormat.heic,
      quality: 100,
      facts: await SourceInspector.inspect(source),
      keepMetadata: false,
      bitDepth: 10,
    );
    expect(result.backend, MediaBackend.androidHeic);
    expect((await DarkLibCore.inspect(result.bytes))!.bitDepth, 10);
    await _artifact('heic-10bit.heic', result.bytes);
    // Through Android's display path, which decodes 10 bits and rounds to
    // 8 (1.52 at most measured); the file itself, read at full precision by
    // libheif, is held to 1.0 by check_heic_tiles.py (section 6).
    final error = _channelError(source, await _platformDecode(result.bytes));
    device['heic10-gradient'] = {
      'bytes': result.bytes.length,
      'meanError': error,
    };
    for (final e in error) {
      expect(e, lessThan(2), reason: 'mean error per channel $error');
    }
    // P3 values kept raw and named by the carried profile, at 10 bits too.
    final p3 = await _fixture('libheif_p3_icc.heic');
    final p3Out = await ImageEncoder.encode(
      source: p3,
      target: DefaultFormat.heic,
      quality: 95,
      facts: await SourceInspector.inspect(p3),
      keepMetadata: false,
      bitDepth: 10,
    );
    await _artifact('heic-10bit-p3.heic', p3Out.bytes);
    _expectP3Quadrants(await _platformDecode(p3Out.bytes));
    // "Match" on Apple's 10-bit HEIC writes 10.
    final deep = await _fixture('apple_heic_10bit_p3.heic');
    final matched = await ImageEncoder.encode(
      source: deep,
      target: DefaultFormat.heic,
      quality: 90,
      facts: await SourceInspector.inspect(deep),
      keepMetadata: false,
    );
    expect((await DarkLibCore.inspect(matched.bytes))!.bitDepth, 10);
  });

  // UI-10: where the library gives no thumbnail (iOS Photos and a 10-bit
  // AVIF), screens show a rendition made from the original. Here: DarkLib's
  // default 10-bit AVIF, as the display path shows it.
  testWidgets('A rendition from the original stands in for a thumbnail', (
    _,
  ) async {
    final source = _gradient(1179, 1251);
    final avif = (await ImageEncoder.encode(
      source: source,
      target: DefaultFormat.avif,
      quality: 90,
      facts: await SourceInspector.inspect(source),
      keepMetadata: false,
    )).bytes;
    final png = await OriginalRendition.png(avif, maxEdge: 300);
    expect(png, isNotNull);
    final shown = await _flutterDecode(png!);
    // Sampled by 4: 1251 / 4 is still at least 300, 1251 / 8 is not.
    final sample = OriginalRendition.sampleFor(1179, 1251, 300);
    expect(sample, 4);
    expect((shown.width, shown.height), (295, 313));
    final whole = await _platformDecode(avif);
    var total = 0;
    for (var y = 0; y < shown.height; y += 25) {
      for (var x = 0; x < shown.width; x += 25) {
        final p = shown.pixel(x, y), q = whole.pixel(x * sample, y * sample);
        for (var c = 0; c < 3; c++) {
          total += (p[c] - q[c]).abs();
        }
      }
    }
    final samples =
        ((shown.height + 24) ~/ 25) * ((shown.width + 24) ~/ 25) * 3;
    expect(total / samples, lessThan(3));
  });

  // IMG-24: Android's JPEG and HEIC came from flutter_image_compress, which
  // decodes into RGB_565 (5/6/5 bits) and hands a HEIC to HeifWriter as a GL
  // texture: banding in every output, and a crash in the GPU driver when a
  // 565 row is not a multiple of four bytes (an odd width). A smooth
  // gradient 1179 px wide at quality 100 must come back within 1.5 levels.
  for (final format in [DefaultFormat.jpeg, DefaultFormat.heic]) {
    testWidgets('${format.name} keeps 8-bit values at an odd width', (_) async {
      final source = _gradient(1179, 97);
      final result = await ImageEncoder.encode(
        source: source,
        target: format,
        quality: 100,
        facts: await SourceInspector.inspect(source),
        keepMetadata: false,
      );
      final error = _channelError(source, await _platformDecode(result.bytes));
      device['precision-${format.name}'] = {
        'backend': result.backend?.name,
        'bytes': result.bytes.length,
        'meanError': error,
      };
      expect(result.format, format);
      for (final e in error) {
        expect(e, lessThan(1.5), reason: 'mean error per channel $error');
      }
    });
  }

  // RUN-02: the gate reads the phone's memory. An estimate no phone holds is
  // refused before its body runs; were memoryInfo silent, it would run.
  testWidgets('The heavy-work gate knows the phone\'s memory', (_) async {
    var ran = false;
    await expectLater(
      HeavyWork.instance.run(
        estimateBytes: 1 << 45,
        body: () async => ran = true,
      ),
      throwsA(isA<InsufficientMemory>()),
    );
    expect(ran, isFalse);
    expect(
      await HeavyWork.instance.run(estimateBytes: 1 << 20, body: () async => 1),
      1,
    );
  });

  // The real flow (user request 2026-10-09): an image in the gallery opened
  // from the library, compressed with the defaults, saved. What crashed the
  // app was an opaque PNG 1179 px wide that Quick Share had saved as .JPG
  // (MediaStore: image/jpeg); this one is saved the same way. The tile is
  // found by its asset id, so no other photo is ever opened.
  testWidgets('Compress from the library: an odd-width PNG named .jpg', (
    tester,
  ) async {
    expect(photos?.isAuth, isTrue, reason: 'Photo access was refused');
    final source = _gradient(1179, 1251);
    final asset = await GallerySaver.saveImage(
      source,
      filename: 'hayn-test-flow-odd-width.jpg',
    );
    expect(asset, isNotNull);
    expect(asset!.mimeType, 'image/jpeg', reason: 'named as Quick Share did');
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
    final tile = find.byKey(ValueKey(asset.id));
    await _pumpUntil(tester, () => tile.evaluate().isNotEmpty);
    await tester.tap(tile);
    await _pumpUntil(
      tester,
      () => find.byType(AssetDetailScreen).evaluate().isNotEmpty,
    );
    await tester.tap(find.byIcon(Icons.compress_rounded).first);
    await _pumpUntil(
      tester,
      () => find.byType(CompressScreen).evaluate().isNotEmpty,
    );
    final screen = tester.element(find.byType(CompressScreen));
    final l = AppLocalizations.of(screen);
    final container = ProviderScope.containerOf(screen);
    // The preview is the real encode: the pane stops saying "compressing".
    await _pumpUntil(
      tester,
      () => find.text(l.compressComputing).evaluate().isEmpty,
      timeout: const Duration(seconds: 60),
    );
    final button = find.widgetWithText(HaynPrimaryButton, l.compressTitle);
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    bool done() {
      final tasks = container.read(taskRunnerProvider);
      return tasks.isNotEmpty &&
          tasks.last.status != TaskStatus.pending &&
          tasks.last.status != TaskStatus.running;
    }

    await _pumpUntil(tester, done, timeout: const Duration(seconds: 60));
    final state = container.read(taskRunnerProvider).last;
    expect(state.status, TaskStatus.completed, reason: '${state.error}');
    final task = state.task as ImageCompressTask;
    final output = await (await AssetEntity.fromId(
      task.outputAssetIds.single,
    ))!.originBytes;
    await _artifact('flow-odd-width-result', output!);
    final shown = await _platformDecode(output);
    device['flowOddWidth'] = {
      'format': ImageProbe.sniff(output).name,
      'bytes': output.length,
      'meanError': _channelError(source, shown),
    };
    _expectSameImage(await _platformDecode(source), shown);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  // RUN-01 step 6: a JPEG source becomes JPEG through DarkLib's stream at
  // every size (user decision 2026-10-09, after both paths ran on the same
  // images). Each output is held against the platform encoder's for the same
  // source and quality (`NativeImageEncoder.encodeJpeg`, which still makes
  // JPEG from other sources): that one bakes the orientation into the
  // pixels, the stream keeps the stored pixels and the tag. Shown upright,
  // the two must be the same image at about the same size, and the stream
  // must keep what the source carries (gain map, profile, orientation).
  testWidgets('JPEG from a JPEG: the stream, against the platform encoder', (
    _,
  ) async {
    final sources = <String, Uint8List>{
      'quadrants-o6': _quadrants(1179, 1251, orientation: 6),
      'gradient-odd': Uint8List.fromList(
        img.encodeJpg(img.decodePng(_gradient(1179, 97))!, quality: 95),
      ),
      'transpose-o5': await _fixture('strip-sources/jpg-o5.jpg'),
      'ultrahdr': await _fixture('seine_sdr_gainmap_srgb.jpg'),
      'apple-gainmap': await _fixture('apple_gainmap_new.jpg'),
    };
    final rows = <String, Object?>{};
    try {
      for (final MapEntry(key: name, value: source) in sources.entries) {
        final facts = await SourceInspector.inspect(source);
        final shownSource = await _platformDecode(source);
        final summary = dl.readMetadataSummary(bytes: source);
        final gainMap = (await DarkLibCore.inspect(source))!.gainMap;
        final perQuality = <String, Object?>{};
        Uint8List? streamQ80;
        for (final quality in [50, 80, 95]) {
          var sw = Stopwatch()..start();
          final stream = await ImageEncoder.encode(
            source: source,
            target: DefaultFormat.jpeg,
            quality: quality,
            facts: facts,
            keepMetadata: true,
          );
          final streamMs = sw.elapsedMilliseconds;
          sw = Stopwatch()..start();
          final reference = await NativeImageEncoder.encodeJpeg(
            source: source,
            quality: quality,
          );
          final platformMs = sw.elapsedMilliseconds;
          expect(stream.backend, MediaBackend.darklibJpeg, reason: name);
          expect(reference, isNotNull, reason: name);
          final platform = EncodedImage(
            (await ImageEncoder.carryMetadata(
              source,
              reference!,
              keepMetadata: true,
            ))!,
            DefaultFormat.jpeg,
          );
          final shownPlatform = await _platformDecode(platform.bytes);
          final shownStream = await _platformDecode(stream.bytes);
          final between = _meanDiff(shownPlatform, shownStream);
          // The coded image alone: Android adds an sRGB profile to an
          // untagged source (472 bytes), which the stream does not.
          final ratio = _scanBytes(stream.bytes) / _scanBytes(platform.bytes);
          final tags = [
            for (final o in [platform, stream])
              dl.readMetadataSummary(bytes: o.bytes),
          ];
          final maps = [
            for (final o in [platform, stream])
              (await DarkLibCore.inspect(o.bytes))!.gainMap.name,
          ];
          final row = {
            'bytes': [platform.bytes.length, stream.bytes.length],
            'scanBytes': [_scanBytes(platform.bytes), _scanBytes(stream.bytes)],
            'scanStreamOverPlatform': (ratio * 1000).round() / 1000,
            'ms': [platformMs, streamMs],
            'meanDiffBetween': (between * 100).round() / 100,
            'meanErrorFromSource': [
              for (final s in [shownPlatform, shownStream])
                (_meanDiff(shownSource, s) * 100).round() / 100,
            ],
            'orientation': [for (final t in tags) t.orientation],
            'icc': [for (final t in tags) t.hasIcc],
            'gainMap': maps,
          };
          perQuality['q$quality'] = row;
          debugPrint('JPEGPATHS $name q$quality $row');
          // Each no farther from the source than the other. A turned source
          // subsamples its colour on another grid in each path (the platform
          // turns first), so the two match closely only when upright.
          final error = row['meanErrorFromSource']! as List<double>;
          expect(
            error[1],
            lessThanOrEqualTo(error[0] + 0.5),
            reason: '$name q$quality',
          );
          if (summary.orientation <= 1) {
            expect(between, lessThan(1.0), reason: '$name q$quality');
          }
          if (_scanBytes(platform.bytes) > 4096) {
            expect(
              (ratio - 1).abs(),
              lessThan(0.02),
              reason: '$name q$quality',
            );
          }
          expect(tags[1].orientation, summary.orientation, reason: name);
          expect(tags[0].orientation, 1, reason: '$name: baked upright');
          expect(tags[1].hasIcc, summary.hasIcc, reason: name);
          expect(maps[1], gainMap.name, reason: '$name: the map is carried');
          if (quality == 80) {
            streamQ80 = stream.bytes;
            await _artifact('jpeg-paths/$name-platform.jpg', platform.bytes);
            await _artifact('jpeg-paths/$name-stream.jpg', stream.bytes);
          }
        }
        // Without metadata: the stream's EXIF goes, its orientation stays.
        final bare = await ImageEncoder.encode(
          source: source,
          target: DefaultFormat.jpeg,
          quality: 80,
          facts: facts,
          keepMetadata: false,
        );
        final tag = dl.readMetadataSummary(bytes: bare.bytes);
        expect(tag.orientation, summary.orientation, reason: name);
        expect((tag.hasGps, tag.hasCamera, tag.hasDate), (false, false, false));
        // Only the metadata differs: the same pixels.
        expect(
          _meanDiff(
            await _platformDecode(streamQ80!),
            await _platformDecode(bare.bytes),
          ),
          0,
          reason: name,
        );
        rows[name] = perQuality;
      }
    } finally {
      device['jpegPaths'] = rows;
    }
  });

  // A JPEG the stream does not take (progressive: libjpeg would hold every
  // coefficient) falls back to the platform path, with its reason recorded.
  testWidgets('A progressive JPEG falls back to the platform encoder', (
    _,
  ) async {
    final source = await _fixture('progressive.jpg');
    final result = await ImageEncoder.encode(
      source: source,
      target: DefaultFormat.jpeg,
      quality: 80,
      facts: await SourceInspector.inspect(source),
      keepMetadata: true,
    );
    expect(result.backend, MediaBackend.androidJpeg);
    expect(
      result.diagnostics.map((d) => d.toString()),
      containsAll([
        'darklib.encode.unsupportedSource',
        'darklibJpeg.encode.formatFallback',
      ]),
    );
    _expectSameImage(
      await _platformDecode(source),
      await _platformDecode(result.bytes),
    );
  });

  // One phone, by the user's decision (2026-10-09): what another phone would
  // show is simulated on this one. Google's software HEVC encoder (on every
  // Android) stands in for another vendor's; forced rate modes for Android
  // below 12, where the QP keys do not exist; a forced answer for an encoder
  // without Main10; and a gate that reads less memory.
  testWidgets('Simulated: another HEVC encoder and older rate modes', (
    _,
  ) async {
    // The gradient shows the colours; the photo (a real one, 384×512) shows
    // whether the quality the user picks still steers the size. VBR is an
    // average bitrate: a photo this simple stops at the encoder's best
    // quality whatever the budget, so its steering shows on a detailed
    // texture instead.
    final gradient = _gradient(1100, 700);
    final realPhoto = await _fixture('apple_png_p3_icc.png');
    final texture = _texture(1100, 700);
    final rows = <String, Object?>{};
    for (final (label, encoder, rateMode) in [
      ('default', null, null),
      ('software', 'c2.android.hevc.encoder', null),
      ('software-cq', 'c2.android.hevc.encoder', 'cq'),
      ('cq', null, 'cq'),
      ('vbr', null, 'vbr'),
    ]) {
      final row = <String, Object?>{};
      final photoSizes = <int>[];
      for (final quality in [50, 80, 95]) {
        Future<HeicTilesOutput> encode(Uint8List source) async {
          final out = await NativeImageEncoder.encodeHeicTiles(
            source: source,
            quality: quality,
            orientation: 1,
            encoder: encoder,
            rateMode: rateMode,
          );
          expect(out, isNotNull, reason: '$label q$quality');
          if (encoder != null) expect(out!.codec, encoder);
          if (rateMode != null) expect(out!.rateMode, rateMode);
          return out!;
        }

        final sw = Stopwatch()..start();
        final shown = await encode(gradient);
        final ms = sw.elapsedMilliseconds;
        final error = _channelError(
          gradient,
          await _platformDecode(shown.bytes),
        );
        final ofPhoto = await encode(rateMode == 'vbr' ? texture : realPhoto);
        photoSizes.add(ofPhoto.bytes.length);
        row['q$quality'] = {
          'codec': shown.codec,
          'rateMode': shown.rateMode,
          'gradientBytes': shown.bytes.length,
          'photoBytes': ofPhoto.bytes.length,
          'ms': ms,
          'meanError': error,
        };
        // A tiled HEIC of the gradient, shown right, whatever the encoder.
        expect(error.reduce(math.max), lessThan(4), reason: '$label q$quality');
      }
      // The quality the user picks still steers the size.
      expect(
        photoSizes[0],
        lessThan(photoSizes[2]),
        reason: '$label: $photoSizes',
      );
      rows[label] = row;
      debugPrint('SIMULATED heic $label $row');
    }
    device['simulatedHeic'] = rows;
  });

  testWidgets('Simulated: an encoder without Main10', (_) async {
    final source = await _fixture('apple_heic_10bit_p3.heic');
    final facts = await SourceInspector.inspect(source);
    expect(facts.bitDepth, 10);
    NativeImageEncoder.simulateHeicTenBit(false);
    try {
      // "Match" of a deep source: 8, recorded.
      final matched = await ImageEncoder.encode(
        source: source,
        target: DefaultFormat.heic,
        quality: 90,
        facts: facts,
        keepMetadata: false,
      );
      expect((await DarkLibCore.inspect(matched.bytes))!.bitDepth, 8);
      expect(
        matched.diagnostics.map((d) => d.code),
        contains(MediaDiagnosticCode.depthReduced),
      );
      // An explicit 10 binds (IMG-23): the screen never sends it here
      // (ImageFormatPolicy.depthFor), and the encoder does not pass an 8 off
      // as one.
      ImageEncodingFailure? refused;
      try {
        await ImageEncoder.encode(
          source: source,
          target: DefaultFormat.heic,
          quality: 90,
          facts: facts,
          keepMetadata: false,
          bitDepth: 10,
        );
      } on ImageEncodingFailure catch (e) {
        refused = e;
      }
      expect(
        refused?.diagnostics.map((d) => d.code),
        contains(MediaDiagnosticCode.depthMismatch),
      );
      const withoutMain10 = FormatCapabilities(
        supportsHeic: false,
        supportsHeif: true,
        supportsAvifHardware: false,
        supportsWebp: true,
      );
      expect(
        ImageFormatPolicy.depthFor(10, DefaultFormat.heic, withoutMain10),
        8,
      );
    } finally {
      NativeImageEncoder.resetHeicTenBit();
    }
  });

  testWidgets('Simulated: a phone with less memory', (_) async {
    const mb = 1 << 20;
    final picture = img.decodePng(_gradient(4032, 3024))!;
    final jpeg = Uint8List.fromList(img.encodeJpg(picture, quality: 90));
    final png = Uint8List.fromList(img.encodePng(picture, level: 1));
    final saved = HeavyWork.instance;
    // 100 MB above the reserve: the stream's 12 MP JPEG fits (about 80 MB),
    // the platform's whole bitmap from the PNG (about 120 MB) does not.
    HeavyWork.instance = HeavyWork(
      memory: () async =>
          const DeviceMemory(available: 200 * mb, reserve: 100 * mb),
    );
    try {
      final fits = await ImageEncoder.encode(
        source: jpeg,
        target: DefaultFormat.jpeg,
        quality: 80,
        facts: await SourceInspector.inspect(jpeg),
        keepMetadata: true,
      );
      expect(fits.backend, MediaBackend.darklibJpeg);
      await expectLater(
        ImageEncoder.encode(
          source: png,
          target: DefaultFormat.jpeg,
          quality: 80,
          facts: await SourceInspector.inspect(png),
          keepMetadata: true,
        ),
        throwsA(
          isA<ImageEncodingFailure>().having(
            (e) => e.diagnostics.map((d) => d.code),
            'codes',
            contains(MediaDiagnosticCode.insufficientMemory),
          ),
        ),
      );
    } finally {
      HeavyWork.instance = saved;
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

List<String> _orientationNames() => [
  for (final ext in ['jpg', 'png', 'webp'])
    for (var o = 1; o <= 8; o++) '$ext-o$o.$ext',
];

/// Pumps frames until [ready], failing after [timeout].
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    expect(clock.elapsed, lessThan(timeout), reason: 'timed out');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// An opaque PNG of smooth gradients, [w]×[h]: banding shows in it.
Uint8List _gradient(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  for (final p in image) {
    p
      ..r = p.x * 255 ~/ (w - 1)
      ..g = p.y * 255 ~/ (h - 1)
      ..b = (p.x * 128 ~/ (w - 1)) + (p.y * 127 ~/ (h - 1));
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Mean absolute difference per channel (R, G, B) between the PNG [source]
/// and [shown], rounded to hundredths.
List<double> _channelError(Uint8List source, _Shown shown) {
  final src = img.decodePng(source)!;
  expect((shown.width, shown.height), (src.width, src.height));
  final sum = [0, 0, 0];
  for (final p in src) {
    final q = shown.pixel(p.x, p.y);
    sum[0] += (p.r.toInt() - q[0]).abs();
    sum[1] += (p.g.toInt() - q[1]).abs();
    sum[2] += (p.b.toInt() - q[2]).abs();
  }
  final n = src.width * src.height;
  return [for (final v in sum) (v * 100 / n).round() / 100];
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

/// The frame now on screen inside [boundary], straight RGBA.
Future<_Shown> _capture(WidgetTester tester, GlobalKey boundary) async {
  final box =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async => _read(await box.toImage())))!;
}

/// Squares of [_checkerboard] (3600×2700) shown right in a 360×270 view of
/// it zoomed ×10 at (1800, 1350), and squares sampled: their centres, 1.5 px
/// from their edges, except where [skip] says.
(int, int) _checkerScore(_Shown shot, {bool Function(int x, int y)? skip}) {
  expect((shot.width, shot.height), (360, 270));
  var right = 0, total = 0;
  for (var y = 2; y < 270; y += 8) {
    for (var x = 0; x < 360; x += 8) {
      if (skip?.call(x, y) ?? false) continue;
      final ix = 1800 + x, iy = 1350 + y;
      final white = (((ix + 2) ~/ 4) + ((iy + 2) ~/ 4)).isOdd;
      final v = shot.pixel(x, y)[0];
      total++;
      if (white ? v > 200 : v < 55) right++;
    }
  }
  return (right, total);
}

/// A JPEG checkerboard of 4 px black and white squares, [w]×[h], shifted
/// 2 px off the 4 px grid.
Uint8List _checkerboard(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  for (final p in image) {
    final v = (((p.x + 2) ~/ 4) + ((p.y + 2) ~/ 4)).isOdd ? 255 : 0;
    p
      ..r = v
      ..g = v
      ..b = v;
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

/// [bytes] put back together from its full-size region tiles, as the
/// zoomed views draw them: straight RGBA, upright.
Future<_Shown> _regionWhole(Uint8List bytes) async {
  final region = await RegionImage.open(bytes);
  expect(region, isNotNull, reason: 'no region decoder');
  try {
    final w = region!.width, h = region.height;
    final rgba = Uint8List(w * h * 4);
    for (var y0 = 0; y0 < h; y0 += 512) {
      for (var x0 = 0; x0 < w; x0 += 512) {
        final rect = Rect.fromLTRB(
          x0.toDouble(),
          y0.toDouble(),
          (x0 + 512).clamp(0, w).toDouble(),
          (y0 + 512).clamp(0, h).toDouble(),
        );
        final tile = await _read((await region.tile(rect, 1))!);
        expect((tile.width, tile.height), (rect.width, rect.height));
        for (var y = 0; y < tile.height; y++) {
          rgba.setRange(
            ((y0 + y) * w + x0) * 4,
            ((y0 + y) * w + x0 + tile.width) * 4,
            tile.rgba,
            y * tile.width * 4,
          );
        }
      }
    }
    return _Shown(w, h, rgba);
  } finally {
    await region?.close();
  }
}

/// Same size and near-identical pixels (a lossy re-encode of one rendition).
/// Bytes from the primary image's SOS to its EOI: its coded scan. Segments
/// are walked by their lengths (an EXIF thumbnail has its own SOS), then
/// stuffing keeps FF D9 out of the data, so the first one ends it.
int _scanBytes(Uint8List jpeg) {
  var i = 2;
  while (jpeg[i + 1] != 0xDA) {
    i += 2 + (jpeg[i + 2] << 8 | jpeg[i + 3]);
  }
  for (var j = i; j + 1 < jpeg.length; j++) {
    if (jpeg[j] == 0xFF && jpeg[j + 1] == 0xD9) return j - i;
  }
  fail('no EOI');
}

/// A detailed opaque PNG, [w]×[h]: a gradient under fixed pseudo-random
/// grain, harder to code than a phone photo of the same size.
Uint8List _texture(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  var seed = 12345;
  int next() => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) >> 16;
  for (final p in image) {
    final base = p.x * 255 ~/ (w - 1);
    p
      ..r = (base + next() % 64 - 32).clamp(0, 255)
      ..g = (p.y * 255 ~/ (h - 1) + next() % 64 - 32).clamp(0, 255)
      ..b = (128 + next() % 64 - 32).clamp(0, 255);
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Mean absolute difference over every pixel and colour channel.
double _meanDiff(_Shown a, _Shown b) {
  expect((b.width, b.height), (a.width, a.height));
  var total = 0;
  for (var i = 0; i < a.rgba.length; i += 4) {
    total +=
        (a.rgba[i] - b.rgba[i]).abs() +
        (a.rgba[i + 1] - b.rgba[i + 1]).abs() +
        (a.rgba[i + 2] - b.rgba[i + 2]).abs();
  }
  return total / (a.width * a.height * 3);
}

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

/// A JPEG of four flat quadrants (red, green, blue, yellow from the top
/// left) whose EXIF names [orientation]: any turn or mirror moves them.
Uint8List _quadrants(int w, int h, {required int orientation}) {
  final image = img.Image(width: w, height: h);
  final colours = [
    img.ColorRgb8(220, 40, 40),
    img.ColorRgb8(40, 200, 60),
    img.ColorRgb8(40, 60, 220),
    img.ColorRgb8(230, 210, 40),
  ];
  for (var q = 0; q < 4; q++) {
    final x0 = q.isEven ? 0 : w ~/ 2;
    final y0 = q < 2 ? 0 : h ~/ 2;
    img.fillRect(
      image,
      x1: x0,
      y1: y0,
      x2: q.isEven ? w ~/ 2 - 1 : w - 1,
      y2: q < 2 ? h ~/ 2 - 1 : h - 1,
      color: colours[q],
    );
  }
  image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

/// The four P3 quadrants of `_quadrants` (and the libheif fixtures) in sRGB
/// as LittleCMS converts them with Apple's Display P3 profile, at the
/// quadrant centres of a 64×48 image (fixtures/README).
void _expectP3Quadrants(_Shown shown) {
  expect((shown.width, shown.height), (64, 48));
  const want = [
    [240, 0, 23],
    [0, 204, 12],
    [34, 61, 228],
    [235, 209, 0],
  ];
  for (var q = 0; q < 4; q++) {
    final p = shown.pixel(16 + 32 * (q % 2), 12 + 24 * (q ~/ 2));
    for (var c = 0; c < 3; c++) {
      expect(p[c], closeTo(want[q][c], 6), reason: 'quadrant $q: $p');
    }
  }
}

/// The four quadrant centres of [b] match [a]'s.
void _expectSameQuadrants(_Shown a, _Shown b) {
  expect((b.width, b.height), (a.width, a.height));
  for (final (fx, fy) in [(1, 1), (3, 1), (1, 3), (3, 3)]) {
    final x = a.width * fx ~/ 4;
    final y = a.height * fy ~/ 4;
    final p = a.pixel(x, y);
    final q = b.pixel(x, y);
    for (var c = 0; c < 3; c++) {
      expect(q[c], closeTo(p[c], 12), reason: 'quadrant at $x,$y');
    }
  }
}

/// T-08 / IMG-15: a transparent HEIC to [target] must succeed with its real
/// transparency (see the loop in main).
void _transparentHeic(
  DefaultFormat target,
  bool keepMetadata,
  Map<String, Object?> device,
) {
  final label = '${target.name}${keepMetadata ? ' with metadata' : ''}';
  testWidgets('Transparent HEIC to $label keeps its transparency', (_) async {
    final source = await _fixture('apple_heic_alpha.heic');
    final facts = await SourceInspector.inspect(source);
    expect(facts.alpha, isTrue);
    final sw = Stopwatch()..start();
    final result = await ImageEncoder.encode(
      source: source,
      target: target,
      quality: 95,
      facts: facts,
      keepMetadata: keepMetadata,
    );
    device['heic-alpha-$label-ms'] = sw.elapsedMilliseconds;
    device['heic-alpha-$label'] = result.backend?.name;
    await _artifact(
      'heic-alpha${keepMetadata ? '-meta' : ''}.${result.extension}',
      result.bytes,
    );
    if (target != DefaultFormat.jpeg) {
      // Alpha values, not channel presence: Android's decoder returned an
      // alpha channel 255 everywhere, which a presence check passed.
      final kept = target == DefaultFormat.avif
          ? img.decodePng(
              (await DarkLibCore.transcode(
                result.bytes,
                format: DarkLibFormat.png,
                quality: 100,
                keepMetadata: false,
              ))!.bytes,
            )!
          : img.decodeImage(result.bytes)!;
      final p = kept.getPixel(6, 6);
      expect(p.a, closeTo(64, 10));
      expect(
        [p.r, p.g, p.b],
        [closeTo(80, 10), closeTo(120, 10), closeTo(160, 10)],
      );
      expect(kept.getPixel(32, 24).a, 255);
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
