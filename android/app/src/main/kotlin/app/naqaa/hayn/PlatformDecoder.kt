package app.naqaa.hayn

import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.os.Build
import java.io.File
import java.nio.ByteBuffer

// ─────────────────────────────────────────────────────────────────────────────
// PlatformDecoder — Android's counterpart of the iOS `bakeUpright` (IMG-13).
//
// Flutter hands AVIF/HEIC to Android's ImageDecoder and reads a 10-bit result
// (RGBA_1010102 / RGBA_F16) as if it were 8-bit, so 10-bit images come back
// with scrambled colours. Here the platform decodes them itself into an 8-bit
// ARGB_8888 bitmap, orientation applied, written as a PNG file Flutter reads
// correctly. [srgb] converts the colours to sRGB, for what Flutter shows or
// crops; without it sRGB and Display P3 stay as they are (named by cICP),
// since the source's own profile is carried onto the result afterwards and
// must describe these pixels (IMG-18). Other spaces go to sRGB.
//
// No tone mapper is verified on Android, so a PQ/HLG source never yields an
// "SDR rendition": with toSdr it returns null and the caller refuses, as
// before (HDR policy, docs/10-DARKLIB.md). A gain map is simply not applied,
// so its SDR base is what comes out. Metadata is not carried here; the Dart
// side carries it through DarkLib. [maxEdge] > 0 (previews) samples the
// decode down by a power of two while the long edge stays at least maxEdge.
// Every failure returns null so callers fall back.
// ─────────────────────────────────────────────────────────────────────────────

object PlatformDecoder {
    /// Decodes [src] upright into a PNG file in [dir]; its path, or null.
    /// The file goes through [PngFile] (PERF-02): banded, fast deflate, never
    /// whole on the Java heap. The caller reads and deletes it.
    fun bakeUprightToFile(
        src: ByteArray,
        toSdr: Boolean,
        maxEdge: Int,
        srgb: Boolean,
        dir: File,
    ): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        var file: File? = null
        return try {
            val source = ImageDecoder.createSource(ByteBuffer.wrap(src))
            val decoded = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                // Stop at the header: the pixels would be thrown away.
                if (toSdr && isHdrTransfer(info.colorSpace)) throw HdrWithoutToneMap()
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                // sRGB and Display P3 are kept as they are (PngFile names
                // them); anything else, or a request for sRGB, goes to sRGB.
                if (srgb || PngFile.cicpOf(info.colorSpace) == null) {
                    decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
                }
                if (maxEdge > 0) {
                    val longEdge = maxOf(info.size.width, info.size.height)
                    var sample = 1
                    while (longEdge / (sample * 2) >= maxEdge) sample *= 2
                    decoder.setTargetSampleSize(sample)
                }
            }
            val bitmap = if (decoded.config == Bitmap.Config.ARGB_8888) {
                decoded
            } else {
                decoded.copy(Bitmap.Config.ARGB_8888, false) ?: return null
            }
            file = File.createTempFile("hayn-bake-", ".png", dir)
            PngFile.write(bitmap, file)
            file.absolutePath
        } catch (_: Throwable) {
            file?.delete()
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
