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
  }
}

/// Strips EXIF/GPS/IPTC/TIFF metadata from an image while copying the coded
/// image data losslessly (no re-encode) and PRESERVING display orientation.
/// Works for any container ImageIO can read/write (HEIC, AVIF on iOS 16+,
/// JPEG, PNG…). Returns nil if the image can't be read or written.
private enum MetadataStripper {
  static func strip(_ data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let uti = CGImageSourceGetType(source) else { return nil }
    let count = CGImageSourceGetCount(source)
    guard count > 0 else { return nil }

    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
      out as CFMutableData, uti, count, nil
    ) else { return nil }

    for i in 0..<count {
      // Null out the metadata-bearing dictionaries; keep orientation so the
      // photo doesn't come out sideways.
      var props: [CFString: Any] = [
        kCGImagePropertyExifDictionary: kCFNull as Any,
        kCGImagePropertyGPSDictionary: kCFNull as Any,
        kCGImagePropertyIPTCDictionary: kCFNull as Any,
        kCGImagePropertyTIFFDictionary: kCFNull as Any,
        kCGImagePropertyExifAuxDictionary: kCFNull as Any,
      ]
      if let srcProps = CGImageSourceCopyPropertiesAtIndex(source, i, nil)
        as? [CFString: Any],
        let orientation = srcProps[kCGImagePropertyOrientation] {
        props[kCGImagePropertyOrientation] = orientation
      }
      CGImageDestinationAddImageFromSource(dest, source, i, props as CFDictionary)
    }

    guard CGImageDestinationFinalize(dest) else { return nil }
    let result = out as Data
    // Guard against an unexpected re-encode that BALLOONS the file — if the
    // "stripped" output is somehow bigger than the original, refuse it so the
    // Dart side skips rather than producing a larger copy.
    if result.isEmpty || result.count > data.count { return nil }
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
