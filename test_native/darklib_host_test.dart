import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:image/image.dart' as img;
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
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
}
