package app.naqaa.hayn

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.os.Build
import androidx.annotation.RequiresApi
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer

// ─────────────────────────────────────────────────────────────────────────────
// PlatformDecoder — Android's counterpart of the iOS `bakeUpright` (IMG-13).
//
// Flutter hands AVIF/HEIC to Android's ImageDecoder and reads a 10-bit result
// (RGBA_1010102 / RGBA_F16) as if it were 8-bit, so 10-bit images come back
// with scrambled colours. Here the platform decodes them itself into an 8-bit
// ARGB_8888 bitmap, orientation applied, written as a PNG file Flutter reads
// correctly. Three colour modes:
//   keep — sRGB and Display P3 stay as they are (named by cICP), since the
//          source's own profile is carried onto the result afterwards and
//          must describe these pixels (IMG-18). Other spaces go to sRGB.
//   srgb — converted to sRGB, for what Flutter shows. Android's HEIF decoder
//          returns a HEIC's stored values labelled sRGB whatever its profile
//          (IMG-21), even when it reports the profile; the profile's space
//          from DarkLib ([space]) then names them, and they are converted as
//          any other image is. Android 10+; before, the decoder converts.
//   raw  — the values as the decoder reads them, written without a colour
//          tag: the crop works on them and carries the source's profile on.
//
// No tone mapper is verified on Android, so a PQ/HLG source never yields an
// "SDR rendition": with toSdr it returns null and the caller refuses, as
// before (HDR policy, docs/10-DARKLIB.md). A gain map is simply not applied,
// so its SDR base is what comes out. Metadata is not carried here; the Dart
// side carries it through DarkLib. [maxEdge] > 0 (previews) samples the
// decode down by a power of two while the long edge stays at least maxEdge.
// Every failure returns null so callers fall back.
//
// The same decode also writes JPEG (IMG-24), in place of flutter_image_compress,
// which decoded into RGB_565: 5/6/5 bits, banding in every JPEG. Here the
// bitmap is ARGB_8888 and Bitmap.compress encodes it (libjpeg-turbo).
// ─────────────────────────────────────────────────────────────────────────────

object PlatformDecoder {
    /// Decodes [src] upright into a PNG file in [dir]; its path, or null.
    /// The file goes through [PngFile] (PERF-02): banded, fast deflate, never
    /// whole on the Java heap. The caller reads and deletes it. [colours] is
    /// "keep", "srgb" or "raw" (above); [space] the source profile's D50
    /// matrix (9, column-major) and transfer (7), or null. [jpegQuality] in
    /// 1..100 writes a JPEG instead. Skia tags it with the bitmap's space; with
    /// "raw" colours the caller carries the source's profile, which names the
    /// values and replaces that tag (DarkLib's inject, IMG-24).
    fun bakeUprightToFile(
        src: ByteArray,
        toSdr: Boolean,
        maxEdge: Int,
        colours: String,
        space: FloatArray?,
        dir: File,
        jpegQuality: Int = 0,
    ): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        var file: File? = null
        return try {
            val source = ImageDecoder.createSource(ByteBuffer.wrap(src))
            val decoded = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                // Stop at the header: the pixels would be thrown away.
                if (toSdr && isHdrTransfer(info.colorSpace)) throw HdrWithoutToneMap()
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                when (colours) {
                    "raw" -> {}
                    // Converted after the decode (below), where the result's own
                    // label can be checked; before Android 10 by the decoder.
                    "srgb" -> if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
                    }
                    // sRGB and Display P3 are kept as they are (PngFile names
                    // them); anything else goes to sRGB.
                    else -> if (PngFile.cicpOf(info.colorSpace) == null) {
                        decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
                    }
                }
                if (maxEdge > 0) {
                    val longEdge = maxOf(info.size.width, info.size.height)
                    var sample = 1
                    while (longEdge / (sample * 2) >= maxEdge) sample *= 2
                    decoder.setTargetSampleSize(sample)
                }
            }
            var bitmap = if (decoded.config == Bitmap.Config.ARGB_8888) {
                decoded
            } else {
                decoded.copy(Bitmap.Config.ARGB_8888, false) ?: return null
            }
            if (colours == "srgb" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                bitmap = toSrgb(bitmap, space)
            }
            if (jpegQuality in 1..100) {
                file = File.createTempFile("hayn-bake-", ".jpg", dir)
                val written = FileOutputStream(file).buffered(1 shl 16).use {
                    bitmap.compress(Bitmap.CompressFormat.JPEG, jpegQuality, it)
                }
                if (!written) throw IllegalStateException("JPEG encode failed")
            } else {
                file = File.createTempFile("hayn-bake-", ".png", dir)
                PngFile.write(bitmap, file, tagged = colours != "raw")
            }
            file.absolutePath
        } catch (_: Throwable) {
            file?.delete()
            null
        }
    }

    /// [bitmap] in sRGB. A HEIC comes from Android's decoder with its stored
    /// values labelled sRGB, although the decoder reads the profile (it even
    /// reports it, IMG-21); then [space], the profile's own from DarkLib,
    /// names them first. Any other space is converted by drawing.
    @RequiresApi(Build.VERSION_CODES.Q)
    internal fun toSrgb(bitmap: Bitmap, space: FloatArray?): Bitmap {
        val srgb = ColorSpace.get(ColorSpace.Named.SRGB)
        if (bitmap.colorSpace == srgb) {
            val named = profileOf(space) ?: return bitmap
            bitmap.setColorSpace(named)
        }
        val out = Bitmap.createBitmap(
            bitmap.width,
            bitmap.height,
            Bitmap.Config.ARGB_8888,
            bitmap.hasAlpha(),
            srgb,
        )
        Canvas(out).drawBitmap(bitmap, 0f, 0f, null)
        bitmap.recycle()
        return out
    }

    /// [space] (D50 matrix, 9 column-major, then the 7 transfer parameters)
    /// as a colour space; null when absent, sRGB itself, or not accepted.
    private fun profileOf(space: FloatArray?): ColorSpace? {
        if (space == null || space.size != 16) return null
        return try {
            val toXyz = space.copyOfRange(0, 9)
            val t = space.copyOfRange(9, 16).map { it.toDouble() }
            val transfer = ColorSpace.Rgb.TransferParameters(t[0], t[1], t[2], t[3], t[4], t[5], t[6])
            val known = ColorSpace.match(toXyz, transfer)
            when {
                known == ColorSpace.get(ColorSpace.Named.SRGB) -> null
                known != null -> known
                else -> ColorSpace.Rgb("Source profile", toXyz, transfer)
            }
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private class HdrWithoutToneMap : Exception()

    /// PQ and HLG have no parametric transfer; sRGB, Display P3, BT.709 and
    /// SDR BT.2020 do. API 34 also names the two HDR spaces directly.
    private fun isHdrTransfer(space: ColorSpace?): Boolean {
        if (space == null) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            if (space == ColorSpace.get(ColorSpace.Named.BT2020_PQ) ||
                space == ColorSpace.get(ColorSpace.Named.BT2020_HLG)
            ) {
                return true
            }
        }
        return space is ColorSpace.Rgb && space.transferParameters == null
    }
}
