import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/image_ops/data/heif_alpha.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/image_probe.dart';
import 'package:hayn/features/image_ops/data/native_image_encoder.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/src/rust/api/metadata.dart';
import 'package:hayn/src/rust/engine/metadata.dart';
import 'package:hayn/src/rust/frb_generated.dart';
import 'package:image/image.dart' as img;

import 'support/bake_channel.dart';
import 'support/encoded_headers.dart';

// IMG-05: HDR facts of the ORIGINAL decide the plan before any engine runs.
// Policy (user decision 2026-09-28): keep HDR where the path exists, otherwise
// a correct SDR rendition without asking; PQ/HLG only via a tone mapper.
// Before the fix a hardware AVIF encode succeeded on a PQ source and HDR HEIC
// reached WebP without any HDR check
// (Development/logs/img05-gap-reproduction-20260928.log).

final _heic = Uint8List.fromList([
  0,
  0,
  0,
  20,
  ...'ftypheic0000mif1'.codeUnits,
]);
final _png = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

class _Api extends Fake implements DarkLibApi {
  final received = <List<int>>[];
  HdrOutcome hdr = HdrOutcome.none;
  Facts inspected = const Facts(
    transfer: Transfer.noHdrSignal,
    gainMap: Presence.absent,
    alpha: Presence.unknown,
    width: 0,
    height: 0,
    orientation: 0,
    bitDepth: 0,
  );

  @override
  Future<Transcoded> crateApiCodecTranscode({
    required List<int> bytes,
    required DarkLibFormat format,
    required int quality,
    required int maxEdge,
    required bool keepMetadata,
    required int bitDepth,
  }) async {
    received.add(bytes);
    // Like the real engine: HEIC is not decoded in software.
    if (String.fromCharCodes(bytes.take(12)).contains('heic')) {
      return Future<Transcoded>.error(
        'malformed: heic decode is hardware-only',
      );
    }
    return Transcoded(
      bytes: encodedHeader(
        format == DarkLibFormat.avif ? DefaultFormat.avif : DefaultFormat.webp,
      ),
      hdr: hdr,
    );
  }

  @override
  Future<Facts> crateApiInspectInspectImage({required List<int> bytes}) async =>
      inspected;

  /// What `heif_alpha_stream` returns; null = no alpha.
  AlphaStream? alphaStream;

  @override
  Future<AlphaStream?> crateApiCodecHeifAlphaStream({
    required List<int> bytes,
  }) async => alphaStream;

  /// Like the engine: the grey plane becomes the base's alpha.
  @override
  Future<Uint8List> crateApiCodecHeifAttachAlpha({
    required List<int> source,
    required List<int> base,
    required List<int> grey,
  }) async {
    final out = img
        .decodePng(Uint8List.fromList(base))!
        .convert(numChannels: 4, alpha: 255);
    var i = 0;
    for (final p in out) {
      p.a = grey[i++];
    }
    return Uint8List.fromList(img.encodePng(out));
  }

  /// Like the engine: decoded alpha values answer; an output showing no
  /// transparency is a loss when the source (here, its container) had some.
  @override
  Future<AlphaKept> crateApiVerifyAlphaKept({
    required List<int> source,
    required List<int> output,
  }) async {
    final decoded = img.decodeImage(Uint8List.fromList(output));
    if (decoded == null) return AlphaKept.unknown;
    if (decoded.any((p) => p.a < p.maxChannelValue)) return AlphaKept.kept;
    return switch (inspected.alpha) {
      Presence.present => AlphaKept.lost,
      Presence.absent => AlphaKept.kept,
      Presence.unknown => AlphaKept.unknown,
    };
  }

  /// Metadata steps seen, in order ('transplant' / 'strip').
  final metadataCalls = <String>[];
  List<MetaKind> dropped = const [];

  @override
  Future<Transplanted> crateApiMetadataTransplantMetadata({
    required List<int> source,
    required List<int> target,
  }) async {
    metadataCalls.add('transplant');
    return Transplanted(bytes: Uint8List.fromList(target), dropped: dropped);
  }

  @override
  Future<Uint8List> crateApiMetadataStripMetadata({
    required List<int> bytes,
    required bool stripIcc,
  }) async {
    metadataCalls.add(stripIcc ? 'strip+icc' : 'strip');
    return Uint8List.fromList(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => DarkLib.initMock(api: api));
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const imageChannel = MethodChannel('hayn/metadata');
  const avifChannel = MethodChannel('hayn/avif');
  final hardwareEncodes = <MethodCall>[];

  setUp(() {
    hardwareEncodes.clear();
    messenger.setMockMethodCallHandler(avifChannel, (call) async {
      if (call.method == 'isAvailable') return true;
      hardwareEncodes.add(call);
      return encodedHeader(DefaultFormat.avif);
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(imageChannel, null);
    messenger.setMockMethodCallHandler(avifChannel, null);
    api
      ..received.clear()
      ..metadataCalls.clear()
      ..hdr = HdrOutcome.none
      ..inspected = const Facts(
        transfer: Transfer.noHdrSignal,
        gainMap: Presence.absent,
        alpha: Presence.unknown,
        width: 0,
        height: 0,
        orientation: 0,
        bitDepth: 0,
      );
  });

  List<MediaDiagnosticCode> codes(Iterable<MediaDiagnostic> d) =>
      d.map((e) => e.code).toList();

  const pq = SourceFacts(alpha: false, directHdr: true, gainMap: false);
  const gainMap = SourceFacts(alpha: false, directHdr: false, gainMap: true);

  test('PQ without a tone mapper is refused before any engine', () async {
    final pqAvif = encodedHeader(DefaultFormat.avif);
    await expectLater(
      ImageEncoder.encode(
        source: pqAvif,
        target: DefaultFormat.avif,
        quality: 80,
        facts: pq,
        keepMetadata: false,
      ),
      throwsA(
        isA<ImageEncodingFailure>().having(
          (e) => codes(e.diagnostics),
          'reason',
          contains(MediaDiagnosticCode.hdrToneMapUnavailable),
        ),
      ),
    );
    expect(hardwareEncodes, isEmpty);
    expect(api.received, isEmpty);
  });

  test('PQ continues only as the platform SDR rendition', () async {
    final bakes = <Map>[];
    messenger.setMockMethodCallHandler(imageChannel, (call) async {
      if (call.method == 'bakeUpright') {
        bakes.add(call.arguments as Map);
        return _png;
      }
      return null;
    });
    final original = encodedHeader(DefaultFormat.avif);
    final r = await ImageEncoder.encode(
      source: original,
      target: DefaultFormat.webp,
      quality: 80,
      facts: pq,
      keepMetadata: true,
    );
    expect(bakes.single['toSdr'], isTrue);
    expect(
      api.received.single,
      _png,
      reason: 'the original never reached Rust',
    );
    expect(r.backend, MediaBackend.darklib);
    expect(codes(r.diagnostics), contains(MediaDiagnosticCode.hdrToSdr));
  });

  test('gain-map HEIC reaches WebP through the SDR bridge', () async {
    final bakes = <Map>[];
    messenger.setMockMethodCallHandler(imageChannel, (call) async {
      if (call.method == 'bakeUpright') {
        bakes.add(call.arguments as Map);
        return _png;
      }
      return null;
    });
    final r = await ImageEncoder.encode(
      source: _heic,
      target: DefaultFormat.webp,
      quality: 80,
      facts: gainMap,
      keepMetadata: false,
    );
    expect(bakes.single['toSdr'], isTrue);
    expect(r.format, DefaultFormat.webp);
    expect(codes(r.diagnostics), contains(MediaDiagnosticCode.hdrToSdr));
    expect(
      codes(r.diagnostics),
      isNot(contains(MediaDiagnosticCode.hdrKeepFailed)),
    );
  });

  test('DarkLib outcome decides what is recorded', () async {
    api.hdr = HdrOutcome.gainMapKept;
    final kept = await ImageEncoder.encode(
      source: encodedHeader(DefaultFormat.avif),
      target: DefaultFormat.webp,
      quality: 80,
      facts: gainMap,
      keepMetadata: true,
    );
    expect(kept.hdr, HdrOutcome.gainMapKept);
    expect(kept.diagnostics, isEmpty);

    api.hdr = HdrOutcome.gainMapKeepFailed;
    final failed = await ImageEncoder.encode(
      source: encodedHeader(DefaultFormat.avif),
      target: DefaultFormat.webp,
      quality: 80,
      facts: gainMap,
      keepMetadata: true,
    );
    expect(
      codes(failed.diagnostics),
      containsAll([
        MediaDiagnosticCode.hdrKeepFailed,
        MediaDiagnosticCode.hdrToSdr,
      ]),
    );
  });

  test('ImageIO drops a gain map only for privacy, via SDR', () async {
    final sent = <Map>[];
    messenger.setMockMethodCallHandler(imageChannel, (call) async {
      if (call.method == 'encodeImage') {
        sent.add(call.arguments as Map);
        return encodedHeader(DefaultFormat.jpeg);
      }
      return null;
    });
    api.inspected = const Facts(
      transfer: Transfer.noHdrSignal,
      gainMap: Presence.present,
      alpha: Presence.unknown,
      width: 0,
      height: 0,
      orientation: 0,
      bitDepth: 0,
    );
    final kept = await ImageEncoder.encode(
      source: _heic,
      target: DefaultFormat.jpeg,
      quality: 80,
      facts: gainMap,
      keepMetadata: true,
    );
    expect(sent.last['toSdr'], isFalse);
    expect(kept.diagnostics, isEmpty);

    api.inspected = const Facts(
      transfer: Transfer.noHdrSignal,
      gainMap: Presence.absent,
      alpha: Presence.unknown,
      width: 0,
      height: 0,
      orientation: 0,
      bitDepth: 0,
    );
    final private = await ImageEncoder.encode(
      source: _heic,
      target: DefaultFormat.jpeg,
      quality: 80,
      facts: gainMap,
      keepMetadata: false,
    );
    expect(sent.last['toSdr'], isTrue);
    expect(codes(private.diagnostics), contains(MediaDiagnosticCode.hdrToSdr));
  });

  test('unknown HDR keeps hardware AVIF off and is recorded', () async {
    final r = await ImageEncoder.encode(
      source: encodedHeader(DefaultFormat.avif),
      target: DefaultFormat.avif,
      quality: 80,
      facts: const SourceFacts(alpha: false, directHdr: null, gainMap: null),
      keepMetadata: false,
    );
    expect(hardwareEncodes, isEmpty);
    expect(r.backend, MediaBackend.darklib);
    expect(codes(r.diagnostics), contains(MediaDiagnosticCode.hdrUnverified));
  });

  test('gain-map AVIF goes to DarkLib, which keeps the map', () async {
    api.hdr = HdrOutcome.gainMapKept;
    final r = await ImageEncoder.encode(
      source: encodedHeader(DefaultFormat.avif),
      target: DefaultFormat.avif,
      quality: 80,
      facts: gainMap,
      keepMetadata: false,
    );
    expect(hardwareEncodes, isEmpty);
    expect(r.backend, MediaBackend.darklib);
    expect(r.hdr, HdrOutcome.gainMapKept);
  });

  test('known SDR source still uses hardware AVIF', () async {
    final r = await ImageEncoder.encode(
      source: _png,
      target: DefaultFormat.avif,
      quality: 80,
      facts: const SourceFacts.sdr(alpha: false),
      keepMetadata: false,
    );
    expect(hardwareEncodes, hasLength(1));
    expect(r.backend, MediaBackend.androidAvif);
    expect(r.diagnostics, isEmpty);
    // IMG-08: without metadata the colour profile is still carried, then
    // the private metadata stripped; the profile itself is kept.
    expect(api.metadataCalls, ['transplant', 'strip']);
  });

  group('SourceInspector', () {
    void native(Map<String, Object?>? probe) =>
        messenger.setMockMethodCallHandler(imageChannel, (_) async => probe);

    test('either signal of HDR wins', () async {
      api.inspected = const Facts(
        transfer: Transfer.pq,
        gainMap: Presence.absent,
        alpha: Presence.unknown,
        width: 0,
        height: 0,
        orientation: 0,
        bitDepth: 0,
      );
      expect((await SourceInspector.inspect(_png)).directHdr, isTrue);

      api.inspected = const Facts(
        transfer: Transfer.noHdrSignal,
        gainMap: Presence.absent,
        alpha: Presence.unknown,
        width: 0,
        height: 0,
        orientation: 0,
        bitDepth: 0,
      );
      native({'hdrTransfer': true, 'hasGainMap': true});
      final f = await SourceInspector.inspect(_png);
      expect((f.directHdr, f.gainMap), (true, true));
    });

    test('confirmed absence needs a real answer', () async {
      native(null);
      final sdr = await SourceInspector.inspect(_png);
      expect((sdr.alpha, sdr.directHdr, sdr.gainMap), (false, false, false));

      api.inspected = const Facts(
        transfer: Transfer.unknown,
        gainMap: Presence.unknown,
        alpha: Presence.unknown,
        width: 0,
        height: 0,
        orientation: 0,
        bitDepth: 0,
      );
      final unknown = await SourceInspector.inspect(_png);
      expect((unknown.directHdr, unknown.gainMap), (null, null));
    });
  });

  // IMG-16: every lossy WebP read as transparent because package:image gives
  // VP8 four channels; the container now answers first. IMG-15: Android's
  // HEIF decoder drops the alpha plane, and compositing its output showed the
  // hidden colours instead of white.
  group('alpha from the container', () {
    test('answers before any decode', () async {
      // WebP magic around bytes no decoder reads: only the container answers.
      final webp = Uint8List.fromList([
        ...'RIFF'.codeUnits,
        0,
        0,
        0,
        0,
        ...'WEBP'.codeUnits,
        ...List.filled(16, 0),
      ]);
      for (final (presence, want) in [
        (Presence.absent, false),
        (Presence.present, true),
        (Presence.unknown, null),
      ]) {
        api.inspected = Facts(
          transfer: Transfer.noHdrSignal,
          gainMap: Presence.absent,
          alpha: presence,
          width: 0,
          height: 0,
          orientation: 0,
          bitDepth: 0,
        );
        expect(await ImageProbe.hasAlpha(webp), want, reason: '$presence');
      }
    });

    test(
      'a decoder that drops known alpha is refused, not flattened',
      () async {
        // The bake returns an opaque PNG for a source known to be transparent.
        api.inspected = const Facts(
          transfer: Transfer.noHdrSignal,
          gainMap: Presence.absent,
          alpha: Presence.present,
          width: 0,
          height: 0,
          orientation: 0,
          bitDepth: 0,
        );
        messenger.setMockMethodCallHandler(
          imageChannel,
          (call) => answerBake(call, _png),
        );
        await expectLater(
          ImageEncoder.encode(
            source: _heic,
            target: DefaultFormat.jpeg,
            quality: 80,
            facts: const SourceFacts(
              alpha: true,
              directHdr: false,
              gainMap: false,
            ),
            keepMetadata: false,
          ),
          throwsA(
            isA<ImageEncodingFailure>().having(
              (e) => codes(e.diagnostics),
              'codes',
              contains(MediaDiagnosticCode.alphaLost),
            ),
          ),
        );
      },
    );

    // What Android's HEIF decoder actually returns (S25 Edge, 2026-10-02):
    // an alpha channel, every sample 255, over the hidden colours. A check on
    // channel presence passed it, so JPEG showed the hidden colours and PNG
    // saved an opaque image as if transparency had survived.
    group('an alpha channel opaque everywhere', () {
      final opaqueRgba = Uint8List.fromList(
        img.encodePng(
          img.Image(width: 2, height: 2, numChannels: 4)
            ..clear(img.ColorRgba8(80, 120, 158, 255)),
        ),
      );
      const transparent = SourceFacts(
        alpha: true,
        directHdr: false,
        gainMap: false,
      );
      setUp(() {
        api.inspected = const Facts(
          transfer: Transfer.noHdrSignal,
          gainMap: Presence.absent,
          alpha: Presence.present,
          width: 0,
          height: 0,
          orientation: 0,
          bitDepth: 0,
        );
        messenger.setMockMethodCallHandler(
          imageChannel,
          (call) => answerBake(call, opaqueRgba),
        );
      });

      for (final target in [DefaultFormat.jpeg, DefaultFormat.png]) {
        test('is refused for ${target.name}', () async {
          await expectLater(
            ImageEncoder.encode(
              source: _heic,
              target: target,
              quality: 80,
              facts: transparent,
              keepMetadata: false,
            ),
            throwsA(
              isA<ImageEncodingFailure>().having(
                (e) => codes(e.diagnostics),
                'codes',
                contains(MediaDiagnosticCode.alphaLost),
              ),
            ),
          );
        });
      }

      // IMG-15 fixed: the plane comes back through FFmpeg and DarkLib.
      group('on Android', () {
        final decodeGrey = HeifAlpha.decodeGrey;
        setUp(() {
          NativeImageEncoder.onAndroid = true;
          api.alphaStream = AlphaStream(
            hevc: Uint8List(0),
            frames: 1,
            width: 2,
            height: 2,
          );
        });
        tearDown(() {
          NativeImageEncoder.onAndroid = false;
          HeifAlpha.decodeGrey = decodeGrey;
          api.alphaStream = null;
        });

        test('the alpha plane is restored, not refused', () async {
          HeifAlpha.decodeGrey = (_) async =>
              Uint8List.fromList([64, 64, 64, 64]);
          final out = await ImageEncoder.encode(
            source: _heic,
            target: DefaultFormat.png,
            quality: 80,
            facts: transparent,
            keepMetadata: false,
          );
          final shown = img.decodePng(out.bytes)!;
          expect(shown.getPixel(1, 1).a, 64);
          expect(shown.getPixel(1, 1).r, 80);
          expect(
            codes(out.diagnostics),
            isNot(contains(MediaDiagnosticCode.alphaLost)),
          );
        });

        // The compress screen keeps metadata by default: the bridge decodes
        // without it, and DarkLib carries the source's onto the result.
        test(
          'with metadata the plane is restored and metadata carried',
          () async {
            HeifAlpha.decodeGrey = (_) async =>
                Uint8List.fromList([64, 64, 64, 64]);
            final out = await ImageEncoder.encode(
              source: _heic,
              target: DefaultFormat.png,
              quality: 80,
              facts: transparent,
              keepMetadata: true,
            );
            expect(img.decodePng(out.bytes)!.getPixel(1, 1).a, 64);
            expect(api.metadataCalls, contains('transplant'));
          },
        );

        test(
          'a failed decode is still refused, never hidden colours',
          () async {
            HeifAlpha.decodeGrey = (_) async => null;
            await expectLater(
              ImageEncoder.encode(
                source: _heic,
                target: DefaultFormat.png,
                quality: 80,
                facts: transparent,
                keepMetadata: false,
              ),
              throwsA(
                isA<ImageEncodingFailure>().having(
                  (e) => codes(e.diagnostics),
                  'codes',
                  containsAll([
                    MediaDiagnosticCode.emptyOutput,
                    MediaDiagnosticCode.alphaLost,
                  ]),
                ),
              ),
            );
          },
        );
      });

      test('real transparency from the bridge is kept', () async {
        final rgba = Uint8List.fromList(
          img.encodePng(
            img.Image(width: 2, height: 2, numChannels: 4)
              ..clear(img.ColorRgba8(80, 120, 158, 64)),
          ),
        );
        messenger.setMockMethodCallHandler(
          imageChannel,
          (call) => answerBake(call, rgba),
        );
        final out = await ImageEncoder.encode(
          source: _heic,
          target: DefaultFormat.png,
          quality: 80,
          facts: transparent,
          keepMetadata: false,
        );
        expect(out.bytes, rgba);
        expect(
          codes(out.diagnostics),
          isNot(contains(MediaDiagnosticCode.alphaLost)),
        );
      });
    });
  });
}
