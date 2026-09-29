import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Writes the fixtures libavif's corpus lacks with Apple's own encoders
// (ImageIO on macOS), from libavif images, so they come from a writer that is
// independent of DarkLib. Output: native/darklib/tests/fixtures/apple_*.
// Usage: swift test_native/make_platform_fixtures.swift native/darklib/tests/fixtures
guard CommandLine.arguments.count == 2 else { fatalError("Pass the fixtures directory") }
let dir = URL(fileURLWithPath: CommandLine.arguments[1])

func source(_ name: String, hdr: Bool = false) -> CGImage {
  let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil)!
  let options = hdr ? [kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR] as CFDictionary : nil
  return CGImageSourceCreateImageAtIndex(src, 0, options)!
}

/// Redraws [image] into [space] at 16 bits per channel (float for HDR).
func redraw(_ image: CGImage, _ space: CFString, float: Bool = false, alpha: Bool = false) -> CGImage {
  let cs = CGColorSpace(name: space)!
  var info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
  info |= CGBitmapInfo.byteOrder16Little.rawValue
  if float { info |= CGBitmapInfo.floatComponents.rawValue }
  let ctx = CGContext(
    data: nil, width: image.width, height: image.height, bitsPerComponent: 16,
    bytesPerRow: 0, space: cs, bitmapInfo: info)!
  ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  return ctx.makeImage()!
}

func write(_ image: CGImage, _ name: String, _ type: UTType, _ props: [CFString: Any] = [:]) {
  let url = dir.appendingPathComponent(name)
  let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, image, props as CFDictionary)
  precondition(CGImageDestinationFinalize(dest), "\(name): write failed")
  print("wrote \(name)")
}

// 10-bit SDR HEIC (Display P3) from the SDR base of the gain-map photo.
write(redraw(source("seine_sdr_gainmap_srgb.avif"), CGColorSpace.displayP3),
      "apple_heic_10bit_p3.heic", .heic, [kCGImageDestinationLossyCompressionQuality: 0.9])
// HLG HEIC from the PQ photo, converted by ImageIO/CoreGraphics.
write(redraw(source("seine_hdr_rec2020.avif", hdr: true), CGColorSpace.itur_2100_HLG, float: true),
      "apple_heic_hlg.heic", .heic, [kCGImageDestinationLossyCompressionQuality: 0.9])
// Transparent HEIC that tells a read alpha from an ignored one: (80,120,160)
// at alpha 64 everywhere (over white ≈ (211,221,231)), an opaque black square
// in the middle. Synthetic, so no licence applies.
func translucent() -> CGImage {
  let ctx = CGContext(
    data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.setFillColor(red: 80 / 255, green: 120 / 255, blue: 160 / 255, alpha: 64 / 255)
  ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
  ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
  ctx.fill(CGRect(x: 24, y: 16, width: 16, height: 16))
  return ctx.makeImage()!
}
write(translucent(), "apple_heic_alpha.heic", .heic, [kCGImageDestinationLossyCompressionQuality: 0.95])
// PNG with a Display P3 ICC profile, from Apple's P3 gain-map JPEG base.
// ImageIO also writes cICP; ICC-only P3 is covered by apple_gainmap_*.jpg.
write(source("apple_gainmap_new.jpg"), "apple_png_p3_icc.png", .png)
