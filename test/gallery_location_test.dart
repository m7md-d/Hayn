import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/image_ops/data/gallery_saver.dart';

// RV-06: a zero on one axis is a real place. Before, each axis equal to zero
// was dropped on its own, and photo_manager stamps nothing without both, so
// a photo on the equator or at Greenwich lost its location.

void main() {
  test('a location with one zero axis is kept whole', () {
    expect(GallerySaver.location(0, 45), (latitude: 0.0, longitude: 45.0));
    expect(GallerySaver.location(24, 0), (latitude: 24.0, longitude: 0.0));
    expect(GallerySaver.location(-33.9, 18.4), (
      latitude: -33.9,
      longitude: 18.4,
    ));
  });

  test("photo_manager's none, and values that are no place, stamp nothing", () {
    expect(GallerySaver.location(0, 0), isNull); // iOS: no PHAsset.location
    expect(GallerySaver.location(null, null), isNull); // Android 10+
    expect(GallerySaver.location(24, null), isNull);
    expect(GallerySaver.location(91, 10), isNull);
    expect(GallerySaver.location(10, -181), isNull);
    expect(GallerySaver.location(double.nan, 10), isNull);
  });
}
