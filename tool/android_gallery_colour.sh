#!/usr/bin/env bash
# Does Samsung Gallery show a Display P3 HEIC with its colours (IMG-21)?
# Android's own decoder on the Galaxy S25 Edge ignores a HEIC's profile; this
# asks the same of the phone's gallery app, with the app's TEST images only:
# the P3 crop sources that `tool/test_android_device.sh` saves
# (hayn-test-crop-source-p3-icc.heic and hayn-test-crop-source-p3.jpg: the
# same four P3 quadrants, as libheif HEIC and as JPEG). The JPEG's profile is
# applied everywhere on Android, so it is the reference. Each file is opened
# in Samsung Gallery and the screen captured; the same four points are read
# from both captures. The same screen pipeline takes both, so the display's
# own colour mode cancels out. Nothing else in the gallery is opened or read;
# MediaStore is queried by these two file names only.
# Usage: tool/android_gallery_colour.sh [adb-serial]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERIAL="${1:-$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')}"
ADB=(adb -s "$SERIAL")
GALLERY=com.sec.android.gallery3d
OUT="$ROOT/build/gallery-colour/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

id_of() {
  "${ADB[@]}" shell content query --uri content://media/external/images/media \
    --projection _id --where "\"_display_name LIKE '$1%'\"" |
    sed -n 's/.*_id=\([0-9]*\).*/\1/p' | tail -1
}

capture() {
  local id
  id="$(id_of "$1")"
  if [ -z "$id" ]; then
    echo "Not in the gallery: $1 (run tool/test_android_device.sh)" >&2
    exit 1
  fi
  "${ADB[@]}" shell input keyevent KEYCODE_WAKEUP
  "${ADB[@]}" shell am start -W -a android.intent.action.VIEW \
    -d "content://media/external/images/media/$id" -t image/* \
    --grant-read-uri-permission -p "$GALLERY" >/dev/null
  sleep 3
  "${ADB[@]}" exec-out screencap -p >"$OUT/$2.png"
  "${ADB[@]}" shell input keyevent KEYCODE_BACK
  sleep 1
}

capture hayn-test-crop-source-p3-icc heic
capture hayn-test-crop-source-p3.jpg jpeg

python3 - "$OUT" <<'EOF'
import struct, sys, zlib

def read_png(path):
    b = open(path, 'rb').read()
    i, idat, w = 8, b'', 0
    while i < len(b):
        n, t = struct.unpack('>I4s', b[i:i + 8])
        d = b[i + 8:i + 8 + n]
        if t == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', d[:10])
            assert depth == 8 and ctype in (2, 6), (depth, ctype)
            bpp = 3 if ctype == 2 else 4
        elif t == b'IDAT':
            idat += d
        i += 12 + n
    raw, rows, prev = zlib.decompress(idat), [], bytearray(w * bpp)
    stride = w * bpp
    for y in range(h):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            up, c = prev[x], prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + up) & 255
            elif f == 3: line[x] = (line[x] + (a + up) // 2) & 255
            elif f == 4:
                p = a + up - c
                pa, pb, pc = abs(p - a), abs(p - up), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else up if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return w, h, bpp, rows

out = sys.argv[1]
shots = {k: read_png(f'{out}/{k}.png') for k in ('heic', 'jpeg')}
def bounds(shot):
    # The image: the bright block around the screen centre (the viewer's
    # background is black). Walk out from the centre until the pixels darken.
    w, h, bpp, rows = shot
    lit = lambda x, y: sum(rows[y][x * bpp:x * bpp + 3]) > 90
    cx, cy = w // 2, h // 2
    x0 = x1 = cx
    y0 = y1 = cy
    while x0 > 0 and lit(x0 - 1, cy): x0 -= 1
    while x1 < w - 1 and lit(x1 + 1, cy): x1 += 1
    while y0 > 0 and lit(cx, y0 - 1): y0 -= 1
    while y1 < h - 1 and lit(cx, y1 + 1): y1 += 1
    return x0, y0, x1, y1

total = 0
centres = {}
for k, shot in shots.items():
    x0, y0, x1, y1 = bounds(shot)
    print(f'{k}: image at {x0},{y0} to {x1},{y1}')
    qw, qh = (x1 - x0) // 4, (y1 - y0) // 4
    centres[k] = [(x0 + qw, y0 + qh), (x1 - qw, y0 + qh), (x0 + qw, y1 - qh), (x1 - qw, y1 - qh)]
for q, name in enumerate(('red', 'green', 'blue', 'yellow')):
    px = {}
    for k, (w, h, bpp, rows) in shots.items():
        x, y = centres[k][q]
        px[k] = tuple(rows[y][x * bpp:x * bpp + 3])
    diff = sum(abs(a - b) for a, b in zip(px['heic'], px['jpeg'])) / 3
    total += diff
    print(f'{name:6} heic {px["heic"]} jpeg {px["jpeg"]} diff {diff:.1f}')
mean = total / 4
print(f'mean difference {mean:.1f}:',
      'the gallery shows the HEIC with its profile' if mean <= 4 else
      'the gallery shows the HEIC WITHOUT its profile (as sRGB)')
print(f'captures: {out}')
EOF
