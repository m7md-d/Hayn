import AVFoundation
import CoreMedia
import Flutter
import ImageIO
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// The topmost presented view controller of the key window — where a share
  /// sheet must be presented from.
  static func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?.rootViewController
    var top = root
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Cheap byte-size lookup for the media index. The Dart side
    // (MediaSizeChannel) treats any id we don't return as "fall back to the
    // slow path", so a failure here only costs speed, never correctness.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaynMediaSize") {
      let channel = FlutterMethodChannel(
        name: "hayn/media_size",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "getSizes" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let ids = (call.arguments as? [String: Any])?["ids"] as? [String] ?? []
        // PhotoKit lookups off the platform thread; reply back on main.
        DispatchQueue.global(qos: .userInitiated).async {
          let sizes = MediaSizeResolver.resolve(ids)
          DispatchQueue.main.async { result(sizes) }
        }
      }
    }

    // ImageIO image channel:
    //   • stripLossless: drop EXIF/GPS from HEIC/AVIF WITHOUT re-encoding
    //     (CGImageDestinationAddImageFromSource copies the coded image as-is).
    //   • encodeImage:   compress to HEIC/JPEG via ImageIO — no spurious alpha
    //     channel (so no "AlphaLast" warning) and carries the source's camera
    //     metadata when asked. Both return nil on any failure → Dart falls back.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaynMetadata") {
      let channel = FlutterMethodChannel(
        name: "hayn/metadata",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "stripLossless":
          guard let typed = args?["bytes"] as? FlutterStandardTypedData else {
            result(nil)
            return
          }
          let data = typed.data
          DispatchQueue.global(qos: .userInitiated).async {
            let stripped = MetadataStripper.strip(data)
            DispatchQueue.main.async {
              result(stripped.map { FlutterStandardTypedData(bytes: $0) })
            }
          }
        case "encodeImage":
          guard let typed = args?["bytes"] as? FlutterStandardTypedData,
                let format = args?["format"] as? String else {
            result(nil)
            return
          }
          let quality = (args?["quality"] as? NSNumber)?.intValue ?? 80
          let keepMetadata = (args?["keepMetadata"] as? Bool) ?? true
          // Time is independent of keepMetadata (its own toggle).
          let keepTime = (args?["keepOriginalTime"] as? Bool) ?? true
          // 0 = match the source's depth; 8 = re-encode the base at 8-bit
          // (colour precision only — HDR is governed separately).
          let bitDepth = (args?["bitDepth"] as? NSNumber)?.intValue ?? 0
          let data = typed.data
          DispatchQueue.global(qos: .userInitiated).async {
            let out = ImageEncoderNative.encode(
              data, format: format, quality: quality,
              keepMetadata: keepMetadata, keepOriginalTime: keepTime,
              targetDepth: bitDepth)
            DispatchQueue.main.async {
              result(out.map { FlutterStandardTypedData(bytes: $0) })
            }
          }
        case "probeImage":
          guard let typed = args?["bytes"] as? FlutterStandardTypedData else {
            result(nil)
            return
          }
          let data = typed.data
          DispatchQueue.global(qos: .userInitiated).async {
            let info = ImageProbeNative.probe(data)
            DispatchQueue.main.async { result(info) }
          }
        case "bakeUpright":
          guard let typed = args?["bytes"] as? FlutterStandardTypedData else {
            result(nil)
            return
          }
          let keepMeta = (args?["keepMetadata"] as? Bool) ?? true
          let keepTime = (args?["keepOriginalTime"] as? Bool) ?? true
          let data = typed.data
          DispatchQueue.global(qos: .userInitiated).async {
            let out = ImageBaker.bakeUprightPng(
              data, keepMetadata: keepMeta, keepOriginalTime: keepTime)
            DispatchQueue.main.async {
              result(out.map { FlutterStandardTypedData(bytes: $0) })
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // OS share sheet (UIActivityViewController). A user-initiated handoff — the
    // app makes no network call; nothing leaves the device unless the user picks
    // a destination. Kept as a tiny native channel so we add no third-party
    // dependency to a deliberately offline app.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaynShare") {
      let channel = FlutterMethodChannel(
        name: "hayn/share",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "shareFiles" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let paths = (call.arguments as? [String: Any])?["paths"] as? [String] ?? []
        let urls = paths.map { URL(fileURLWithPath: $0) }
        DispatchQueue.main.async {
          guard !urls.isEmpty, let top = AppDelegate.topViewController() else {
            result(nil)
            return
          }
          let vc = UIActivityViewController(
            activityItems: urls, applicationActivities: nil)
          // iPad requires a popover anchor or it crashes.
          if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(
              x: top.view.bounds.midX, y: top.view.bounds.midY,
              width: 0, height: 0)
            pop.permittedArrowDirections = []
          }
          top.present(vc, animated: true)
          result(nil)
        }
      }
    }

    // Read-only technical probe for a video asset (codec / fps / frame count),
    // which photo_manager doesn't expose. Offline only — never pulls from
    // iCloud. Returns nil for non-videos or anything not locally available.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaynVideoProbe") {
      let channel = FlutterMethodChannel(
        name: "hayn/video",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "probe" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let id = (call.arguments as? [String: Any])?["id"] as? String ?? ""
        DispatchQueue.global(qos: .userInitiated).async {
          let info = VideoProbe.probe(id)
          DispatchQueue.main.async { result(info) }
        }
      }
    }
  }
}

/// Reads a video's codec, frame rate and frame count via AVFoundation.
private enum VideoProbe {
  static func probe(_ id: String) -> [String: Any]? {
    if id.isEmpty { return nil }
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
    guard let asset = assets.firstObject, asset.mediaType == .video else {
      return nil
    }

    let options = PHVideoRequestOptions()
    options.isNetworkAccessAllowed = false // offline only (no iCloud pull)
    options.deliveryMode = .fastFormat

    let semaphore = DispatchSemaphore(value: 0)
    var out: [String: Any]?
    PHImageManager.default().requestAVAsset(forVideo: asset, options: options) {
      avAsset, _, _ in
      defer { semaphore.signal() }
      guard let track = avAsset?.tracks(withMediaType: .video).first else { return }
      let fps = Double(track.nominalFrameRate)
      let seconds = track.timeRange.duration.seconds
      let frames = (fps > 0 && seconds.isFinite) ? Int((fps * seconds).rounded()) : 0
      var codec = ""
      if let desc = track.formatDescriptions.first {
        let subType = CMFormatDescriptionGetMediaSubType(desc as! CMFormatDescription)
        codec = VideoProbe.fourCC(subType)
      }
      out = ["codec": codec, "fps": fps, "frames": frames]
    }
    // Bounded wait so a stuck request can't hang the worker forever.
    _ = semaphore.wait(timeout: .now() + 8)
    return out
  }

  /// Map a CoreMedia FourCC to a friendly codec name.
  static func fourCC(_ code: FourCharCode) -> String {
    let chars = [
      Character(UnicodeScalar((code >> 24) & 0xFF)!),
      Character(UnicodeScalar((code >> 16) & 0xFF)!),
      Character(UnicodeScalar((code >> 8) & 0xFF)!),
      Character(UnicodeScalar(code & 0xFF)!),
    ]
    let raw = String(chars).trimmingCharacters(in: .whitespaces)
    switch raw.lowercased() {
    case "hvc1", "hev1": return "HEVC (H.265)"
    case "avc1", "avc3": return "H.264"
    case "av01": return "AV1"
    case "vp09": return "VP9"
    case "mp4v": return "MPEG-4"
    case "jpeg": return "Motion JPEG"
    default: return raw
    }
  }
}

/// Strips EXIF/GPS/IPTC/TIFF metadata from an image while copying the coded
/// image data losslessly (no re-encode) and PRESERVING display orientation.
/// Works for any container ImageIO can read/write (HEIC, AVIF on iOS 16+,
/// JPEG, PNG…). Returns nil if the image can't be read or written.
private enum MetadataStripper {
  static func strip(_ data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      NSLog("hayn/metadata: CGImageSourceCreateWithData failed")
      return nil
    }
    guard let uti = CGImageSourceGetType(source) else {
      NSLog("hayn/metadata: CGImageSourceGetType returned nil")
      return nil
    }
    let count = CGImageSourceGetCount(source)
    guard count > 0 else {
      NSLog("hayn/metadata: image count is 0")
      return nil
    }

    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
      out as CFMutableData, uti, count, nil
    ) else {
      // Most likely an unwritable container on this OS (e.g. AVIF write).
      NSLog("hayn/metadata: CGImageDestinationCreateWithData failed for \(uti)")
      return nil
    }

    // Remove the privacy-bearing metadata; leave orientation + the rest of the
    // image untouched. (Keeping it minimal is more robust across formats than
    // nulling every dictionary.)
    let stripProps: [CFString: Any] = [
      kCGImagePropertyExifDictionary: kCFNull as Any,
      kCGImagePropertyGPSDictionary: kCFNull as Any,
    ]
    for i in 0..<count {
      CGImageDestinationAddImageFromSource(
        dest, source, i, stripProps as CFDictionary)
    }

    guard CGImageDestinationFinalize(dest) else {
      NSLog("hayn/metadata: CGImageDestinationFinalize failed for \(uti)")
      return nil
    }
    let result = out as Data
    // Refuse a wildly larger output (a real re-encode) so strip can never
    // balloon a file; a lossless copy is ≤ the original.
    if result.isEmpty || result.count > data.count {
      NSLog("hayn/metadata: output \(result.count) vs original \(data.count) — refused")
      return nil
    }
    NSLog("hayn/metadata: stripped \(data.count) → \(result.count) (\(uti))")
    return result
  }
}

/// Compresses image data to HEIC or JPEG using ImageIO directly. Decoding
/// straight to the source's CGImage means an opaque photo stays opaque (no
/// spurious alpha → no "AlphaLast" warning, no size bloat) and a 10-bit photo
/// stays 10-bit. The source's colour profile rides along inside the CGImage;
/// display orientation is always kept. Metadata is handled by COPYING the whole
/// source property set and then removing only what the toggles say to drop, so
/// we always know exactly what survives. The HDR gain map is tied to
/// keepMetadata (Photos needs the maker-note headroom we only keep then to
/// render HDR), and is INDEPENDENT of bit depth.
///
/// [keepOriginalTime]: when false, the in-file capture date is removed so a
/// re-dated copy isn't stamped with the original time (time is its own toggle).
/// [targetDepth]: 0 = match the source; 8 = re-encode the base at 8-bit (colour
/// precision only — does NOT drop HDR). Higher-than-source is treated as match.
///
/// Returns nil if the source can't be decoded or the format isn't writable on
/// this OS (e.g. a device with no HEVC encoder) — the Dart side then falls back.
private enum ImageEncoderNative {
  static func encode(
    _ data: Data, format: String, quality: Int, keepMetadata: Bool,
    keepOriginalTime: Bool, targetDepth: Int
  ) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      NSLog("hayn/encode: source create failed")
      return nil
    }
    guard CGImageSourceGetCount(source) > 0,
          var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      NSLog("hayn/encode: decode failed")
      return nil
    }

    let uti: CFString
    switch format.lowercased() {
    case "heic": uti = "public.heic" as CFString
    case "jpeg", "jpg": uti = "public.jpeg" as CFString
    case "png": uti = "public.png" as CFString
    default:
      NSLog("hayn/encode: unsupported format \(format)")
      return nil
    }

    // Re-encode the base at 8-bit when asked (a 10-bit source → 8-bit). This is
    // COLOUR PRECISION only; the HDR gain map below is independent and is kept
    // regardless, so an 8-bit photo can still be HDR.
    let force8Bit = targetDepth == 8 && image.bitsPerComponent > 8
    if force8Bit, let flat = Self.redraw8Bit(image) { image = flat }

    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
      out as CFMutableData, uti, 1, nil
    ) else {
      // Format not writable here (old device w/o HEVC) → caller falls back.
      NSLog("hayn/encode: destination create failed for \(uti)")
      return nil
    }

    let q = max(0.0, min(1.0, Double(quality) / 100.0))
    let srcProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      as? [CFString: Any]
    let props = Self.buildProperties(
      srcProps, quality: q,
      keepMetadata: keepMetadata, keepOriginalTime: keepOriginalTime)
    CGImageDestinationAddImage(dest, image, props as CFDictionary)

    // The HDR gain map (Apple stores HDR as a base image + this auxiliary) is
    // tied to keepMetadata: Photos needs the maker-note HDR headroom — which we
    // only keep then — to actually RENDER HDR. Copying the gain map without that
    // metadata would make the file CLAIM HDR yet look flat, so we keep them
    // together. Independent of bit depth.
    if keepMetadata {
      var auxTypes: [CFString] = []
      if #available(iOS 14.1, *) {
        auxTypes.append(kCGImageAuxiliaryDataTypeHDRGainMap)
      }
      if #available(iOS 18.0, *) {
        auxTypes.append(kCGImageAuxiliaryDataTypeISOGainMap)
      }
      for auxType in auxTypes {
        if let aux = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
          source, 0, auxType) {
          CGImageDestinationAddAuxiliaryDataInfo(dest, auxType, aux)
        }
      }
    }

    guard CGImageDestinationFinalize(dest) else {
      NSLog("hayn/encode: finalize failed for \(uti)")
      return nil
    }
    let result = out as Data
    if result.isEmpty { return nil }
    NSLog("hayn/encode: \(format) q\(quality) keepMeta:\(keepMetadata) "
      + "keepTime:\(keepOriginalTime) 8bit:\(force8Bit) "
      + "\(data.count) → \(result.count)")
    return result
  }

  /// Build destination properties by COPYING the whole source set and then
  /// removing only what the toggles say to drop — so we always know exactly what
  /// survives (no blind "keep" call). Time is governed by keepOriginalTime,
  /// independent of keepMetadata.
  static func buildProperties(
    _ srcProps: [CFString: Any]?, quality: Double,
    keepMetadata: Bool, keepOriginalTime: Bool
  ) -> [CFString: Any] {
    var props: [CFString: Any] =
      [kCGImageDestinationLossyCompressionQuality: quality]
    guard let src = srcProps else { return props }

    if keepMetadata {
      for (k, v) in src { props[k] = v } // copy everything…
      if !keepOriginalTime { Self.removeDateTags(&props) } // …then drop the date
    } else {
      // Privacy: keep ONLY display orientation. Colour fidelity rides inside the
      // CGImage, so dropping the profile name here doesn't shift colour.
      if let o = src[kCGImagePropertyOrientation] {
        props[kCGImagePropertyOrientation] = o
      }
      if !keepOriginalTime { Self.removeDateTags(&props) }
    }
    return props
  }

  /// Strip the in-file capture date (EXIF DateTimeOriginal/Digitized + TIFF
  /// DateTime) so a re-dated copy isn't stamped with the original moment.
  static func removeDateTags(_ props: inout [CFString: Any]) {
    if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
      exif.removeValue(forKey: kCGImagePropertyExifDateTimeOriginal)
      exif.removeValue(forKey: kCGImagePropertyExifDateTimeDigitized)
      props[kCGImagePropertyExifDictionary] = exif
    }
    if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
      tiff.removeValue(forKey: kCGImagePropertyTIFFDateTime)
      props[kCGImagePropertyTIFFDictionary] = tiff
    }
  }

  /// Redraw a (possibly 10/16-bit) image into a standard 8-bit RGB bitmap,
  /// preserving an alpha channel if the source has one (so an SDR PNG keeps its
  /// transparency).
  static func redraw8Bit(_ image: CGImage) -> CGImage? {
    let w = image.width, h = image.height
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) ?? image.colorSpace
    else { return nil }
    let a = image.alphaInfo
    let hasAlpha = !(a == .none || a == .noneSkipFirst || a == .noneSkipLast)
    let bitmap = hasAlpha
      ? CGImageAlphaInfo.premultipliedLast.rawValue
      : CGImageAlphaInfo.noneSkipLast.rawValue
    guard let ctx = CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8,
      bytesPerRow: 0, space: space, bitmapInfo: bitmap) else {
      return nil
    }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
  }
}

/// Bakes an image's EXIF orientation INTO the pixels and writes a LOSSLESS PNG
/// carrying the corrected metadata (orientation = 1; capture date kept/stripped
/// per the toggle). This is the fix for AVIF: flutter_avif mishandles
/// orientation/date, so instead of trusting it we hand it an already-upright PNG
/// whose embedded EXIF is exactly what we want — it then just copies that EXIF
/// in. PNG is lossless, so the only lossy step is the AVIF encode itself.
private enum ImageBaker {
  static func bakeUprightPng(
    _ data: Data, keepMetadata: Bool, keepOriginalTime: Bool
  ) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetCount(source) > 0,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      NSLog("hayn/bake: decode failed")
      return nil
    }
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      as? [CFString: Any]
    let orientation =
      (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let upright = orientation == 1
      ? image
      : (Self.bake(image, exifOrientation: orientation) ?? image)

    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
      out as CFMutableData, "public.png" as CFString, 1, nil
    ) else {
      NSLog("hayn/bake: png destination failed")
      return nil
    }
    var destProps: [CFString: Any] = [:]
    if keepMetadata, let p = props {
      for (k, v) in p { destProps[k] = v }
      if !keepOriginalTime { ImageEncoderNative.removeDateTags(&destProps) }
    }
    // Pixels are physically upright now → every orientation field must read 1.
    destProps[kCGImagePropertyOrientation] = 1
    if var tiff = destProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
      tiff[kCGImagePropertyTIFFOrientation] = 1
      destProps[kCGImagePropertyTIFFDictionary] = tiff
    }
    CGImageDestinationAddImage(dest, upright, destProps as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      NSLog("hayn/bake: finalize failed")
      return nil
    }
    let result = out as Data
    if result.isEmpty { return nil }
    NSLog("hayn/bake: ori\(orientation) meta:\(keepMetadata) "
      + "keepTime:\(keepOriginalTime) \(data.count) → \(result.count)")
    return result
  }

  /// Redraw applying the EXIF orientation so the output pixels are upright.
  /// UIImage knows the per-orientation transform, so drawing it bakes it in.
  static func bake(_ image: CGImage, exifOrientation o: Int) -> CGImage? {
    let ui = UIImage(cgImage: image, scale: 1, orientation: Self.uiOrientation(o))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(size: ui.size, format: format)
    let baked = renderer.image { _ in
      ui.draw(in: CGRect(origin: .zero, size: ui.size))
    }
    return baked.cgImage
  }

  static func uiOrientation(_ o: Int) -> UIImage.Orientation {
    switch o {
    case 2: return .upMirrored
    case 3: return .down
    case 4: return .downMirrored
    case 5: return .leftMirrored
    case 6: return .right
    case 7: return .rightMirrored
    case 8: return .left
    default: return .up
    }
  }
}

/// Read-only inspection of an image's real bit depth, alpha-channel presence and
/// HDR status — straight from ImageIO, so it's accurate for HEIC (which
/// package:image can't even decode). We report what the file ACTUALLY contains,
/// never a guess from the container type.
private enum ImageProbeNative {
  static func probe(_ data: Data) -> [String: Any]? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetCount(source) > 0,
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any] else {
      NSLog("hayn/probe: read failed")
      return nil
    }
    let depth = (props[kCGImagePropertyDepth] as? NSNumber)?.intValue ?? 8
    let hasAlpha = (props[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue
      ?? false
    let colorModel = (props[kCGImagePropertyColorModel] as? String) ?? ""

    // HDR (dynamic range) is a gain map OR an HDR transfer function — NOT bit
    // depth. A 10-bit photo can be plain SDR, and an 8-bit photo can be HDR via
    // a gain map, so we never infer HDR from depth.
    var hasGainMap = false
    if #available(iOS 14.1, *) {
      hasGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
        source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
    }
    if !hasGainMap, #available(iOS 18.0, *) {
      hasGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
        source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil
    }
    var hdrTransfer = false
    if #available(iOS 14.0, *),
       let cs = CGImageSourceCreateImageAtIndex(source, 0, nil)?.colorSpace {
      hdrTransfer = CGColorSpaceUsesITUR_2100TF(cs)
    }
    let isHdr = hasGainMap || hdrTransfer
    return [
      "bitDepth": depth,
      "hasAlpha": hasAlpha,
      "isHdr": isHdr,
      "colorModel": colorModel,
    ]
  }
}

/// Resolves PhotoKit asset byte sizes WITHOUT exporting the file. There's no
/// public API for an asset's file size, but `PHAssetResource` exposes it via
/// the `fileSize` key (read with KVC) — orders of magnitude cheaper than
/// requesting the data just to measure its length. Kept inline in this file so
/// no extra source needs registering in the Xcode target.
private enum MediaSizeResolver {
  static func resolve(_ ids: [String]) -> [String: Int] {
    var out = [String: Int]()
    if ids.isEmpty { return out }

    // photo_manager asset ids on iOS are PHAsset localIdentifiers.
    let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
    fetched.enumerateObjects { asset, _, _ in
      let resources = PHAssetResource.assetResources(for: asset)
      let primary = resources.first {
        $0.type == .photo || $0.type == .video || $0.type == .audio
      } ?? resources.first

      guard let resource = primary,
            let value = resource.value(forKey: "fileSize") as? NSNumber else {
        return
      }
      let bytes = value.int64Value
      if bytes > 0 {
        out[asset.localIdentifier] = Int(bytes)
      }
    }
    return out
  }
}
