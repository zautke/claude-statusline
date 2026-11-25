#!/usr/bin/env python3
"""Laboratory font for E-002/E-003, two-cell ring (kb: claude-statusline radial indicators laboratory ledger).

Monochrome. Every glyph advances one cell (600 units).
  track  base_t      : full ring, circle centre x = +600 (drawn from cell 1 across cells 1-2)
         with --tile: base_t + p is only the unfilled remainder for p % (E-003, no overlap with the arc)
  arcs   base_r + p  : arc for p %, circle centre x = shift (0 = drawn from cell 2 back over cell 1)
"""
import argparse
import math

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

EM, ASC, DESC, ADV = 1000, 800, 200, 600


def arc(pct, cx, cy, r_out, r_in, start=0.0):
    """Annular sector from `start` degrees to 3.6*pct degrees."""
    def pt(r, deg):
        a = math.radians(90 - deg)  # 0 deg = 12 o'clock, clockwise
        return (round(cx + r * math.cos(a)), round(cy + r * math.sin(a)))
    pen = TTGlyphPen(None)
    end = 3.6 * pct
    sweep = end - start
    if sweep <= 0:
        return pen.glyph()
    n = max(2, int(sweep / 3))
    angs = [start + sweep * i / n for i in range(n + 1)]
    if sweep >= 360:
        for r, seq in ((r_out, angs[:-1]), (r_in, angs[-2::-1])):
            pen.moveTo(pt(r, seq[0]))
            for a in seq[1:]:
                pen.lineTo(pt(r, a))
            pen.closePath()
    else:
        pen.moveTo(pt(r_out, angs[0]))
        for a in angs[1:]:
            pen.lineTo(pt(r_out, a))
        for a in reversed(angs):
            pen.lineTo(pt(r_in, a))
        pen.closePath()
    return pen.glyph()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", required=True, help="output .ttf path")
    ap.add_argument("-n", "--name", required=True, help="family name suffix, e.g. Lab2")
    ap.add_argument("-t", "--base-track", type=lambda s: int(s, 16), default=0xFFC00, help="hex codepoint of the track glyph")
    ap.add_argument("-r", "--base-arcs", type=lambda s: int(s, 16), default=0xFFC80, help="hex base codepoint of the arc glyphs")
    ap.add_argument("-x", "--track-cx", type=int, default=600, help="track circle centre x")
    ap.add_argument("-s", "--arc-cx", type=int, default=0, help="arc circle centre x")
    ap.add_argument("-y", "--cy", type=int, default=300, help="circle centre y")
    ap.add_argument("-u", "--r-out", type=int, default=540, help="outer radius")
    ap.add_argument("-i", "--r-in", type=int, default=330, help="inner radius")
    ap.add_argument("-T", "--tile", action="store_true", help="per-percentage remainder track glyphs instead of one full ring")
    ap.add_argument("-v", "--overlap", type=float, default=0.0, help="degrees the remainder extends under the arc tip and start (with --tile)")
    args = ap.parse_args()

    P = range(101)
    names = [".notdef", "track"] + [f"arc{p:03d}" for p in P]
    glyphs = {".notdef": TTGlyphPen(None).glyph(), "track": arc(100, args.track_cx, args.cy, args.r_out, args.r_in)}
    for p in P:
        glyphs[f"arc{p:03d}"] = arc(p, args.arc_cx, args.cy, args.r_out, args.r_in)
    cmap = {args.base_track: "track"}
    if args.tile:
        cmap = {}
        for p in P:
            ov = args.overlap if 0 < p < 100 else 0.0
            names.append(f"rem{p:03d}")
            # remainder runs from the arc tip round to 360 degrees (= pct 100)
            glyphs[f"rem{p:03d}"] = arc(100 + ov / 3.6, args.track_cx, args.cy, args.r_out, args.r_in, start=3.6 * p - ov)
            cmap[args.base_track + p] = f"rem{p:03d}"
    cmap.update({args.base_arcs + p: f"arc{p:03d}" for p in P})

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
    fb.save(args.output)


if __name__ == "__main__":
    main()
