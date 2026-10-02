"""Independent check of the phone's HEIC outputs (RUN-01 step 5, IMG-21).

Android's own decoder ignores the colour profile of every HEIC on the Galaxy
S25 Edge, so colour is judged here: libheif decodes (applying irot/imir), and
LittleCMS (Pillow's ImageCms) turns each file's profile into sRGB. A PNG is
read by PNG-3 precedence: cICP before iCCP.

1. heic-tiles/WxH-oN.heic: the tiled encoder's output for a JPEG of four
   flat quadrants whose EXIF names orientation N. Upright, the quadrants
   must be where the EXIF transform puts them.
2. heic-tiles/p3.heic against heic-tiles/p3-source.jpg: the same colours
   after colour management.
3. p3heic/*: the Android bridge's WebP and PNG from Apple's P3 HEIC, against
   the source through libheif (IMG-18/21).
4. crop-p3/*: the crop task's outputs from P3 sources (HAYN_GALLERY=1 runs),
   against the colours LittleCMS gives the P3 quadrants.

Usage (Pillow + pillow-heif, as in ~/hayn-venv):
  ~/hayn-venv/bin/python test_native/check_heic_tiles.py \
      build/android-device/<run>/results native/darklib/tests/fixtures
"""
import glob
import io
import os
import struct
import sys

import pillow_heif
from PIL import Image, ImageCms

pillow_heif.register_heif_opener()
results, fixtures = sys.argv[1], sys.argv[2]
failures = []
SRGB = ImageCms.createProfile("sRGB")

# Display P3: P3 primaries, D65, the sRGB curve. Only for PNG cICP 12/13.
P3_ICC = Image.open(os.path.join(fixtures, "apple_png_p3_icc.png")).info["icc_profile"]


def png_cicp(path):
    b = open(path, "rb").read()
    i = 8
    while i + 8 <= len(b):
        n, t = struct.unpack(">I4s", b[i:i + 8])
        if t == b"cICP":
            return tuple(b[i + 8:i + 12])
        i += 12 + n
    return None


def managed(path):
    """The image upright, in sRGB, as a colour-managed viewer shows it."""
    im = Image.open(path)
    im.load()
    rgb = im.convert("RGB")
    icc = im.info.get("icc_profile")
    if path.endswith(".png"):
        cicp = png_cicp(path)
        if cicp is not None:
            if cicp[:2] == (1, 13):
                return rgb
            if cicp[:2] == (12, 13):
                icc = P3_ICC
            else:
                failures.append(f"{path}: cICP {cicp} not handled here")
    if not icc:
        return rgb
    src = ImageCms.ImageCmsProfile(io.BytesIO(icc))
    return ImageCms.profileToProfile(rgb, src, SRGB)


def close(a, b, tol):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


# 1. Orientation: where the quadrant colours land.
COLOURS = {"r": (220, 40, 40), "g": (40, 200, 60), "b": (40, 60, 220), "y": (230, 210, 40)}
EXIF = {
    1: lambda m: m,
    2: lambda m: [r[::-1] for r in m],
    3: lambda m: [r[::-1] for r in m[::-1]],
    4: lambda m: m[::-1],
    5: lambda m: [list(r) for r in zip(*m)],
    6: lambda m: [list(r) for r in zip(*m[::-1])],
    7: lambda m: [list(r) for r in zip(*[r[::-1] for r in m][::-1])],
    8: lambda m: [list(r) for r in zip(*m)][::-1],
}
for path in sorted(glob.glob(os.path.join(results, "heic-tiles", "*-o*.heic"))):
    name = os.path.basename(path)
    w, h = map(int, name.split("-")[0].split("x"))
    o = int(name.split("-o")[1].split(".")[0])
    grid = EXIF[o]([["r", "g"], ["b", "y"]])
    im = Image.open(path).convert("RGB")
    want = (h, w) if o >= 5 else (w, h)
    if im.size != want:
        failures.append(f"{name}: size {im.size}, want {want}")
        continue
    for qy in range(2):
        for qx in range(2):
            p = im.getpixel((im.width * (1 + 2 * qx) // 4, im.height * (1 + 2 * qy) // 4))
            if not close(p, COLOURS[grid[qy][qx]], 12):
                failures.append(f"{name}: quadrant {qx},{qy} is {p}, want {grid[qy][qx]}")
    print(f"{name}: {im.size}")

# 2. The P3 tiles output against its source.
src = managed(os.path.join(results, "heic-tiles", "p3-source.jpg"))
out = managed(os.path.join(results, "heic-tiles", "p3.heic"))
for x, y in [(64, 48), (192, 48), (64, 144), (192, 144)]:
    a, b = src.getpixel((x, y)), out.getpixel((x, y))
    print(f"p3 at {x},{y}: source {a} heic {b}")
    # Lossy at quality 95 (stored values within 2); P3 to sRGB stretches
    # that near the gamut edge.
    if not close(a, b, 8):
        failures.append(f"p3.heic at {x},{y}: {b}, source {a}")

# 3. The bridge's outputs from Apple's P3 HEIC.
ref = managed(os.path.join(fixtures, "apple_heic_10bit_p3.heic"))
for path in sorted(glob.glob(os.path.join(results, "p3heic", "*"))):
    got = managed(path)
    err = []
    for y in range(0, ref.height, 9):
        for x in range(0, ref.width, 9):
            a, b = ref.getpixel((x, y)), got.getpixel((x, y))
            err.append(sum(abs(i - j) for i, j in zip(a, b)) / 3)
    mean = sum(err) / len(err)
    print(f"p3heic/{os.path.basename(path)}: mean error {mean:.1f}")
    if mean > 4:
        failures.append(f"p3heic/{os.path.basename(path)}: mean error {mean:.1f}")

# 4. The crop's outputs from P3 sources (IMG-21): the colours LittleCMS gives
# the source, at the quadrant centres of the 64x48 image.
P3_SHOWN = [(240, 0, 23), (0, 204, 12), (34, 61, 228), (235, 209, 0)]
for path in sorted(glob.glob(os.path.join(results, "crop-p3", "*"))):
    got = managed(path)
    for q, want in enumerate(P3_SHOWN):
        p = got.getpixel((16 + 32 * (q % 2), 12 + 24 * (q // 2)))
        if not close(p, want, 6):
            failures.append(f"crop-p3/{os.path.basename(path)} quadrant {q}: {p}, want {want}")
    print(f"crop-p3/{os.path.basename(path)}: {Image.open(path).format}")

for f in failures:
    print("FAIL", f)
print("ok" if not failures else f"{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
