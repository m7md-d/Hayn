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
