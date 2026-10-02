#!/usr/bin/env python3
"""Writes the HEIC and PNG copies of the 12 MP performance photo without Apple's
encoders, for hosts that cannot run make_perf_fixtures.swift (Linux). Every
source format holds the same pixels; WebP and AVIF sources are produced on the
phone by the conversion test itself.

The HEIC comes from libheif, so its bytes differ from the Apple-encoded file the
macOS script writes: compare timings only between runs that used the same
generator (docs/18-PERFORMANCE.md).

Needs: pip install pillow pillow-heif
Usage: python3 test_native/make_perf_fixtures.py build/perf-fixtures
"""
import sys
from pathlib import Path

from PIL import Image
from pillow_heif import register_heif_opener

if len(sys.argv) != 2:
    sys.exit("Pass the fixtures directory")
register_heif_opener()
out = Path(sys.argv[1])

source = Image.open(out / "photo-12mp.jpg")
icc = source.info.get("icc_profile")
image = source.convert("RGB")


def save(name, img, **options):
    if icc:
        options["icc_profile"] = icc
    img.save(out / name, **options)
    print(f"wrote {name}")


save("photo-12mp.heic", image, format="HEIF", quality=80)
save("photo-12mp.png", image, format="PNG")

# The same photo with its left half at alpha 128: a transparent source for the
# JPEG flatten onto white (PERF-01), which opaque sources never reach.
translucent = image.convert("RGBA")
width, height = translucent.size
alpha = Image.new("L", (width, height), 255)
alpha.paste(128, (0, 0, width // 2, height))
translucent.putalpha(alpha)
save("photo-12mp-alpha.png", translucent, format="PNG")
