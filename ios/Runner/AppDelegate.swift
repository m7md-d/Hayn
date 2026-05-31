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

    // Lossless metadata strip for HEIC/AVIF (which pure-Dart can't edit).
    // CGImageDestinationAddImageFromSource copies the coded image WITHOUT
    // re-encoding when the source and destination types match, so the pixels
    // are untouched; we only drop the metadata dictionaries. Returns nil on any
    // failure → the Dart side then skips the file (never degrades it).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaynMetadata") {
      let channel = FlutterMethodChannel(
        name: "hayn/metadata",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "stripLossless" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let args = call.arguments as? [String: Any],
              let typed = args["bytes"] as? FlutterStandardTypedData else {
          result(nil)
          return
        }
        let data = typed.data
        DispatchQueue.global(qos: .userInitiated).async {
          let stripped = MetadataStripper.strip(data)
          DispatchQueue.main.async {
            if let stripped = stripped {
              result(FlutterStandardTypedData(bytes: stripped))
            } else {
              result(nil)
            }
          }
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
