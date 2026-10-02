package app.naqaa.hayn

import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.os.Build
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

// ─────────────────────────────────────────────────────────────────────────────
// PlatformDecoder — Android's counterpart of the iOS `bakeUpright` (IMG-13).
//
// Flutter hands AVIF/HEIC to Android's ImageDecoder and reads a 10-bit result
// (RGBA_1010102 / RGBA_F16) as if it were 8-bit, so 10-bit images come back
// with scrambled colours. Here the platform decodes them itself into an 8-bit
// ARGB_8888 bitmap, orientation applied, and returns a PNG that Flutter reads
// correctly. [srgb] converts the colours to sRGB, for what Flutter shows or
// crops; without it a conversion keeps the source's colour space (Display P3
// stays P3, its profile in the PNG), since the source's own profile is carried
// onto the result afterwards and must describe these pixels (IMG-08/IMG-15).
//
// No tone mapper is verified on Android, so a PQ/HLG source never yields an
// "SDR rendition": with toSdr it returns null and the caller refuses, as
// before (HDR policy, docs/10-DARKLIB.md). A gain map is simply not applied,
// so its SDR base is what comes out. Metadata is not carried; the Dart side
// only asks without it. [maxEdge] > 0 (previews) samples the decode down by a
// power of two while the long edge stays at least maxEdge. Every failure
// returns null so callers fall back.
// ─────────────────────────────────────────────────────────────────────────────

object PlatformDecoder {
    fun bakeUprightPng(src: ByteArray, toSdr: Boolean, maxEdge: Int, srgb: Boolean): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        return try {
            val source = ImageDecoder.createSource(ByteBuffer.wrap(src))
            val decoded = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                // Stop at the header: the pixels would be thrown away.
                if (toSdr && isHdrTransfer(info.colorSpace)) throw HdrWithoutToneMap()
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                // An 8-bit bitmap holds an SDR RGB space as is; anything else
                // (no profile, extended or linear ranges) goes to sRGB.
                if (srgb || !isSdrRgb(info.colorSpace)) {
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
            val out = ByteArrayOutputStream()
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) return null
            out.toByteArray()
        } catch (_: Throwable) {
            null
        }
    }

    private class HdrWithoutToneMap : Exception()

    private fun isSdrRgb(space: ColorSpace?): Boolean =
        space is ColorSpace.Rgb && space.transferParameters != null &&
            space.getMinValue(0) == 0f && space.getMaxValue(0) == 1f

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
