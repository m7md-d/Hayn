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
