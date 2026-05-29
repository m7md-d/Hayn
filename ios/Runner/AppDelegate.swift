import Flutter
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
