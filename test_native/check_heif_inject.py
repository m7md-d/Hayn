"""Independent check of DarkLib's metadata injection into an idat grid HEIF.

`cargo test --test heif_inject` writes the Android HeifWriter fixture and its
copy with EXIF and an ICC profile added (target/tmp/heif-inject). libheif (not
DarkLib's code) must decode both to the same pixels and size, and must find
the profile and the EXIF in the copy (RUN-01 step 5).

Usage (Pillow + pillow-heif, as in ~/hayn-venv):
  ~/hayn-venv/bin/python test_native/check_heif_inject.py native/darklib
"""
import os
import sys

import pillow_heif
from PIL import Image

pillow_heif.register_heif_opener()
out = os.path.join(sys.argv[1], "target", "tmp", "heif-inject")
src = Image.open(os.path.join(out, "source.heic"))
dst = Image.open(os.path.join(out, "with_metadata.heic"))
print(f"libheif {pillow_heif.libheif_version()}")

failures = []
if src.size != dst.size:
    failures.append(f"size {src.size} -> {dst.size}")
if src.convert("RGB").tobytes() != dst.convert("RGB").tobytes():
    failures.append("pixels differ")
if not dst.info.get("icc_profile"):
    failures.append("no ICC profile")
if not dst.info.get("exif"):
    failures.append("no EXIF")
for f in failures:
    print("FAIL", f)
print("ok" if not failures else f"{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
