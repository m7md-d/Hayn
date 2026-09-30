"""Independent check of DarkLib's JPEG privacy strip on MPF files (Hayn IMG-06).

Reads the MP Entry list by the CIPA DC-007 layout (not DarkLib's code) in each
original and in its stripped copy from `cargo test --test jpeg_mpf_strip`
(target/tmp/jpeg-strip). Every image after the primary must start with SOI at
its new offset, be byte-identical to the original's, and decode (Pillow). The
primary's size must move by exactly the bytes the strip removed. ImageIO is no
judge here: it found the gain map even when the MPF offset was wrong.

Usage (Pillow in a throwaway venv, see make_webp_fixtures.py):
  /tmp/pillow/bin/python test_native/check_jpeg_mpf.py native/darklib
"""
import io
import os
import struct
import sys

from PIL import Image

root = sys.argv[1]
fixtures = os.path.join(root, "tests/fixtures")
stripped = os.path.join(root, "target/tmp/jpeg-strip")


def segments(b):
    i = 2
    while b[i] == 0xFF and b[i + 1] != 0xDA:
        n = struct.unpack(">H", b[i + 2 : i + 4])[0]
        yield i, b[i + 1], b[i + 4 : i + 2 + n]
        i += 2 + n
    yield i, 0xDA, b""


def mp_entries(b):
    """(tiff_start, [(size, absolute_offset)]) from the first APP2 MPF."""
    for at, marker, payload in segments(b):
        if marker == 0xE2 and payload.startswith(b"MPF\0"):
            t = at + 8
            e = "<" if b[t : t + 2] == b"II" else ">"
            ifd = t + struct.unpack(e + "I", b[t + 4 : t + 8])[0]
            for k in range(struct.unpack(e + "H", b[ifd : ifd + 2])[0]):
                tag, _, count, value = struct.unpack(e + "HHII", b[ifd + 2 + 12 * k : ifd + 14 + 12 * k])
                if tag == 0xB002:
                    out = []
                    for j in range(count // 16):
                        _, size, off, _, _ = struct.unpack(e + "IIIHH", b[t + value + 16 * j : t + value + 16 * j + 16])
                        out.append((size, t + off if off else 0))
                    return t, out
    raise ValueError("no MPF")


failed = False
for name in ["seine_sdr_gainmap_srgb", "apple_gainmap_new", "apple_gainmap_old"]:
    orig = open(os.path.join(fixtures, name + ".jpg"), "rb").read()
    out = open(os.path.join(stripped, name + ".jpg"), "rb").read()
    _, before = mp_entries(orig)
    _, after = mp_entries(out)
    removed = len(orig) - len(out)
    notes = []
    ok = len(before) == len(after) and after[0][0] == before[0][0] - removed
    for (size0, at0), (size1, at1) in zip(before[1:], after[1:]):
        image = out[at1 : at1 + size1]
        same = image == orig[at0 : at0 + size0] and image[:2] == b"\xff\xd8"
        w, h = Image.open(io.BytesIO(image)).size if same else (0, 0)
        notes.append(f"image at {at1}: {'identical' if same else 'WRONG'} {w}x{h}")
        ok &= same
    print(f"{name}: removed {removed} bytes, primary size {before[0][0]}→{after[0][0]}; " + "; ".join(notes))
    failed |= not ok
print("FAIL" if failed else "Independent MPF reader: every image found, byte-identical")
sys.exit(1 if failed else 0)
