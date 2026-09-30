import CoreGraphics
import Foundation
import ImageIO

// Independent check for Hayn IMG-08: a convert without metadata keeps what the
// pixel values mean. ImageIO renders source and output into sRGB with colour
// management. A lossless pair must match to within rounding while its control
// (profile dropped, the old behaviour) must not. From a JPEG, ImageIO's decoder
// and DarkLib's differ at edges, so the output must instead sit far closer to
// the source than a control from the same decode without the profile. The
// output must carry no EXIF/GPS/TIFF camera fields.
// Pairs come from `cargo test --test icc_privacy` (target/tmp/icc-privacy).
// Usage: swift test_native/compare_colour_privacy.swift native/darklib
guard CommandLine.arguments.count == 2 else { fatalError("Pass native/darklib") }
let dir = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("target/tmp/icc-privacy")

func source(_ name: String) -> CGImageSource {
  CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil)!
}

/// 8-bit sRGB rendering, colour-managed by ImageIO/CoreGraphics.
func srgb(_ name: String) -> (Int, Int, [UInt8]) {
  let img = CGImageSourceCreateImageAtIndex(source(name), 0, nil)!
  let (w, h) = (img.width, img.height)
  var px = [UInt8](repeating: 0, count: w * h * 4)
  let ctx = CGContext(
    data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  return (w, h, px)
}

/// Mean and largest per-channel difference of the two sRGB renderings.
func diff(_ a: String, _ b: String) -> (mean: Double, max: Int) {
  let (x, y) = (srgb(a), srgb(b))
  precondition((x.0, x.1) == (y.0, y.1), "\(a) vs \(b): size")
  var (total, top) = (0, 0)
  for i in stride(from: 0, to: x.2.count, by: 4) {
    for c in 0..<3 {
      let d = abs(Int(x.2[i + c]) - Int(y.2[i + c]))
      total += d
      top = max(top, d)
    }
  }
  return (Double(total) / Double(x.2.count / 4 * 3), top)
}

func privateFields(_ name: String) -> [String] {
  let p = CGImageSourceCopyPropertiesAtIndex(source(name), 0, nil) as! [CFString: Any]
  var found: [String] = []
  if p[kCGImagePropertyGPSDictionary] != nil { found.append("GPS") }
  if let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any],
     exif[kCGImagePropertyExifDateTimeOriginal] != nil || exif[kCGImagePropertyExifLensModel] != nil {
    found.append("EXIF")
  }
  if let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
     tiff[kCGImagePropertyTIFFMake] != nil || tiff[kCGImagePropertyTIFFModel] != nil {
    found.append("camera")
  }
  return found
}

func profileName(_ name: String) -> String {
  let img = CGImageSourceCreateImageAtIndex(source(name), 0, nil)!
  return (img.colorSpace?.name as String?) ?? (img.colorSpace?.copyICCData() != nil ? "ICC" : "none")
}

var failed = false
func report(_ src: String, _ out: String) -> (mean: Double, max: Int) {
  let d = diff(src, out)
  let leaks = privateFields(out)
  print("\(src) → \(out): sRGB diff mean \(String(format: "%.2f", d.mean)) max \(d.max), "
    + "profile \(profileName(out)), private fields in source \(privateFields(src)), in output \(leaks)")
  if !leaks.isEmpty { failed = true }
  return d
}
for (src, out) in [("icc_p3.png", "icc_p3-to.webp"), ("cicp_only.png", "cicp_only-to.webp")] {
  if report(src, out).max > 4 { failed = true }
}
let control = diff("icc_p3.png", "control_no_profile.webp")
print("lossless control (profile dropped): mean \(String(format: "%.2f", control.mean)) max \(control.max)")
if control.max < 12 { failed = true; print("control too close: the comparison cannot tell") }

let jpeg = report("exif_p3.jpg", "exif_p3-to.png")
let jpegControl = diff("exif_p3.jpg", "control_jpeg_no_profile.png")
print("JPEG control (profile dropped): mean \(String(format: "%.2f", jpegControl.mean)) max \(jpegControl.max)")
if jpeg.mean * 2 > jpegControl.mean { failed = true }
print(failed ? "FAIL" : "Colour kept, private metadata gone")
exit(failed ? 1 : 0)
