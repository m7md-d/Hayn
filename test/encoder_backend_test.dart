import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/src/rust/frb_generated.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/native_avif_encoder.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

class _Api extends Fake implements DarkLibApi {
  int calls = 0;
  bool empty = false;
  bool reject = false;
  @override
  Future<Uint8List> crateApiCodecTranscode({
    required List<int> bytes,
    required DarkLibFormat format,
    required int quality,
    required int maxEdge,
  }) async {
    calls++;
    if (reject) throw StateError('secret filename');
    return Uint8List.fromList(empty ? [] : [9, 8, 7]);
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
  tearDown(() {
    messenger.setMockMethodCallHandler(imageChannel, null);
    messenger.setMockMethodCallHandler(avifChannel, null);
    api.empty = false;
    api.reject = false;
  });

  test('primary DarkLib succeeds without touching plugin fallback', () async {
    final before = api.calls;
    final result = await ImageEncoder.encode(
      source: Uint8List(3),
      target: DefaultFormat.webp,
      quality: 80,
      hasAlpha: false,
      keepMetadata: false,
    );
    expect(api.calls, before + 1);
    expect(result.backend, MediaBackend.darklib);
    expect(result.format, DefaultFormat.webp);
    expect(result.requestedFormat, DefaultFormat.webp);
    expect(result.diagnostics, isEmpty);
  });

  test(
    'DarkLib empty and exceptional outputs have distinct diagnostics',
    () async {
      api.empty = true;
      expect(
        await DarkLibCore.transcode(
          Uint8List(3),
          format: DarkLibFormat.webp,
          quality: 80,
          keepMetadata: false,
        ),
        isNull,
      );
      expect(
        MediaDiagnostics.recent.last.code,
        MediaDiagnosticCode.emptyOutput,
      );
      api.reject = true;
      expect(
        await DarkLibCore.transcode(
          Uint8List(3),
          format: DarkLibFormat.webp,
          quality: 80,
          keepMetadata: false,
        ),
        isNull,
      );
      expect(MediaDiagnostics.recent.last.code, MediaDiagnosticCode.exception);
      expect(
        MediaDiagnostics.recent.join(),
        isNot(contains('secret filename')),
      );
    },
  );

  test(
    'primary ImageIO returns backend without attempting another format',
    () async {
      messenger.setMockMethodCallHandler(imageChannel, (call) async {
        expect(call.method, 'encodeImage');
        return Uint8List.fromList([3, 2, 1]);
      });
      final result = await ImageEncoder.encode(
        source: Uint8List(3),
        target: DefaultFormat.jpeg,
        quality: 80,
        hasAlpha: false,
        keepMetadata: false,
      );
      expect(result.backend, MediaBackend.imageIO);
      expect(result.diagnostics, isEmpty);
    },
  );

  test(
    'transient hardware probe failure is diagnosable and retryable',
    () async {
      var probes = 0;
      messenger.setMockMethodCallHandler(avifChannel, (call) async {
        if (call.method == 'isAvailable') {
          probes++;
          if (probes == 1) throw PlatformException(code: 'transient');
          return true;
        }
        return Uint8List.fromList([1]);
      });
      expect(await NativeAvifEncoder.isAvailable(), isFalse);
      expect(MediaDiagnostics.recent.last.operation, MediaOperation.probe);
      expect(await NativeAvifEncoder.isAvailable(), isTrue);
      expect(probes, 2);
      final result = await ImageEncoder.encode(
        source: Uint8List(3),
        target: DefaultFormat.avif,
        quality: 80,
        hasAlpha: false,
        keepMetadata: false,
      );
      expect(result.backend, MediaBackend.androidAvif);
    },
  );
}
