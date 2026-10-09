"""Independent check of DarkLib's metadata model (Hayn, docs/10-DARKLIB.md).

Reads with ExifTool, not DarkLib, the outputs `native/darklib/tests/metadata_model.rs`
writes when `DARKLIB_METADATA_OUT` is set: every fixture carried into JPEG,
PNG, WebP, AVIF and HEIF. For each output, against its source fixture:

- ExifTool's validation finds no error (a bad Extended XMP GUID, a broken
  IFD, a chunk out of order);
- the camera, date, GPS and profile are the source's, the orientation is
  upright and the old thumbnail is gone;
- the XMP is whole: an Extended XMP description reads back at its length;
- IPTC-IIM stays IIM in a JPEG and becomes XMP elsewhere (IPTC Core).

Usage (ExifTool 13.59 in ~/tools, see docs/20-LINUX-WORKFLOW.md):
  mkdir -p /tmp/mm && (cd native/darklib && \
    DARKLIB_METADATA_OUT=/tmp/mm cargo test --locked --test metadata_model)
  python3 test_native/check_metadata_model.py native/darklib/tests/fixtures /tmp/mm
"""
import json
import os
import subprocess
import sys

EXIFTOOL = os.environ.get(
    "EXIFTOOL", os.path.expanduser("~/tools/Image-ExifTool-13.59/exiftool")
)
fixtures, outputs = sys.argv[1], sys.argv[2]
SOURCES = {
    "rich": "meta_rich.jpg",
    "extended": "meta_extended_xmp.jpg",
    "split": "meta_extended_xmp.jpg",  # through a PNG of it
    "zxmp": "meta_zxmp.png",
}


def exiftool(*args):
    out = subprocess.run([EXIFTOOL, "-j", "-G1", "-a", *args], capture_output=True, text=True)
    return json.loads(out.stdout)[0]


def tags(path):
    """Every tag, and ExifTool's validation warnings and errors under
    `Validate:`. (Naming `-warning` with the tags would list it alone.)"""
    t = exiftool(path)
    t.update({"Validate:" + k: v for k, v in exiftool("-validate", "-warning", "-error", path).items() if k != "SourceFile"})
    return t


def value(t, suffix):
    """The first tag whose name is `suffix`, in any group."""
    for k, v in t.items():
        if k.split(":")[-1] == suffix and not k.startswith("Validate:"):
            return v
    return None


failures = 0
for name in sorted(os.listdir(outputs)):
    stem, ext = name.split("-to.")
    source = tags(os.path.join(fixtures, SOURCES[stem]))
    out = tags(os.path.join(outputs, name))
    problems = []
    errors = [v for k, v in out.items() if k.startswith("Validate:") and k.endswith(":Error")]
    warnings = [v for k, v in out.items() if k.startswith("Validate:") and k.endswith(":Warning")]
    if errors:
        problems.append(f"error {errors}")
    for w in warnings:
        # Of ExifTool's validation, what concerns the metadata carried.
        if any(s in str(w) for s in ("GUID", "XMP", "IFD", "ICC", "IPTC", "Exif")):
            # A JPEG made by DarkLib names no pixel size in EXIF (minor).
            if "ExifImageWidth" not in str(w) and "ExifImageHeight" not in str(w):
                problems.append(f"warning {w}")
    for tag in ("Make", "Model", "DateTimeOriginal", "GPSLatitude"):
        if value(source, tag) != value(out, tag):
            problems.append(f"{tag}: {value(out, tag)!r} not {value(source, tag)!r}")
    # Named in IIM and XMP both: each in its own group.
    for tag in ("XMP-dc:Title", "XMP-photoshop:City", "XMP-dc:Creator", "XMP-dc:Subject"):
        if source.get(tag) != out.get(tag):
            problems.append(f"{tag}: {out.get(tag)!r} not {source.get(tag)!r}")
    # "split" comes from a PNG made of its source, where the IIM became XMP.
    if ext == "jpg" and stem != "split":
        for tag in ("IPTC:City", "IPTC:By-line", "IPTC:Keywords"):
            if source.get(tag) != out.get(tag):
                problems.append(f"{tag}: {out.get(tag)!r} not {source.get(tag)!r}")
    if value(source, "ProfileDescription") != value(out, "ProfileDescription"):
        problems.append(f"profile {value(out, 'ProfileDescription')!r}")
    if value(out, "Orientation") not in (None, "Horizontal (normal)"):
        problems.append(f"orientation {value(out, 'Orientation')!r}")
    if value(out, "ThumbnailImage") or value(out, "ThumbnailLength"):
        problems.append("the old thumbnail is still there")
    want = value(source, "Description")
    if want and value(out, "Description") != want:
        got = value(out, "Description") or ""
        problems.append(f"XMP description {len(got)} characters, not {len(want)}")
    if value(source, "Headline"):
        if ext == "jpg":
            if value(out, "Headline") != value(source, "Headline"):
                problems.append("IIM Headline")
        elif out.get("XMP-photoshop:Headline") != value(source, "Headline"):
            problems.append(f"Headline as XMP: {out.get('XMP-photoshop:Headline')!r}")
    status = "ok" if not problems else "FAIL: " + "; ".join(problems)
    failures += bool(problems)
    print(f"{name}: {status}")
sys.exit(1 if failures else 0)
