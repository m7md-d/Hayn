"""Independent check of DarkLib's streaming JPEG re-encode (Hayn RUN-01 step 6).

Reads the outputs the Android device test keeps (`results/jpeg-paths`, both
paths at quality 80) with code that is not DarkLib's: the MP Entry list by the
CIPA DC-007 layout, the segments by their lengths, the pixels by Pillow
(libjpeg-turbo). For each stream output against its source:

- the images after the primary start with SOI at their MPF offsets and are
  byte-identical to the source's, and the primary's MPF size ends at its EOI;
- the source's EXIF, XMP and ICC segments are there, byte for byte;
- Pillow decodes it, at the source's stored size;
- shown upright (EXIF orientation applied), its pixels are the platform
  path's output pixels, for a source stored upright.

Usage (Pillow, see docs/20-LINUX-WORKFLOW.md):
  ~/hayn-venv/bin/python test_native/check_jpeg_stream.py \
      native/darklib/tests/fixtures build/android-device/<run>/results/jpeg-paths
"""
import io
import os
import struct
import sys

from PIL import Image, ImageChops, ImageOps

fixtures, results = sys.argv[1], sys.argv[2]
SOURCES = {
    "ultrahdr": "seine_sdr_gainmap_srgb.jpg",
    "apple-gainmap": "apple_gainmap_new.jpg",
}


def segments(b):
    """(marker, start, end) of each segment before the first scan."""
    out, i = [], 2
    while True:
        assert b[i] == 0xFF, f"no marker at {i}"
        m = b[i + 1]
        n = struct.unpack(">H", b[i + 2 : i + 4])[0]
        out.append((m, i, i + 2 + n))
        if m == 0xDA:
            return out
        i += 2 + n


def primary_end(b):
    sos = segments(b)[-1][1]
    return b.index(b"\xff\xd9", sos) + 2


def kept(b):
    """The EXIF, XMP and ICC segments, as bytes."""
    names = (b"Exif\0\0", b"http://ns.adobe.com/xap/1.0/\0", b"ICC_PROFILE\0")
    return [
        b[s:e]
        for m, s, e in segments(b)
        if m in (0xE1, 0xE2) and b[s + 4 : e].startswith(names)
    ]


def mpf_images(b):
    """(offset from file start, size) of each MP entry; the primary first."""
    for m, s, e in segments(b):
        if m == 0xE2 and b[s + 4 : s + 8] == b"MPF\0":
            tiff = s + 8
            le = b[tiff : tiff + 2] == b"II"
            u16 = "<H" if le else ">H"
            u32 = "<I" if le else ">I"
            ifd = tiff + struct.unpack(u32, b[tiff + 4 : tiff + 8])[0]
            count = struct.unpack(u16, b[ifd : ifd + 2])[0]
            for k in range(count):
                e0 = ifd + 2 + 12 * k
                if struct.unpack(u16, b[e0 : e0 + 2])[0] == 0xB002:
                    n = struct.unpack(u32, b[e0 + 4 : e0 + 8])[0] // 16
                    at = tiff + struct.unpack(u32, b[e0 + 8 : e0 + 12])[0]
                    out = []
                    for j in range(n):
                        size, off = struct.unpack(u32[0] + "II", b[at + 16 * j + 4 : at + 16 * j + 12])
                        out.append((0 if off == 0 else tiff + off, size))
                    return out
    return []


def upright(b):
    return ImageOps.exif_transpose(Image.open(io.BytesIO(b))).convert("RGB")


failures = 0
names = sorted(f[: -len("-stream.jpg")] for f in os.listdir(results) if f.endswith("-stream.jpg"))
for name in names:
    stream = open(os.path.join(results, f"{name}-stream.jpg"), "rb").read()
    platform = open(os.path.join(results, f"{name}-platform.jpg"), "rb").read()
    problems = []
    image = Image.open(io.BytesIO(stream))
    image.load()
    if name in SOURCES:
        source = open(os.path.join(fixtures, SOURCES[name]), "rb").read()
        if (image.width, image.height) != Image.open(io.BytesIO(source)).size:
            problems.append("stored size differs from the source")
        if kept(stream) != kept(source):
            problems.append("EXIF/XMP/ICC differ from the source")
        theirs, ours = mpf_images(source), mpf_images(stream)
        if len(theirs) != len(ours):
            problems.append(f"MP entries {len(ours)} vs {len(theirs)}")
        for (o1, n1), (o2, n2) in zip(theirs[1:], ours[1:]):
            if stream[o2 : o2 + 2] != b"\xff\xd8" or stream[o2 : o2 + n2] != source[o1 : o1 + n1]:
                problems.append(f"MP image at {o2} is not the source's")
            else:
                Image.open(io.BytesIO(stream[o2 : o2 + n2])).load()
        if ours and ours[0][1] != primary_end(stream):
            problems.append("primary MP size does not end at its EOI")
    if ImageOps.exif_transpose(Image.open(io.BytesIO(platform))).size != upright(stream).size:
        problems.append("upright sizes differ between the paths")
    elif Image.open(io.BytesIO(stream)).getexif().get(0x0112, 1) == 1:
        diff = ImageChops.difference(upright(platform), upright(stream)).getextrema()
        if max(hi for _, hi in diff) != 0:
            problems.append(f"pixels differ from the platform path: {diff}")
    status = "ok" if not problems else "FAIL: " + "; ".join(problems)
    failures += bool(problems)
    print(f"{name}: {len(mpf_images(stream))} MP entries, {status}")
sys.exit(1 if failures else 0)
