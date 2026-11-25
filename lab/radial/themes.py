#!/usr/bin/env python3
"""E-005 driver: one iTerm2 window per test theme via the iTerm2 Python API, grey track at several contrast ratios.

Needs iTerm2 > Settings > General > Magic > Enable Python API. Run: uv run --with iterm2 themes.py -o <dir>
"""
import argparse
import asyncio
import os
import subprocess

import iterm2

from grey import grey_for, parse_rgb

HERE = os.path.dirname(os.path.abspath(__file__))
THEMES = [  # name, background, foreground
    ("current", "0E2A35", "8693A0"), ("black", "000000", "C7C7C7"), ("white", "FFFFFF", "333333"),
    ("solarized-light", "FDF6E3", "657B83"), ("dracula", "282A36", "F8F8F2"), ("mid-grey", "777777", "111111"),
]


def color(hexrgb):
    return iterm2.Color(*parse_rgb(hexrgb))


async def run(connection, args):
    ratios = [float(x) for x in args.ratios.split(",")]
    wanted = set(args.themes.split(",")) if args.themes else None
    for name, bg, fg in THEMES:
        if wanted and name not in wanted:
            continue
        prof = iterm2.LocalWriteOnlyProfile()
        for suffix in ("", "_light", "_dark"):
            for kind, value in (("background", bg), ("foreground", fg)):
                setter = getattr(prof, f"set_{kind}_color{suffix}", None)
                if setter:
                    setter(color(value))
        window = await iterm2.Window.async_create(connection, profile_customizations=prof)
        await asyncio.sleep(args.settle)
        neutrals = ",".join("%d;%d;%d" % grey_for(parse_rgb(bg), t) for t in ratios)
        cmd = f"exec {HERE}/demo2.sh -n '{neutrals}' -t {args.track} -r {args.arcs} --tile -s {args.hold}\n"
        await window.current_tab.current_session.async_send_text(cmd)
        await asyncio.sleep(3)
        wid = subprocess.run(["osascript", "-e", 'tell application "iTerm2" to id of current window'],
                             capture_output=True, text=True).stdout.strip()
        out = os.path.join(args.output, f"e5-{name}.png")
        subprocess.run(["screencapture", "-x", "-o", "-l", wid, out], check=False)
        print(name, bg, neutrals, out, flush=True)
        await window.async_close(force=True)
        await asyncio.sleep(1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", required=True, help="directory for screenshots")
    ap.add_argument("-r", "--ratios", default="1.5,1.75,2.0,2.5", help="target contrast ratios, one demo row each")
    ap.add_argument("-m", "--themes", default="", help="comma-separated theme names; default all")
    ap.add_argument("-t", "--track", default="FFA00", help="hex base of the remainder glyphs")
    ap.add_argument("-a", "--arcs", default="FFA80", help="hex base of the arc glyphs")
    ap.add_argument("-s", "--settle", type=float, default=6.0, help="seconds to wait for the shell before sending the demo")
    ap.add_argument("-d", "--hold", type=int, default=8, help="seconds the demo stays on screen")
    args = ap.parse_args()
    os.makedirs(args.output, exist_ok=True)
    iterm2.run_until_complete(lambda c: run(c, args))


if __name__ == "__main__":
    main()
