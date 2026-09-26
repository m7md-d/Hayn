// Re-encodes a PNG at a square size with CoreGraphics — the image steps
// Chrome can't do: dropping the alpha channel (App Store rejects an app icon
// that has one), high-quality downscaling for the legacy Android mipmaps, and
// clipping to iOS's own icon shape (SwiftUI's continuous corners) for the
// README.
//
// usage: swift png_tool.swift <in.png> <out.png> <size> <opaque|alpha|ios-mask>

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let args = CommandLine.arguments
let modes = ["opaque", "alpha", "ios-mask"]
guard args.count == 5, let size = Int(args[3]), modes.contains(args[4]) else {
  FileHandle.standardError.write("usage: png_tool <in> <out> <size> <opaque|alpha|ios-mask>\n".data(using: .utf8)!)
  exit(2)
}
let opaque = args[4] == "opaque"

guard
  let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
  let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)
else {
  FileHandle.standardError.write("cannot read \(args[1])\n".data(using: .utf8)!)
  exit(1)
}
context.interpolationQuality = .high
if args[4] == "ios-mask" {
  // Apple's icon mask: a continuous-curvature rounded square, radius 22.37%.
  let bounds = CGRect(x: 0, y: 0, width: size, height: size)
  let shape = RoundedRectangle(cornerRadius: CGFloat(size) * 0.2237, style: .continuous)
  context.addPath(shape.path(in: bounds).cgPath)
  context.clip()
}
context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

guard
  let output = context.makeImage(),
  let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
  FileHandle.standardError.write("cannot write \(args[2])\n".data(using: .utf8)!)
  exit(1)
}
CGImageDestinationAddImage(destination, output, nil)
guard CGImageDestinationFinalize(destination) else {
  FileHandle.standardError.write("cannot finalize \(args[2])\n".data(using: .utf8)!)
  exit(1)
}
