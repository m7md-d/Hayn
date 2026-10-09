import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// M-07 step 5: how an image's region can be read through Apple's frameworks
// with bounded memory, for the iOS region reader the viewer lacks (PERF-03).
// One way per process, so its peak memory is its own: run it under
// `/usr/bin/time -l` and read "peak memory footprint".
//
//   imageio_region_study <file> full            decode everything, draw it
//   imageio_region_study <file> crop            CGImage.cropping(to:) of a
//                                               1024² square at the centre
//   imageio_region_study <file> subsample <n>   kCGImageSourceSubsampleFactor
//   imageio_region_study <file> thumb <edge>    CreateThumbnailAtIndex
//   imageio_region_study <file> ci-crop         CIImage cropped, rendered
//   imageio_region_study <file> crop-loop <n>   n crops across the image from
//                                               one CGImage (what a pan does)
//   imageio_region_study <in> heic <out>        Apple's HEIC encoder (q 0.9)
//
// Build: swiftc -O test_native/imageio_region_study.swift -o <scratch>/study
let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("Pass a file and a way") }
let url = URL(fileURLWithPath: args[1]) as CFURL
let way = args[2]
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func footprintMB() -> Double {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
  _ = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  return Double(info.phys_footprint) / 1_048_576
}

/// Draws [image] into an 8-bit sRGB context of its size: forces the decode
/// and returns one pixel so nothing is optimised away.
func render(_ image: CGImage) -> UInt8 {
  let ctx = CGContext(
    data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
    bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  return ctx.data!.load(fromByteOffset: (image.height / 2 * ctx.bytesPerRow) + image.width / 2 * 4, as: UInt8.self)
}

let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
let source = CGImageSourceCreateWithURL(url, nil)!
let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
let (w, h) = (props[kCGImagePropertyPixelWidth] as! Int, props[kCGImagePropertyPixelHeight] as! Int)
let centre = CGRect(x: w / 2 - 512, y: h / 2 - 512, width: 1024, height: 1024)
let start = Date()
var out = ""

switch way {
case "full":
  let image = CGImageSourceCreateImageAtIndex(source, 0, noCache)!
  _ = render(image)
  out = "\(image.width)x\(image.height)"
case "crop":
  let image = CGImageSourceCreateImageAtIndex(source, 0, noCache)!
  let crop = image.cropping(to: centre)!
  _ = render(crop)
  out = "\(crop.width)x\(crop.height) of \(w)x\(h)"
case "crop-loop":
  let n = Int(args[3])!
  let image = CGImageSourceCreateImageAtIndex(source, 0, noCache)!
  var times: [Int] = []
  for i in 0..<n {
    let t = Date()
    let x = (w - 1024) * i / max(n - 1, 1), y = (h - 1024) * i / max(n - 1, 1)
    _ = render(image.cropping(to: CGRect(x: x, y: y, width: 1024, height: 1024))!)
    times.append(Int(Date().timeIntervalSince(t) * 1000))
  }
  out = "\(n) crops, ms each: \(times)"
case "subsample":
  let n = Int(args[3])!
  let options = [kCGImageSourceShouldCache: false, kCGImageSourceSubsampleFactor: n] as CFDictionary
  let image = CGImageSourceCreateImageAtIndex(source, 0, options)!
  _ = render(image)
  out = "factor \(n): \(image.width)x\(image.height)"
case "thumb":
  let edge = Int(args[3])!
  let options = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceThumbnailMaxPixelSize: edge,
    kCGImageSourceShouldCacheImmediately: true,
  ] as CFDictionary
  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)!
  _ = render(image)
  out = "max \(edge): \(image.width)x\(image.height)"
case "ci-crop":
  let ci = CIImage(contentsOf: URL(fileURLWithPath: args[1]))!
  // Core Image's origin is bottom-left; the centre square is symmetric.
  let context = CIContext(options: [.workingColorSpace: srgb, .cacheIntermediates: false])
  let image = context.createCGImage(ci, from: centre)!
  _ = render(image)
  out = "\(image.width)x\(image.height) of \(w)x\(h)"
case "heic":
  let image = CGImageSourceCreateImageAtIndex(source, 0, noCache)!
  let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: args[3]) as CFURL, UTType.heic.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
  precondition(CGImageDestinationFinalize(dest))
  out = "wrote \(args[3])"
default:
  fatalError("Unknown way \(way)")
}
let ms = Int(Date().timeIntervalSince(start) * 1000)
print("\(way) \(out): \(ms) ms, footprint now \(String(format: "%.0f", footprintMB())) MB")
