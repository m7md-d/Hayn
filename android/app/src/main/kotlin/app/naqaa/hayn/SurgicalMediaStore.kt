package app.naqaa.hayn

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.IntentSender
import android.os.Build
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel

// ─────────────────────────────────────────────────────────────────────────────
// SurgicalMediaStore — the Android in-place replacement for Surgical Replace.
//
// Writes new bytes OVER the original via its MediaStore content URI, keeping the
// same _ID / DATE_ADDED / bucket → album, folder, Samsung tags and timeline
// order are preserved, and space is reclaimed (CLAUDE.md §3 / F2). The caller
// (the Dart safe-transaction service) only invokes this AFTER it has verified
// the candidate and written a byte-for-byte backup, so a failure here is always
// recoverable.
//
// Scoped storage (Android 11+): writing media the app didn't create needs the
// user's consent. We request it via MediaStore.createWriteRequest (API 30+) or
// the RecoverableSecurityException action (API 29), then complete the write in
// onActivityResult. Results: "ok" | "cancelled" | "failed".
// ─────────────────────────────────────────────────────────────────────────────

class SurgicalMediaStore(private val activity: Activity) {

    private class Pending(
        val id: Long,
        val bytes: ByteArray,
        val mime: String?,
        val name: String?,
        val result: MethodChannel.Result,
    )

    private var pending: Pending? = null

    fun overwrite(
        id: Long,
        bytes: ByteArray,
        mime: String?,
        name: String?,
        result: MethodChannel.Result,
    ) {
        try {
            writeAndUpdate(id, bytes, mime, name)
            result.success("ok")
        } catch (sec: SecurityException) {
            val sender = consentIntentSender(id, sec)
            if (sender == null) {
                result.success("failed")
                return
            }
            // Defer: complete the write once the user grants access.
            pending = Pending(id, bytes, mime, name, result)
            try {
                @Suppress("DEPRECATION")
                activity.startIntentSenderForResult(sender, REQUEST_CODE, null, 0, 0, 0)
            } catch (_: Throwable) {
                pending = null
                result.success("failed")
            }
        } catch (_: Throwable) {
            result.success("failed")
        }
    }

    /** Forwarded from the Activity. Returns true if it handled this request. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val p = pending ?: return true
        pending = null
        if (resultCode == Activity.RESULT_OK) {
            try {
                writeAndUpdate(p.id, p.bytes, p.mime, p.name)
                p.result.success("ok")
            } catch (_: Throwable) {
                p.result.success("failed")
            }
        } else {
            p.result.success("cancelled")
        }
        return true
    }

    private fun uriFor(id: Long) =
        ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)

    private fun writeAndUpdate(id: Long, bytes: ByteArray, mime: String?, name: String?) {
        val resolver = activity.applicationContext.contentResolver
        val uri = uriFor(id)
        val scoped = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

        // Phase 1 — HIDE + retype/rename atomically while pending. Doing the
        // rename/MIME change BEFORE writing (and while IS_PENDING) is what stops
        // the gallery from ever seeing a mismatched file (e.g. AVIF bytes in a
        // ".jpg" entry), which is what made Samsung mark the original corrupt and
        // index the change as a NEW, duplicate image. Same _ID throughout.
        if (scoped) {
            val v1 = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 1)
                if (!mime.isNullOrEmpty()) put(MediaStore.MediaColumns.MIME_TYPE, mime)
                if (!name.isNullOrEmpty()) put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            }
            resolver.update(uri, v1, null, null)
        }

        // Phase 2 — overwrite the bytes ("wt" truncates first).
        resolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
            ?: throw IllegalStateException("no output stream")

        // Phase 3 — PUBLISH: clear pending + refresh modified time (on legacy
        // storage there's no pending flag, so apply name/MIME here instead).
        val v2 = ContentValues().apply {
            put(MediaStore.MediaColumns.DATE_MODIFIED, System.currentTimeMillis() / 1000)
            if (scoped) {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            } else {
                if (!mime.isNullOrEmpty()) put(MediaStore.MediaColumns.MIME_TYPE, mime)
                if (!name.isNullOrEmpty()) put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            }
        }
        resolver.update(uri, v2, null, null)
    }

    private fun consentIntentSender(id: Long, sec: SecurityException): IntentSender? {
        val resolver = activity.applicationContext.contentResolver
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                MediaStore.createWriteRequest(resolver, listOf(uriFor(id))).intentSender
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                sec is RecoverableSecurityException ->
                sec.userAction.actionIntent.intentSender
            else -> null
        }
    }

    companion object {
        const val REQUEST_CODE = 0x5A11 // "SAfe replace"
    }
}
