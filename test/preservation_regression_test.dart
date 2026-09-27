import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/image_ops/data/native_image_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hayn/features/image_ops/data/image_probe.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

class RecoveringEncoder extends FlutterImageCompressPlatform {
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
    if (format == CompressFormat.jpeg) throw PlatformException(code: 'failed');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final brand in ['heic', 'avif']) {
    test('$brand alpha stays unknown without a reliable probe', () async {
      final bytes = Uint8List.fromList([
        0,
        0,
        0,
        20,
        ...'ftyp${brand}0000mif1'.codeUnits,
      ]);
      expect(await ImageProbe.hasAlpha(bytes), isNull);
    });
  }
  test('unrecognised source alpha stays unknown', () async {
    expect(await ImageProbe.hasAlpha(Uint8List(20)), isNull);
  });
  test('malformed PNG alpha stays unknown', () async {
    final b = Uint8List(20)..setAll(0, [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(await ImageProbe.hasAlpha(b), isNull);
  });
  test('forced format cannot silently change after failure', () async {
    final old = FlutterImageCompressPlatform.instance;
    final fake = RecoveringEncoder();
    FlutterImageCompressPlatform.instance = fake;
    addTearDown(() => FlutterImageCompressPlatform.instance = old);
    await expectLater(
      ImageEncoder.encode(
        source: Uint8List(20),
        target: DefaultFormat.jpeg,
        quality: 80,
        hasAlpha: false,
        keepMetadata: false,
      ),
      throwsA(isA<ImageEncodingFailure>()),
    );
    expect(fake.calls, [CompressFormat.jpeg]);
  });
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('hayn/metadata');
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('missing and ill-typed native fields stay unknown', () async {
    for (final response in [
      {},
      {'hasAlpha': 'false'},
      {'isHdr': true},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      expect(await NativeImageProbe.probeAlpha(Uint8List(20)), isNull);
      expect(await NativeImageProbe.probe(Uint8List(20)), isNull);
    }
  });
  test('explicit native alpha facts are retained', () async {
    for (final value in [false, true]) {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'hasAlpha': value},
      );
      expect(await NativeImageProbe.probeAlpha(Uint8List(20)), value);
    }
  });
  test('native probe failure is diagnosed and stays unknown', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'failed'),
    );
    expect(await NativeImageProbe.probeAlpha(Uint8List(20)), isNull);
    expect(MediaDiagnostics.recent.last.code, MediaDiagnosticCode.exception);
  });
  test('unknown alpha cannot enter an opaque fallback', () {
    for (final target in DefaultFormat.values) {
      expect(
        ImageEncoder.fallbackChain(target, null),
        isNot(contains(DefaultFormat.jpeg)),
      );
    }
  });
  test('forced JPEG with unknown alpha fails before encoding', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    await expectLater(
      ImageEncoder.encode(
        source: Uint8List(20),
        target: DefaultFormat.jpeg,
        quality: 80,
        hasAlpha: null,
        keepMetadata: false,
      ),
      throwsA(isA<ImageEncodingFailure>()),
    );
    expect(calls, 0);
  });
  test('mismatched output container is rejected', () async {
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    messenger.setMockMethodCallHandler(channel, (_) async => png);
    await expectLater(
      ImageEncoder.encode(
        source: png,
        target: DefaultFormat.jpeg,
        quality: 80,
        hasAlpha: false,
        keepMetadata: false,
      ),
      throwsA(
        isA<ImageEncodingFailure>().having(
          (e) => e.diagnostics.map((d) => d.code),
          'format check',
          contains(MediaDiagnosticCode.outputFormatMismatch),
        ),
      ),
    );
  });
  test(
    'alpha channel loss is rejected even in an alpha-capable format',
    () async {
      final opaque = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2, numChannels: 3)),
      );
      messenger.setMockMethodCallHandler(channel, (_) async => opaque);
      await expectLater(
        ImageEncoder.encode(
          source: opaque,
          target: DefaultFormat.png,
          quality: 80,
          hasAlpha: true,
          keepMetadata: false,
        ),
        throwsA(
          isA<ImageEncodingFailure>().having(
            (e) => e.diagnostics.map((d) => d.code),
            'alpha check',
            contains(MediaDiagnosticCode.alphaLost),
          ),
        ),
      );
    },
  );
  test('primary alpha-preserving PNG path passes inspection', () async {
    final pixels = img.Image(width: 2, height: 2, numChannels: 4);
    pixels.setPixelRgba(0, 0, 20, 40, 80, 64);
    final png = Uint8List.fromList(img.encodePng(pixels));
    messenger.setMockMethodCallHandler(channel, (_) async => png);
    final result = await ImageEncoder.encode(
      source: png,
      target: DefaultFormat.png,
      quality: 80,
      hasAlpha: true,
      keepMetadata: false,
    );
    expect(result.diagnostics, isEmpty);
    expect(img.decodePng(result.bytes)!.getPixel(0, 0).a, 64);
  });
  test(
    'compatible AVIF brand takes precedence over generic HEIF major brand',
    () {
      final bytes = Uint8List.fromList([
        0,
        0,
        0,
        20,
        ...'ftypmif10000avif'.codeUnits,
      ]);
      expect(ImageProbe.sniff(bytes), SniffedFormat.avif);
      bytes[3] = 24;
      expect(ImageProbe.sniff(bytes), SniffedFormat.unknown);
    },
  );
  test('oversized brand list is refused without scanning image payload', () {
    final bytes = Uint8List(8192)..setAll(4, 'ftypavif'.codeUnits);
    expect(ImageProbe.sniff(bytes), SniffedFormat.unknown);
  });
}
