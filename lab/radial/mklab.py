#!/usr/bin/env python3
"""Laboratory ring fonts for the radial-indicator ledger (kb: claude-statusline radial indicators laboratory ledger).

Blocks per font (p = 0..100):
  control  base_c + p : monochrome arc
  block A  base_a + p : COLR v0, track = palette 0, arc = text foreground (0xFFFF)
  block B  base_b + p : COLR v0, track = palette 0, arc = baked heat colour
"""
import argparse
import math

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

EM, ASC, DESC, ADV = 1000, 800, 200, 1200
CX, CY, R_OUT, R_IN = 520, 300, 520, 310


def pt(r, deg):
    a = math.radians(90 - deg)  # 0 deg = 12 o'clock, clockwise
    return (round(CX + r * math.cos(a)), round(CY + r * math.sin(a)))


def arc(pct):
    pen = TTGlyphPen(None)
    if pct <= 0:
        return pen.glyph()
    sweep = 3.6 * pct
    n = max(2, int(sweep / 3))
    angs = [sweep * i / n for i in range(n + 1)]
    if pct >= 100:
        for r, seq in ((R_OUT, angs[:-1]), (R_IN, angs[-2::-1])):
            pen.moveTo(pt(r, seq[0]))
            for a in seq[1:]:
                pen.lineTo(pt(r, a))
            pen.closePath()
    else:
        pen.moveTo(pt(R_OUT, 0))
        for a in angs[1:]:
            pen.lineTo(pt(R_OUT, a))
        for a in reversed(angs):
            pen.lineTo(pt(R_IN, a))
        pen.closePath()
    return pen.glyph()


def heat_rgb(pos):
    """Port of heat_rgb in scripts/statusline-command.sh (integer arithmetic)."""
    if pos <= 50:
        return (40 + 180 * pos // 50, 170 - 10 * pos // 50, 60 - 60 * pos // 50)
    p2 = pos - 50
    return (220 - 40 * p2 // 50, 160 - 160 * p2 // 50, 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", required=True, help="output .ttf path")
    ap.add_argument("-n", "--name", required=True, help="family name suffix, e.g. Lab1")
    ap.add_argument("-t", "--track", default="128,128,128,0.35", help="track colour r,g,b,alpha (0-255, alpha 0-1)")
    ap.add_argument("-c", "--base-control", type=lambda s: int(s, 16), default=0xFFD00, help="hex base codepoint, control block")
    ap.add_argument("-a", "--base-a", type=lambda s: int(s, 16), default=0xFFE00, help="hex base codepoint, block A")
    ap.add_argument("-b", "--base-b", type=lambda s: int(s, 16), default=0xFFE80, help="hex base codepoint, block B")
    args = ap.parse_args()
    tr, tg, tb, ta = (float(x) for x in args.track.split(","))

    P = range(101)
    names = [".notdef", "track"] + [f"arc{p:03d}" for p in P] + [f"a{p:03d}" for p in P] + [f"b{p:03d}" for p in P]
    glyphs = {".notdef": TTGlyphPen(None).glyph(), "track": arc(100)}
    for p in P:
        glyphs[f"arc{p:03d}"] = arc(p)
        glyphs[f"a{p:03d}"] = arc(100)   # outline fallback when colour layers are ignored
        glyphs[f"b{p:03d}"] = arc(100)
    cmap = {}
    for p in P:
        cmap[args.base_control + p] = f"arc{p:03d}"
        cmap[args.base_a + p] = f"a{p:03d}"
        cmap[args.base_b + p] = f"b{p:03d}"

    palette = [(tr / 255, tg / 255, tb / 255, ta)] + [tuple(c / 255 for c in heat_rgb(p)) + (1.0,) for p in P]
    layers = {}
    for p in P:
        layers[f"a{p:03d}"] = [("track", 0)] + ([(f"arc{p:03d}", 0xFFFF)] if p else [])
        layers[f"b{p:03d}"] = [("track", 0)] + ([(f"arc{p:03d}", 1 + p)] if p else [])

    fam = f"Statusline Rings {args.name}"
    fb = FontBuilder(EM, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({n: (ADV, 0) for n in names})
    fb.setupHorizontalHeader(ascent=ASC, descent=-DESC)
    fb.setupNameTable({"familyName": fam, "styleName": "Regular", "psName": fam.replace(" ", "") + "-Regular"})
    fb.setupOS2(sTypoAscender=ASC, sTypoDescender=-DESC, usWinAscent=ASC, usWinDescent=DESC)
    fb.setupPost()
    fb.setupCOLR(layers, version=0)
    fb.setupCPAL([palette])
    fb.save(args.output)


if __name__ == "__main__":
    main()
