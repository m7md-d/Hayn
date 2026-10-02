#!/usr/bin/env python3
"""Writes the HEIC and PNG copies of the 12 MP performance photo without Apple's
encoders, for hosts that cannot run make_perf_fixtures.swift (Linux). Every
source format holds the same pixels; WebP and AVIF sources are produced on the
phone by the conversion test itself.

The HEIC comes from libheif, so its bytes differ from the Apple-encoded file the
macOS script writes: compare timings only between runs that used the same
generator (docs/18-PERFORMANCE.md).

With --alpha-heic it writes only photo-12mp-alpha.heic (the transparent copy
as HEIC), for hosts that made the others with Apple's encoders.
With --large it writes only photo-200mp.jpg instead: the photo enlarged four
times on each side (16128x12096, about 195 MP), the size of a 200 MP camera's
output, for the RUN-01 memory test (integration_test/large_image_test.dart).

Needs: pip install pillow pillow-heif
Usage: python3 test_native/make_perf_fixtures.py build/perf-fixtures [--large | --alpha-heic]
"""
import sys
from pathlib import Path

from PIL import Image

if len(sys.argv) not in (2, 3) or sys.argv[2:] not in ([], ["--large"], ["--alpha-heic"]):
    sys.exit("Pass the fixtures directory, and --large or --alpha-heic")
out = Path(sys.argv[1])

source = Image.open(out / "photo-12mp.jpg")
icc = source.info.get("icc_profile")
image = source.convert("RGB")


def save(name, img, **options):
    if icc:
        options["icc_profile"] = icc
    img.save(out / name, **options)
    print(f"wrote {name}")


if sys.argv[2:] == ["--large"]:
    Image.MAX_IMAGE_PIXELS = None  # our own enlargement, not an untrusted file
    w, h = image.size
    save("photo-200mp.jpg", image.resize((w * 4, h * 4), Image.LANCZOS),
         format="JPEG", quality=92)
    sys.exit(0)

from pillow_heif import register_heif_opener  # noqa: E402

register_heif_opener()
only_alpha_heic = sys.argv[2:] == ["--alpha-heic"]

if not only_alpha_heic:
    save("photo-12mp.heic", image, format="HEIF", quality=80)
    save("photo-12mp.png", image, format="PNG")

# The same photo with its left half at alpha 128: a transparent source for the
# JPEG flatten onto white (PERF-01), which opaque sources never reach.
translucent = image.convert("RGBA")
width, height = translucent.size
alpha = Image.new("L", (width, height), 255)
alpha.paste(128, (0, 0, width // 2, height))
translucent.putalpha(alpha)
if not only_alpha_heic:
    save("photo-12mp-alpha.png", translucent, format="PNG")
# The same as HEIC: libheif codes its alpha as monochrome HEVC like Apple, the
# plane Android's decoder drops (IMG-15).
save("photo-12mp-alpha.heic", translucent, format="HEIF", quality=80)
