import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativeSurgical — bridge to the Android in-place MediaStore overwrite
// (hayn/surgical). The safe-transaction service calls this ONLY after it has
// verified the candidate and written a byte-for-byte backup, so a non-ok result
// is always recoverable. On scoped storage the platform shows a one-time write
// consent dialog; "cancelled" means the user declined it.
// ─────────────────────────────────────────────────────────────────────────────

enum SurgicalOverwriteStatus { ok, cancelled, failed }

abstract final class NativeSurgical {
  static const MethodChannel _channel = MethodChannel('hayn/surgical');

  /// Overwrite the original (Android MediaStore [id]) with [bytes] in place,
  /// keeping the same id/bucket; updates MIME + display name when the format
  /// changed. iOS / no native handler → [SurgicalOverwriteStatus.failed].
  /// Never throws.
  static Future<SurgicalOverwriteStatus> overwrite({
    required String id,
    required Uint8List bytes,
    String? mime,
    String? name,
  }) async {
    try {
      final status = await _channel.invokeMethod<String>('overwrite', {
        'id': id,
        'bytes': bytes,
        'mime': mime,
        'name': name,
      });
      return switch (status) {
        'ok' => SurgicalOverwriteStatus.ok,
        'cancelled' => SurgicalOverwriteStatus.cancelled,
        _ => SurgicalOverwriteStatus.failed,
      };
    } catch (_) {
      return SurgicalOverwriteStatus.failed;
    }
  }
}
