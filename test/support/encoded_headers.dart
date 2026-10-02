import 'dart:typed_data';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

// Signatures for orchestration tests, not decodable fixtures. Native integration
// and the alpha-verification tests use real images separately.
Uint8List encodedHeader(DefaultFormat format) => switch (format) {
  DefaultFormat.webp => Uint8List.fromList('RIFF0000WEBP'.codeUnits),
  DefaultFormat.avif => Uint8List.fromList([
    0,
    0,
    0,
    20,
    ...'ftypavif0000avif'.codeUnits,
  ]),
  DefaultFormat.jpeg => Uint8List.fromList([
    255,
    216,
    255,
    ...List.filled(9, 0),
  ]),
  DefaultFormat.heic => Uint8List.fromList([
    0,
    0,
    0,
    20,
    ...'ftypheic0000mif1'.codeUnits,
  ]),
  _ => throw ArgumentError.value(format),
};
