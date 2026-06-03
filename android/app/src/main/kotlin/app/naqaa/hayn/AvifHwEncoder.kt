package app.naqaa.hayn

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

// ─────────────────────────────────────────────────────────────────────────────
// AvifHwEncoder — encodes an image to AVIF using the SoC's HARDWARE AV1 encoder
// (MediaCodec `video/av01`) instead of software libaom, then muxes the coded
// frame into a valid AVIF (ISOBMFF) file by hand — Android has no AVIF writer.
//
// This is the royalty-free + hardware path (CLAUDE.md §5). It is 8-bit / 4:2:0
// for now (HDR 10-bit + metadata items come next). Every entry point returns
// null on ANY problem so the Dart side falls back to the software encoder — a
// muxing imperfection can never corrupt or block output.
//
// AVIF layout produced:
//   ftyp(avif) + meta(hdlr,pitm,iinf/infe av01,iprp[ipco(av1C,ispe,pixi,colr),
//   ipma],iloc) + mdat(AV1 OBUs)
// ─────────────────────────────────────────────────────────────────────────────

object AvifHwEncoder {
    private const val AV1 = MediaFormat.MIMETYPE_VIDEO_AV1 // "video/av01"

    /// Longest edge we'll encode — memory-bounded (a 200 MP decode would OOM) and
    /// within typical hardware AV1 encoder dimension limits.
    private const val MAX_EDGE = 8192

    /// Largest power-of-two inSampleSize that keeps the long edge ≥ MAX_EDGE
    /// (so the post-decode scale only trims a little). 1 for normal-size images.
    private fun sampleSizeForMaxEdge(w: Int, h: Int): Int {
        var s = 1
        val longEdge = maxOf(w, h)
        while (longEdge / (s * 2) >= MAX_EDGE) s *= 2
        return s
    }

    /** True when a HARDWARE-accelerated AV1 encoder exists on this device. */
    fun isAvailable(): Boolean = hardwareEncoderName() != null

    private fun hardwareEncoderName(): String? {
        return try {
            val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            list.codecInfos.firstOrNull { info ->
                info.isEncoder &&
                    info.supportedTypes.any { it.equals(AV1, ignoreCase = true) } &&
                    info.isHardwareAccelerated
            }?.name
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * Encode [src] (any decodable image bytes) to AVIF at [quality] (0–100).
     * Returns the .avif bytes, or null to signal "fall back to software".
     */
    fun encode(src: ByteArray, quality: Int): ByteArray? {
        return try {
            val encoderName = hardwareEncoderName() ?: return null

            // Memory-bounded decode: a 200 MP image is ~800 MB as RGBA and would
            // OOM. Decode downsampled so the long edge is ≈ MAX_EDGE, which also
            // keeps within hardware AV1 encoders' dimension limits. Normal photos
            // (≤ MAX_EDGE) decode at full size (inSampleSize 1).
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(src, 0, src.size, bounds)
            val opts = BitmapFactory.Options().apply {
                inSampleSize = sampleSizeForMaxEdge(bounds.outWidth, bounds.outHeight)
            }
            var bmp = BitmapFactory.decodeByteArray(src, 0, src.size, opts) ?: return null
            bmp = applyOrientation(bmp, src)
            // Sampling is power-of-two/coarse — hard-cap the long edge after it.
            val longEdge = maxOf(bmp.width, bmp.height)
            if (longEdge > MAX_EDGE) {
                val s = MAX_EDGE.toFloat() / longEdge
                bmp = Bitmap.createScaledBitmap(
                    bmp, (bmp.width * s).toInt(), (bmp.height * s).toInt(), true,
                )
            }

            // AV1 wants even dimensions.
            val w = bmp.width and 1.inv()
            val h = bmp.height and 1.inv()
            if (w < 2 || h < 2) return null
            if (w != bmp.width || h != bmp.height) {
                bmp = Bitmap.createBitmap(bmp, 0, 0, w, h)
            }

            val i420 = argbToI420(bmp, w, h)
            val coded = encodeAv1(encoderName, i420, w, h, quality) ?: return null
            val avif = muxAvif(coded.configObus, coded.frameObus, w, h) ?: return null
            // Self-validate: the muxed AVIF MUST decode back, else our hand-built
            // container is wrong → return null so Dart falls back to software
            // libaom. This makes the hardware path safe to use by default even
            // while the muxer is still being proven on real files.
            if (decodesOk(avif)) avif else null
        } catch (_: Throwable) {
            null
        }
    }

    /** True if the platform can decode these bytes back (bounds only). */
    private fun decodesOk(bytes: ByteArray): Boolean = try {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
        opts.outWidth > 0 && opts.outHeight > 0
    } catch (_: Throwable) {
        false
    }

    // ── MediaCodec AV1 ─────────────────────────────────────────────────────────

    private class Coded(val configObus: ByteArray, val frameObus: ByteArray)

    private fun encodeAv1(
        encoderName: String,
        i420: ByteArray,
        w: Int,
        h: Int,
        quality: Int,
    ): Coded? {
        val codec = MediaCodec.createByCodecName(encoderName)
        try {
            val format = MediaFormat.createVideoFormat(AV1, w, h).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
                )
                // Single still keyframe.
                setInteger(MediaFormat.KEY_FRAME_RATE, 30)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 0)
                // Constant-quality where supported (maps to better size/quality
                // than a guessed bitrate); fall back to a pixel-derived bitrate.
                val caps = codec.codecInfo
                    .getCapabilitiesForType(AV1).encoderCapabilities
                if (caps.isBitrateModeSupported(
                        MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CQ,
                    )
                ) {
                    setInteger(
                        MediaFormat.KEY_BITRATE_MODE,
                        MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CQ,
                    )
                    // CQ: lower = better. Map quality 0–100 → ~[63..10].
                    val cq = (63 - quality.coerceIn(0, 100) * 0.53).toInt().coerceIn(10, 63)
                    setInteger(MediaFormat.KEY_QUALITY, cq)
                } else {
                    setInteger(
                        MediaFormat.KEY_BITRATE_MODE,
                        MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR,
                    )
                    val bpp = 0.6 + (quality.coerceIn(0, 100) / 100.0) * 3.4
                    setInteger(MediaFormat.KEY_BIT_RATE, (w * h * bpp).toInt().coerceAtLeast(64_000))
                }
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()

            val config = ByteArrayOutputStream()
            val frame = ByteArrayOutputStream()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            val deadline = System.currentTimeMillis() + 15_000

            while (!outputDone) {
                if (System.currentTimeMillis() > deadline) return null

                if (!inputDone) {
                    val inIx = codec.dequeueInputBuffer(10_000)
                    if (inIx >= 0) {
                        val buf = codec.getInputBuffer(inIx)!!
                        buf.clear()
                        buf.put(i420)
                        codec.queueInputBuffer(
                            inIx, 0, i420.size, 0,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                        )
                        inputDone = true
                    }
                }

                val outIx = codec.dequeueOutputBuffer(info, 10_000)
                if (outIx >= 0) {
                    val out = codec.getOutputBuffer(outIx)!!
                    val bytes = ByteArray(info.size)
                    out.position(info.offset)
                    out.get(bytes)
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                        config.write(bytes)
                    } else if (info.size > 0) {
                        frame.write(bytes)
                    }
                    codec.releaseOutputBuffer(outIx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                }
            }
            val frameBytes = frame.toByteArray()
            if (frameBytes.isEmpty()) return null
            // The codec-config buffer holds the sequence-header OBU (+ maybe a
            // temporal delimiter). If a device folds config into the frame, we
            // still parse the seq header out of the frame below.
            return Coded(config.toByteArray(), frameBytes)
        } finally {
            try {
                codec.stop()
            } catch (_: Throwable) {
            }
            codec.release()
        }
    }

    // ── AVIF (ISOBMFF) muxer ─────────────────────────────────────────────────

    private fun muxAvif(configObus: ByteArray, frameObus: ByteArray, w: Int, h: Int): ByteArray? {
        // The sequence-header OBU lives in av1C; the frame OBUs live in mdat.
        val seqHeader = findSeqHeaderObu(if (configObus.isNotEmpty()) configObus else frameObus)
            ?: return null
        val seq = parseSeqHeader(seqHeader) ?: return null
        val av1c = buildAv1C(seqHeader, seq)

        // ipco properties (1-based indices): 1=av1C, 2=ispe, 3=pixi, 4=colr.
        val ipco = box(
            "ipco",
            av1c +
                fullBox("ispe", 0, 0, int32(w) + int32(h)) +
                box("pixi", byteArrayOf(0, 0, 0, 0, 3, 8, 8, 8)) +
                box(
                    "colr",
                    "nclx".toByteArray(Charsets.US_ASCII) +
                        int16(1) + int16(13) + int16(6) + // BT.709 primaries/transfer/matrix (SDR)
                        byteArrayOf(if (seq.fullRange) 0x80.toByte() else 0x00),
                ),
        )
        val ipma = fullBox(
            "ipma", 0, 0,
            int32(1) + // entry_count
                int16(1) + // item_ID = 1
                byteArrayOf(4) + // association_count
                byteArrayOf(0x81.toByte()) + // essential + property 1 (av1C)
                byteArrayOf(0x02) + // property 2 (ispe)
                byteArrayOf(0x03) + // property 3 (pixi)
                byteArrayOf(0x04), // property 4 (colr)
        )
        val iprp = box("iprp", ipco + ipma)

        val hdlr = fullBox(
            "hdlr", 0, 0,
            int32(0) + "pict".toByteArray(Charsets.US_ASCII) +
                ByteArray(12) + byteArrayOf(0),
        )
        val pitm = fullBox("pitm", 0, 0, int16(1))
        val infe = fullBox(
            "infe", 2, 0,
            int16(1) + int16(0) + "av01".toByteArray(Charsets.US_ASCII) + byteArrayOf(0),
        )
        val iinf = fullBox("iinf", 0, 0, int16(1) + infe)

        // iloc with a single 4-byte extent; offset patched once total layout is
        // known. construction_method 0 (file offset into mdat).
        fun ilocWith(mdatDataOffset: Int): ByteArray = fullBox(
            "iloc", 0, 0,
            byteArrayOf(0x44, 0x00) + // offset_size=4, length_size=4, base/index=0
                int16(1) + // item_count
                int16(1) + // item_ID
                int16(0) + // data_reference_index
                int16(1) + // extent_count
                int32(mdatDataOffset) +
                int32(frameObus.size),
        )

        val metaNoIloc = { iloc: ByteArray -> fullBox("meta", 0, 0, hdlr + pitm + iinf + iprp + iloc) }
        val ftyp = box(
            "ftyp",
            "avif".toByteArray(Charsets.US_ASCII) + int32(0) +
                "avif".toByteArray(Charsets.US_ASCII) +
                "mif1".toByteArray(Charsets.US_ASCII) +
                "miaf".toByteArray(Charsets.US_ASCII) +
                "MA1B".toByteArray(Charsets.US_ASCII),
        )

        // Two-pass: iloc offset depends on meta size, which depends on iloc size
        // (fixed here), so one correction pass suffices.
        val metaSizeProbe = metaNoIloc(ilocWith(0)).size
        val mdatHeader = 8
        val mdatDataOffset = ftyp.size + metaSizeProbe + mdatHeader
        val meta = metaNoIloc(ilocWith(mdatDataOffset))
        if (meta.size != metaSizeProbe) return null // size must be stable

        val mdat = box("mdat", frameObus)
        return ftyp + meta + mdat
    }

    // ── AV1 OBU helpers ────────────────────────────────────────────────────────

    private class Seq(
        val profile: Int,
        val levelIdx0: Int,
        val tier0: Int,
        val highBitdepth: Boolean,
        val mono: Boolean,
        val subX: Int,
        val subY: Int,
        val fullRange: Boolean,
    )

    /** Scan OBUs for the sequence header (type 1); return its full OBU bytes. */
    private fun findSeqHeaderObu(data: ByteArray): ByteArray? {
        var i = 0
        while (i < data.size) {
            val b0 = data[i].toInt() and 0xFF
            val type = (b0 shr 3) and 0xF
            val hasSize = (b0 shr 1) and 1
            val hasExt = (b0 shr 2) and 1
            var p = i + 1
            if (hasExt == 1) p += 1
            if (hasSize != 1) return null
            val (size, used) = leb128(data, p) ?: return null
            p += used
            val obuEnd = p + size
            if (obuEnd > data.size) return null
            if (type == 1) return data.copyOfRange(i, obuEnd)
            i = obuEnd
        }
        return null
    }

    private fun parseSeqHeader(obu: ByteArray): Seq? {
        return try {
            // Skip the OBU header (1 byte, no extension for seq header) + leb size.
            var p = 1
            val (_, used) = leb128(obu, p) ?: return null
            p += used
            val r = BitReader(obu, p)
            val profile = r.bits(3)
            r.bit() // still_picture
            val reducedStill = r.bit()
            var levelIdx0 = 0
            var tier0 = 0
            if (reducedStill == 1) {
                levelIdx0 = r.bits(5)
            } else {
                val timing = r.bit()
                if (timing == 1) return null // timing_info present → bail (rare)
                val initialDisplayDelayPresent = r.bit()
                val opCnt = r.bits(5) + 1
                for (k in 0 until opCnt) {
                    r.bits(12) // operating_point_idc
                    val lvl = r.bits(5)
                    var tier = 0
                    if (lvl > 7) tier = r.bit()
                    if (initialDisplayDelayPresent == 1 && r.bit() == 1) r.bits(4)
                    if (k == 0) {
                        levelIdx0 = lvl
                        tier0 = tier
                    }
                }
            }
            // We only need profile/level/tier for av1C; the colour fields are
            // fixed by our encoder configuration (8-bit, 4:2:0, limited range),
            // so we don't risk parsing the variable colour_config block.
            Seq(
                profile = profile,
                levelIdx0 = levelIdx0,
                tier0 = tier0,
                highBitdepth = false,
                mono = false,
                subX = 1,
                subY = 1,
                fullRange = false,
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun buildAv1C(seqHeaderObu: ByteArray, s: Seq): ByteArray {
        val b0 = 0x80 or 1 // marker(1)=1, version(7)=1
        val b1 = (s.profile shl 5) or (s.levelIdx0 and 0x1F)
        val b2 = (s.tier0 shl 7) or
            ((if (s.highBitdepth) 1 else 0) shl 6) or
            (0 shl 5) or // twelve_bit
            ((if (s.mono) 1 else 0) shl 4) or
            (s.subX shl 3) or
            (s.subY shl 2) or
            0 // chroma_sample_position
        val b3 = 0 // reserved + initial_presentation_delay absent
        return box(
            "av1C",
            byteArrayOf(b0.toByte(), b1.toByte(), b2.toByte(), b3.toByte()) + seqHeaderObu,
        )
    }

    private fun leb128(data: ByteArray, at: Int): Pair<Int, Int>? {
        var value = 0
        var i = 0
        while (i < 8) {
            if (at + i >= data.size) return null
            val b = data[at + i].toInt() and 0xFF
            value = value or ((b and 0x7F) shl (i * 7))
            i++
            if (b and 0x80 == 0) return Pair(value, i)
        }
        return null
    }

    private class BitReader(val data: ByteArray, startByte: Int) {
        private var bytePos = startByte
        private var bitPos = 0
        fun bit(): Int {
            val b = data[bytePos].toInt() and 0xFF
            val v = (b shr (7 - bitPos)) and 1
            bitPos++
            if (bitPos == 8) {
                bitPos = 0; bytePos++
            }
            return v
        }

        fun bits(n: Int): Int {
            var v = 0
            repeat(n) { v = (v shl 1) or bit() }
            return v
        }
    }

    // ── Box + int helpers ────────────────────────────────────────────────────

    private fun box(type: String, payload: ByteArray): ByteArray {
        val size = 8 + payload.size
        return int32(size) + type.toByteArray(Charsets.US_ASCII) + payload
    }

    private fun fullBox(type: String, version: Int, flags: Int, payload: ByteArray): ByteArray {
        val vf = int32((version shl 24) or (flags and 0xFFFFFF))
        return box(type, vf + payload)
    }

    private fun int32(v: Int): ByteArray = byteArrayOf(
        (v ushr 24).toByte(), (v ushr 16).toByte(), (v ushr 8).toByte(), v.toByte(),
    )

    private fun int16(v: Int): ByteArray = byteArrayOf((v ushr 8).toByte(), v.toByte())

    // ── Pixels ───────────────────────────────────────────────────────────────

    private fun applyOrientation(bmp: Bitmap, src: ByteArray): Bitmap {
        return try {
            val exif = ExifInterface(ByteArrayInputStream(src))
            val o = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
            )
            val m = android.graphics.Matrix()
            when (o) {
                ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.postScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.postScale(1f, -1f)
                else -> return bmp
            }
            Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
        } catch (_: Throwable) {
            bmp
        }
    }

    /** BT.601 limited-range ARGB → I420 (planar Y, U, V). */
    private fun argbToI420(bmp: Bitmap, w: Int, h: Int): ByteArray {
        val argb = IntArray(w * h)
        bmp.getPixels(argb, 0, w, 0, 0, w, h)
        val ySize = w * h
        val cSize = (w / 2) * (h / 2)
        val out = ByteArray(ySize + cSize * 2)
        var uIx = ySize
        var vIx = ySize + cSize
        for (j in 0 until h) {
            for (i in 0 until w) {
                val c = argb[j * w + i]
                val r = (c shr 16) and 0xFF
                val g = (c shr 8) and 0xFF
                val b = c and 0xFF
                val yv = (66 * r + 129 * g + 25 * b + 128 shr 8) + 16
                out[j * w + i] = yv.coerceIn(16, 235).toByte()
                if (j % 2 == 0 && i % 2 == 0) {
                    val uv = (-38 * r - 74 * g + 112 * b + 128 shr 8) + 128
                    val vv = (112 * r - 94 * g - 18 * b + 128 shr 8) + 128
                    out[uIx++] = uv.coerceIn(16, 240).toByte()
                    out[vIx++] = vv.coerceIn(16, 240).toByte()
                }
            }
        }
        return out
    }
}
