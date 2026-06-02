import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../data/index/media_index_database.dart';
import '../../image_ops/data/image_encoder.dart';
import '../../image_ops/data/output_name.dart';
import '../../settings/providers/preferences_providers.dart';
import '../../trash/data/trash_repository.dart';
import 'native_surgical.dart';
import 'surgical_verify.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SurgicalReplaceService — the SAFE TRANSACTION (CLAUDE.md §3 / F2). Order is
// mandatory and never reordered:
//   1. verify   — decode the candidate; dimensions match; strictly smaller.
//   2. backup   — write the original's bytes byte-for-byte to the trash dir,
//      + journal   AND insert a `pending` journal row — BEFORE any write.
//   3. overwrite— replace the original's bytes in place (same id/album/order).
//   4. commit   — flip the journal row to committed (now a restorable trash
//                 item) on success; roll back / restore on cancel / failure.
//
// The original is ALWAYS intact or restorable: nothing is overwritten until
// verify passes and the backup exists; a failed write triggers a restore from
// that backup; a crash leaves a `pending` row whose backup recovery keeps.
//
// Android-only for now (in-place MediaStore). iOS (Path B) plugs in as a second
// strategy later; here a non-Android call returns `failed` without side effects.
// ─────────────────────────────────────────────────────────────────────────────

enum SurgicalStatus { success, cancelled, verifyFailed, unsupported, failed }

class SurgicalOutcome {
  const SurgicalOutcome({
    required this.status,
    this.savedBytes = 0,
    this.verify,
  });

  final SurgicalStatus status;
  final int savedBytes;
  final SurgicalVerifyResult? verify;

  bool get isSuccess => status == SurgicalStatus.success;
}

class SurgicalReplaceService {
  SurgicalReplaceService(this._repo);
  final TrashRepository _repo;

  /// Replace [assetId] in place with the already-encoded [candidate].
  Future<SurgicalOutcome> replace({
    required String assetId,
    required EncodedImage candidate,
  }) async {
    if (!Platform.isAndroid) {
      return const SurgicalOutcome(status: SurgicalStatus.unsupported);
    }

    final entity = await AssetEntity.fromId(assetId);
    final originBytes = await entity?.originBytes;
    if (entity == null || originBytes == null || originBytes.isEmpty) {
      return const SurgicalOutcome(status: SurgicalStatus.failed);
    }

    final originalBytes = originBytes.length;
    final candidateBytes = candidate.bytes.length;

    // 1. VERIFY — decode the candidate (native, handles HEIF/AVIF) + gate.
    final (cw, ch) = await NativeSurgical.probeBounds(candidate.bytes);
    final verdict = SurgicalVerify.check(
      originalBytes: originalBytes,
      candidateBytes: candidateBytes,
      originalWidth: entity.width,
      originalHeight: entity.height,
      decodedWidth: cw,
      decodedHeight: ch,
    );
    if (!SurgicalVerify.passed(verdict)) {
      return SurgicalOutcome(status: SurgicalStatus.verifyFailed, verify: verdict);
    }

    // 2. BACKUP + JOURNAL — before touching the original.
    final entryId = TrashRepository.newId();
    final filename = (await entity.titleAsync).trim();
    final originalMime = entity.mimeType;
    final backupPath = await _repo.writeBackup(
      entryId,
      originBytes,
      ext: _extOf(filename),
    );
    await _repo.insertPending(TrashDraft(
      id: entryId,
      originalAssetId: entity.id,
      filename: filename,
      backupPath: backupPath,
      createdDateMs: entity.createDateTime.millisecondsSinceEpoch,
      modifiedDateMs: entity.modifiedDateTime.millisecondsSinceEpoch,
      latitude: entity.latitude,
      longitude: entity.longitude,
      isFavorite: entity.isFavorite,
      mimeType: originalMime,
      assetType: entity.typeInt,
      width: entity.width,
      height: entity.height,
      originalBytes: originalBytes,
      newBytes: candidateBytes,
    ));

    // 3. OVERWRITE — in place; update name/mime when the format changed.
    final newName = await outputFilename(entity, candidate.extension);
    final newMime = _mimeFor(candidate.format);
    final status = await NativeSurgical.overwrite(
      id: entity.id,
      bytes: candidate.bytes,
      mime: newMime,
      name: newName,
    );

    switch (status) {
      case SurgicalOverwriteStatus.ok:
        await _repo.markCommitted(entryId,
            newAssetId: entity.id, newBytes: candidateBytes);
        return SurgicalOutcome(
          status: SurgicalStatus.success,
          savedBytes: (originalBytes - candidateBytes).clamp(0, originalBytes),
        );
      case SurgicalOverwriteStatus.cancelled:
        // Consent declined → no write happened, original intact. Clean up.
        await _repo.drop(entryId);
        return const SurgicalOutcome(status: SurgicalStatus.cancelled);
      case SurgicalOverwriteStatus.failed:
        // A write may have partially landed → restore from the backup to
        // guarantee the original. If even that fails, KEEP the entry (backup
        // stays in trash as the safety net).
        final restored = await NativeSurgical.overwrite(
          id: entity.id,
          bytes: originBytes,
          mime: originalMime,
          name: filename.isEmpty ? null : filename,
        );
        if (restored == SurgicalOverwriteStatus.ok) {
          await _repo.drop(entryId);
        } else {
          await _repo.markCommitted(entryId,
              newAssetId: entity.id, newBytes: candidateBytes);
        }
        return const SurgicalOutcome(status: SurgicalStatus.failed);
    }
  }

  /// Restore a trashed original byte-for-byte over its current bytes.
  Future<bool> restore(TrashEntry entry) async {
    if (!Platform.isAndroid) return false;
    final bytes = await _repo.readBackup(entry.backupPath);
    if (bytes == null) return false;
    final status = await NativeSurgical.overwrite(
      id: entry.originalAssetId,
      bytes: bytes,
      mime: entry.mimeType,
      name: entry.filename.isEmpty ? null : entry.filename,
    );
    if (status == SurgicalOverwriteStatus.ok) {
      await _repo.drop(entry.id);
      return true;
    }
    return false;
  }

  /// On startup: any `pending` row means a replacement was interrupted. The
  /// byte-for-byte backup is safe, so promote it to a restorable trash item —
  /// no surprise consent prompt. The user can restore from Trash if needed.
  Future<void> recoverPending() async {
    final pending = await _repo.listPending();
    for (final e in pending) {
      await _repo.markCommitted(e.id,
          newAssetId: e.originalAssetId, newBytes: e.newBytes);
    }
  }

  static String _extOf(String filename) {
    final dot = filename.lastIndexOf('.');
    return (dot >= 0 && dot < filename.length - 1)
        ? filename.substring(dot + 1)
        : 'img';
  }

  static String _mimeFor(DefaultFormat f) => switch (f) {
        DefaultFormat.avif => 'image/avif',
        DefaultFormat.heic => 'image/heic',
        DefaultFormat.webp => 'image/webp',
        DefaultFormat.png => 'image/png',
        DefaultFormat.jpeg || DefaultFormat.auto => 'image/jpeg',
      };
}

final surgicalReplaceServiceProvider = Provider<SurgicalReplaceService>((ref) {
  return SurgicalReplaceService(ref.watch(trashRepositoryProvider));
});
