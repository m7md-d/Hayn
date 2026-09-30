import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/image_probe.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/src/rust/frb_generated.dart';
import 'package:image/image.dart' as img;

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
  );

  @override
  Future<Transcoded> crateApiCodecTranscode({
    required List<int> bytes,
    required DarkLibFormat format,
    required int quality,
    required int maxEdge,
    required bool keepMetadata,
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
      ..hdr = HdrOutcome.none
      ..inspected = const Facts(
        transfer: Transfer.noHdrSignal,
        gainMap: Presence.absent,
        alpha: Presence.unknown,
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
  });

  group('SourceInspector', () {
    void native(Map<String, Object?>? probe) =>
        messenger.setMockMethodCallHandler(imageChannel, (_) async => probe);

    test('either signal of HDR wins', () async {
      api.inspected = const Facts(
        transfer: Transfer.pq,
        gainMap: Presence.absent,
        alpha: Presence.unknown,
      );
      expect((await SourceInspector.inspect(_png)).directHdr, isTrue);

      api.inspected = const Facts(
        transfer: Transfer.noHdrSignal,
        gainMap: Presence.absent,
        alpha: Presence.unknown,
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
        );
        expect(await ImageProbe.hasAlpha(webp), want, reason: '$presence');
      }
    });

    test(
      'a decoder that drops known alpha is refused, not flattened',
      () async {
        // The bake returns an opaque PNG for a source known to be transparent.
        messenger.setMockMethodCallHandler(
          imageChannel,
          (call) async => call.method == 'bakeUpright' ? _png : null,
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
  });
}
