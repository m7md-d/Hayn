import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/src/rust/frb_generated.dart';

// RUN-01 step 6 / RUN-02: an encode whose estimate exceeds the memory the
// platform reports is refused before any engine runs, with a diagnosis,
// instead of the system killing the app midway.

/// Any DarkLib call would throw: none may run.
class _Api extends Fake implements DarkLibApi {}

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
}
