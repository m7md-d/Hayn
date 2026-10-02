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

// RUN-01 step 5: on Android a giant image's HEIC comes from bands and tiles
// (HeifWriter failed outright), smaller ones from the plugin's HeifWriter
// (faster, user decision 2026-10-02). Either way DarkLib carries the source's
// profile and on request its metadata (IMG-22): before, HeifWriter's output
// was returned with neither.

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
  late bool tilesFail;

  setUp(() {
    NativeImageEncoder.onAndroid = true;
    api.metadataCalls.clear();
    tileCalls = [];
    tilesFail = false;
    final old = FlutterImageCompressPlatform.instance;
    plugin = _Plugin();
    FlutterImageCompressPlatform.instance = plugin;
    addTearDown(() => FlutterImageCompressPlatform.instance = old);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'encodeHeicTiles') return null;
      tileCalls.add(call.arguments as Map);
      if (tilesFail) return null;
      final dir = await Directory.systemTemp.createTemp('hayn-tiles-test');
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

  test('a source up to 64 MP takes HeifWriter, with its profile', () async {
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
      expect(r.backend, MediaBackend.imageCompress);
      expect(
        api.metadataCalls,
        keepMetadata ? ['transplant'] : ['transplant', 'strip'],
      );
    }
    expect(tileCalls, isEmpty);
    expect(plugin.calls, [CompressFormat.heic, CompressFormat.heic]);
  });

  test('alpha, unknown alpha and iOS never reach the tiles', () async {
    for (final alpha in [true, null]) {
      try {
        await heic(SourceFacts(alpha: alpha, directHdr: false, gainMap: false));
      } on ImageEncodingFailure {
        // HeifWriter keeps no transparency: refused, as before.
      }
    }
    NativeImageEncoder.onAndroid = false;
    await heic(opaque);
    expect(tileCalls, isEmpty);
  });

  test(
    'when the tiles fail, the plugin answers with metadata carried',
    () async {
      tilesFail = true;
      final r = await heic(opaque);
      expect(tileCalls, hasLength(1));
      expect(r.backend, MediaBackend.imageCompress);
      expect(plugin.calls, [CompressFormat.heic]);
      expect(api.metadataCalls, ['transplant', 'strip']);
      expect(
        r.diagnostics.map((d) => d.toString()),
        contains('androidHeic.encode.emptyOutput'),
      );
    },
  );
}
