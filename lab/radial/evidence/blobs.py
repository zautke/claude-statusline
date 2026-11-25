"""List non-background blobs per text row with their dominant colours. usage: blobs.py IMG y0 y1 x1"""
import sys
from collections import Counter
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); y0, y1, x1 = map(int, sys.argv[2:5])
px = im.load(); bg = Counter(px[x, y] for x in range(0, x1, 7) for y in range(y0, y1, 7)).most_common(1)[0][0]
print("bg", bg)
far = lambda c: max(abs(a - b) for a, b in zip(c, bg)) > 6
rows = [y for y in range(y0, y1) if any(far(px[x, y]) for x in range(0, x1, 2))]
bands, s = [], None
for y in rows:
    if s is None: s = p = y
    elif y - p > 6: bands.append((s, p)); s = y
    p = y
if s is not None: bands.append((s, p))
for (a, b) in bands:
    cols = [x for x in range(x1) if any(far(px[x, y]) for y in range(a, b + 1))]
    runs, s = [], None
    for x in cols:
        if s is None: s = p = x
        elif x - p > 14: runs.append((s, p)); s = x
        p = x
    if s is not None: runs.append((s, p))
    out = []
    for (xa, xb) in runs:
        c = Counter(px[x, y] for x in range(xa, xb + 1) for y in range(a, b + 1) if far(px[x, y]))
        top = c.most_common(1)[0][0]
        if max(top) - min(top) > 25 or True:
            # report most common, and most saturated colour
            sat = max(c, key=lambda k: (max(k) - min(k)) * (c[k] > 2))
            out.append(f"x{xa}-{xb} n={sum(c.values())} top={top} sat={sat}")
    print(f"band y{a}-{b}:"); [print("  ", o) for o in out]
