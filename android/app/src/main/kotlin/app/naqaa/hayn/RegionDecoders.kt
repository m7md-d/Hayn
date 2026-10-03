package app.naqaa.hayn

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Matrix
import android.graphics.Rect
import android.os.Build
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Semaphore

// ─────────────────────────────────────────────────────────────────────────────
// RegionDecoders — the pixels of one part of an image, at one level of detail
// (PERF-03, docs/23-LARGE-IMAGES.md §4). The viewer and the compare screen
// show a screen-sized rendition from afar and ask for the tiles in view when
// zoomed, so no image is ever decoded whole for display, whatever its size.
//
// BitmapRegionDecoder reads the STORED pixels: it applies neither the EXIF
// orientation nor `irot`/`imir`. The caller passes the EXIF-style code
// (DarkLib `inspect`), rectangles arrive in upright coordinates, and each tile
// is mapped to the stored image, decoded, then turned upright. Colours go to
// sRGB as the display bridge does (PlatformDecoder.toSrgb, IMG-21): [space]
// names a HEIC's stored values that the decoder labels sRGB.
//
// The source is a file the caller wrote; it is deleted on close. A tile is
// premultiplied RGBA 8-bit, the layout Flutter's rgba8888 takes. Every
// failure returns null, and the caller keeps its rendition.
// ─────────────────────────────────────────────────────────────────────────────

object RegionDecoders {
    private const val TAG = "RegionDecoders"

    /// Open images past this are closed oldest first: a page the caller
    /// never closed (a crash in Dart) cannot pin files and native memory.
    private const val MAX_OPEN = 6

    /// Decoders per image. One decoder serialises its regions, and a JPEG
    /// region re-reads the entropy-coded data from the start of the scan:
    /// two let the two region threads work on one image together.
    private const val DECODERS_PER_IMAGE = 2

    private class Entry(
        val path: String,
        first: BitmapRegionDecoder,
        val orientation: Int,
        val space: FloatArray?,
    ) {
        val storedW = first.width
        val storedH = first.height
        val turned = orientation in 5..8
        val width get() = if (turned) storedH else storedW
        val height get() = if (turned) storedW else storedH
        val permits = Semaphore(DECODERS_PER_IMAGE)
        val idle = ArrayDeque<BitmapRegionDecoder>().apply { add(first) }
        var closed = false
    }

    private val open = LinkedHashMap<Int, Entry>()
    private var nextId = 1

    class Opened(val id: Int, val width: Int, val height: Int)

    /// A decoder over [path]; null when the platform cannot read it by
    /// regions (AVIF, GIF, an unknown file). [path] is deleted then too.
    fun open(path: String, orientation: Int, space: FloatArray?): Opened? {
        val decoder = newDecoder(path)
        if (decoder == null || decoder.width <= 0 || decoder.height <= 0) {
            decoder?.recycle()
            File(path).delete()
            return null
        }
        val entry = Entry(path, decoder, orientation, space)
        val (id, stale) = synchronized(this) {
            val id = nextId++
            open[id] = entry
            val out = mutableListOf<Entry>()
            while (open.size > MAX_OPEN) {
                out += open.remove(open.keys.first())!!
            }
            Pair(id, out)
        }
        stale.forEach(::release)
        return Opened(id, entry.width, entry.height)
    }

    private fun newDecoder(path: String): BitmapRegionDecoder? = try {
        @Suppress("DEPRECATION")
        BitmapRegionDecoder.newInstance(path, false)
    } catch (e: Throwable) {
        Log.w(TAG, "no region decoder: ${e.javaClass.simpleName}")
        null
    }

    fun close(id: Int) {
        val entry = synchronized(this) { open.remove(id) } ?: return
        release(entry)
    }

    /// Idle decoders go now, busy ones when they come back; the file goes
    /// at once (an open file outlives its name).
    private fun release(entry: Entry) {
        synchronized(entry) {
            entry.closed = true
            entry.idle.forEach { it.recycle() }
            entry.idle.clear()
        }
        File(entry.path).delete()
    }

    /// An idle decoder of [entry], or a new one: a permit stands for one
    /// decoder, idle or yet to be made.
    private fun acquire(entry: Entry): BitmapRegionDecoder? {
        entry.permits.acquire()
        synchronized(entry) {
            if (entry.closed) {
                entry.permits.release()
                return null
            }
            entry.idle.removeFirstOrNull()?.let { return it }
        }
        return newDecoder(entry.path) ?: run {
            entry.permits.release()
            null
        }
    }

    private fun giveBack(entry: Entry, decoder: BitmapRegionDecoder) {
        synchronized(entry) {
            if (entry.closed) decoder.recycle() else entry.idle.addLast(decoder)
        }
        entry.permits.release()
    }

    class Tile(val width: Int, val height: Int, val pixels: ByteArray)

    /// The upright rectangle [left, top, right, bottom) of image [id], sampled
    /// down by [sample] (a power of two) and cut at the upright x positions
    /// [cuts] into tiles, left to right. One decode for the whole row: a JPEG
    /// region costs the entropy-coded data before it, whatever its width.
    fun tiles(
        id: Int,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        cuts: IntArray,
        sample: Int,
    ): List<Tile>? {
        val entry = synchronized(this) { open[id] } ?: return null
        val decoder = acquire(entry) ?: return null
        return try {
            val l = left.coerceIn(0, entry.width)
            val t = top.coerceIn(0, entry.height)
            val r = right.coerceIn(l, entry.width)
            val b = bottom.coerceIn(t, entry.height)
            if (r <= l || b <= t) return null
            val s = sample.coerceAtLeast(1)
            val options = BitmapFactory.Options().apply {
                inSampleSize = s
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val decoded = decoder.decodeRegion(stored(entry, l, t, r, b), options) ?: return null
            var bitmap = if (decoded.config == Bitmap.Config.ARGB_8888) {
                decoded
            } else {
                // A 10-bit HEIC comes as RGBA_1010102 or F16.
                decoded.copy(Bitmap.Config.ARGB_8888, false).also { decoded.recycle() }
                    ?: return null
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                bitmap = PlatformDecoder.toSrgb(bitmap, entry.space)
            }
            bitmap = upright(bitmap, entry.orientation)
            val edges = (listOf(l) + cuts.filter { it in (l + 1) until r } + listOf(r))
                .map { ((it - l) / s).coerceAtMost(bitmap.width) }
            val out = edges.zipWithNext().mapNotNull { (x0, x1) ->
                if (x1 <= x0) return@mapNotNull null
                val part = Bitmap.createBitmap(bitmap, x0, 0, x1 - x0, bitmap.height)
                val pixels = ByteBuffer.allocate(part.byteCount)
                part.copyPixelsToBuffer(pixels) // premultiplied, R G B A
                Tile(part.width, part.height, pixels.array()).also {
                    if (part !== bitmap) part.recycle()
                }
            }
            bitmap.recycle()
            out
        } catch (e: Throwable) {
            Log.w(TAG, "tiles failed: ${e.javaClass.simpleName}")
            null
        } finally {
            giveBack(entry, decoder)
        }
    }

    /// The stored-pixel rectangle under an upright one. [orientation] is the
    /// EXIF code that turns the stored image upright.
    internal fun storedRect(
        orientation: Int,
        storedW: Int,
        storedH: Int,
        l: Int,
        t: Int,
        r: Int,
        b: Int,
    ): IntArray {
        val w = storedW
        val h = storedH
        return when (orientation) {
            2 -> intArrayOf(w - r, t, w - l, b)
            3 -> intArrayOf(w - r, h - b, w - l, h - t)
            4 -> intArrayOf(l, h - b, r, h - t)
            5 -> intArrayOf(t, l, b, r)
            6 -> intArrayOf(t, h - r, b, h - l)
            7 -> intArrayOf(w - b, h - r, w - t, h - l)
            8 -> intArrayOf(w - b, l, w - t, r)
            else -> intArrayOf(l, t, r, b)
        }
    }

    private fun stored(entry: Entry, l: Int, t: Int, r: Int, b: Int): Rect {
        val s = storedRect(entry.orientation, entry.storedW, entry.storedH, l, t, r, b)
        return Rect(s[0], s[1], s[2], s[3])
    }

    /// [bitmap] (stored orientation) turned upright.
    private fun upright(bitmap: Bitmap, orientation: Int): Bitmap {
        val m = Matrix()
        when (orientation) {
            2 -> m.setScale(-1f, 1f)
            3 -> m.setRotate(180f)
            4 -> m.setScale(1f, -1f)
            5 -> { m.setRotate(90f); m.postScale(-1f, 1f) }
            6 -> m.setRotate(90f)
            7 -> { m.setRotate(90f); m.postScale(1f, -1f) }
            8 -> m.setRotate(270f)
            else -> return bitmap
        }
        val out = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, false)
        if (out !== bitmap) bitmap.recycle()
        return out
    }
}
