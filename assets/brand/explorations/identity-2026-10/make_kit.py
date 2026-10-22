"""Hareeg Table identity kit generator: refined symbols, colour versions,
outlined bilingual wordmarks (Reem Kufi, via fontTools) and lockups for the
two shortlisted directions, A "Lit card" and B "Fifty".

Writes into <repo>/assets/brand/explorations/identity-2026-10/.
"""
import math
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

REPO = Path(r"E:\Work\Projects\Personal\hareeg-table")
OUT = REPO / "assets" / "brand" / "explorations" / "identity-2026-10"
FONT = REPO / "assets" / "fonts" / "ReemKufi-Variable.ttf"

EMBER = "#E4522B"      # flame
CHARCOAL = "#15110E"   # ground
SAND = "#D7BD83"       # spark / accent
IVORY = "#F8F0DD"      # card / paper
BLACK = "#111111"


def svg(title, body, w=256, h=256):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" '
            f'height="{h}" role="img" aria-labelledby="title">\n<title id="title">{title}</title>\n'
            f'{body}</svg>\n')


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


# ---------------------------------------------------------------------------
# A: Lit card (v3). Card 112 wide, bottom 232, rx 14. Flame top: a softer left
# lick (wider tip), a valley, a tall tongue leaning right.
FLAME_A = (
    "C72 112 96 104 100 76 "
    "C102 64 96 52 90 42 "
    "C114 56 126 78 122 100 "
    "C120 110 128 114 134 106 "
    "C154 84 156 50 146 18 "
    "C170 40 184 82 184 130 "
)
A_OUTER = "M72 218 V140 " + FLAME_A + "V218 A14 14 0 0 1 170 232 H86 A14 14 0 0 1 72 218 Z"
A_PIP = "M128 142 L150 172 L128 202 L106 172 Z"
A_FLAME_ONLY = "M72 150 V140 " + FLAME_A + "V150 Z"            # overlaps the card top
A_CARD_BODY = "M72 134 A14 14 0 0 1 86 120 H170 A14 14 0 0 1 184 134 V218 A14 14 0 0 1 170 232 H86 A14 14 0 0 1 72 218 Z"


def symbol_a(color=BLACK, two_tone=False, pip=True):
    if not two_tone:
        d = A_OUTER + (" " + A_PIP if pip else "")
        return f'<path fill="{color}" fill-rule="evenodd" d="{d}"/>\n'
    body = A_CARD_BODY + (" " + A_PIP if pip else "")
    return (f'<path fill="{IVORY}" fill-rule="evenodd" d="{body}"/>\n'
            f'<path fill="{EMBER}" d="{A_FLAME_ONLY}"/>\n')


# ---------------------------------------------------------------------------
# B: Fifty. Flame ring leaning right (the five), spark low left (the zero).
def tangent_points(cx, cy, r, ax, ay):
    dx, dy = ax - cx, ay - cy
    d = math.hypot(dx, dy)
    base = math.atan2(dy, dx)
    phi = math.acos(r / d)
    return ((cx + r * math.cos(base + phi), cy + r * math.sin(base + phi)),
            (cx + r * math.cos(base - phi), cy + r * math.sin(base - phi)))


def flame_ring(cx, cy, r, ax, ay):
    (x1, y1), (x2, y2) = tangent_points(cx, cy, r, ax, ay)
    return f"M{ax:.1f} {ay:.1f} L{x1:.1f} {y1:.1f} A{r} {r} 0 1 1 {x2:.1f} {y2:.1f} Z"


B_CX, B_CY, B_R, B_W = 146, 162, 60, 24
B_AX, B_AY = 182, 26
_d = math.hypot(B_AX - B_CX, B_AY - B_CY)
_half = math.asin(B_R / _d)
_k = B_W / math.sin(_half)
_ux, _uy = (B_AX - B_CX) / _d, (B_AY - B_CY) / _d
B_OUTER = flame_ring(B_CX, B_CY, B_R, B_AX, B_AY)
B_INNER = flame_ring(B_CX, B_CY, B_R - B_W, B_AX - _ux * _k, B_AY - _uy * _k)
B_DOT = "M38 190 A24 24 0 1 1 38.1 190 Z"


def symbol_b(color=BLACK, two_tone=False):
    ring = EMBER if two_tone else color
    dot = SAND if two_tone else color
    return (f'<path fill="{ring}" fill-rule="evenodd" d="{B_OUTER} {B_INNER}"/>\n'
            f'<path fill="{dot}" d="{B_DOT}"/>\n')


# ---------------------------------------------------------------------------
# Wordmarks: Reem Kufi at wght 600, shaped with HarfBuzz (joining forms, mark
# placement, kerning) and outlined with fontTools.
import uharfbuzz as hb

STATIC = Path(__file__).parent / "reemkufi-600.ttf"
_font = instancer.instantiateVariableFont(TTFont(FONT), {"wght": 600})
_font.save(STATIC)
_glyphs = _font.getGlyphSet()
UPM = _font["head"].unitsPerEm
CAP = _font["OS/2"].sCapHeight
_hb_font = hb.Font(hb.Face(STATIC.read_bytes()))


def shape(text, rtl=False):
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(_hb_font, buf, {"kern": True, "liga": True})
    return list(zip(buf.glyph_infos, buf.glyph_positions))


def shape_latin(text):
    return shape(text)


def shape_arabic(text):
    return shape(text, rtl=True)


def wordmark(shaped, height, rtl=False, tracking=0.0):
    """Return (path_d, width) with the cap height scaled to `height` px.

    HarfBuzz already returns glyphs in visual (left-to-right) order.
    """
    scale = height / CAP
    track = tracking * UPM
    total = sum(pos.x_advance for _, pos in shaped) + track * (len(shaped) - 1)
    parts = []
    x = 0.0
    for info, pos in shaped:
        name = _font.getGlyphName(info.codepoint)
        pen = SVGPathPen(_glyphs)
        tp = TransformPen(pen, (scale, 0, 0, -scale,
                                (x + pos.x_offset) * scale, height - pos.y_offset * scale))
        _glyphs[name].draw(tp)
        parts.append(pen.getCommands())
        x += pos.x_advance + track
    return " ".join(p for p in parts if p), total * scale


# ---------------------------------------------------------------------------
def build(direction, name, symbol_fn, two_tone_fn):
    d = OUT / direction
    # Symbols
    write(d / f"{name}-symbol.svg", svg(f"Hareeg Table {name} symbol", symbol_fn(BLACK)))
    write(d / f"{name}-symbol-color.svg",
          svg(f"Hareeg Table {name} symbol (colour)",
              f'<rect width="256" height="256" fill="{CHARCOAL}"/>\n' + two_tone_fn()))
    write(d / f"{name}-symbol-ember.svg", svg(f"Hareeg Table {name} symbol (ember)", symbol_fn(EMBER)))

    # Wordmarks: Latin 72 px cap height, Arabic set to a matching visual height.
    # Arabic is set 1/3 taller than the Latin cap height: Kufi letters carry
    # their mass low and wide, so equal cap heights leave the Arabic looking
    # small next to the symbol.
    lat_d, lat_w = wordmark(shape_latin("Hareeg Table"), 72, tracking=0.01)
    ar_d, ar_w = wordmark(shape_arabic("حريق"), 96, rtl=True)
    write(d / f"{name}-wordmark-latin.svg",
          svg("Hareeg Table wordmark",
              f'<g id="wordmark" transform="translate(16 92)"><path fill="{BLACK}" d="{lat_d}"/></g>\n',
              w=int(lat_w + 32), h=256))
    write(d / f"{name}-wordmark-arabic.svg",
          svg("حريق wordmark",
              f'<g id="wordmark" transform="translate(16 92)"><path fill="{BLACK}" d="{ar_d}"/></g>\n',
              w=int(ar_w + 32), h=256))

    # Horizontal lockup (Latin): symbol at 256, gap 48, wordmark centred on the
    # symbol's optical middle; Arabic lockup mirrors it (symbol on the right).
    gap = 48
    lat_y = 128 - 36 + 6
    body = (f'<g id="symbol">{symbol_fn(BLACK)}</g>\n'
            f'<g id="wordmark" transform="translate({256 + gap} {lat_y})">'
            f'<path fill="{BLACK}" d="{lat_d}"/></g>\n')
    write(d / f"{name}-horizontal.svg", svg(f"Hareeg Table {name} horizontal", body, w=int(256 + gap + lat_w), h=256))
    body = (f'<g id="wordmark" transform="translate(0 {lat_y - 18})"><path fill="{BLACK}" d="{ar_d}"/></g>\n'
            f'<g id="symbol" transform="translate({ar_w + gap} 0)">{symbol_fn(BLACK)}</g>\n')
    write(d / f"{name}-horizontal-arabic.svg", svg(f"حريق {name} horizontal", body, w=int(ar_w + gap + 256), h=256))

    # Stacked bilingual: symbol, Latin, Arabic.
    lat_s, lat_sw = wordmark(shape_latin("Hareeg Table"), 44, tracking=0.01)
    ar_s, ar_sw = wordmark(shape_arabic("حريق"), 58, rtl=True)
    width = max(256, lat_sw, ar_sw) + 32
    cx = width / 2
    body = (f'<g id="symbol" transform="translate({cx - 128:.1f} 0) scale(0.78)">{symbol_fn(BLACK)}</g>\n'
            f'<g id="wordmark-latin" transform="translate({cx - lat_sw / 2:.1f} 224)"><path fill="{BLACK}" d="{lat_s}"/></g>\n'
            f'<g id="wordmark-arabic" transform="translate({cx - ar_sw / 2:.1f} 296)"><path fill="{BLACK}" d="{ar_s}"/></g>\n')
    write(d / f"{name}-stacked.svg", svg(f"Hareeg Table {name} stacked", body, w=int(width), h=360))
    print("built", direction, f"latin {lat_w:.0f}px, arabic {ar_w:.0f}px")


build("a-lit-card", "lit-card", lambda c: symbol_a(c), lambda: symbol_a(two_tone=True))
write(OUT / "a-lit-card" / "lit-card-symbol-small.svg",
      svg("Hareeg Table lit card symbol (small sizes)", symbol_a(BLACK, pip=False)))
build("b-fifty", "fifty", lambda c: symbol_b(c), lambda: symbol_b(two_tone=True))
print("done")


# ---------------------------------------------------------------------------
# A: tile-less two-tone artwork (what sits on a tile), Android adaptive-icon
# preview under the three launcher masks, and a palette pass as icon tiles.
def two_tone_a(ground, card, flame, pip=True):
    body = A_CARD_BODY + (" " + A_PIP if pip else "")
    return (f'<path fill="{card}" fill-rule="evenodd" d="{body}"/>\n'
            f'<path fill="{flame}" d="{A_FLAME_ONLY}"/>\n')


write(OUT / "a-lit-card" / "lit-card-symbol-two-tone.svg",
      svg("Hareeg Table lit card symbol (two-tone, no tile)", two_tone_a(CHARCOAL, IVORY, EMBER)))

# Adaptive icon: 108 dp canvas, 72 dp safe zone, masks at 72 dp. The symbol is
# scaled to 62 % of the canvas so the flame tip clears every mask.
def adaptive_tile(x, y, mask_id, ground, card, flame, label):
    s = 160
    return (f'<g transform="translate({x} {y})">'
            f'<g clip-path="url(#{mask_id})">'
            f'<rect width="{s}" height="{s}" fill="{ground}"/>'
            f'<g transform="translate({s*0.19} {s*0.17}) scale({s*0.62/256})">{two_tone_a(ground, card, flame)}</g>'
            f'</g>'
            f'<text x="{s/2}" y="{s+22}" font-family="Segoe UI, sans-serif" font-size="12" text-anchor="middle" fill="#444">{label}</text>'
            f'</g>\n')


masks = (
    '<defs>'
    '<clipPath id="m-circle"><circle cx="80" cy="80" r="80"/></clipPath>'
    '<clipPath id="m-squircle"><path d="M80 0 C148 0 160 12 160 80 C160 148 148 160 80 160 C12 160 0 148 0 80 C0 12 12 0 80 0 Z"/></clipPath>'
    '<clipPath id="m-rounded"><rect width="160" height="160" rx="36"/></clipPath>'
    '</defs>\n'
)
body = masks + "".join([
    adaptive_tile(24, 24, "m-circle", CHARCOAL, IVORY, EMBER, "Circle"),
    adaptive_tile(216, 24, "m-squircle", CHARCOAL, IVORY, EMBER, "Squircle (Pixel)"),
    adaptive_tile(408, 24, "m-rounded", CHARCOAL, IVORY, EMBER, "Rounded square (Samsung)"),
])
write(OUT / "a-lit-card" / "lit-card-adaptive-preview.svg",
      svg("Lit card adaptive launcher preview", f'<rect width="592" height="232" fill="#ECEFF1"/>\n' + body, w=592, h=232))

# Palette pass: six tiles, ground / card / flame.
AMBER = "#F0962E"
BRICK = "#C8401F"
NIGHT = "#0F2C25"
options = [
    ("1  Charcoal · Ivory · Ember (current)", CHARCOAL, IVORY, EMBER),
    ("2  Charcoal · Sand · Ember", CHARCOAL, SAND, EMBER),
    ("3  Charcoal · Ivory · Amber", CHARCOAL, IVORY, AMBER),
    ("4  Ember · Ivory · Charcoal", EMBER, IVORY, CHARCOAL),
    ("5  Ivory · Charcoal · Ember", IVORY, CHARCOAL, EMBER),
    ("6  Night green · Ivory · Brick", NIGHT, IVORY, BRICK),
]
tiles = []
for i, (label, g, c, fl) in enumerate(options):
    x, y = 24 + (i % 3) * 200, 24 + (i // 3) * 220
    tiles.append(adaptive_tile(x, y, "m-squircle", g, c, fl, label))
write(OUT / "a-lit-card" / "lit-card-palette-options.svg",
      svg("Lit card palette options", f'<rect width="624" height="464" fill="#ECEFF1"/>\n' + masks + "".join(tiles), w=624, h=464))
print("extras written")
