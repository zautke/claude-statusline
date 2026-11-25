#!/usr/bin/env python3
"""Laboratory font for E-009: continuous hue along the arc by dithered tiling (mechanism M11).

Four glyphs in four cells draw one ring without overlapping:
  cell 1  base_g + p   grey remainder for p %
  cell 2  base_a + p   green slices of the filled range 0..p
  cell 3  base_b + p   amber slices
  cell 4  base_c + p   red slices
The ring centre is the boundary between cells 2 and 3. Hue glyphs are interleaved radial slices whose share per
period follows the three-stop heat ramp (green at 0 %, amber at 50 %, red at 100 %).
Reach test glyphs (E-009a): base_r + k is a full ring centred k cell widths from its origin, k = 0..6 meaning -3..+3.
"""
import argparse
import math

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

EM, ASC, DESC = 1000, 800, 200


def wedge(pen, a, b, cx, cy, r_out, r_in):
    """Add an annular sector a..b degrees (clockwise from 12 o'clock) to pen."""
    if b - a <= 1e-6:
        return
    def pt(r, deg):
        t = math.radians(90 - deg)
        return (round(cx + r * math.cos(t)), round(cy + r * math.sin(t)))
    n = max(1, int((b - a) / 3))
    angs = [a + (b - a) * i / n for i in range(n + 1)]
    pen.moveTo(pt(r_out, angs[0]))
    for x in angs[1:]:
        pen.lineTo(pt(r_out, x))
    for x in reversed(angs):
        pen.lineTo(pt(r_in, x))
    pen.closePath()


def shares(pos):
    """(green, amber, red) shares at ramp position pos in 0..100."""
    if pos <= 50:
        t = pos / 50
        return (1 - t, t, 0.0)
    t = (pos - 50) / 50
    return (0.0, 1 - t, t)


def hue_glyphs(p, period, geo, centres):
    """Three glyphs (green, amber, red) for fill p %, slices of `period` degrees."""
    pens = [TTGlyphPen(None) for _ in range(3)]
    end = 3.6 * p
    a = 0.0
    while a < end - 1e-6:
        b = min(a + period, end)
        full = period
        sh = shares((a + full / 2) / 3.6)
        start = a
        for k in range(3):
            stop = min(start + sh[k] * full, b)
            if stop - start > 0.02:
                wedge(pens[k], start, stop, centres[k], *geo)
            start = max(start, stop)
        a += period
    return [pen.glyph() for pen in pens]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", required=True, help="output .ttf path")
    ap.add_argument("-n", "--name", required=True, help="family name suffix, e.g. Lab6")
    ap.add_argument("-w", "--cell", type=int, default=545, help="cell width per 1000 em of the terminal font")
    ap.add_argument("-y", "--cy", type=int, default=386, help="circle centre y")
    ap.add_argument("-u", "--r-out", type=int, default=615, help="outer radius")
    ap.add_argument("-i", "--r-in", type=int, default=346, help="inner radius")
    ap.add_argument("-d", "--period", type=float, default=3.0, help="slice period in degrees")
    ap.add_argument("-v", "--notch", type=float, default=9.0, help="background gap in degrees at arc start and tip")
    ap.add_argument("-g", "--base-grey", type=lambda s: int(s, 16), default=0xFEC00, help="hex base, grey remainder")
    ap.add_argument("-a", "--base-green", type=lambda s: int(s, 16), default=0xFEC80, help="hex base, green slices")
    ap.add_argument("-b", "--base-amber", type=lambda s: int(s, 16), default=0xFED00, help="hex base, amber slices")
    ap.add_argument("-c", "--base-red", type=lambda s: int(s, 16), default=0xFED80, help="hex base, red slices")
    ap.add_argument("-r", "--base-reach", type=lambda s: int(s, 16), default=0xFEE00, help="hex base, reach test glyphs")
    args = ap.parse_args()
    W, geo = args.cell, (args.cy, args.r_out, args.r_in)
    cg, centres = 2 * W, (W, 0, -W)          # grey in cell 1; green, amber, red in cells 2, 3, 4

    names, glyphs, cmap = [".notdef"], {".notdef": TTGlyphPen(None).glyph()}, {}
    def add(name, glyph, cp):
        names.append(name); glyphs[name] = glyph; cmap[cp] = name
    for p in range(101):
        pen = TTGlyphPen(None)
        gap = args.notch if 0 < p < 100 else 0.0
        wedge(pen, 3.6 * p + gap, 360 - gap, cg, *geo)
        add(f"grey{p:03d}", pen.glyph(), args.base_grey + p)
        g, a, r = hue_glyphs(p, args.period, geo, centres)
        add(f"green{p:03d}", g, args.base_green + p)
        add(f"amber{p:03d}", a, args.base_amber + p)
        add(f"red{p:03d}", r, args.base_red + p)
    for k in range(7):
        pen = TTGlyphPen(None)
        wedge(pen, 0, 180, (k - 3) * W, *geo); wedge(pen, 180, 360, (k - 3) * W, *geo)
        add(f"reach{k}", pen.glyph(), args.base_reach + k)

    fam = f"Statusline Rings {args.name}"
    fb = FontBuilder(EM, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({n: (W, glyphs[n].xMin if glyphs[n].numberOfContours else 0) for n in names})
    fb.setupHorizontalHeader(ascent=ASC, descent=-DESC)
    fb.setupNameTable({"familyName": fam, "styleName": "Regular", "psName": fam.replace(" ", "") + "-Regular"})
    fb.setupOS2(sTypoAscender=ASC, sTypoDescender=-DESC, usWinAscent=ASC, usWinDescent=DESC)
    fb.setupPost()
    fb.save(args.output)


if __name__ == "__main__":
    main()
