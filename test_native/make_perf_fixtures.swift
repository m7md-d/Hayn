import Foundation
import ImageIO
import UniformTypeIdentifiers

// Writes the HEIC and PNG copies of the 12 MP performance photo with Apple's
// encoders, so every source format holds the same pixels. WebP and AVIF
// sources are produced on the phone by the conversion test itself.
// Usage: swift test_native/make_perf_fixtures.swift build/perf-fixtures
guard CommandLine.arguments.count == 2 else { fatalError("Pass the fixtures directory") }
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let src = CGImageSourceCreateWithURL(dir.appendingPathComponent("photo-12mp.jpg") as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!

func write(_ name: String, _ type: UTType, _ props: [CFString: Any] = [:]) {
  let url = dir.appendingPathComponent(name)
  let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, image, props as CFDictionary)
  precondition(CGImageDestinationFinalize(dest), "\(name): write failed")
  print("wrote \(name)")
}

write("photo-12mp.heic", .heic, [kCGImageDestinationLossyCompressionQuality: 0.8])
write("photo-12mp.png", .png)

// The same photo with its left half at alpha 128: a transparent source for the
// JPEG flatten onto white (PERF-01), which opaque sources never reach.
func translucentLeftHalf(_ img: CGImage) -> CGImage {
  let (w, h) = (img.width, img.height)
  let ctx = CGContext(
    data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
    space: img.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  ctx.setBlendMode(.destinationIn)
  ctx.setFillColor(gray: 0, alpha: 0.5)
  ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
  return ctx.makeImage()!
}
let alphaURL = dir.appendingPathComponent("photo-12mp-alpha.png")
let alphaDest = CGImageDestinationCreateWithURL(alphaURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(alphaDest, translucentLeftHalf(image), nil)
precondition(CGImageDestinationFinalize(alphaDest), "photo-12mp-alpha.png: write failed")
print("wrote photo-12mp-alpha.png")
