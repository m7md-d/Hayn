package app.naqaa.hayn

import android.app.ActivityManager
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val avifExecutor = Executors.newSingleThreadExecutor()
    private val decodeExecutor = Executors.newSingleThreadExecutor()
    // Two threads: the compare screen's two images decode side by side; one
    // decoder serialises its own regions anyway.
    private val regionExecutor = Executors.newFixedThreadPool(2)
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

        // The iOS image channel's pixel bridge, as a file on Android (PERF-02);
        // its other methods stay iOS-only (notImplemented → MissingPlugin
        // in Dart, as before).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, IMAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Memory for the heavy-work gate (RUN-02): what can be
                    // allocated before the system reclaims, and its threshold.
                    // Whether HEIC can be written at 10 bits (IMG-23).
                    "heicTenBit" -> result.success(HeicTiles.tenBitAvailable())
                    "memoryInfo" -> {
                        val info = ActivityManager.MemoryInfo()
                        (getSystemService(ACTIVITY_SERVICE) as ActivityManager)
                            .getMemoryInfo(info)
                        result.success(
                            mapOf("available" to info.availMem, "threshold" to info.threshold),
                        )
                    }
                    "bakeUprightFile" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val toSdr = call.argument<Boolean>("toSdr") ?: false
                        val maxEdge = call.argument<Int>("maxEdge") ?: 0
                        val colours = call.argument<String>("colours") ?: "srgb"
                        val space = call.argument<FloatArray>("space")
                        val jpegQuality = call.argument<Int>("jpegQuality") ?: 0
                        if (bytes == null) {
                            result.success(null)
                        } else {
                            decodeExecutor.execute {
                                val out = PlatformDecoder.bakeUprightToFile(
                                    bytes, toSdr, maxEdge, colours, space, cacheDir,
                                    jpegQuality,
                                )
                                mainHandler.post { result.success(out) }
                            }
                        }
                    }
                    // HEIC from bands and tiles (RUN-01): a file path plus the
                    // encoder and its rate mode, for the caller's records.
                    "encodeHeicTiles" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val quality = call.argument<Int>("quality") ?: 80
                        val orientation = call.argument<Int>("orientation") ?: 0
                        val depth = call.argument<Int>("depth") ?: 8
                        if (bytes == null) {
                            result.success(null)
                        } else {
                            decodeExecutor.execute {
                                val out = HeicTiles.encodeToFile(bytes, quality, orientation, depth, cacheDir)
                                mainHandler.post {
                                    result.success(
                                        out?.let {
                                            mapOf(
                                                "path" to it.path,
                                                "codec" to it.codec,
                                                "rateMode" to it.rateMode,
                                            )
                                        },
                                    )
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Region decoding for the zoomed viewer and compare screen (PERF-03):
        // tiles of the part in view, never the whole image.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REGION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val path = call.argument<String>("path")
                        val orientation = call.argument<Int>("orientation") ?: 0
                        val space = call.argument<FloatArray>("space")
                        if (path == null) {
                            result.success(null)
                        } else {
                            regionExecutor.execute {
                                val out = RegionDecoders.open(path, orientation, space)
                                mainHandler.post {
                                    result.success(
                                        out?.let {
                                            mapOf("id" to it.id, "width" to it.width, "height" to it.height)
                                        },
                                    )
                                }
                            }
                        }
                    }
                    "tiles" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val rect = call.argument<IntArray>("rect")
                        val cuts = call.argument<IntArray>("cuts") ?: IntArray(0)
                        val sample = call.argument<Int>("sample") ?: 1
                        if (rect == null || rect.size != 4) {
                            result.success(null)
                        } else {
                            regionExecutor.execute {
                                val out = RegionDecoders.tiles(
                                    id, rect[0], rect[1], rect[2], rect[3], cuts, sample,
                                )
                                mainHandler.post {
                                    result.success(
                                        out?.map {
                                            mapOf("width" to it.width, "height" to it.height, "pixels" to it.pixels)
                                        },
                                    )
                                }
                            }
                        }
                    }
                    "close" -> {
                        val id = call.argument<Int>("id") ?: 0
                        regionExecutor.execute { RegionDecoders.close(id) }
                        result.success(null)
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
        const val IMAGE_CHANNEL = "hayn/metadata"
        const val REGION_CHANNEL = "hayn/region"
    }
}
