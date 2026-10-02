#!/usr/bin/env python3
"""Prints the headline numbers of a performance report (tool/test_performance.sh).

The JSON keeps every measurement; this is the part worth reading first.
Usage: tool/performance_summary.py build/performance/<run>/report.json
"""
import json
import sys

data = json.load(open(sys.argv[1]))

# HAYN_PERF_LARGE=1 runs only the 200 MP test (RUN-01): its own short summary.
large = data.get("large")
if large is not None:
    device = large.get("device", {})
    source = large.get("source", {})
    print(f"{device.get('model')} · RAM {device.get('memTotalMb')} MB · source "
          f"{source.get('size')} ({source.get('kb')} KB, RSS {source.get('rssMb')} MB)")
    print(f"  plan: {large.get('plan')}")
    for name in ("displayFull", "display4096", "viewerZoom"):
        r = large.get(name)
        if r is not None:
            print(f"  {name:<12} {r.get('ms')} ms / peak {r.get('peakRssMb')} MB "
                  f"(+{r.get('peakAboveBeforeMb')}) / {r.get('size') or r.get('failed')}")
    print("target  ms / peak RSS MB (above before) / output / backend / full size")
    for target in ("jpeg", "heic", "webp", "avif", "png"):
        r = large.get(target)
        if r is None:
            print(f"  {target:<6} not reached (killed before it?)")
        elif "failed" in r:
            print(f"  {target:<6} {r['ms']} / {r['peakRssMb']} ({r['peakAboveBeforeMb']}) / "
                  f"failed: {', '.join(r['failed'])}")
        else:
            print(f"  {target:<6} {r['ms']} / {r['peakRssMb']} ({r['peakAboveBeforeMb']}) / "
                  f"{r['size']} {r['outKb']} KB / {r['backend']} / {r['fullSize']}")
    sys.exit(0)

perf = data.get("performance", {})
device = perf.get("device", {})
print(
    f"{device.get('model')} · {device.get('os')} {device.get('osVersion')} · "
    f"{device.get('refreshHz')} Hz · photos: {device.get('photoPermission')} · "
    f"max RSS {data.get('maxRssMb')} MB"
)


def frames(label, f):
    if not f:
        return
    if not f.get("frames"):
        print(f"  {label:<14} no frames reported ({f.get('actionMs')} ms)")
        return
    print(
        f"  {label:<14} {f['frames']:>4} frames  {f.get('fps') or '-':>4} fps  "
        f"build p90 {f['buildP90Ms']:>5} ms  raster p90 {f['rasterP90Ms']:>5} ms  "
        f"over {f['budgetMs']} ms: {f['overBudgetPct']}%  (>2x: {f['overTwiceBudget']})"
    )


for name in ("library.mount", "library.scroll", "viewer", "navigation"):
    section = perf.get(name)
    if section is None:
        print(f"\n{name}: not run")
        continue
    print(f"\n{name}")
    if "skipped" in section:
        print(f"  skipped: {section['skipped']}")
    for key, value in section.items():
        if isinstance(value, dict) and "frames" in value:
            frames(key, value)
        elif key.endswith("Ms") or key in ("libraryItems", "firstPageItems", "flingDistancePx", "notSharpWithin3s", "notSharpPages", "videoSwipes"):
            print(f"  {key:<24} {value}")
    for line in section.get("overBudget", []):
        print(f"  OVER BUDGET: {line}")

conversion = perf.get("conversion")
if conversion:
    targets = ["jpeg", "heic", "webp", "avif", "png"]
    print("\nconversion (ms / output KB / backend)")
    print("  " + "from \\ to".ljust(10) + "".join(t.ljust(26) for t in targets))
    for source, row in conversion.items():
        if "skipped" in row:
            print(f"  {source:<10}skipped: {row['skipped']}")
            continue
        cells = []
        for t in targets:
            c = row.get(t, {})
            if not c:
                cells.append("-".ljust(26))
            elif "failed" in c:
                cells.append("failed".ljust(26))
            else:
                fmt = "" if c.get("format") == t else f" ->{c.get('format')}"
                cells.append(f"{c.get('ms')} / {c.get('outKb')} / {c.get('backend')}{fmt}".ljust(26))
        print(f"  {source:<10}" + "".join(cells))

decode = perf.get("decode")
if decode:
    print("\ndecode median ms (full / 1080 px / app display path)")
    for source, row in decode.items():
        if source == "flattenOnWhite":
            continue
        full = row.get("flutterFullMs", {}).get("median", row.get("flutterFailed", "-"))
        small = row.get("flutter1080Ms", {}).get("median", "-")
        app = row.get("appDisplayMs", {}).get("median", "-")
        print(f"  {source:<6} {full} / {small} / {app}")

flatten = (decode or {}).get("flattenOnWhite")
if flatten:
    print(f"\nflatten onto white, 12 MP (median ms): DarkLib {flatten['darklibMs'].get('median')} · "
          f"Dart {flatten['dartMs'].get('median')}")

over = data.get("overBudget") or []
print(f"\nOver budget: {len(over)}")
for line in over:
    print(f"  - {line}")
