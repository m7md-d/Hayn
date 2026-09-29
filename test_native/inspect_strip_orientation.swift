import Foundation
import ImageIO

// Independent check for IMG-07: files written by native/darklib/tests/strip_orientation.rs.
// Usage: swift inspect_strip_orientation.swift native/darklib/target/tmp/strip-orientation
guard CommandLine.arguments.count == 2 else { fatalError("Pass the output directory") }
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
precondition(names.count == 24, "expected 3 formats × 8 orientations, got \(names.count)")
for name in names {
  let o = Int(name.split(separator: "-")[1].dropFirst().split(separator: ".")[0])!
  let source = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil)!
  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
  let read = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
  precondition(read == o, "\(name): ImageIO orientation \(read)")
  precondition(props[kCGImagePropertyGPSDictionary] == nil, "\(name): GPS remains")
  let shown = CGImageSourceCreateThumbnailAtIndex(source, 0, [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: 64,
  ] as CFDictionary)!
  let expected = o >= 5 ? (4, 6) : (6, 4)
  precondition((shown.width, shown.height) == expected, "\(name): shown \(shown.width)x\(shown.height)")
}
print("Independent ImageIO: \(names.count) stripped files keep their orientation, no GPS")
