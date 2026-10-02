package app.naqaa.hayn

import android.graphics.Bitmap
import android.graphics.ColorSpace
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.util.zip.CRC32
import java.util.zip.Deflater
import java.util.zip.DeflaterOutputStream

// ─────────────────────────────────────────────────────────────────────────────
// PngFile — an ARGB_8888 bitmap written to a PNG file in bands (PERF-02).
//
// Bitmap.compress(PNG) deflates at a slow level and builds the whole file in a
// ByteArray on the Java heap, which is capped (256 MB on a Galaxy S25 Edge):
// a large PNG killed the app there (RUN-01), and a 12 MP decode for display
// took over 3 s. Here pixels go to a file band by band, deflated at the
// fastest level with the Sub filter, so the Java heap holds one band.
//
// Pixels keep the bitmap's own colour space: getPixels() would convert them
// to sRGB, so each band is copied raw (copyPixelsToBuffer, premultiplied RGBA)
// and un-premultiplied. The space is named by a cICP chunk (sRGB or Display
// P3); DarkLib reads cICP as a colour profile (IMG-08), and the caller carries
// the source's own profile on top. Any other space is refused here: the caller
// decodes to sRGB instead.
// ─────────────────────────────────────────────────────────────────────────────

object PngFile {
    private const val BAND_ROWS = 256

    /// cICP (primaries, transfer, matrix, full range) for the spaces written.
    fun cicpOf(space: ColorSpace?): ByteArray? = when (space) {
        ColorSpace.get(ColorSpace.Named.SRGB) -> byteArrayOf(1, 13, 0, 1)
        ColorSpace.get(ColorSpace.Named.DISPLAY_P3) -> byteArrayOf(12, 13, 0, 1)
        else -> null
    }

    /// [tagged] = false writes no cICP: the values as they are, for a caller
    /// that names them itself (the crop's raw mode).
    fun write(bitmap: Bitmap, file: File, tagged: Boolean = true) {
        require(bitmap.config == Bitmap.Config.ARGB_8888)
        val cicp = if (tagged) {
            requireNotNull(cicpOf(bitmap.colorSpace)) { "unsupported colour space" }
        } else {
            null
        }
        val w = bitmap.width
        val h = bitmap.height
        DataOutputStream(BufferedOutputStream(FileOutputStream(file), 1 shl 16)).use { out ->
            out.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
            chunk(out, "IHDR", ByteBuffer.allocate(13).putInt(w).putInt(h)
                .put(8).put(6).put(0).put(0).put(0).array())
            if (cicp != null) chunk(out, "cICP", cicp)
            val deflater = Deflater(Deflater.BEST_SPEED)
            try {
                DeflaterOutputStream(IdatStream(out), deflater, 1 shl 16).use { z ->
                    val line = ByteArray(1 + w * 4)
                    line[0] = 1 // Sub filter
                    val raw = ByteArray(w * 4)
                    var y = 0
                    while (y < h) {
                        val rows = minOf(BAND_ROWS, h - y)
                        val band = Bitmap.createBitmap(bitmap, 0, y, w, rows)
                        val buffer = ByteBuffer.allocateDirect(w * rows * 4)
                        band.copyPixelsToBuffer(buffer)
                        if (band !== bitmap) band.recycle()
                        buffer.rewind()
                        for (r in 0 until rows) {
                            buffer.get(raw)
                            unpremultiply(raw)
                            // Sub: each byte minus the same channel one pixel left.
                            for (i in 0 until 4) line[1 + i] = raw[i]
                            for (i in 4 until raw.size) {
                                line[1 + i] = (raw[i] - raw[i - 4]).toByte()
                            }
                            z.write(line)
                        }
                        y += rows
                    }
                }
            } finally {
                deflater.end()
            }
            chunk(out, "IEND", ByteArray(0))
        }
    }

    private fun unpremultiply(rgba: ByteArray) {
        var i = 0
        while (i < rgba.size) {
            val a = rgba[i + 3].toInt() and 0xff
            if (a != 255) {
                for (c in 0 until 3) {
                    val v = rgba[i + c].toInt() and 0xff
                    rgba[i + c] = if (a == 0) 0 else minOf(255, (v * 255 + a / 2) / a).toByte()
                }
            }
            i += 4
        }
    }

    private fun chunk(out: DataOutputStream, type: String, data: ByteArray) {
        val crc = CRC32()
        val t = type.toByteArray(Charsets.US_ASCII)
        out.writeInt(data.size)
        out.write(t)
        out.write(data)
        crc.update(t)
        crc.update(data)
        out.writeInt(crc.value.toInt())
    }

    /// Deflated bytes cut into IDAT chunks of up to 64 KiB.
    private class IdatStream(private val out: DataOutputStream) : OutputStream() {
        private val buf = ByteArray(1 shl 16)
        private var n = 0

        override fun write(b: Int) {
            buf[n++] = b.toByte()
            if (n == buf.size) flushChunk()
        }

        override fun write(b: ByteArray, off: Int, len: Int) {
            var o = off
            var left = len
            while (left > 0) {
                val k = minOf(left, buf.size - n)
                System.arraycopy(b, o, buf, n, k)
                n += k
                o += k
                left -= k
                if (n == buf.size) flushChunk()
            }
        }

        override fun close() = flushChunk()

        private fun flushChunk() {
            if (n == 0) return
            chunk(out, "IDAT", buf.copyOf(n))
            n = 0
        }
    }
}
