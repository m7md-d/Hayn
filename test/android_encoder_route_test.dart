import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/native_image_encoder.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/src/rust/frb_generated.dart';

import 'support/encoded_headers.dart';

// Android's HEIC and JPEG never come from flutter_image_compress (IMG-24):
// it decodes into RGB_565 (banding in every output) and hands HeifWriter a GL
// texture that crashed the GPU driver at an odd width. HEIC comes from bands
// and tiles at every size (RUN-01 step 5, once giant images only), JPEG from
// the platform decoder's 8-bit pixels and Bitmap.compress. DarkLib carries
// the source's profile and on request its metadata (IMG-22).

class _Api extends Fake implements DarkLibApi {
  final metadataCalls = <String>[];

  /// The plugin's HEIC (HeifWriter) never keeps transparency.
  @override
  Future<AlphaKept> crateApiVerifyAlphaKept({
    required List<int> source,
    required List<int> output,
  }) async => AlphaKept.lost;

  @override
  Future<Uint8List> crateApiMetadataTransplantMetadata({
    required List<int> source,
    required List<int> target,
  }) async {
    metadataCalls.add('transplant');
    return Uint8List.fromList(target);
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

class _Plugin extends FlutterImageCompressPlatform {
  final calls = <CompressFormat>[];

  @override
  Future<Uint8List> compressWithList(
    Uint8List image, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    int inSampleSize = 1,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
  }) async {
    calls.add(format);
    return encodedHeader(DefaultFormat.heic);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => DarkLib.initMock(api: api));
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('hayn/metadata');
  final source = encodedHeader(DefaultFormat.jpeg);
  late _Plugin plugin;
  late List<Map> tileCalls;
  late List<Map> jpegCalls;
  late bool tilesFail;
  late bool tenBit;

  setUp(() {
    NativeImageEncoder.onAndroid = true;
    api.metadataCalls.clear();
    tileCalls = [];
    tilesFail = false;
    tenBit = true;
    NativeImageEncoder.resetHeicTenBit();
    final old = FlutterImageCompressPlatform.instance;
    plugin = _Plugin();
    FlutterImageCompressPlatform.instance = plugin;
    addTearDown(() => FlutterImageCompressPlatform.instance = old);
    jpegCalls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'heicTenBit') return tenBit;
      final dir = await Directory.systemTemp.createTemp('hayn-route-test');
      if (call.method == 'bakeUprightFile') {
        jpegCalls.add(call.arguments as Map);
        if (tilesFail) return null;
        final file = File('${dir.path}/out.jpg');
        await file.writeAsBytes(encodedHeader(DefaultFormat.jpeg));
        return file.path;
      }
      if (call.method != 'encodeHeicTiles') return null;
      tileCalls.add(call.arguments as Map);
      if (tilesFail) return null;
      final file = File('${dir.path}/out.heic');
      await file.writeAsBytes(encodedHeader(DefaultFormat.heic));
      return {'path': file.path, 'codec': 'test.hevc', 'rateMode': 'qp'};
    });
  });
  tearDown(() {
    NativeImageEncoder.onAndroid = false;
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<EncodedImage> heic(SourceFacts facts, {bool keepMetadata = false}) =>
      ImageEncoder.encode(
        source: source,
        target: DefaultFormat.heic,
        quality: 85,
        facts: facts,
        keepMetadata: keepMetadata,
      );

  const opaque = SourceFacts(
    alpha: false,
    directHdr: false,
    gainMap: false,
    width: 16128,
    height: 12096,
    orientation: 6,
  );

  test(
    'an opaque source takes the tiles, its orientation and quality',
    () async {
      final r = await heic(opaque);
      expect(r.backend, MediaBackend.androidHeic);
      expect(r.format, DefaultFormat.heic);
      expect(tileCalls.single['orientation'], 6);
      expect(tileCalls.single['quality'], 85);
      expect(plugin.calls, isEmpty);
      // Without metadata the profile still travels (IMG-08).
      expect(api.metadataCalls, ['transplant', 'strip']);
      expect(r.diagnostics, isEmpty);
    },
  );

  test('with metadata the source\'s is carried whole', () async {
    await heic(opaque, keepMetadata: true);
    expect(api.metadataCalls, ['transplant']);
  });

  test('a 12 MP source takes the tiles too, with its profile', () async {
    for (final keepMetadata in [false, true]) {
      api.metadataCalls.clear();
      final r = await heic(
        const SourceFacts(
          alpha: false,
          directHdr: false,
          gainMap: false,
          width: 4032,
          height: 3024,
        ),
        keepMetadata: keepMetadata,
      );
      expect(r.backend, MediaBackend.androidHeic);
      expect(
        api.metadataCalls,
        keepMetadata ? ['transplant'] : ['transplant', 'strip'],
      );
    }
    expect(tileCalls, hasLength(2));
    expect(plugin.calls, isEmpty);
  });

  test('unknown alpha takes the tiles; alpha and iOS never do', () async {
    await heic(
      const SourceFacts(alpha: null, directHdr: false, gainMap: false),
    );
    expect(tileCalls, hasLength(1));
    await expectLater(
      heic(const SourceFacts(alpha: true, directHdr: false, gainMap: false)),
      throwsA(isA<ImageEncodingFailure>()),
    );
    expect(tileCalls, hasLength(1));
    NativeImageEncoder.onAndroid = false;
    await heic(opaque);
    expect(tileCalls, hasLength(1));
    expect(plugin.calls, [CompressFormat.heic], reason: 'iOS fallback only');
  });

  test('when the tiles fail, it fails: the plugin is never asked', () async {
    tilesFail = true;
    final failure = await heic(
      opaque,
    ).then<Object?>((_) => null, onError: (Object e) => e);
    expect(failure, isA<ImageEncodingFailure>());
    expect(tileCalls, hasLength(1));
    expect(plugin.calls, isEmpty);
    expect(
      (failure! as ImageEncodingFailure).diagnostics.map((d) => d.toString()),
      contains('androidHeic.encode.emptyOutput'),
    );
  });

  // IMG-23: the user's 8 or 10, or the source's depth ("match"); 10 needs
  // Main10, and a device without it writes 8, recorded.
  test('HEIC depth: the choice, else the source\'s', () async {
    Future<int> depthFor(int bitDepth, int? sourceDepth) async {
      tileCalls.clear();
      await ImageEncoder.encode(
        source: source,
        target: DefaultFormat.heic,
        quality: 85,
        facts: SourceFacts(
          alpha: false,
          directHdr: false,
          gainMap: false,
          bitDepth: sourceDepth,
        ),
        keepMetadata: false,
        bitDepth: bitDepth,
      );
      return tileCalls.single['depth'] as int;
    }

    expect(await depthFor(10, 8), 10);
    expect(await depthFor(8, 10), 8);
    expect(await depthFor(0, 10), 10);
    expect(await depthFor(0, 8), 8);
    expect(await depthFor(0, null), 8);
  });

  test('HEIC depth: no Main10 writes 8, recorded', () async {
    tenBit = false;
    final r = await ImageEncoder.encode(
      source: source,
      target: DefaultFormat.heic,
      quality: 85,
      facts: const SourceFacts(
        alpha: false,
        directHdr: false,
        gainMap: false,
        bitDepth: 10,
      ),
      keepMetadata: false,
    );
    expect(tileCalls.single['depth'], 8);
    expect(
      r.diagnostics.map((d) => d.toString()),
      contains('androidHeic.encode.depthReduced'),
    );
  });

  Future<EncodedImage> jpeg({bool keepMetadata = false}) => ImageEncoder.encode(
    source: source,
    target: DefaultFormat.jpeg,
    quality: 85,
    facts: opaque,
    keepMetadata: keepMetadata,
  );

  test('JPEG: the decoder\'s raw values, then the profile carried', () async {
    final r = await jpeg();
    expect(r.backend, MediaBackend.androidJpeg);
    expect(r.format, DefaultFormat.jpeg);
    expect(jpegCalls.single['colours'], 'raw');
    expect(jpegCalls.single['jpegQuality'], 85);
    expect(plugin.calls, isEmpty);
    expect(api.metadataCalls, ['transplant', 'strip']);
    api.metadataCalls.clear();
    await jpeg(keepMetadata: true);
    expect(api.metadataCalls, ['transplant']);
  });

  test('JPEG: when the bridge fails, it fails without the plugin', () async {
    tilesFail = true;
    await expectLater(jpeg(), throwsA(isA<ImageEncodingFailure>()));
    expect(jpegCalls, hasLength(1));
    expect(plugin.calls, isEmpty);
  });
}
