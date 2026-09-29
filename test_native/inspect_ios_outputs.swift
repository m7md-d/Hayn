import Foundation
import ImageIO
import CoreGraphics

// Independent host reader for the synthetic files exported by the iOS suite.
// Usage: swift inspect_ios_outputs.swift <build/ios-preservation/timestamp>
guard CommandLine.arguments.count == 2 else { fatalError("Pass artifact directory") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
func decode(_ name: String) -> (CGImage, [UInt8]) {
  guard let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(data: nil, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Cannot decode \(name)")
  }
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  let pixels = Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self),
                                      count: image.width * image.height * 4))
  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
  let i = (image.height / 2 * image.width + image.width / 2) * 4
  print("\(name): \(image.width)x\(image.height) depth=\(image.bitsPerComponent) alpha=\(image.alphaInfo.rawValue) center=\(Array(pixels[i..<i+4]))")
  if name.hasPrefix("jpeg-") { print("  properties: \(props)") }
  precondition(image.width == 16 && image.height == 12)
  return (image, pixels)
}
let (_, jpegBefore) = decode("jpeg-encoded.jpg")
let (_, jpegAfter) = decode("jpeg-photos.jpg")
precondition(jpegBefore == jpegAfter, "JPEG rendering changed after Photos")
for name in ["avif-encoded.avif", "avif-imageio.png"] {
  let (_, pixels) = decode(name)
  let i = (6 * 16 + 8) * 4
  for (channel, value) in [80, 120, 160, 255].enumerated() {
    precondition(abs(Int(pixels[i + channel]) - value) <= 8, "Unexpected AVIF pixel")
  }
}
print("Independent ImageIO: JPEG rendering unchanged; AVIF SDR pixels and opacity match")

// HDR policy outputs (2026-09-28), present in runs from that date onwards.
func hdrFacts(_ name: String) -> (transfer: Bool, gainMap: Bool)? {
  let url = directory.appendingPathComponent(name)
  guard FileManager.default.fileExists(atPath: url.path) else { return nil }
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot decode \(name)")
  }
  let transfer = image.colorSpace.map(CGColorSpaceUsesITUR_2100TF) ?? false
  var gainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
    source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
  if #available(macOS 15.0, *) {
    gainMap = gainMap || CGImageSourceCopyAuxiliaryDataInfoAtIndex(
      source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil
  }
  print("\(name): \(image.width)x\(image.height) hdrTransfer=\(transfer) gainMap=\(gainMap)")
  return (transfer, gainMap)
}
if let gm = hdrFacts("gainmap-to-webp.webp") {
  precondition(!gm.transfer && !gm.gainMap, "WebP carries no gain map")
  let avif = hdrFacts("gainmap-to-avif.avif")!
  precondition(!avif.transfer && avif.gainMap, "AVIF keeps the gain map (IMG-10)")
  // Present only where the platform produced an SDR rendition of PQ.
  if let pq = hdrFacts("pq-to-webp.webp") {
    precondition(!pq.transfer && !pq.gainMap, "PQ output must be SDR")
  }
  print("Independent ImageIO: WebP/PQ outputs are SDR; AVIF keeps its gain map")
}
