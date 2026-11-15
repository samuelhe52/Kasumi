#!/usr/bin/env python3
"""Generate the Kasumi app icon (light, dark, tinted) as SVG.

Four soft pills -- three full lines and a short last line -- sit on a dusk
gradient. A low sun glows from behind the top line, warming its upper edge.

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
# Geometry measured from the 1254 px reference, scaled to 1024.
K = S / 1254
BAR_X, BAR_W, BAR_H = 249 * K, 756 * K, 76 * K
LAST_W = 491 * K
BAR_Y = [(483 + 130 * i) * K for i in range(4)]
GLOW_C = (770 * K, 483 * K)
GLOW_SX = 1.12  # the glow spreads wider than it rises

PALETTES = {
    "light": dict(
        sky=[(0, "#1E285E"), (0.19, "#282F68"), (0.38, "#3B3E7B"), (0.53, "#56518D"),
             (0.67, "#846D9B"), (0.81, "#B388A5"), (1, "#DFA5AE")],
        # glow: (offset, colour, opacity) from the sun outward
        # fitted to the reference's radial falloff (offset = distance / 520 px)
        glow=[(0, "#FEF3CB", 1), (0.058, "#FDDBAA", 1), (0.115, "#FDBF98", 1),
              (0.173, "#FDA78D", 0.96), (0.231, "#FD9A8A", 0.86), (0.308, "#FE938B", 0.69),
              (0.385, "#FC9192", 0.54), (0.481, "#FB9195", 0.40), (0.577, "#F88E97", 0.27),
              (0.692, "#F696AB", 0.17), (0.808, "#F1A4BD", 0.10), (1, "#F1A4BD", 0)],
        glow_r=520 * K, glow_below=(0.6, 0.25),
        streak=[(0, "#FFF8DC", 0.95), (0.3, "#FFE2B0", 0.55), (0.65, "#FFC096", 0.22), (1, "#FFB090", 0)],
        bar=[(0, "#FFFFFF"), (0.09, "#F9F2EF"), (0.5, "#F3EBE8"), (0.9, "#EFE6E4"),
             (1, "#E4D6D4")],
        rim="#FFFFFF", rim_op=0.7,
        warm=[(0, "#FFE2BC", 1), (0.3, "#FFD9C2", 0.85), (0.65, "#F8D2CA", 0.5),
              (1, "#F6D4CF", 0)],
        warm_r=400 * K,
        shade="#22164A", shade_op=(0.5, 0.45),
    ),
    "dark": dict(
        sky=[(0, "#090C1F"), (0.22, "#0F1430"), (0.42, "#181C40"), (0.58, "#25264F"),
             (0.72, "#3A3260"), (0.86, "#57426B"), (1, "#704F72")],
        glow=[(0, "#FFE6BC", 1), (0.058, "#FFCB98", 0.97), (0.115, "#FBA97F", 0.9),
              (0.173, "#F38E72", 0.78), (0.231, "#E87C6C", 0.64), (0.308, "#D86E6C", 0.48),
              (0.385, "#C76570", 0.35), (0.481, "#B35E74", 0.24), (0.577, "#9C5876", 0.15),
              (0.692, "#86537A", 0.09), (0.808, "#74507C", 0.05), (1, "#74507C", 0)],
        glow_r=520 * K, glow_below=(0.5, 0.2),
        streak=[(0, "#FFEBC4", 0.85), (0.3, "#FFD09C", 0.5), (0.65, "#F5A07C", 0.18), (1, "#F0987A", 0)],
        bar=[(0, "#F4F1F4"), (0.09, "#E6E1E6"), (0.5, "#DCD6DC"), (0.9, "#D3CCD3"),
             (1, "#C2B9C2")],
        rim="#FFFFFF", rim_op=0.45,
        warm=[(0, "#FFD3A6", 0.9), (0.3, "#F4C0AC", 0.7), (0.65, "#E6B7B6", 0.35),
              (1, "#E6B7B6", 0)],
        warm_r=400 * K,
        shade="#000000", shade_op=(0.55, 0.5),
    ),
    # iOS tints by luminance: greyscale on black, pills brightest.
    "tinted": dict(
        sky=[(0, "#000000"), (1, "#141414")],
        glow=[(0, "#D0D0D0", 0.9), (0.115, "#B0B0B0", 0.75), (0.231, "#909090", 0.5),
              (0.385, "#707070", 0.28), (0.577, "#585858", 0.12), (0.808, "#484848", 0.04),
              (1, "#404040", 0)],
        glow_r=520 * K, glow_below=(0.4, 0.12),
        streak=[(0, "#E0E0E0", 0.7), (0.3, "#C0C0C0", 0.4), (0.65, "#909090", 0.12),
                (1, "#808080", 0)],
        bar=[(0, "#FFFFFF"), (0.09, "#FAFAFA"), (0.5, "#F2F2F2"), (0.9, "#EAEAEA"),
             (1, "#DADADA")],
        rim="#FFFFFF", rim_op=0.5,
        warm=[(0, "#FFFFFF", 0), (1, "#FFFFFF", 0)],
        warm_r=400 * K,
        shade="#000000", shade_op=(0.5, 0.45),
    ),
}


def f(v):
    return f"{v:.1f}".rstrip("0").rstrip(".")


def about(cx, cy, sx, sy):
    """Scale a gradient about (cx, cy)."""
    return f"translate({f(cx)} {f(cy)}) scale({sx} {sy}) translate({f(-cx)} {f(-cy)})"


def stops(items):
    out = []
    for item in items:
        if len(item) == 2:
            out.append(f'<stop offset="{item[0]}" stop-color="{item[1]}" />')
        else:
            out.append(f'<stop offset="{item[0]}" stop-color="{item[1]}" stop-opacity="{item[2]}" />')
    return "".join(out)


def pill(y, w, **attrs):
    extra = "".join(f' {k.replace("_", "-")}="{v}"' for k, v in attrs.items())
    return (f'<rect x="{f(BAR_X)}" y="{f(y)}" width="{f(w)}" height="{f(BAR_H)}" '
            f'rx="{f(BAR_H / 2)}"{extra} />')


def svg(p):
    gx, gy = GLOW_C
    top = BAR_Y[0]
    widths = [BAR_W] * 3 + [LAST_W]
    # a long ambient shadow plus a tight contact shadow under each line
    shadows = "\n    ".join(
        pill(y + 16, w, fill=p["shade"], opacity=p["shade_op"][0], filter="url(#ambient)") + "\n    " +
        pill(y + 4, w, fill=p["shade"], opacity=p["shade_op"][1], filter="url(#contact)")
        for y, w in zip(BAR_Y, widths))
    bars = "\n    ".join(pill(y, w, fill="url(#bar)") for y, w in zip(BAR_Y, widths))
    rims = "\n    ".join(
        pill(y + 1, w - 2, transform=f"translate(1 0)", fill="none", stroke="url(#rim)",
             stroke_width="2")
        for y, w in zip(BAR_Y, widths))
    # The glow is mostly hidden below the top line; a vertical mask fades it out.
    # 1 above the line, then (glow_below) at +30 and +105 px, gone by +250
    fade = [(top, 1), (top + 30, p["glow_below"][0]), (top + 105, p["glow_below"][1]),
            (top + 250, 0)]
    fade_stops = "".join(f'<stop offset="{y / S:.3f}" stop-color="#FFFFFF" stop-opacity="{o}" />'
                         for y, o in fade)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">{stops(p["sky"])}</linearGradient>
    <radialGradient id="glow" gradientUnits="userSpaceOnUse" cx="{f(gx)}" cy="{f(gy)}" r="{f(p["glow_r"])}" gradientTransform="{about(gx, gy, GLOW_SX, 1)}">{stops(p["glow"])}</radialGradient>
    <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">
      {fade_stops}
    </linearGradient>
    <mask id="above" maskUnits="userSpaceOnUse" x="0" y="0" width="{S}" height="{S}"><rect width="{S}" height="{S}" fill="url(#fade)" /></mask>
    <linearGradient id="bar" x1="0" y1="0" x2="0" y2="1">{stops(p["bar"])}</linearGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{p["rim"]}" stop-opacity="{p["rim_op"]}" /><stop offset="0.5" stop-color="{p["rim"]}" stop-opacity="{p["rim_op"] * 0.3:.2f}" /><stop offset="1" stop-color="{p["rim"]}" stop-opacity="0" />
    </linearGradient>
    <radialGradient id="warm" gradientUnits="userSpaceOnUse" cx="{f(gx)}" cy="{f(gy)}" r="{f(p["warm_r"])}" gradientTransform="{about(gx, gy, 1, 0.55)}">{stops(p["warm"])}</radialGradient>
    <radialGradient id="streak" gradientUnits="userSpaceOnUse" cx="{f(gx)}" cy="{f(top)}" r="{f(330 * K)}" gradientTransform="{about(gx, top, 1, 0.36)}">{stops(p["streak"])}</radialGradient>
    <filter id="ambient" x="-15%" y="-120%" width="130%" height="340%"><feGaussianBlur stdDeviation="22" /></filter>
    <filter id="contact" x="-5%" y="-30%" width="110%" height="160%"><feGaussianBlur stdDeviation="5" /></filter>
  </defs>
  <rect width="{S}" height="{S}" fill="url(#sky)" />
  <g mask="url(#above)">
    <rect width="{S}" height="{S}" fill="url(#glow)" />
    <rect width="{S}" height="{S}" fill="url(#streak)" />
  </g>
  <g>
    {shadows}
  </g>
  <g>
    {bars}
  </g>
  {pill(BAR_Y[0], BAR_W, fill="url(#warm)")}
  <g>
    {rims}
  </g>
</svg>
'''


def main(out):
    out = pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    for name, p in PALETTES.items():
        (out / f"kasumi-{name}.svg").write_text(svg(p))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).parent)
