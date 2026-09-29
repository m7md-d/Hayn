import Foundation
import ImageIO
import CoreGraphics

// Independent semantic check for a kept gain map (IMG-10): ImageIO renders the
// source and our output as HDR in linear extended Display P3, and the two
// renditions must match (lossy re-encode tolerance) and exceed SDR white.
// Usage: swift compare_hdr_rendition.swift <source> <output>
guard CommandLine.arguments.count == 3 else { fatalError("Pass source and output") }
guard #available(macOS 14.0, *) else { fatalError("Needs macOS 14 ImageIO HDR decode") }

func hdrPixels(_ path: String) -> (w: Int, h: Int, px: [Float], headroom: Double) {
  let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
  let image = CGImageSourceCreateImageAtIndex(
    src, 0, [kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR] as CFDictionary)!
  let (w, h) = (image.width, image.height)
  let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
  let info = CGImageAlphaInfo.premultipliedLast.rawValue
    | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 32,
    bytesPerRow: w * 16, space: space, bitmapInfo: info)!
  ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
  let px = Array(UnsafeBufferPointer(
    start: ctx.data!.assumingMemoryBound(to: Float.self), count: w * h * 4))
  return (w, h, px, (props["Headroom"] as? NSNumber)?.doubleValue ?? 1)
}

let a = hdrPixels(CommandLine.arguments[1])
let b = hdrPixels(CommandLine.arguments[2])
precondition((a.w, a.h) == (b.w, b.h), "size differs")
var diff = 0.0, sumA = 0.0, peakA: Float = 0, peakB: Float = 0
for i in stride(from: 0, to: a.px.count, by: 4) {
  for c in 0..<3 {
    diff += Double(abs(a.px[i + c] - b.px[i + c]))
    sumA += Double(a.px[i + c])
    peakA = max(peakA, a.px[i + c])
    peakB = max(peakB, b.px[i + c])
  }
}
let n = Double(a.px.count / 4 * 3)
let relative = diff / sumA
print(String(format: "headroom %.3f / %.3f, peak %.3f / %.3f, mean %.4f, mean |Δ| %.4f (%.2f%%)",
  a.headroom, b.headroom, peakA, peakB, sumA / n, diff / n, relative * 100))
precondition(abs(a.headroom - b.headroom) < 0.01, "headroom changed")
precondition(peakA > 1.05 && peakB > 1.05, "HDR rendition does not exceed SDR white")
precondition(relative < 0.03, "HDR renditions differ by more than 3%")
print("Independent ImageIO: the kept gain map renders the same HDR image")
