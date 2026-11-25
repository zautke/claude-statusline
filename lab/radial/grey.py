#!/usr/bin/env python3
"""Neutral track colour as a pure grey at a target WCAG contrast ratio against the terminal background.

WCAG 2 relative luminance Y and contrast ratio (Y1 + 0.05) / (Y2 + 0.05). The grey is lighter than the
background when the background is dark (Y < 0.179, the luminance where black and white contrast equally)
and darker otherwise.
"""
import argparse


def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lum(rgb):
    r, g, b = rgb
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def ratio(a, b):
    ya, yb = lum(a), lum(b)
    return (max(ya, yb) + 0.05) / (min(ya, yb) + 0.05)


def lstar(rgb):
    y = lum(rgb)
    return 116 * y ** (1 / 3) - 16 if y > 0.008856 else 903.3 * y


def grey_for(bg, target):
    """Grey (r, g, b) whose contrast ratio against bg is `target`."""
    y = lum(bg)
    yg = target * (y + 0.05) - 0.05 if y < 0.179 else (y + 0.05) / target - 0.05
    yg = min(1.0, max(0.0, yg))
    c = 12.92 * yg if yg <= 0.0031308 else 1.055 * yg ** (1 / 2.4) - 0.055
    v = round(c * 255)
    return (v, v, v)


def parse_rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-b", "--background", required=True, help="background as RRGGBB")
    ap.add_argument("-r", "--ratios", default="1.5,1.75,2.0,2.5", help="comma-separated target contrast ratios")
    args = ap.parse_args()
    bg = parse_rgb(args.background)
    print(f"background {bg} Y={lum(bg):.4f} L*={lstar(bg):.1f}")
    for t in (float(x) for x in args.ratios.split(",")):
        g = grey_for(bg, t)
        print(f"ratio {t}: grey {g} achieved {ratio(g, bg):.2f} L*={lstar(g):.1f}")


if __name__ == "__main__":
    main()
