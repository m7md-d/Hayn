import CoreGraphics
import Foundation
import ImageIO

// Apple's reader for the phone's tiled HEIC outputs (RUN-01 step 5, IMG-21/22),
// the counterpart of check_heic_tiles.py (libheif + LittleCMS on Linux).
//
// 1. heic-tiles/WxH-oN.heic: a JPEG of four flat quadrants whose EXIF names
//    orientation N went through the tiled encoder. ImageIO, with its own
//    orientation transform, must show the quadrants where EXIF puts them.
// 2. heic-tiles/p3.heic against p3-source.jpg: the same colours once ImageIO
//    colour-manages both into sRGB.
//
// Usage: swift test_native/check_heic_tiles.swift build/android-device/<run>/results
guard CommandLine.arguments.count == 2 else { fatalError("Pass the results directory") }
let results = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("heic-tiles")
var failures: [String] = []

func transpose<T>(_ m: [[T]]) -> [[T]] { (0..<m[0].count).map { c in m.map { $0[c] } } }
/// EXIF orientation [o] applied to a row-major matrix (what a viewer shows).
func exif<T>(_ o: Int, _ m: [[T]]) -> [[T]] {
  switch o {
  case 1: return m
  case 2: return m.map { Array($0.reversed()) }
  case 3: return m.reversed().map { Array($0.reversed()) }
  case 4: return Array(m.reversed())
  case 5: return transpose(m)
  case 6: return transpose(Array(m.reversed()))
  case 7: return transpose(m.map { Array($0.reversed()) }.reversed())
  default: return Array(transpose(m).reversed())
  }
}

/// The image as RGBA8 in sRGB, then upright by the orientation ImageIO reports
/// (it hands back the stored pixels and names irot/imir as the EXIF orientation,
/// as Photos and Preview apply it). The thumbnail API is not used: its output
/// carries no colour space, so its colours cannot be compared.
func upright(_ url: URL) -> (w: Int, h: Int, rgba: [UInt8], orientation: Int)? {
  guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
    let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
  else { return nil }
  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
  let orientation = props?[kCGImagePropertyOrientation] as? Int ?? 1
  let w = img.width, h = img.height
  var buf = [UInt8](repeating: 0, count: w * h * 4)
  guard
    let ctx = CGContext(
      data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return nil }
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  let rows: [[[UInt8]]] = (0..<h).map { y in
    (0..<w).map { x in Array(buf[(y * w + x) * 4..<(y * w + x) * 4 + 4]) }
  }
  let turned = exif(orientation, rows)
  return (turned[0].count, turned.count, turned.flatMap { $0.flatMap { $0 } }, orientation)
}

func pixel(_ i: (w: Int, h: Int, rgba: [UInt8], orientation: Int), _ x: Int, _ y: Int) -> [Int] {
  let o = (y * i.w + x) * 4
  return [Int(i.rgba[o]), Int(i.rgba[o + 1]), Int(i.rgba[o + 2])]
}

func close(_ a: [Int], _ b: [Int], _ tol: Int) -> Bool {
  zip(a, b).allSatisfy { abs($0 - $1) <= tol }
}

let colours: [Character: [Int]] = [
  "r": [220, 40, 40], "g": [40, 200, 60], "b": [40, 60, 220], "y": [230, 210, 40],
]
let files = try FileManager.default.contentsOfDirectory(atPath: results.path).sorted()

// 1. Orientation: size and where the quadrant colours land.
for name in files where name.hasSuffix(".heic") && name.contains("-o") {
  let parts = name.replacingOccurrences(of: ".heic", with: "").components(separatedBy: "-o")
  let dims = parts[0].components(separatedBy: "x").compactMap { Int($0) }
  let o = Int(parts[1])!
  let (w, h) = (dims[0], dims[1])
  guard let img = upright(results.appendingPathComponent(name)) else {
    failures.append("\(name): ImageIO cannot read it")
    continue
  }
  let want = o >= 5 ? (h, w) : (w, h)
  var verdict = "ok"
  if (img.w, img.h) != want {
    failures.append("\(name): size \(img.w)x\(img.h), want \(want.0)x\(want.1)")
    verdict = "SIZE"
  } else {
    let grid: [[Character]] = exif(o, [["r", "g"], ["b", "y"]])
    for qy in 0..<2 {
      for qx in 0..<2 {
        let p = pixel(img, img.w * (1 + 2 * qx) / 4, img.h * (1 + 2 * qy) / 4)
        if !close(p, colours[grid[qy][qx]]!, 12) {
          failures.append("\(name): quadrant \(qx),\(qy) is \(p), want \(grid[qy][qx])")
          verdict = "COLOUR"
        }
      }
    }
  }
  print("\(name): \(img.w)x\(img.h) ImageIO orientation \(img.orientation) → \(verdict)")
}

// 2. The P3 tiles output against its source, both colour-managed by ImageIO.
if let src = upright(results.appendingPathComponent("p3-source.jpg")),
  let out = upright(results.appendingPathComponent("p3.heic"))
{
  print("p3: source \(src.w)x\(src.h), heic \(out.w)x\(out.h)")
  for (x, y) in [(64, 48), (192, 48), (64, 144), (192, 144)] {
    let a = pixel(src, x, y), b = pixel(out, x, y)
    print("p3 at \(x),\(y): source \(a) heic \(b)")
    if !close(a, b, 8) { failures.append("p3.heic at \(x),\(y): \(b), source \(a)") }
  }
} else {
  failures.append("p3.heic or p3-source.jpg unreadable")
}

// Files outside the checks: only that ImageIO reads them.
for name in files where name.hasSuffix(".heic") && !name.contains("-o") && name != "p3.heic" {
  if let img = upright(results.appendingPathComponent(name)) {
    print("\(name): readable, \(img.w)x\(img.h)")
  } else {
    failures.append("\(name): ImageIO cannot read it")
  }
}

for f in failures { print("FAIL", f) }
print(failures.isEmpty ? "ok" : "\(failures.count) failure(s)")
exit(failures.isEmpty ? 0 : 1)
