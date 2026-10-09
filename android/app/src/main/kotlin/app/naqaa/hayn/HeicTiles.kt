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
import java.nio.ByteOrder

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
// Each tile gets a fixed QP (Android 12+; the encoder has no CQ mode). Every
// HEIC on Android comes from here since IMG-24: HeifWriter took RGB_565
// through a GL texture, banding every image and crashing at an odd width.
//
// Bit depth is the user's choice (IMG-23): 8, or 10 where the encoder offers
// HEVC Main10 with P010 input (Android 13+). At 10 the bands are decoded as
// RGBA_1010102, which keeps the decoder's colour space as ARGB_8888 does, so
// a 10-bit source keeps its precision.
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

    /// True when [encodeToFile] can write 10 bits: an HEVC encoder with Main10
    /// and P010 input (Android 13+).
    fun tenBitAvailable(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && encoderName(tenBit = true) != null

    /// Encodes [src] to a HEIC file in [dir]. [orientation] is the EXIF code
    /// (1–8, 0 = none) that turns the decoded pixels upright; [depth] 10
    /// writes Main10 (see [tenBitAvailable]), anything else 8 bits.
    ///
    /// [encoder] and [rateMode] stand in for other phones in the device
    /// tests (one phone, by the user's decision): a named HEVC encoder that
    /// takes the tiles (Google's software one is on every Android), and the
    /// rate mode Android below 12 gets ("cq" or "vbr"). Null in the app.
    fun encodeToFile(
        src: ByteArray,
        quality: Int,
        orientation: Int,
        depth: Int,
        dir: File,
        encoder: String? = null,
        rateMode: String? = null,
    ): Result? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        val tenBit = depth >= 10
        if (tenBit && Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return fail("10-bit needs Android 13")
        var file: File? = null
        var bands: Bands? = null
        return try {
            bands = bandsOf(src, tenBit) ?: return fail("no decoder")
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
            // Below Android 12 there is no fixed QP: constant quality (CQ) is
            // the mode that follows the content, so an encoder offering it
            // comes first (a Qualcomm phone lists it as a sibling, `….cq`).
            val preferCq = rateMode == "cq" ||
                (rateMode == null && Build.VERSION.SDK_INT < Build.VERSION_CODES.S)
            val name = encoderName(tenBit, encoder, preferCq) ?: return fail("no HEVC encoder (10-bit $tenBit)")
            file = File.createTempFile("hayn-heic-", ".heic", dir)
            val mode = encode(name, bands, w, h, rows, cols, mirror, degrees, quality, tenBit, file, rateMode)
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

    /// The band's pixel layout: 8 bits per channel, or 10 for Main10.
    private fun configFor(tenBit: Boolean): Bitmap.Config =
        if (tenBit && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Bitmap.Config.RGBA_1010102
        } else {
            Bitmap.Config.ARGB_8888
        }

    private fun optionsFor(tenBit: Boolean) = BitmapFactory.Options().apply {
        inPreferredConfig = configFor(tenBit)
    }

    /// JPEG and HEIF decode a region without the rows above it.
    private class Regions(
        private val decoder: BitmapRegionDecoder,
        private val options: BitmapFactory.Options,
    ) : Bands {
        override val width get() = decoder.width
        override val height get() = decoder.height
        override fun band(y0: Int, rows: Int): Bitmap? =
            decoder.decodeRegion(Rect(0, y0, width, y0 + rows), options)
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
    private fun bandsOf(src: ByteArray, tenBit: Boolean): Bands? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(src, 0, src.size, bounds)
        val options = optionsFor(tenBit)
        return when (bounds.outMimeType) {
            "image/jpeg", "image/heif", "image/heic" -> Regions(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    BitmapRegionDecoder.newInstance(src, 0, src.size)
                } else {
                    BitmapRegionDecoder.newInstance(src, 0, src.size, false)
                } ?: return null,
                options,
            )
            else -> Whole(BitmapFactory.decodeByteArray(src, 0, src.size, options) ?: return null)
        }
    }

    /// The input colour format: flexible 8-bit YUV, or P010 for Main10.
    @Suppress("InlinedApi")
    private fun colorFormatFor(tenBit: Boolean): Int =
        if (tenBit) {
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUVP010
        } else {
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible
        }

    /// A hardware HEVC encoder taking 512×512 tiles in [colorFormatFor], with
    /// Main10 for [tenBit]; else any such encoder. [named], when given, only
    /// if it is one of them. [preferCq]: one with constant quality first.
    private fun encoderName(tenBit: Boolean, named: String? = null, preferCq: Boolean = false): String? {
        val candidates = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(HEVC, ignoreCase = true) } &&
                runCatching {
                    val caps = info.getCapabilitiesForType(HEVC)
                    caps.videoCapabilities.isSizeSupported(TILE, TILE) &&
                        caps.colorFormats.contains(colorFormatFor(tenBit)) &&
                        (!tenBit || caps.profileLevels.any {
                            it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10
                        })
                }.getOrDefault(false)
        }
        if (named != null) return candidates.firstOrNull { it.name == named }?.name
        fun cq(info: MediaCodecInfo) = runCatching {
            info.getCapabilitiesForType(HEVC).encoderCapabilities
                .isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CQ)
        }.getOrDefault(false)
        val ordered = if (preferCq) candidates.sortedByDescending { cq(it) } else candidates
        val hardware = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ordered.firstOrNull { it.isHardwareAccelerated }
        } else {
            null
        }
        return (hardware ?: ordered.firstOrNull())?.name
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

    /// Quality to bits per tile pixel for VBR (an encoder with neither fixed
    /// QP nor CQ, below Android 12): what the fixed QP of [qpFor] spends on
    /// a 12 MP photo, measured on the S25 Edge by forcing VBR (2026-10-09,
    /// docs/23 §2). VBR is an average, so content simpler than that photo
    /// stops at the encoder's best quality whatever the budget.
    private val VBR_POINTS = listOf(
        0 to 0.39, 50 to 1.50, 70 to 1.61, 80 to 1.73, 90 to 2.22, 95 to 2.92, 100 to 3.86,
    )

    internal fun vbrBitsPerPixel(quality: Int): Double {
        val q = quality.coerceIn(0, 100)
        val (hi, hiBits) = VBR_POINTS.first { it.first >= q }
        val (lo, loBits) = VBR_POINTS.last { it.first <= q }
        if (hi == lo) return hiBits
        return loBits + (hiBits - loBits) * (q - lo) / (hi - lo)
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
        tenBit: Boolean,
        out: File,
        forcedMode: String? = null,
    ): String? {
        val codec = MediaCodec.createByCodecName(name)
        var muxer: MediaMuxer? = null
        var muxing = false
        try {
            val caps = codec.codecInfo.getCapabilitiesForType(HEVC).encoderCapabilities
            val video = codec.codecInfo.getCapabilitiesForType(HEVC).videoCapabilities
            // A fixed QP per tile follows the content, as constant quality
            // does; this encoder (c2.qti.hevc.encoder) offers no CQ mode.
            val mode = forcedMode ?: when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> "qp"
                caps.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CQ) -> "cq"
                else -> "vbr"
            }
            val format = MediaFormat.createVideoFormat(HEVC, TILE, TILE).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, colorFormatFor(tenBit))
                if (tenBit) {
                    setInteger(
                        MediaFormat.KEY_PROFILE,
                        MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10,
                    )
                }
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
                        // Each tile is one frame at 30 fps, so this budgets
                        // vbrBitsPerPixel per tile pixel.
                        val bpp = vbrBitsPerPixel(quality)
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
                // A 10-bit HEIF comes as RGBA_1010102 whatever is asked, an
                // 8-bit source may come as ARGB_8888 at 10; copy keeps the
                // colour space.
                val config = configFor(tenBit)
                val band = if (decoded.config == config) {
                    decoded
                } else {
                    decoded.copy(config, false).also { decoded.recycle() }
                        ?: return fail("band ${decoded.config}")
                }
                try {
                    if (band.config != config || band.width != w ||
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
                        if (tenBit) {
                            fillTile10(image, pixels, stride, w, bh, c * TILE, mirror)
                        } else {
                            fillTile(image, pixels, stride, w, bh, c * TILE, mirror)
                        }
                        val size = TILE * TILE * 3 / 2 * (if (tenBit) 2 else 1)
                        codec.queueInputBuffer(ix, 0, size, queued * 33_333L, 0)
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
    /// averaging each 2×2 block. Coefficients in 16-bit fixed point, rounded:
    /// the common 8-bit ones (66/129/25, -38/-74/112, 112/-94/-18) were off
    /// by up to a level in U and V, which moved a saturated P3 green's blue
    /// by 8 levels once converted to sRGB (IMG-24). Past the image's right or bottom edge the
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
                uBuf.put(cy * uRow + cx * uPix, chroma(-9714 * r - 19071 * g + 28784 * bl))
                vBuf.put(cy * vRow + cx * vPix, chroma(28784 * r - 24103 * g - 4681 * bl))
            }
            yBuf.position(ty * yRow)
            yBuf.put(y0Line)
            yBuf.position((ty + 1) * yRow)
            yBuf.put(y1Line)
        }
    }

    /// [fillTile] at 10 bits: RGBA_1010102 in (R in the low 10 bits of each
    /// little-endian word), P010 out (each sample in the top 10 bits of a
    /// little-endian 16-bit word), BT.601 limited range for 10 bits (luma
    /// 64–940, chroma 64–960).
    private fun fillTile10(
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
        val yBuf = yPlane.buffer.order(ByteOrder.LITTLE_ENDIAN)
        val uBuf = uPlane.buffer.order(ByteOrder.LITTLE_ENDIAN)
        val vBuf = vPlane.buffer.order(ByteOrder.LITTLE_ENDIAN)
        val yRow = yPlane.rowStride
        val yPix = yPlane.pixelStride
        val uRow = uPlane.rowStride
        val vRow = vPlane.rowStride
        val uPix = uPlane.pixelStride
        val vPix = vPlane.pixelStride
        val col = IntArray(TILE) { tx ->
            val x = minOf(x0 + tx, w - 1)
            (if (mirror) w - 1 - x else x) * 4
        }
        fun word(i: Int): Int = (px[i].toInt() and 0xFF) or ((px[i + 1].toInt() and 0xFF) shl 8) or
            ((px[i + 2].toInt() and 0xFF) shl 16) or ((px[i + 3].toInt() and 0xFF) shl 24)
        var rs = 0
        var gs = 0
        var bs = 0
        // One pixel's luma at (tx, ty) of the tile; its RGB summed for chroma.
        fun pixel(rowOff: Int, tx: Int, ty: Int) {
            val p = word(rowOff + col[tx])
            val r = p and 0x3FF
            val g = (p shr 10) and 0x3FF
            val b = (p shr 20) and 0x3FF
            rs += r
            gs += g
            bs += b
            val y = (16780 * r + 32942 * g + 6398 * b + 32768 shr 16) + 64
            yBuf.putShort(ty * yRow + tx * yPix, (y shl 6).toShort())
        }
        for (ty in 0 until TILE step 2) {
            val r0 = minOf(ty, bh - 1) * stride
            val r1 = minOf(ty + 1, bh - 1) * stride
            for (tx in 0 until TILE step 2) {
                rs = 0
                gs = 0
                bs = 0
                pixel(r0, tx, ty)
                pixel(r0, tx + 1, ty)
                pixel(r1, tx, ty + 1)
                pixel(r1, tx + 1, ty + 1)
                val r = (rs + 2) shr 2
                val g = (gs + 2) shr 2
                val b = (bs + 2) shr 2
                val u = (-9685 * r - 19015 * g + 28700 * b + 32768 shr 16) + 512
                val v = (28700 * r - 24033 * g - 4667 * b + 32768 shr 16) + 512
                val cx = tx shr 1
                val cy = ty shr 1
                uBuf.putShort(cy * uRow + cx * uPix, (u shl 6).toShort())
                vBuf.putShort(cy * vRow + cx * vPix, (v shl 6).toShort())
            }
        }
    }

    private fun luma(r: Int, g: Int, b: Int): Byte =
        ((16829 * r + 33039 * g + 6416 * b + 32768 shr 16) + 16).toByte()

    private fun chroma(sum: Int): Byte = ((sum + 32768 shr 16) + 128).toByte()
}
