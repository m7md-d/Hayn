import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/core/isolates/heavy_work.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/src/rust/api/codec.dart';
import 'package:hayn/src/rust/engine/codec.dart';
import 'package:hayn/src/rust/frb_generated.dart';

// RUN-01 step 6 / RUN-02: an encode whose estimate exceeds the memory the
// platform reports is refused before any engine runs, with a diagnosis,
// instead of the system killing the app midway.

/// Any DarkLib call would throw: none may run. Transcodes are recorded.
class _Api extends Fake implements DarkLibApi {
  final transcodes = <CodecFormat>[];

  @override
  Future<Transcoded> crateApiCodecTranscode({
    required List<int> bytes,
    required CodecFormat format,
    required int quality,
    required int maxEdge,
    required bool keepMetadata,
    required int bitDepth,
  }) async {
    transcodes.add(format);
    throw 'unsupported';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => DarkLib.initMock(api: api));
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('hayn/metadata');
  final calls = <String>[];
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  const giant = SourceFacts(
    alpha: false,
    directHdr: false,
    gainMap: false,
    width: 16128,
    height: 12096,
  );

  test('a 200 MP PNG with 1 GB free is refused before any engine', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'memoryInfo'
          ? {'available': 1 << 30, 'threshold': 200 << 20}
          : null;
    });
    await expectLater(
      ImageEncoder.encode(
        source: Uint8List(16),
        target: DefaultFormat.png,
        quality: 90,
        facts: giant,
        keepMetadata: false,
      ),
      throwsA(
        isA<ImageEncodingFailure>().having(
          (e) => e.diagnostics.map((d) => d.code),
          'diagnosis',
          contains(MediaDiagnosticCode.insufficientMemory),
        ),
      ),
    );
    expect(calls, ['memoryInfo'], reason: 'no engine was asked');
  });

  test('a 10-bit HEIC of an 8-bit source off Android is drawn at 16 bits', () {
    int mb(int bitDepth) =>
        ImageEncoder.memoryEstimate(
          giant,
          DefaultFormat.heic,
          0,
          bitDepth: bitDepth,
        ) >>
        20;
    expect(mb(10), greaterThan(8 * mb(8)), reason: '8 bytes a pixel');
  });

  test('estimates: HEIC in bands, the others whole', () {
    int mb(DefaultFormat f) => ImageEncoder.memoryEstimate(giant, f, 0) >> 20;
    expect(mb(DefaultFormat.heic), lessThan(mb(DefaultFormat.jpeg)));
    expect(mb(DefaultFormat.png), greaterThan(1000));
    expect(
      ImageEncoder.memoryEstimate(
        const SourceFacts.sdr(alpha: false),
        DefaultFormat.png,
        1 << 20,
      ),
      0,
      reason: 'unknown size: only the count limits it',
    );
  });

  // RV-03: Auto admitted for HEIC (a byte a pixel) fell back to WebP (17) in
  // the same admission. A fallback now runs only if its own estimate fits.
  test('a fallback costlier than the room left is skipped, not run', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      // 600 MB to use: HEIC (60 MB) and JPEG (540 MB) fit, WebP (1 GB) not.
      return call.method == 'memoryInfo'
          ? {'available': 700 << 20, 'threshold': 100 << 20}
          : null;
    });
    api.transcodes.clear();
    const photo = SourceFacts(
      alpha: false,
      directHdr: false,
      gainMap: false,
      width: 7746,
      height: 7746,
    );
    ImageEncodingFailure? failure;
    try {
      await ImageEncoder.encode(
        source: Uint8List(16),
        target: DefaultFormat.heic,
        allowFormatFallback: true,
        quality: 80,
        facts: photo,
        keepMetadata: false,
      );
    } on ImageEncodingFailure catch (e) {
      failure = e; // no engine here
    }
    expect(
      failure!.diagnostics.map((d) => d.code),
      contains(MediaDiagnosticCode.insufficientMemory),
    );
    expect(api.transcodes, isNot(contains(CodecFormat.webp)));
  });

  test(
    "within the caller's admission an encode does not queue again",
    () async {
      final old = HeavyWork.instance;
      addTearDown(() => HeavyWork.instance = old);
      HeavyWork.instance = HeavyWork(
        memory: () async => null,
        maxConcurrent: 1,
      );
      final ticket = HeavyWorkTicket();
      final result = HeavyWork.instance.run(
        estimateBytes: 0,
        ticket: ticket,
        body: () => ImageEncoder.encode(
          source: Uint8List(16),
          target: DefaultFormat.png,
          quality: 90,
          facts: const SourceFacts.sdr(alpha: false),
          keepMetadata: false,
          ticket: ticket,
          withinAdmission: true,
        ),
      );
      // A nested admission would wait for its own holder forever.
      await expectLater(
        result.timeout(const Duration(seconds: 5)),
        throwsA(isA<ImageEncodingFailure>()),
      );
    },
  );
}
