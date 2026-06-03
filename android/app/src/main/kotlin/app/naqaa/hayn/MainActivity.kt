package app.naqaa.hayn

import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val avifExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SIZE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSizes" -> {
                        val ids = call.argument<List<String>>("ids").orEmpty()
                        result.success(querySizes(ids))
                    }
                    else -> result.notImplemented()
                }
            }

        // Hardware AVIF (MediaCodec AV1). Encoding blocks, so run it off the
        // platform thread and post the result back. Any failure returns null →
        // Dart falls back to the software encoder, so output can't regress.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AVIF_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(AvifHwEncoder.isAvailable())
                    "encode" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val quality = call.argument<Int>("quality") ?: 80
                        if (bytes == null) {
                            result.success(null)
                        } else {
                            avifExecutor.execute {
                                val out = runCatching { AvifHwEncoder.encode(bytes, quality) }
                                    .getOrNull()
                                mainHandler.post { result.success(out) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Resolves byte sizes straight from MediaStore's `_size` column — no file
     * is opened or copied. photo_manager asset ids on Android are the
     * MediaStore `_id`, so we select rows by id and read their size.
     *
     * Returns `id -> size`; ids without a positive size are omitted so the Dart
     * side falls back for them.
     */
    private fun querySizes(ids: List<String>): Map<String, Long> {
        val out = HashMap<String, Long>()
        // Only numeric MediaStore ids are queryable here.
        val numeric = ids.filter { it.toLongOrNull() != null }
        if (numeric.isEmpty()) return out

        val resolver = applicationContext.contentResolver
        val uri = MediaStore.Files.getContentUri("external")
        val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.SIZE)

        // Chunk to stay well under SQLite's 999 bound-variable limit.
        numeric.chunked(900).forEach { chunk ->
            val placeholders = chunk.joinToString(",") { "?" }
            val selection = "${MediaStore.MediaColumns._ID} IN ($placeholders)"
            val args = chunk.toTypedArray()
            resolver.query(uri, projection, selection, args, null)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                while (cursor.moveToNext()) {
                    val size = cursor.getLong(sizeCol)
                    if (size > 0) {
                        out[cursor.getLong(idCol).toString()] = size
                    }
                }
            }
        }
        return out
    }

    private companion object {
        const val SIZE_CHANNEL = "hayn/media_size"
        const val AVIF_CHANNEL = "hayn/avif"
    }
}
