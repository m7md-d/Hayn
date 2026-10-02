import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/native_image_encoder.dart';
import 'package:hayn/features/image_ops/data/platform_pixels.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/src/rust/frb_generated.dart';
import 'package:image/image.dart' as img;

import 'support/bake_channel.dart';
import 'support/encoded_headers.dart';

// IMG-13: Flutter misreads 10-bit AVIF/HEIC decoded by Android's ImageDecoder
// (on-device probe, docs/14-ISSUES.md). On Android those two containers go
// through the platform bridge. Its PNG carries no metadata, so DarkLib carries
// the source's onto it when asked. iOS and other formats are unchanged.

final _heic = Uint8List.fromList([
  0,
  0,
  0,
  20,
  ...'ftypheic0000mif1'.codeUnits,
]);
final _png = Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

/// DarkLib as the bridge uses it: inspect (no alpha), and carrying the
/// source's metadata, which [carries] = false makes fail.
class _Api extends Fake implements DarkLibApi {
  bool carries = true;

  @override
  Future<Facts> crateApiInspectInspectImage({required List<int> bytes}) async =>
      const Facts(
        transfer: Transfer.noHdrSignal,
        gainMap: Presence.absent,
        alpha: Presence.absent,
        width: 0,
        height: 0,
      );

  @override
  Future<Uint8List> crateApiMetadataTransplantMetadata({
    required List<int> source,
    required List<int> target,
  }) async =>
      carries ? Uint8List.fromList(target) : Future.error('malformed: test');

  @override
  Future<Uint8List> crateApiMetadataStripMetadata({
    required List<int> bytes,
    required bool stripIcc,
  }) async => Uint8List.fromList(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => DarkLib.initMock(api: api));
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <Map>[];
  Uint8List? answer;

  setUp(() {
    calls.clear();
    answer = _png;
    messenger.setMockMethodCallHandler(NativeImageEncoder.channel, (
      call,
    ) async {
      if (!isBake(call)) return null;
      calls.add(call.arguments as Map);
      return answerBake(call, answer);
    });
  });
  tearDown(() {
    NativeImageEncoder.onAndroid = false;
    api.carries = true;
    messenger.setMockMethodCallHandler(NativeImageEncoder.channel, null);
  });

  Future<(T, List<String>)> traced<T>(Future<T> Function() body) =>
      MediaDiagnostics.trace((trace) async {
        final r = await body();
        return (r, trace.events.map((e) => e.toString()).toList());
      });

  test('only Android AVIF/HEIC take the bridge', () {
    NativeImageEncoder.onAndroid = true;
    expect(PlatformPixels.needsBridge(encodedHeader(DefaultFormat.avif)), true);
    expect(PlatformPixels.needsBridge(_heic), true);
    expect(PlatformPixels.needsBridge(_png), false);
    expect(
      PlatformPixels.needsBridge(encodedHeader(DefaultFormat.jpeg)),
      false,
    );

    NativeImageEncoder.onAndroid = false;
    expect(PlatformPixels.needsBridge(_heic), false);
  });

  test('display bytes come from the bridge, without metadata', () async {
    NativeImageEncoder.onAndroid = true;
    final shown = await PlatformPixels.forDisplay(_heic, maxEdge: 4096);
    expect(shown, _png);
    expect(calls.single['keepMetadata'], false);
    expect(calls.single['maxEdge'], 4096);
    expect(calls.single['srgb'], true); // Flutter shows sRGB

    // A failed bridge leaves the original and a recorded reason.
    answer = null;
    final (fallback, events) = await traced(
      () => PlatformPixels.forDisplay(_heic, maxEdge: 4096),
    );
    expect(fallback, _heic);
    expect(events, ['androidDecoder.bake.emptyOutput']);

    // Nothing to fix: no channel call at all.
    calls.clear();
    expect(await PlatformPixels.forDisplay(_png, maxEdge: 4096), _png);
    expect(calls, isEmpty);
  });

  // The bridge itself carries no metadata: DarkLib carries the source's onto
  // its PNG, its colour profile always (IMG-18). When that fails the request
  // gets nothing rather than an image silently stripped or mislabelled.
  test('Android bridge needs DarkLib to carry the source', () async {
    NativeImageEncoder.onAndroid = true;
    api.carries = false;
    final (out, events) = await traced(
      () => NativeImageEncoder.bakeUpright(
        source: encodedHeader(DefaultFormat.avif),
        keepMetadata: true,
        keepOriginalTime: true,
      ),
    );
    expect(out, isNull);
    expect(calls.single['srgb'], false);
    expect(events, contains('androidDecoder.transplant.unavailable'));
  });

  test('PNG output names the engine that produced it', () async {
    NativeImageEncoder.onAndroid = true;
    final r = await ImageEncoder.encode(
      source: encodedHeader(DefaultFormat.jpeg),
      target: DefaultFormat.png,
      quality: 90,
      facts: const SourceFacts.sdr(alpha: false),
      keepMetadata: false,
    );
    expect(r.backend, MediaBackend.androidDecoder);
    expect(r.bytes, _png);

    NativeImageEncoder.onAndroid = false;
    final ios = await ImageEncoder.encode(
      source: encodedHeader(DefaultFormat.jpeg),
      target: DefaultFormat.png,
      quality: 90,
      facts: const SourceFacts.sdr(alpha: false),
      keepMetadata: false,
    );
    expect(ios.backend, MediaBackend.imageIO);
  });
}
