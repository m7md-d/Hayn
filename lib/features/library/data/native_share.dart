import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativeShare — hands files to the OS share sheet (iOS UIActivityViewController)
// via a platform channel. This is a user-initiated OS handoff, NOT a network
// call by the app (same spirit as url_launcher for maps) — nothing leaves the
// device unless the user picks a destination. No third-party package. Returns
// quietly on any failure or where there's no native impl (Android/desktop).
// ─────────────────────────────────────────────────────────────────────────────

abstract final class NativeShare {
  static const MethodChannel channel = MethodChannel('hayn/share');

  static Future<void> shareFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await channel.invokeMethod<void>('shareFiles', {'paths': paths});
    } catch (_) {
      // No handler / dismissed — nothing to do.
    }
  }
}
