import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:image/image.dart' as img;
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/src/rust/frb_generated.dart';

// Explicit host smoke test. Requires a real, matching Rust library; never mocks
// or silently skips the primary backend. This does not validate HDR or phones.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real DarkLib converts an SDR PNG to decodable WebP', () async {
    const path = String.fromEnvironment('DARKLIB_TEST_LIBRARY');
    if (path.isEmpty) {
      fail('Set DARKLIB_TEST_LIBRARY to the compiled host library');
    }
    await DarkLib.init(externalLibrary: ExternalLibrary.open(path));
    addTearDown(DarkLib.dispose);
    final source = img.Image(width: 16, height: 12, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(80, 120, 160));
    final result = await ImageEncoder.encode(
      source: Uint8List.fromList(img.encodePng(source)),
      target: DefaultFormat.webp,
      quality: 90,
      hasAlpha: false,
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
}
