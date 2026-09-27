import Foundation
import ImageIO
import CoreGraphics

// Independent check of the public regression inputs, not of DarkLib's output.
// Run on macOS 15+ with the fixture directory as the sole argument.
guard CommandLine.arguments.count == 2 else { fatalError("Pass fixture directory") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
func source(_ name: String) -> CGImageSource {
  guard let result = CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, nil) else {
    fatalError("ImageIO could not open \(name)")
  }
  return result
}
let pqSource = source("seine_hdr_rec2020.avif")
guard let pq = CGImageSourceCreateImageAtIndex(pqSource, 0, nil),
      let space = pq.colorSpace,
      CGColorSpaceUsesITUR_2100TF(space) else {
  fatalError("Independent reader did not identify direct HDR")
}
print("PQ: decoded \(pq.width)x\(pq.height), depth=\(pq.bitsPerComponent), HDR transfer=true")
let gmSource = source("seine_sdr_gainmap_srgb.avif")
guard CGImageSourceCreateImageAtIndex(gmSource, 0, nil) != nil else {
  fatalError("Independent reader could not decode gain-map base")
}
if #available(macOS 15.0, *) {
  guard CGImageSourceCopyAuxiliaryDataInfoAtIndex(gmSource, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil else {
    fatalError("Independent reader did not find ISO gain map")
  }
  print("Gain map: base decodes; ISO auxiliary data found")
} else {
  fatalError("ISO gain-map inspection requires macOS 15+")
}
