#!/usr/bin/env python3
"""Laboratory font for the Windows Terminal round: ring split into a left-half and a right-half glyph, no overhang.

Every glyph advances one cell (600 units) and keeps its ink inside its own cell.
  base_c + p        left half,  monochrome arc only   (control; single-colour ring)
  base_c + 0x80 + p right half, monochrome arc only
  base_k + p        left half,  COLR v0: track = palette 0, arc = text foreground (0xFFFF)   (mechanism M8)
  base_k + 0x80 + p right half, COLR v0: same
The right half holds angles 0-180 degrees (clockwise from 12 o'clock), the left half 180-360.
"""
import argparse

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

from mklab2 import ADV, ASC, DESC, EM, arc


def sector(a, b, cx, cy, r_out, r_in):
    """Annular sector from a to b degrees; empty glyph when b <= a."""
    return arc(b / 3.6, cx, cy, r_out, r_in, start=a)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", required=True, help="output .ttf path")
    ap.add_argument("-n", "--name", required=True, help="family name suffix, e.g. Lab4a")
    ap.add_argument("-t", "--track", default="128,128,128,0.35", help="track colour r,g,b,alpha (0-255, alpha 0-1)")
    ap.add_argument("-c", "--base-control", type=lambda s: int(s, 16), default=0xFF600, help="hex base, monochrome halves")
    ap.add_argument("-k", "--base-colour", type=lambda s: int(s, 16), default=0xFF800, help="hex base, colour halves")
    ap.add_argument("-y", "--cy", type=int, default=300, help="circle centre y")
    ap.add_argument("-u", "--r-out", type=int, default=540, help="outer radius")
    ap.add_argument("-i", "--r-in", type=int, default=330, help="inner radius")
    args = ap.parse_args()
    tr, tg, tb, ta = (float(x) for x in args.track.split(","))
    geo = (args.cy, args.r_out, args.r_in)

    names = [".notdef", "trackL", "trackR"]
    glyphs = {".notdef": TTGlyphPen(None).glyph(), "trackL": sector(180, 360, ADV, *geo), "trackR": sector(0, 180, 0, *geo)}
    cmap, layers = {}, {}
    for p in range(101):
        sweep = 3.6 * p
        halves = (("L", 0x00, sector(180, sweep, ADV, *geo)), ("R", 0x80, sector(0, min(sweep, 180), 0, *geo)))
        for side, off, g in halves:
            mono, col = f"m{side}{p:03d}", f"k{side}{p:03d}"
            names += [mono, col]
            glyphs[mono] = g
            glyphs[col] = glyphs[f"track{side}"]          # outline fallback when colour layers are ignored
            cmap[args.base_control + off + p] = mono
            cmap[args.base_colour + off + p] = col
            layers[col] = [(f"track{side}", 0)] + ([(mono, 0xFFFF)] if g.numberOfContours else [])

    fam = f"Statusline Rings {args.name}"
    fb = FontBuilder(EM, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({n: (ADV, glyphs[n].xMin if glyphs[n].numberOfContours else 0) for n in names})
    fb.setupHorizontalHeader(ascent=ASC, descent=-DESC)
    fb.setupNameTable({"familyName": fam, "styleName": "Regular", "psName": fam.replace(" ", "") + "-Regular"})
    fb.setupOS2(sTypoAscender=ASC, sTypoDescender=-DESC, usWinAscent=ASC, usWinDescent=DESC)
    fb.setupPost()
    fb.setupCOLR(layers, version=0)
    fb.setupCPAL([[(tr / 255, tg / 255, tb / 255, ta)]])
    fb.save(args.output)


if __name__ == "__main__":
    main()
