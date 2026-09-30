"""Writes WebP fixtures with libwebp through Pillow, a writer independent of
DarkLib, for the container alpha check (Hayn IMG-16). Synthetic content, so no
licence applies. Output: native/darklib/tests/fixtures/pillow_webp_*.webp

Usage (Pillow in a throwaway venv):
  python3 -m venv /tmp/pillow && /tmp/pillow/bin/pip install pillow
  /tmp/pillow/bin/python test_native/make_webp_fixtures.py native/darklib/tests/fixtures
"""
import os
import sys

from PIL import Image, features

out = sys.argv[1]
W, H = 64, 48


def gradient(alpha=None):
    img = Image.new("RGBA" if alpha is not None else "RGB", (W, H))
    for y in range(H):
        for x in range(W):
            rgb = (x * 4, y * 5, 160)
            img.putpixel((x, y), rgb + (alpha(x, y),) if alpha else rgb)
    return img


# Translucent left half, opaque right half.
half = lambda x, y: 64 if x < W // 2 else 255
cases = {
    "pillow_webp_lossy_opaque.webp": (gradient(), False),
    "pillow_webp_lossy_alpha.webp": (gradient(half), False),
    "pillow_webp_lossless_opaque.webp": (gradient(), True),
    "pillow_webp_lossless_alpha.webp": (gradient(half), True),
}
# An RGBA image with alpha 255 everywhere comes out byte-identical to the
# opaque lossy file: libwebp 1.6.0 drops an unused alpha plane.
for name, (img, lossless) in cases.items():
    img.save(os.path.join(out, name), "WEBP", quality=80, lossless=lossless, method=4)
    print("wrote", name)
print("Pillow", Image.__version__ if hasattr(Image, "__version__") else "", "libwebp", features.version("webp"))
