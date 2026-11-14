#!/usr/bin/env python3
"""Generate the Kasumi app icon (light, dark, tinted) as SVG.

Concept: 霞 (kasumi, "haze"). Horizontal suyari-gasumi mist bands drift across
a rising sun; the bands double as the lines of a paragraph -- a thick heading
line, body lines, and a short final line -- so the mark reads both as a
Japanese landscape and as a page of typeset text.

Regenerate the asset catalog PNGs (opaque, no alpha) from the repo root:

    python3 design/icon/make_icon.py design/icon
    SET=apps/iOS/Kasumi/Assets.xcassets/AppIcon.appiconset
    for v in light:AppIcon dark:AppIcon-Dark tinted:AppIcon-Tinted; do
      rsvg-convert -w 1024 -h 1024 design/icon/kasumi-${v%%:*}.svg |
        magick png:- -background black -alpha remove -alpha off -strip \
          PNG24:$SET/${v##*:}.png
    done
"""
import pathlib, sys

S = 1024
SUN = (640, 404, 146)  # cx, cy, r

# x, y, width, height -- heading line, two body lines (one indented), last line
BANDS = [
    (160, 440, 560, 108),
    (288, 600, 576, 64),
    (160, 702, 640, 64),
    (160, 804, 404, 64),
]

PALETTES = {
    "light": dict(
        sky=[("0", "#222C55"), ("0.6", "#5E5A86"), ("1", "#C9918A")],
        sun=("#FFD9A0", "#FFA062", "#F4683C"), glow="#FF9A62", glow_op=0.55,
        grain_op=0.10, haze_op=0.30,
        band=("#FFFDF8", "#F6EEE6"), band_op=[0.97, 0.93, 0.90, 0.86],
        fog="#F3D6CB", fog_op=0.35, shade="#1E1838", shade_op=0.28,
    ),
    "dark": dict(
        sky=[("0", "#070B18"), ("0.6", "#141B36"), ("1", "#2C2C4E")],
        sun=("#FFC992", "#F58D58", "#DC5A36"), glow="#E86A40", glow_op=0.40,
        grain_op=0.12, haze_op=0.24,
        band=("#DCE1F2", "#A9B1CF"), band_op=[0.92, 0.86, 0.80, 0.74],
        fog="#5A5F86", fog_op=0.35, shade="#000000", shade_op=0.35,
    ),
    "tinted": dict(
        sky=[("0", "#000000"), ("1", "#000000")],
        sun=("#D8D8D8", "#B4B4B4", "#929292"), glow="#B4B4B4", glow_op=0.22,
        grain_op=0.08, haze_op=0.0,
        band=("#FFFFFF", "#E6E6E6"), band_op=[1.0, 0.95, 0.9, 0.85],
        fog="#3A3A3A", fog_op=0.0, shade="#000000", shade_op=0.0,
    ),
}


def svg(p):
    cx, cy, r = SUN
    stops = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in p["sky"])
    bands = []
    for (x, y, w, h), op in zip(BANDS, p["band_op"]):
        rr = h / 2
        # soft shadow under each band, then the band itself
        bands.append(
            f'<rect x="{x}" y="{y + 10}" width="{w}" height="{h}" rx="{rr}" '
            f'fill="{p["shade"]}" opacity="{p["shade_op"]}" filter="url(#soft)"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rr}" '
            f'fill="url(#band)" opacity="{op}"/>'
        )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">{stops}</linearGradient>
    <radialGradient id="sun" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="{p["sun"][0]}"/>
      <stop offset="0.7" stop-color="{p["sun"][1]}"/>
      <stop offset="1" stop-color="{p["sun"][2]}"/>
    </radialGradient>
    <!-- lower limb sinks into the haze, as a low sun does -->
    <linearGradient id="sink" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0.45" stop-color="{p["fog"]}" stop-opacity="0"/>
      <stop offset="1" stop-color="{p["fog"]}" stop-opacity="{p["haze_op"]}"/>
    </linearGradient>
    <clipPath id="disc"><circle cx="{cx}" cy="{cy}" r="{r}"/></clipPath>
    <!-- fine paper grain, neutral grey so it only shifts value -->
    <filter id="grain" x="0" y="0" width="100%" height="100%">
      <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="7"/>
      <feColorMatrix type="saturate" values="0"/>
      <feComponentTransfer><feFuncA type="linear" slope="0" intercept="1"/></feComponentTransfer>
    </filter>
    <radialGradient id="glow">
      <stop offset="0" stop-color="{p["glow"]}" stop-opacity="{p["glow_op"]}"/>
      <stop offset="0.45" stop-color="{p["glow"]}" stop-opacity="{p["glow_op"] * 0.35:.3f}"/>
      <stop offset="1" stop-color="{p["glow"]}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="band" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="{p["band"][0]}"/><stop offset="1" stop-color="{p["band"][1]}"/>
    </linearGradient>
    <linearGradient id="fog" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{p["fog"]}" stop-opacity="0"/>
      <stop offset="1" stop-color="{p["fog"]}" stop-opacity="{p["fog_op"]}"/>
    </linearGradient>
    <filter id="soft" x="-10%" y="-50%" width="120%" height="200%"><feGaussianBlur stdDeviation="14"/></filter>
  </defs>
  <rect width="{S}" height="{S}" fill="url(#sky)"/>
  <circle cx="{cx}" cy="{cy}" r="{r * 2.6:.0f}" fill="url(#glow)"/>
  <circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#sun)"/>
  <g clip-path="url(#disc)">
    <rect x="{cx - r}" y="{cy - r}" width="{2 * r}" height="{2 * r}" filter="url(#grain)" opacity="{p["grain_op"]}" style="mix-blend-mode:overlay"/>
    <rect x="{cx - r}" y="{cy - r}" width="{2 * r}" height="{2 * r}" fill="url(#sink)"/>
  </g>
  <rect y="{S * 0.55:.0f}" width="{S}" height="{S * 0.45:.0f}" fill="url(#fog)"/>
  {"".join(bands)}
</svg>
'''


out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
for name, pal in PALETTES.items():
    (out / f"kasumi-{name}.svg").write_text(svg(pal))
