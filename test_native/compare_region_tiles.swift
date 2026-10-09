import CoreGraphics
import Foundation
import ImageIO

// The AVIF region reader against Apple's decoder (M-07, PERF-03): a band of
// the performance photo's AVIF read by DarkLib's region reader (rav1d,
// LittleCMS to sRGB) in integration_test/ios_region_test.dart, saved as
// photo-region-<W>x<H>-at<top>.rgba, and the same rows of the AVIF through
// ImageIO, colour-managed into sRGB here.
//
// Usage: swift test_native/compare_region_tiles.swift build/ios-preservation/<run>
guard CommandLine.arguments.count == 2 else { fatalError("Pass the results directory") }
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
guard let raw = files.first(where: { $0.hasPrefix("photo-region-") && $0.hasSuffix(".rgba") })
else { fatalError("No photo-region-WxH.rgba in \(dir.path)") }
let parts = raw.dropFirst("photo-region-".count).dropLast(".rgba".count)
  .split(separator: "-")
let dims = parts[0].split(separator: "x").compactMap { Int($0) }
let (w, h) = (dims[0], dims[1])
let top = Int(parts[1].dropFirst("at".count))!
let tiles = [UInt8](try Data(contentsOf: dir.appendingPathComponent(raw)))
precondition(tiles.count == w * h * 4, "\(raw): \(tiles.count) bytes")

let src = CGImageSourceCreateWithURL(dir.appendingPathComponent("photo.avif") as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
let orientation = props?[kCGImagePropertyOrientation] as? Int ?? 1
let space = image.colorSpace.flatMap { $0.name as String? } ?? "none"
print("ImageIO: \(image.width)x\(image.height) orientation \(orientation) space \(space)")
precondition(orientation == 1, "the photo is upright; a turn is not handled here")
precondition(image.width == w && top + h <= image.height, "size \(image.width)x\(image.height)")

// The whole image drawn so that rows top..<top+h land in the buffer
// (Core Graphics' origin is bottom-left).
var apple = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(
  data: &apple, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
  space: CGColorSpace(name: CGColorSpace.sRGB)!,
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(image, in: CGRect(x: 0, y: top + h - image.height, width: w, height: image.height))
print("band: rows \(top)..<\(top + h)")

var total = 0, samples = 0, worst = 0, over8 = 0
var histogram = [Int](repeating: 0, count: 6)  // 0, 1, 2, 3-4, 5-8, >8
for y in stride(from: 0, to: h, by: 3) {
  for x in stride(from: 0, to: w, by: 3) {
    let i = (y * w + x) * 4
    for c in 0..<3 {
      let d = abs(Int(apple[i + c]) - Int(tiles[i + c]))
      total += d
      samples += 1
      worst = max(worst, d)
      if d > 8 { over8 += 1 }
      histogram[d == 0 ? 0 : d == 1 ? 1 : d == 2 ? 2 : d <= 4 ? 3 : d <= 8 ? 4 : 5] += 1
    }
  }
}
let mean = Double(total) / Double(samples)
print(String(format: "tiles vs ImageIO: mean %.3f, max %d, over 8: %.4f%%", mean, worst,
             100 * Double(over8) / Double(samples)))
print("differences 0 / 1 / 2 / 3-4 / 5-8 / >8:", histogram.map {
  String(format: "%.2f%%", 100 * Double($0) / Double(samples))
}.joined(separator: " / "))
let ok = mean < 2 && Double(over8) / Double(samples) < 0.001
print(ok ? "ok" : "FAIL")
exit(ok ? 0 : 1)
