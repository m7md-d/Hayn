package app.naqaa.hayn

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.ColorSpace
import android.graphics.Rect
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.util.Log
import java.io.File
import java.nio.ByteBuffer

// ─────────────────────────────────────────────────────────────────────────────
// HeicTiles — HEIC at any size with memory that does not follow it (RUN-01).
//
// HeifWriter (the plugin's path) asks for one graphics buffer the size of the
// whole image, which a 200 MP photo cannot get, and its input is a Bitmap of
// the whole image too. Here a JPEG or HEIF source is decoded one band of
// 512 rows at a time (BitmapRegionDecoder); other formats re-read every row
// above a region, so they are decoded once, whole, as HeifWriter's input is.
// Each 512×512 tile becomes one intra frame of the HEVC encoder (what
// HeifWriter does inside), and MediaMuxer writes the HEIF grid: the container
// Android itself writes, not a new one (native.md).
//
// The stored pixels are the source's as decoded: no rotation, which would need
// the whole image. The orientation goes into the container instead: a
// horizontal mirror is done per band, and the rest is a rotation, which
// MediaMuxer writes as `irot`. Colours stay in the space the decoder chose
// (the source's own when Android can represent it, IMG-18), BT.601 limited
// range YUV as HeifWriter writes; the caller carries the source's profile
// and metadata onto the file (DarkLib). Alpha is not encoded: the caller runs
// this for opaque sources only. Every failure returns null, with a reason in
// the log.
//
// Each tile gets a fixed QP (Android 12+; the encoder has no CQ mode). The
// caller uses this for giant images only: at 12 MP it was a little more
// accurate than HeifWriter at equal size but 0.2 to 0.5 s slower, and the
// user chose speed there (docs/18-PERFORMANCE.md).
// ─────────────────────────────────────────────────────────────────────────────

object HeicTiles {
    private const val TILE = 512
    private const val HEVC = MediaFormat.MIMETYPE_VIDEO_HEVC

    /// A grid descriptor stores rows and columns minus one in a byte.
    private const val MAX_GRID = 256

    /// No output buffer for this long means the encoder is stuck.
    private const val STALL_MS = 10_000L

    /// [rateMode]: "qp" (a fixed QP per tile), "cq" or "vbr".
    class Result(val path: String, val codec: String, val rateMode: String)

    /// Encodes [src] to a HEIC file in [dir]. [orientation] is the EXIF code
    /// (1–8, 0 = none) that turns the decoded pixels upright.
    fun encodeToFile(src: ByteArray, quality: Int, orientation: Int, dir: File): Result? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        var file: File? = null
        var bands: Bands? = null
        return try {
            bands = bandsOf(src) ?: return fail("no decoder")
            val w = bands.width
            val h = bands.height
            val cols = (w + TILE - 1) / TILE
            val rows = (h + TILE - 1) / TILE
            if (w < 1 || h < 1 || rows > MAX_GRID || cols > MAX_GRID) return fail("size")
            // EXIF code = an optional left↔right mirror, then a clockwise turn.
            val (mirror, degrees) = when (orientation) {
                2 -> true to 0
                3 -> false to 180
                4 -> true to 180
                5 -> true to 270
                6 -> false to 90
                7 -> true to 90
                8 -> false to 270
                else -> false to 0
            }
            val name = encoderName() ?: return fail("no HEVC encoder")
            file = File.createTempFile("hayn-heic-", ".heic", dir)
            val mode = encode(name, bands, w, h, rows, cols, mirror, degrees, quality, file)
                ?: throw IllegalStateException("encode")
            Result(file.absolutePath, name, mode)
        } catch (e: Throwable) {
            file?.delete()
            fail(e.javaClass.simpleName + ": " + e.message)
        } finally {
            bands?.close()
        }
    }

    /// A reason in the log (no file data) for a null result.
    private fun <T> fail(reason: String): T? {
        Log.w("HeicTiles", reason)
        return null
    }

    /// The stored image, band by band, top to bottom: raw values in the
    /// decoder's colour space, no orientation applied.
    private interface Bands {
        val width: Int
        val height: Int
        fun band(y0: Int, rows: Int): Bitmap?
        fun close()
    }

    private val ARGB = BitmapFactory.Options().apply {
        inPreferredConfig = Bitmap.Config.ARGB_8888
    }

    /// JPEG and HEIF decode a region without the rows above it.
    private class Regions(private val decoder: BitmapRegionDecoder) : Bands {
        override val width get() = decoder.width
        override val height get() = decoder.height
        override fun band(y0: Int, rows: Int): Bitmap? =
            decoder.decodeRegion(Rect(0, y0, width, y0 + rows), ARGB)
        override fun close() = decoder.recycle()
    }

    /// PNG, WebP, AVIF… decoded once: on a 12 MP PNG the regions took
    /// 1.3 s against 0.6 s, and the cost grows with the square of the height.
    private class Whole(private val bitmap: Bitmap) : Bands {
        override val width get() = bitmap.width
        override val height get() = bitmap.height

        // createBitmap returns the bitmap itself for the whole area, and
        // the caller recycles each band.
        override fun band(y0: Int, rows: Int): Bitmap? =
            if (y0 == 0 && rows == height) {
                bitmap.copy(bitmap.config ?: Bitmap.Config.ARGB_8888, false)
            } else {
                Bitmap.createBitmap(bitmap, 0, y0, width, rows)
            }
        override fun close() = bitmap.recycle()
    }

    @Suppress("DEPRECATION")
    private fun bandsOf(src: ByteArray): Bands? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(src, 0, src.size, bounds)
        return when (bounds.outMimeType) {
            "image/jpeg", "image/heif", "image/heic" -> Regions(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    BitmapRegionDecoder.newInstance(src, 0, src.size)
                } else {
                    BitmapRegionDecoder.newInstance(src, 0, src.size, false)
                } ?: return null,
            )
            else -> Whole(BitmapFactory.decodeByteArray(src, 0, src.size, ARGB) ?: return null)
        }
    }

    /// A hardware HEVC encoder taking 512×512 flexible YUV, else any.
    private fun encoderName(): String? {
        val candidates = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(HEVC, ignoreCase = true) } &&
                runCatching {
                    val caps = info.getCapabilitiesForType(HEVC)
                    caps.videoCapabilities.isSizeSupported(TILE, TILE) &&
                        caps.colorFormats.contains(
                            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
                        )
                }.getOrDefault(false)
        }
        val hardware = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            candidates.firstOrNull { it.isHardwareAccelerated }
        } else {
            null
        }
        return (hardware ?: candidates.firstOrNull())?.name
    }

    /// Quality (0–100) to the tiles' QP, through points measured against
    /// HeifWriter on a 12 MP photo (S25 Edge, 2026-10-02): the same quality
    /// gives about the same file size, 0.6 to 2.3 dB higher PSNR.
    private val QP_POINTS = listOf(0 to 40, 50 to 29, 70 to 28, 80 to 27, 90 to 23, 95 to 18, 100 to 12)

    internal fun qpFor(quality: Int): Int {
        val q = quality.coerceIn(0, 100)
        val (hi, hiQp) = QP_POINTS.first { it.first >= q }
        val (lo, loQp) = QP_POINTS.last { it.first <= q }
        if (hi == lo) return hiQp
        return loQp + ((hiQp - loQp) * (q - lo) + (hi - lo) / 2) / (hi - lo)
    }

    /// The rate mode used ("qp", "cq" or "vbr"); null on failure.
    private fun encode(
        name: String,
        bands: Bands,
        w: Int,
        h: Int,
        rows: Int,
        cols: Int,
        mirror: Boolean,
        degrees: Int,
        quality: Int,
        out: File,
    ): String? {
        val codec = MediaCodec.createByCodecName(name)
        var muxer: MediaMuxer? = null
        var muxing = false
        try {
            val caps = codec.codecInfo.getCapabilitiesForType(HEVC).encoderCapabilities
            val video = codec.codecInfo.getCapabilitiesForType(HEVC).videoCapabilities
            // A fixed QP per tile follows the content, as constant quality
            // does; this encoder (c2.qti.hevc.encoder) offers no CQ mode.
            val mode = when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> "qp"
                caps.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CQ) -> "cq"
                else -> "vbr"
            }
            val format = MediaFormat.createVideoFormat(HEVC, TILE, TILE).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
                )
                // Every tile is an intra frame, as in HeifWriter.
                setInteger(MediaFormat.KEY_FRAME_RATE, 30)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 0)
                setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT601_PAL)
                setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
                setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
                when (mode) {
                    "qp" -> {
                        setInteger(
                            MediaFormat.KEY_BITRATE_MODE,
                            MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR,
                        )
                        // The ceiling, so the QP alone decides.
                        setInteger(MediaFormat.KEY_BIT_RATE, video.bitrateRange.upper)
                        val qp = qpFor(quality)
                        setInteger(MediaFormat.KEY_VIDEO_QP_I_MIN, qp)
                        setInteger(MediaFormat.KEY_VIDEO_QP_I_MAX, qp)
                    }
                    "cq" -> {
                        setInteger(
                            MediaFormat.KEY_BITRATE_MODE,
                            MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CQ,
                        )
                        val range = caps.qualityRange
                        val q = range.lower + (range.upper - range.lower) * quality.coerceIn(0, 100) / 100
                        setInteger(MediaFormat.KEY_QUALITY, q)
                    }
                    else -> {
                        setInteger(
                            MediaFormat.KEY_BITRATE_MODE,
                            MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR,
                        )
                        // Not measured: bits per pixel per tile, 0.5 to 4.
                        val bpp = 0.5 + quality.coerceIn(0, 100) / 100.0 * 3.5
                        setInteger(MediaFormat.KEY_BIT_RATE, (TILE * TILE * 30 * bpp).toInt())
                    }
                }
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val mux = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_HEIF)
            muxer = mux
            mux.setOrientationHint(degrees)

            val tiles = rows * cols
            var queued = 0
            var written = 0
            var track = -1
            var eos = false
            val info = MediaCodec.BufferInfo()
            var lastProgress = System.currentTimeMillis()

            // Moves every ready output to the muxer; true at end of stream.
            fun drain(timeoutUs: Long): Boolean {
                while (true) {
                    val ix = codec.dequeueOutputBuffer(info, timeoutUs)
                    when {
                        ix == MediaCodec.INFO_TRY_AGAIN_LATER -> return false
                        ix == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            check(track < 0)
                            val f = codec.outputFormat
                            f.setString(MediaFormat.KEY_MIME, MediaFormat.MIMETYPE_IMAGE_ANDROID_HEIC)
                            f.setInteger(MediaFormat.KEY_WIDTH, w)
                            f.setInteger(MediaFormat.KEY_HEIGHT, h)
                            f.setInteger(MediaFormat.KEY_TILE_WIDTH, TILE)
                            f.setInteger(MediaFormat.KEY_TILE_HEIGHT, TILE)
                            f.setInteger(MediaFormat.KEY_GRID_ROWS, rows)
                            f.setInteger(MediaFormat.KEY_GRID_COLUMNS, cols)
                            track = mux.addTrack(f)
                            mux.start()
                            muxing = true
                        }
                        ix >= 0 -> {
                            val buf = checkNotNull(codec.getOutputBuffer(ix))
                            val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                            if (!config && info.size > 0) {
                                check(track >= 0)
                                buf.position(info.offset)
                                buf.limit(info.offset + info.size)
                                mux.writeSampleData(track, buf, info)
                                written++
                            }
                            codec.releaseOutputBuffer(ix, false)
                            lastProgress = System.currentTimeMillis()
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return true
                        }
                    }
                }
            }

            var pixels = ByteArray(0)
            for (r in 0 until rows) {
                val y0 = r * TILE
                val bh = minOf(TILE, h - y0)
                val decoded = bands.band(y0, bh) ?: return fail("band $r")
                // A 10-bit HEIF comes as RGBA_1010102 whatever is asked;
                // copy keeps its colour space.
                val band = if (decoded.config == Bitmap.Config.ARGB_8888) {
                    decoded
                } else {
                    decoded.copy(Bitmap.Config.ARGB_8888, false).also { decoded.recycle() }
                        ?: return fail("band ${decoded.config}")
                }
                try {
                    if (band.config != Bitmap.Config.ARGB_8888 || band.width != w ||
                        band.height != bh || !sdr(band.colorSpace)
                    ) {
                        return fail("band ${band.config} ${band.width}x${band.height} ${band.colorSpace?.name}")
                    }
                    // Raw values in the band's own space (getPixels would
                    // convert them to sRGB): R, G, B, A bytes per pixel.
                    val stride = band.rowBytes
                    if (pixels.size < stride * bh) pixels = ByteArray(stride * TILE)
                    band.copyPixelsToBuffer(ByteBuffer.wrap(pixels, 0, stride * bh))
                    for (c in 0 until cols) {
                        var ix: Int
                        do {
                            ix = codec.dequeueInputBuffer(10_000)
                            if (ix < 0) {
                                drain(0)
                                if (System.currentTimeMillis() - lastProgress > STALL_MS) return fail("stalled")
                            }
                        } while (ix < 0)
                        val image = checkNotNull(codec.getInputImage(ix))
                        fillTile(image, pixels, stride, w, bh, c * TILE, mirror)
                        codec.queueInputBuffer(ix, 0, TILE * TILE * 3 / 2, queued * 33_333L, 0)
                        queued++
                        lastProgress = System.currentTimeMillis()
                        drain(0)
                    }
                } finally {
                    band.recycle()
                }
            }
            while (!eos) {
                val ix = codec.dequeueInputBuffer(10_000)
                if (ix >= 0) {
                    codec.queueInputBuffer(ix, 0, 0, queued * 33_333L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    break
                }
                eos = drain(0)
                if (System.currentTimeMillis() - lastProgress > STALL_MS) return fail("stalled at end")
            }
            while (!eos) {
                eos = drain(10_000)
                if (!eos && System.currentTimeMillis() - lastProgress > STALL_MS) return fail("no end")
            }
            if (written != tiles) return fail("$written of $tiles tiles")
            mux.stop()
            muxing = false
            return mode
        } finally {
            runCatching { codec.stop() }
            codec.release()
            if (muxing) runCatching { muxer?.stop() }
            runCatching { muxer?.release() }
        }
    }

    /// SDR spaces with a transfer function (not PQ/HLG); the caller has
    /// already sent HDR sources elsewhere.
    private fun sdr(space: ColorSpace?): Boolean =
        space is ColorSpace.Rgb && space.transferParameters != null

    /// One TILE×TILE frame from the band: BT.601 limited range, 4:2:0 by
    /// averaging each 2×2 block. Past the image's right or bottom edge the
    /// last column or row repeats (the grid crops it). [mirror] reads the
    /// band right to left.
    private fun fillTile(
        image: android.media.Image,
        px: ByteArray,
        stride: Int,
        w: Int,
        bh: Int,
        x0: Int,
        mirror: Boolean,
    ) {
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val yBuf = yPlane.buffer
        val uBuf = uPlane.buffer
        val vBuf = vPlane.buffer
        val yRow = yPlane.rowStride
        val uRow = uPlane.rowStride
        val vRow = vPlane.rowStride
        val uPix = uPlane.pixelStride
        val vPix = vPlane.pixelStride
        val y0Line = ByteArray(TILE)
        val y1Line = ByteArray(TILE)
        // Source byte offset of each tile column, edge-clamped and mirrored.
        val col = IntArray(TILE) { tx ->
            val x = minOf(x0 + tx, w - 1)
            (if (mirror) w - 1 - x else x) * 4
        }
        for (ty in 0 until TILE step 2) {
            val r0 = minOf(ty, bh - 1) * stride
            val r1 = minOf(ty + 1, bh - 1) * stride
            for (tx in 0 until TILE step 2) {
                val a = r0 + col[tx]
                val b = r0 + col[tx + 1]
                val c = r1 + col[tx]
                val d = r1 + col[tx + 1]
                val ra = px[a].toInt() and 0xFF
                val ga = px[a + 1].toInt() and 0xFF
                val ba = px[a + 2].toInt() and 0xFF
                val rb = px[b].toInt() and 0xFF
                val gb = px[b + 1].toInt() and 0xFF
                val bb = px[b + 2].toInt() and 0xFF
                val rc = px[c].toInt() and 0xFF
                val gc = px[c + 1].toInt() and 0xFF
                val bc = px[c + 2].toInt() and 0xFF
                val rd = px[d].toInt() and 0xFF
                val gd = px[d + 1].toInt() and 0xFF
                val bd = px[d + 2].toInt() and 0xFF
                y0Line[tx] = luma(ra, ga, ba)
                y0Line[tx + 1] = luma(rb, gb, bb)
                y1Line[tx] = luma(rc, gc, bc)
                y1Line[tx + 1] = luma(rd, gd, bd)
                val r = (ra + rb + rc + rd + 2) shr 2
                val g = (ga + gb + gc + gd + 2) shr 2
                val bl = (ba + bb + bc + bd + 2) shr 2
                val cx = tx shr 1
                val cy = ty shr 1
                uBuf.put(cy * uRow + cx * uPix, ((-38 * r - 74 * g + 112 * bl + 128 shr 8) + 128).toByte())
                vBuf.put(cy * vRow + cx * vPix, ((112 * r - 94 * g - 18 * bl + 128 shr 8) + 128).toByte())
            }
            yBuf.position(ty * yRow)
            yBuf.put(y0Line)
            yBuf.position((ty + 1) * yRow)
            yBuf.put(y1Line)
        }
    }

    private fun luma(r: Int, g: Int, b: Int): Byte =
        ((66 * r + 129 * g + 25 * b + 128 shr 8) + 16).toByte()
}
