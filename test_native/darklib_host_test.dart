import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:image/image.dart' as img;
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/image_ops/data/alpha_flatten.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/src/rust/api/metadata.dart' as rust_meta;
import 'package:hayn/src/rust/frb_generated.dart';

// Explicit host smoke test. Requires a real, matching Rust library; never mocks
// or silently skips the primary backend. This does not validate HDR or phones.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const path = String.fromEnvironment('DARKLIB_TEST_LIBRARY');
    if (path.isEmpty) {
      fail('Set DARKLIB_TEST_LIBRARY to the compiled host library');
    }
    await DarkLib.init(externalLibrary: ExternalLibrary.open(path));
  });
  tearDownAll(DarkLib.dispose);
  test('real DarkLib converts an SDR PNG to decodable WebP', () async {
    final source = img.Image(width: 16, height: 12, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(80, 120, 160));
    final png = Uint8List.fromList(img.encodePng(source));
    final facts = await SourceInspector.inspect(png);
    expect(
      (facts.alpha, facts.directHdr, facts.gainMap),
      (false, false, false),
    );
    // The size comes from the header (RUN-01: the giant threshold).
    expect((facts.width, facts.height, facts.giant), (16, 12, false));
    final result = await ImageEncoder.encode(
      source: png,
      target: DefaultFormat.webp,
      quality: 90,
      facts: facts,
      keepMetadata: false,
    );
    expect(result.backend, MediaBackend.darklib);
    expect(result.diagnostics, isEmpty);
    final decoded = img.decodeWebP(result.bytes)!;
    expect((decoded.width, decoded.height), (16, 12));
    final pixel = decoded.getPixel(8, 6);
    expect(pixel.r, closeTo(80, 8));
    expect(pixel.g, closeTo(120, 8));
    expect(pixel.b, closeTo(160, 8));
  });
  test('real PQ source is refused before any engine off iOS', () async {
    final bytes = await File(
      'native/darklib/tests/fixtures/seine_hdr_rec2020.avif',
    ).readAsBytes();
    final facts = await SourceInspector.inspect(bytes);
    expect(facts.directHdr, isTrue);
    await expectLater(
      ImageEncoder.encode(
        source: bytes,
        target: DefaultFormat.webp,
        quality: 80,
        facts: facts,
        keepMetadata: true,
        allowFormatFallback: true,
      ),
      throwsA(
        isA<ImageEncodingFailure>()
            .having(
              (e) => e.diagnostics.map((d) => d.code),
              'no tone mapper',
              contains(MediaDiagnosticCode.hdrToneMapUnavailable),
            )
            .having(
              (e) => e.diagnostics.map((d) => d.code),
              'no format retry',
              isNot(contains(MediaDiagnosticCode.formatFallback)),
            ),
      ),
    );
  });

  test('real Rust veto on a PQ original still crosses FFI', () async {
    final bytes = await File(
      'native/darklib/tests/fixtures/seine_hdr_rec2020.avif',
    ).readAsBytes();
    await expectLater(
      DarkLibCore.transcode(bytes, format: DarkLibFormat.webp, quality: 80),
      throwsA(isA<DarkLibPreservationFailure>()),
    );
  });

  test(
    'real gain-map AVIF: SDR base to WebP, map kept to AVIF',
    () async {
      final bytes = await File(
        'native/darklib/tests/fixtures/seine_sdr_gainmap_srgb.avif',
      ).readAsBytes();
      final facts = await SourceInspector.inspect(bytes);
      expect((facts.directHdr, facts.gainMap), (false, true));

      final webp = await ImageEncoder.encode(
        source: bytes,
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
      expect(img.decodeWebP(webp.bytes), isNotNull);

      // AVIF→AVIF keeps the map (ImageIO-verified, IMG-10).
      final avif = await ImageEncoder.encode(
        source: bytes,
        target: DefaultFormat.avif,
        quality: 80,
        facts: facts,
        keepMetadata: false,
      );
      expect(avif.hdr, HdrOutcome.gainMapKept);
      expect(
        avif.diagnostics.map((d) => d.code),
        isNot(
          anyOf(
            contains(MediaDiagnosticCode.hdrToSdr),
            contains(MediaDiagnosticCode.hdrKeepFailed),
          ),
        ),
      );
      expect(
        (await DarkLibCore.inspect(avif.bytes))!.gainMap,
        Presence.present,
      );
    },
    // AV1 encodes in the unoptimised debug library are slow.
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'real primary backend keeps transparent PNG alpha through WebP',
    () async {
      final input = img.Image(width: 8, height: 8, numChannels: 4);
      img.fill(input, color: img.ColorRgba8(100, 120, 140, 64));
      final png = Uint8List.fromList(img.encodePng(input));
      final result = await ImageEncoder.encode(
        source: png,
        target: DefaultFormat.webp,
        quality: 90,
        facts: await SourceInspector.inspect(png),
        keepMetadata: false,
      );
      expect(result.backend, MediaBackend.darklib);
      expect(result.diagnostics, isEmpty);
      final decoded = img.decodeWebP(result.bytes)!;
      expect((decoded.width, decoded.height), (8, 8));
      expect(decoded.getPixel(4, 4).a, 64);
    },
  );

  // IMG-16: an opaque lossy WebP read as transparent (package:image gives VP8
  // four channels), so AVIF/HEIC/PNG targets were refused as alphaLost on the
  // iPhone. The fixtures come from libwebp through Pillow, not DarkLib.
  Future<Uint8List> webp(String name) => File(
    'native/darklib/tests/fixtures/pillow_webp_$name.webp',
  ).readAsBytes();

  test('opaque lossy WebP reads opaque and converts without refusal', () async {
    final source = await webp('lossy_opaque');
    final facts = await SourceInspector.inspect(source);
    expect(facts.alpha, isFalse);
    for (final target in [DefaultFormat.avif, DefaultFormat.webp]) {
      final result = await ImageEncoder.encode(
        source: source,
        target: target,
        quality: 80,
        facts: facts,
        keepMetadata: true,
      );
      expect(result.format, target);
      expect(
        result.diagnostics.map((d) => d.code),
        isNot(
          anyOf(
            contains(MediaDiagnosticCode.alphaLost),
            contains(MediaDiagnosticCode.alphaUnverified),
          ),
        ),
        reason: '$target',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('translucent WebP keeps its alpha through AVIF', () async {
    for (final name in ['lossy_alpha', 'lossless_alpha']) {
      final source = await webp(name);
      final facts = await SourceInspector.inspect(source);
      expect(facts.alpha, isTrue, reason: name);
      final result = await ImageEncoder.encode(
        source: source,
        target: DefaultFormat.avif,
        quality: 90,
        facts: facts,
        keepMetadata: false,
      );
      expect(
        await SourceInspector.inspect(result.bytes).then((f) => f.alpha),
        isTrue,
        reason: name,
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  // IMG-08: without metadata the colour profile stays. The JPEG flatten and
  // Android's hardware AVIF produce output with no profile and restore it
  // through carryMetadata; it runs here on a DarkLib JPEG, since this host has
  // no platform JPEG encoder for the full path.
  test('carryMetadata without metadata keeps the P3 profile only', () async {
    final camera = await File(
      'native/darklib/tests/fixtures/apple_gainmap_new.jpg',
    ).readAsBytes();
    final before = rust_meta.readMetadataSummary(bytes: camera);
    expect((before.hasIcc, before.hasExif, before.hasGps), (true, true, true));
    final bare = (await DarkLibCore.transcode(
      camera,
      format: DarkLibFormat.jpeg,
      quality: 90,
      keepMetadata: false,
    ))!.bytes;
    for (final keep in [false, true]) {
      final out = (await ImageEncoder.carryMetadata(
        camera,
        bare,
        keepMetadata: keep,
      ))!;
      final after = rust_meta.readMetadataSummary(bytes: out);
      expect(
        (after.hasIcc, after.hasExif, after.hasGps),
        (true, keep, keep),
        reason: 'keepMetadata: $keep',
      );
    }
  });

  // RUN-01: a header past the decode budget is refused before any pixel
  // buffer, and classified.
  test('oversized header is refused as tooLarge', () async {
    int crc(List<int> data) {
      var c = 0xFFFFFFFF;
      for (final b in data) {
        c ^= b;
        for (var k = 0; k < 8; k++) {
          c = c & 1 == 1 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
        }
      }
      return c ^ 0xFFFFFFFF;
    }

    List<int> be(int v) => [
      v >> 24 & 255,
      v >> 16 & 255,
      v >> 8 & 255,
      v & 255,
    ];
    List<int> chunk(String kind, List<int> data) => [
      ...be(data.length),
      ...kind.codeUnits,
      ...data,
      ...be(crc([...kind.codeUnits, ...data])),
    ];
    final png = Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      ...chunk('IHDR', [...be(20000), ...be(20000), 8, 6, 0, 0, 0]),
      ...chunk('IDAT', [0x78, 0x9c, 0x03, 0, 0, 0, 0, 1]),
      ...chunk('IEND', []),
    ]);
    final trace = await MediaDiagnostics.trace((trace) async {
      expect(
        await DarkLibCore.transcode(
          png,
          format: DarkLibFormat.webp,
          quality: 80,
          keepMetadata: false,
        ),
        isNull,
      );
      return trace.events;
    });
    expect(trace.map((d) => d.code), contains(MediaDiagnosticCode.tooLarge));
  });

  // PERF-01: the JPEG flatten runs in Rust. The composite must match the one
  // the phone test checks, and nothing may fall back to Dart for a PNG.
  test('flatten onto white runs in DarkLib with the same composite', () async {
    final input = img.Image(width: 64, height: 48, numChannels: 4);
    img.fill(input, color: img.ColorRgba8(80, 120, 160, 64));
    final png = Uint8List.fromList(img.encodePng(input));
    final trace = await MediaDiagnostics.trace((trace) async {
      final flat = (await AlphaFlatten.toOpaquePng(
        png,
        toSdr: false,
        alpha: true,
      ))!;
      final shown = img.decodePng(flat)!;
      expect(shown.numChannels, 3);
      final p = shown.getPixel(8, 6);
      expect((p.r, p.g, p.b), (211, 221, 231));
      return trace.events;
    });
    expect(trace, isEmpty, reason: 'no DarkLib failure, no Dart fallback');
  });

  // IMG-15: Android's HEIF decoder gives a transparent HEIC back with an alpha
  // channel opaque everywhere. The real library judges by decoded values.
  test('an opaque alpha channel from a transparent HEIC is lost', () async {
    final heic = await File(
      'native/darklib/tests/fixtures/apple_heic_alpha.heic',
    ).readAsBytes();
    Uint8List rgba(int alpha) {
      final image = img.Image(width: 64, height: 48, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(80, 120, 158, alpha));
      return Uint8List.fromList(img.encodePng(image));
    }

    expect(
      await DarkLibCore.alphaKept(source: heic, output: rgba(255)),
      AlphaKept.lost,
    );
    expect(
      await DarkLibCore.alphaKept(source: heic, output: rgba(64)),
      AlphaKept.kept,
    );
  });

  // IMG-15 fixed: the real library extracts the alpha stream and attaches
  // the plane FFmpeg decoded (the fixture is FFmpeg's output).
  test('a HEIC alpha plane goes out as HEVC and comes back as alpha', () async {
    const dir = 'native/darklib/tests/fixtures';
    final heic = await File('$dir/apple_heic_alpha.heic').readAsBytes();
    final grey = await File('$dir/apple_heic_alpha.gray').readAsBytes();
    final stream = (await DarkLibCore.heifAlphaStream(heic))!;
    expect((stream.frames, stream.width, stream.height), (1, 64, 48));
    final base = img.Image(width: 64, height: 48, numChannels: 4);
    img.fill(base, color: img.ColorRgba8(80, 120, 158, 255));
    final png = (await DarkLibCore.heifAttachAlpha(
      source: heic,
      base: Uint8List.fromList(img.encodePng(base)),
      grey: grey,
    ))!;
    final shown = img.decodePng(png)!;
    expect(shown.getPixel(6, 6).a, 64);
    expect(shown.getPixel(32, 24).a, 255);
    expect(
      await DarkLibCore.alphaKept(source: heic, output: png),
      AlphaKept.kept,
    );
  });
}
