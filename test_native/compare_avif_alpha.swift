import CoreGraphics
import Foundation
import ImageIO

// Independent check of DarkLib's AVIF alpha (Hayn IMG-02). DarkLib's decodes
// come from `cargo test --test avif_alpha` (PNG in target/tmp/avif-alpha). The
// reference alpha is ImageIO's, except for the per-tile file ImageIO reads as
// opaque: there it is ffmpeg's decode of each alpha tile, placed at the colour
// tile offsets ffprobe reports. AV1 decoding is normative, so the planes should
// agree to within a rounding step.
// Usage: swift test_native/compare_avif_alpha.swift native/darklib
guard CommandLine.arguments.count == 2 else { fatalError("Pass native/darklib") }
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fixtures = root.appendingPathComponent("tests/fixtures")
let decoded = root.appendingPathComponent("target/tmp/avif-alpha")

/// Straight alpha of the first image in `url`, via ImageIO, upright: the
/// container's orientation (AVIF irot/imir) applied as a viewer shows it.
func imageIOAlpha(_ url: URL) -> (Int, Int, [UInt8]) {
  let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
  let edge = max(props[kCGImagePropertyPixelWidth] as! Int, props[kCGImagePropertyPixelHeight] as! Int)
  let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: edge,
  ] as CFDictionary)!
  let (w, h) = (img.width, img.height)
  var px = [UInt8](repeating: 0, count: w * h * 4)
  let ctx = CGContext(
    data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  return (w, h, stride(from: 3, to: px.count, by: 4).map { px[$0] })
}

func run(_ tool: String, _ args: [String]) -> Data {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/\(tool)")
  p.arguments = args
  let pipe = Pipe()
  p.standardOutput = pipe
  p.standardError = FileHandle.nullDevice
  try! p.run()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  p.waitUntilExit()
  precondition(p.terminationStatus == 0, "\(tool) failed")
  return data
}

/// ffmpeg's alpha for a grid whose tiles each carry an alpha item: the gray
/// streams after the colour tiles, in the colour tiles' order.
func ffmpegTileAlpha(_ url: URL) -> (Int, Int, [UInt8]) {
  let info = try! JSONSerialization.jsonObject(
    with: run("ffprobe", ["-v", "error", "-show_stream_groups", "-show_streams", "-of", "json", url.path]))
    as! [String: Any]
  let group = (info["stream_groups"] as! [[String: Any]])[0]
  let comp = (group["components"] as! [[String: Any]])[0]
  let (w, h) = (comp["width"] as! Int, comp["height"] as! Int)
  let tiles = comp["subcomponents"] as! [[String: Any]]
  let streams = info["streams"] as! [[String: Any]]
  let gray = streams.filter { ($0["pix_fmt"] as? String) == "gray" }.map { $0["index"] as! Int }
  precondition(gray.count == tiles.count, "one alpha stream per tile")
  var alpha = [UInt8](repeating: 0, count: w * h)
  for (tile, stream) in zip(tiles, gray) {
    let s = streams.first { ($0["index"] as! Int) == stream }!
    let (tw, th) = (s["width"] as! Int, s["height"] as! Int)
    let (x0, y0) = (tile["tile_horizontal_offset"] as! Int, tile["tile_vertical_offset"] as! Int)
    let raw = [UInt8](run("ffmpeg", ["-v", "error", "-i", url.path, "-map", "0:\(stream)",
                                     "-f", "rawvideo", "-pix_fmt", "gray", "-"]))
    precondition(raw.count == tw * th, "tile size")
    for y in 0..<th where y0 + y < h {
      for x in 0..<tw where x0 + x < w {
        alpha[(y0 + y) * w + x0 + x] = raw[y * tw + x]
      }
    }
  }
  return (w, h, alpha)
}

var failed = false
for (name, perTile) in [
  ("color_grid_alpha_nogrid", true),
  ("color_grid_alpha_grid_gainmap_nogrid", false),
  ("abc_color_irot_alpha_irot", false),
] {
  let avif = fixtures.appendingPathComponent("\(name).avif")
  let ref = perTile ? ffmpegTileAlpha(avif) : imageIOAlpha(avif)
  let ours = imageIOAlpha(decoded.appendingPathComponent("\(name).png"))
  guard (ref.0, ref.1) == (ours.0, ours.1) else {
    print("\(name): size \(ours.0)x\(ours.1) vs reference \(ref.0)x\(ref.1)")
    failed = true
    continue
  }
  let diffs = zip(ref.2, ours.2).map { abs(Int($0) - Int($1)) }
  let maxDiff = diffs.max()!
  let translucent = ref.2.filter { $0 < 255 }.count
  print("\(name): \(ours.0)x\(ours.1), reference \(perTile ? "ffmpeg tiles" : "ImageIO"), "
    + "\(translucent) translucent px, max alpha diff \(maxDiff)")
  if maxDiff > 2 || translucent == 0 { failed = true }
}
print(failed ? "FAIL" : "Independent readers: DarkLib's AVIF alpha matches")
exit(failed ? 1 : 0)
