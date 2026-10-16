#!/usr/bin/env python3
"""Composes the App Store marketing images from the raw app screens.

    flutter test test_screenshots/store_shots_test.dart --update-goldens \
        --dart-define=STORE_BUILD=true          # raw screens, from apps/nija
    python3 tool/store_shots/compose.py         # framed store images

Raw screens come from build/store_shots/raw/<device>/; the framed images land
in build/store_shots/out/<kind>/<lang>/NN.png:

    iphone  1320x2868  iPhone 6.9", 3D frame
    ipad    2064x2752  iPad 13", flat bezel
    mac     2880x1800  Mac, window with traffic lights
    header  3840x1646  product page header (21:9), three phones
    search  3840x2560  search results asset (3:2), three phones

Like Pixfide's listing, each slide lifts the screen's key element out of
the phone as a tilted card with a white border: the capture test records
where those widgets sit (<shot>.rects.json) and `sips` crops them.

Rendering uses the appscreen batch renderer (headless Chrome + Three.js),
found at $APPSCREEN_DIR or next to this repository. It runs twice: the first
pass measures how tall each headline really is, the second places the
subtitle and the device under it.
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys
from functools import lru_cache

ROOT = pathlib.Path(__file__).resolve().parents[2]
RAW = ROOT / "build/store_shots/raw"
OUT = ROOT / "build/store_shots/out"
APPSCREEN = pathlib.Path(
    os.environ.get("APPSCREEN_DIR", ROOT.parents[1] / "Internal/appscreen")
)
RENDER = APPSCREEN / "batch/render.mjs"
COPY = json.loads((pathlib.Path(__file__).parent / "copy.json").read_text())

FONT = "Plus Jakarta Sans"
FONTS = [f"{FONT}:800", f"{FONT}:500"]
WHITE_SUB = "rgba(255,255,255,0.78)"

# Nija's palette: navy, the app's primary blue, and the green it uses for
# "live" and "synced".
BRAND_BG = {
    "color": "#060a14",
    "gradient": {
        "type": "linear",
        "angle": 165,
        "stops": [
            {"color": "#13254d", "pos": 0},
            {"color": "#0b1530", "pos": 0.5},
            {"color": "#05080f", "pos": 1},
        ],
    },
    "glows": [
        {"color": "#2563eb", "x": 0.14, "y": 0.08, "radius": 0.62, "opacity": 0.55},
        {"color": "#10b981", "x": 0.92, "y": 0.82, "radius": 0.5, "opacity": 0.26},
    ],
    "noise": {"opacity": 0.04},
}

# Screen, caption key, tilt (degrees) for the 3D phone.
SLIDES = [
    ("01-history", "s1", -8),
    ("02-search", "s2", 8),
    ("03-devices", "s3", -8),
    ("04-databases", "s4", 8),
    ("05-pair", "s5", -8),
    ("06-settings", "s6", 8),
]


@lru_cache(maxsize=None)
def crops(device, shot):
    """Highlight crops for one raw screen: [(path, width, height), ...] in
    the order the capture test listed them."""
    rects_file = RAW / device / f"{shot}.rects.json"
    if not rects_file.exists():
        return []
    out = []
    for key, (x, y, w, h) in json.loads(rects_file.read_text()).items():
        dst = RAW / device / "crops" / f"{shot}.{key}.png"
        dst.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["sips", "-c", str(h), str(w), "--cropOffset", str(y), str(x),
             str(RAW / device / f"{shot}.png"), "--out", str(dst)],
            check=True, capture_output=True,
        )
        out.append((dst, w, h))
    return out


def cards(device, shot, W, H, slide, max_w, min_w, ys, inset):
    """Floating highlight cards, alternating sides like Pixfide's listing:
    tilted, white-bordered and shadowed, overlapping the device's edge."""
    images = []
    for k, (path, w, h) in enumerate(crops(device, shot)):
        # Rows grow a little; small elements (a pill, a PIN) at most 2x.
        cw = int(min(max_w * W, max(w * 1.15, min(min_w * W, w * 2.0))))
        ch = int(cw * h / w)
        left = (slide + k) % 2 == 0
        x = int(inset * W) if left else int(W - inset * W - cw)
        y = int(ys[min(k, len(ys) - 1)] * H)
        images.append({
            "src": str(path),
            "x": x,
            "y": y,
            "width": cw,
            "height": ch,
            "radius": int(min(cw, ch) * 0.12),
            "fit": "cover",
            "rotate": -5 if left else 5,
            "shadow": True,
            "border": {"width": max(6, int(W * 0.0055)), "color": "rgba(255,255,255,0.85)"},
        })
    return images


def captions(copy, key, W, top, side, title, sub, sub_y=None):
    texts = [
        {
            "id": "headline",
            "text": copy[f"{key}_title"],
            "x": side,
            "y": top,
            "width": W - 2 * side,
            "align": "center",
            "font": [FONT, "sans-serif"],
            "weight": 800,
            "size": title,
            "minSize": int(title * 0.66),
            "maxLines": 2,
            "lineHeight": 1.1,
            "color": "#ffffff",
            "letterSpacing": "-0.02em",
        }
    ]
    if f"{key}_sub" in copy:
        texts.append(
            {
                "id": "sub",
                "text": copy[f"{key}_sub"],
                "x": int(side * 1.3),
                "y": sub_y if sub_y is not None else top + int(title * 2.6),
                "width": W - int(2.6 * side),
                "align": "center",
                "font": [FONT, "sans-serif"],
                "weight": 500,
                "size": sub,
                "minSize": int(sub * 0.72),
                "maxLines": 2,
                "lineHeight": 1.3,
                "color": WHITE_SUB,
            }
        )
    return texts


def ink_bottom(metrics, tid):
    for t in metrics.get("texts", []):
        if t.get("id") == tid:
            b = t.get("inkBox") or t.get("box")
            if b:
                return b.get("bottom", b.get("y", 0) + b.get("height", 0))
    return None


def text_bottom_at(metrics, tid, y):
    """Where block [tid] ends when placed at [y], from its measured height."""
    for t in metrics.get("texts", []):
        if t.get("id") == tid and t.get("inkBox") and t.get("box"):
            return y + (t["inkBox"]["bottom"] - t["box"]["top"])
    return None


def layout(metrics, dst, H, top, gap):
    """Subtitle y and the bottom of the caption block for one image."""
    m = metrics.get(str(dst), {})
    hb = ink_bottom(m, "headline")
    sub_y = hb + int(H * gap) if hb else None
    sb = text_bottom_at(m, "sub", sub_y) if sub_y else None
    return sub_y, sb


def iphone(lang, copy, metrics):
    W, H = 1320, 2868
    side, top = int(W * 0.068), int(H * 0.058)
    jobs = []
    for i, (shot, key, tilt) in enumerate(SLIDES, 1):
        dst = OUT / "iphone" / lang / f"{i:02d}.png"
        sub_y, sb = layout(metrics, dst, H, top, 0.018)
        text_bottom = sb or top + int(H * 0.2)
        dev_h = 0.80
        cy = (text_bottom + int(H * 0.045) + dev_h * H / 2) / H
        jobs.append(
            {
                "out": str(dst),
                "spec": {
                    "width": W,
                    "height": H,
                    "lang": lang,
                    "fonts": FONTS,
                    "safeArea": {"left": int(W * 0.05), "right": int(W * 0.05), "top": int(H * 0.03), "bottom": 0},
                    "supersample": 2,
                    "background": BRAND_BG,
                    "devices": [
                        {
                            "model": "iphone",
                            "screenshot": str(RAW / "iphone" / f"{shot}.png"),
                            "cx": 0.5,
                            "cy": round(cy, 4),
                            "height": dev_h,
                            "rotX": 3,
                            "rotY": tilt,
                            "rotZ": 0,
                            "frameColor": "black",
                            "shadow": True,
                        }
                    ],
                    "images": cards("iphone", shot, W, H, i, 0.74, 0.36, (0.47, 0.67), 0.025),
                    "texts": captions(copy, key, W, top, side, int(W * 0.094), int(W * 0.042), sub_y),
                },
            }
        )
    return jobs


def ipad(lang, copy, metrics):
    """Flat bezel: the renderer has no 3D iPad, and a straight tablet reads
    better at this size anyway."""
    W, H = 2064, 2752
    side, top = int(W * 0.09), int(H * 0.055)
    jobs = []
    for i, (shot, key, _) in enumerate(SLIDES, 1):
        dst = OUT / "ipad" / lang / f"{i:02d}.png"
        sub_y, sb = layout(metrics, dst, H, top, 0.014)
        text_bottom = sb or top + int(H * 0.16)
        bezel = int(W * 0.022)
        sw = int(W * 0.80)
        sh = int(sw * 2752 / 2064)
        x = (W - sw) // 2
        y = text_bottom + int(H * 0.05)
        jobs.append(
            {
                "out": str(dst),
                "spec": {
                    "width": W,
                    "height": H,
                    "lang": lang,
                    "fonts": FONTS,
                    "safeArea": {"left": int(W * 0.05), "right": int(W * 0.05), "top": int(H * 0.03), "bottom": 0},
                    "background": BRAND_BG,
                    "decorations": [
                        {
                            "type": "rect",
                            "x": x - bezel,
                            "y": y - bezel,
                            "w": sw + 2 * bezel,
                            "h": sh + 2 * bezel,
                            "r": int(W * 0.045),
                            "fill": "#0d0f14",
                            "stroke": "rgba(255,255,255,0.16)",
                            "lineWidth": 4,
                        }
                    ],
                    "images": [
                        {
                            "src": str(RAW / "ipad" / f"{shot}.png"),
                            "x": x,
                            "y": y,
                            "width": sw,
                            "height": sh,
                            "radius": int(W * 0.03),
                            "fit": "cover",
                            "focus": {"x": 0.5, "y": 0.0},
                            "shadow": True,
                        },
                        *cards("ipad", shot, W, H, i, 0.62, 0.3, (0.44, 0.66), 0.03),
                    ],
                    "texts": captions(copy, key, W, top, side, int(W * 0.068), int(W * 0.03), sub_y),
                },
            }
        )
    return jobs


def mac(lang, copy, metrics):
    """A macOS window (title bar, traffic lights) under the caption."""
    W, H = 2880, 1800
    side, top = int(W * 0.12), int(H * 0.07)
    jobs = []
    for i, (shot, key, _) in enumerate(SLIDES, 1):
        dst = OUT / "mac" / lang / f"{i:02d}.png"
        sub_y, sb = layout(metrics, dst, H, top, 0.016)
        text_bottom = sb or top + int(H * 0.2)
        ww = int(W * 0.74)
        wh = int(ww * 900 / 1440)
        bar = int(ww * 0.028)
        x = (W - ww) // 2
        y = text_bottom + int(H * 0.05)
        dots = [
            {"type": "circle", "x": x + int(bar * (0.9 + 0.95 * k)), "y": y + bar // 2, "r": int(bar * 0.23), "fill": c}
            for k, c in enumerate(["#ff5f57", "#febc2e", "#28c840"])
        ]
        jobs.append(
            {
                "out": str(dst),
                "spec": {
                    "width": W,
                    "height": H,
                    "lang": lang,
                    "fonts": FONTS,
                    "safeArea": {"left": int(W * 0.04), "right": int(W * 0.04), "top": int(H * 0.03), "bottom": 0},
                    "background": BRAND_BG,
                    "decorations": [
                        {
                            "type": "rect",
                            "x": x,
                            "y": y,
                            "w": ww,
                            "h": wh + bar,
                            "r": int(ww * 0.012),
                            "fill": "#1b1f27",
                            "stroke": "rgba(255,255,255,0.14)",
                            "lineWidth": 3,
                        },
                        *dots,
                    ],
                    "images": [
                        {
                            "src": str(RAW / "mac" / f"{shot}.png"),
                            "x": x,
                            "y": y + bar,
                            "width": ww,
                            "height": wh,
                            "radius": int(ww * 0.006),
                            "fit": "cover",
                            "shadow": True,
                        },
                        *cards("mac", shot, W, H, i, 0.42, 0.2, (0.42, 0.66), 0.03),
                    ],
                    "texts": captions(copy, key, W, top, side, int(W * 0.04), int(W * 0.018), sub_y),
                },
            }
        )
    return jobs


def wide(kind, lang, copy, metrics):
    """Product page header (21:9) and search results asset (3:2): captions
    and three phones in the centre, where every crop still shows them."""
    W, H = (3840, 1646) if kind == "header" else (3840, 2560)
    dst = OUT / kind / f"{lang}.png"
    cw = int(W * 0.5)
    top = int(H * (0.075 if kind == "header" else 0.07))
    title = int(H * (0.085 if kind == "header" else 0.075))
    sub_y, sb = layout(metrics, dst, H, top, 0.015)
    tb = sb or top + title * 2.4
    dev_h = 1.05 if kind == "header" else 0.82
    cy = (tb + int(H * 0.05) + dev_h * H / 2) / H
    spread = 0.135 if kind == "header" else 0.17
    phones = [("03-devices", 0.5 - spread, -14, 4), ("05-pair", 0.5 + spread, 14, -4), ("01-history", 0.5, 0, 0)]
    devices = [
        {
            "model": "iphone",
            "screenshot": str(RAW / "iphone" / f"{shot}.png"),
            "cx": cx,
            "cy": round(cy + (0.03 if cx != 0.5 else 0), 4),
            "height": dev_h * (0.9 if cx != 0.5 else 1),
            "rotX": 3,
            "rotY": ry,
            "rotZ": rz,
            "frameColor": "black",
            "shadow": True,
        }
        for shot, cx, ry, rz in phones
    ]
    # Highlight cards fanned along both edges, outside the safe centre.
    edge = [("01-history", 0, 0.02, 0.16, -7), ("03-devices", 0, 0.08, 0.45, 5), ("04-databases", 0, 0.015, 0.72, 4),
            ("06-settings", 0, 0.76, 0.15, 6), ("05-pair", 0, 0.82, 0.46, -5), ("04-databases", 1, 0.77, 0.73, -4)]
    if kind == "search":
        edge = [(s_, i_, {0.02: 0.012, 0.08: 0.04, 0.015: 0.01, 0.76: 0.82, 0.82: 0.85, 0.77: 0.83}[fx], fy, r)
                for s_, i_, fx, fy, r in edge]
    imgs = []
    for shot, idx, fx, fy, rot in edge:
        got = crops("iphone", shot)
        if len(got) <= idx:
            continue
        path, w, h = got[idx]
        card_w = int(W * (0.17 if w / h > 2.5 else 0.12))
        imgs.append({"src": str(path), "x": int(W * fx), "y": int(H * fy), "width": card_w,
                     "height": int(card_w * h / w), "radius": int(min(card_w, card_w * h / w) * 0.12), "fit": "cover", "rotate": rot, "shadow": True,
                     "border": {"width": 10, "color": "rgba(255,255,255,0.8)"}, "opacity": 0.95})
    bg = json.loads(json.dumps(BRAND_BG))
    bg["glows"] = [
        {"color": "#2563eb", "x": 0.5, "y": 0.0, "radius": 0.45, "opacity": 0.6},
        {"color": "#10b981", "x": 0.5, "y": 1.0, "radius": 0.4, "opacity": 0.28},
    ]
    return [
        {
            "out": str(dst),
            "spec": {
                "width": W,
                "height": H,
                "lang": lang,
                "fonts": FONTS,
                "safeArea": {"left": (W - cw) // 2 - 40, "right": (W - cw) // 2 - 40, "top": int(H * 0.04), "bottom": 0},
                "supersample": 1,
                "background": bg,
                "devices": devices,
                "images": imgs,
                "texts": captions(copy, kind, W, top, (W - cw) // 2, title, int(title * 0.45), sub_y),
            },
        }
    ]


KINDS = {
    "iphone": iphone,
    "ipad": ipad,
    "mac": mac,
    "header": lambda lang, copy, m: wide("header", lang, copy, m),
    "search": lambda lang, copy, m: wide("search", lang, copy, m),
}


def build(kinds, langs, metrics):
    jobs = []
    for lang in langs:
        for k in kinds:
            jobs += KINDS[k](lang, COPY[lang], metrics)
    return jobs


def render(jobs, path, concurrency):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(jobs, indent=1))
    r = subprocess.run(
        ["node", str(RENDER), str(path), "--concurrency", str(concurrency)],
        capture_output=True,
        text=True,
    )
    return r.returncode, r.stdout + r.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kinds", default="iphone,ipad,mac,header,search")
    ap.add_argument("--langs", default=",".join(COPY))
    ap.add_argument("--concurrency", type=int, default=2)
    a = ap.parse_args()
    if not RENDER.exists():
        sys.exit(f"renderer not found at {RENDER}; set APPSCREEN_DIR")
    kinds, langs = a.kinds.split(","), a.langs.split(",")
    for k in kinds:
        if k not in ("header", "search") and not (RAW / k).is_dir():
            sys.exit(f"no raw screens in {RAW / k}; run the store_shots golden test first")

    # Pass 1 measures the captions; pass 2 lays out under them.
    jobs = build(kinds, langs, {})
    code, log = render(jobs, OUT / "jobs.pass1.json", a.concurrency)
    metrics = {}
    for j in jobs:
        mp = pathlib.Path(j["out"] + ".json")
        if mp.exists():
            metrics[j["out"]] = json.loads(mp.read_text())
    jobs = build(kinds, langs, metrics)
    code, log = render(jobs, OUT / "jobs.json", a.concurrency)
    print(log[-3000:])
    for j in jobs:
        pathlib.Path(j["out"] + ".json").unlink(missing_ok=True)
    sys.exit(code)


if __name__ == "__main__":
    main()
