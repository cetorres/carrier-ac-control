"""Final CarrierBar app icon: navy squircle, thermostat arc, white snowflake.

Writes:
  <out>/Assets.xcassets/...                      asset catalog with every macOS AppIcon size
  <out>/Design/AppIcon/CarrierBar-icon.svg       full icon source
  <out>/Design/AppIcon/CarrierBar-icon-1024.png  full icon preview
  <out>/Design/AppIcon/layers/*.svg              unmasked background and glyph, for Icon Composer
"""
import json
import math
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

OUT = Path(sys.argv[1])
CANVAS, BODY = 1024, 824
ORIGIN = (CANVAS - BODY) / 2
CX = CY = CANVAS / 2

TOP, BOTTOM = "#2257BA", "#0A1A42"     # navy gradient
ARC_TO = "#5FD6FF"                      # cyan end of the active arc


def squircle_path(n=5.0, steps=720):
    a = BODY / 2
    c = ORIGIN + a
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = c + a * math.copysign(abs(math.cos(t)) ** (2 / n), math.cos(t))
        y = c + a * math.copysign(abs(math.sin(t)) ** (2 / n), math.sin(t))
        pts.append(f"{x:.2f},{y:.2f}")
    return "M" + " L".join(pts) + " Z"


def polar(cx, cy, r, deg):
    rad = math.radians(deg)
    return cx + r * math.cos(rad), cy + r * math.sin(rad)


def arc(r, start, end):
    x1, y1 = polar(CX, CY, r, start)
    x2, y2 = polar(CX, CY, r, end)
    large = 1 if (end - start) % 360 > 180 else 0
    return f"M{x1:.2f},{y1:.2f} A{r},{r} 0 {large} 1 {x2:.2f},{y2:.2f}"


def snowflake(r, stroke, branches=True):
    lines = []
    for k in range(3):
        ang = 90 + k * 60
        x1, y1 = polar(CX, CY, r, ang)
        x2, y2 = polar(CX, CY, r, ang + 180)
        lines.append((x1, y1, x2, y2))
    if branches:
        for k in range(6):
            ang = 90 + k * 60
            bx, by = polar(CX, CY, r * 0.58, ang)
            for side in (-1, 1):
                ex, ey = polar(bx, by, r * 0.36, ang + side * 45)
                lines.append((bx, by, ex, ey))
    body = "".join(f'<line x1="{a:.2f}" y1="{b:.2f}" x2="{c:.2f}" y2="{d:.2f}"/>' for a, b, c, d in lines)
    return (f'<g stroke="#fff" stroke-width="{stroke}" stroke-linecap="round" '
            f'stroke-linejoin="round" fill="none">{body}</g>')


def glyph(small=False):
    """The dial and snowflake. `small` is a bolder, simpler drawing for 16 and 32 px."""
    r = 262 if not small else 250
    width = 64 if not small else 104
    start, end, active = 135, 405, 325
    kx, ky = polar(CX, CY, r, active)
    knob_r = width * (0.72 if not small else 0.62)
    flake = snowflake(132, 30) if not small else snowflake(118, 64, branches=False)
    track_opacity = 0.18 if not small else 0.24
    return f"""
    <path d="{arc(r, start, end)}" stroke="#fff" stroke-opacity="{track_opacity}" stroke-width="{width}" stroke-linecap="round" fill="none"/>
    <path d="{arc(r, start, active)}" stroke="url(#arc)" stroke-width="{width}" stroke-linecap="round" fill="none"/>
    <circle cx="{kx:.2f}" cy="{ky:.2f}" r="{knob_r:.1f}" fill="#fff" filter="url(#knob)"/>
    {flake}"""


GLYPH_DEFS = f"""
    <linearGradient id="arc" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0" stop-color="#ffffff"/>
      <stop offset="1" stop-color="{ARC_TO}"/>
    </linearGradient>
    <filter id="knob" x="-50%" y="-50%" width="200%" height="200%">
      <feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#00163d" flood-opacity="0.35"/>
    </filter>"""

BG_DEF = f"""
    <linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="{TOP}"/>
      <stop offset="1" stop-color="{BOTTOM}"/>
    </linearGradient>"""


def icon_svg(small=False):
    path = squircle_path()
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" width="{CANVAS}" height="{CANVAS}">
  <defs>{BG_DEF}{GLYPH_DEFS}
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="0.20"/>
      <stop offset="0.45" stop-color="#fff" stop-opacity="0"/>
    </linearGradient>
    <clipPath id="shape"><path d="{path}"/></clipPath>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.32"/>
    </filter>
  </defs>
  <path d="{path}" fill="url(#bg)" filter="url(#shadow)"/>
  <g clip-path="url(#shape)">
    <rect width="{CANVAS}" height="{CANVAS}" fill="url(#sheen)"/>
    {glyph(small)}
  </g>
  <path d="{path}" fill="none" stroke="#fff" stroke-opacity="0.10" stroke-width="2"/>
</svg>"""


def layer_background_svg():
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" width="{CANVAS}" height="{CANVAS}">
  <defs>{BG_DEF}</defs>
  <rect width="{CANVAS}" height="{CANVAS}" fill="url(#bg)"/>
</svg>"""


def layer_glyph_svg():
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" width="{CANVAS}" height="{CANVAS}">
  <defs>{GLYPH_DEFS}</defs>
  {glyph()}
</svg>"""


# macOS AppIcon slots: (point size, scale) -> pixel size
SLOTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def main():
    appiconset = OUT / "Assets.xcassets" / "AppIcon.appiconset"
    design = OUT / "Design" / "AppIcon"
    layers = design / "layers"
    for folder in (appiconset, layers):
        folder.mkdir(parents=True, exist_ok=True)

    full, small = icon_svg(), icon_svg(small=True)
    (design / "CarrierBar-icon.svg").write_text(full)
    (design / "CarrierBar-icon-small.svg").write_text(small)
    (layers / "background.svg").write_text(layer_background_svg())
    (layers / "glyph.svg").write_text(layer_glyph_svg())

    images = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(device_scale_factor=1)

        def render(svg, size, dest):
            sized = svg.replace(f'width="{CANVAS}" height="{CANVAS}"', f'width="{size}" height="{size}"', 1)
            page.set_viewport_size({"width": size, "height": size})
            page.set_content(f'<html><body style="margin:0;background:transparent">{sized}</body></html>')
            page.screenshot(path=str(dest), omit_background=True, clip={"x": 0, "y": 0, "width": size, "height": size})

        for points, scale in SLOTS:
            pixels = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            render(small if pixels <= 32 else full, pixels, appiconset / name)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})

        render(full, 1024, design / "CarrierBar-icon-1024.png")
        render(layer_glyph_svg(), 1024, layers / "glyph-1024.png")
        render(layer_background_svg(), 1024, layers / "background-1024.png")
        browser.close()

    info = {"author": "xcode", "version": 1}
    (appiconset / "Contents.json").write_text(json.dumps({"images": images, "info": info}, indent=2) + "\n")
    (OUT / "Assets.xcassets" / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
    print("done:", sorted(p.name for p in appiconset.iterdir()))


if __name__ == "__main__":
    main()
