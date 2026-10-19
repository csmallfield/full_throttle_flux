#!/usr/bin/env python3
"""Motion blur check: is the ship sharp while the world streaks?

Needs <name>_off.png, <name>_on.png and <name>_noship.png from
render_motion_shots.gd (variants ["off", "on", "noship"]).
  ship mask  = pixels where off and noship differ (the ships), eroded 2 px
  world mask = everything else, dilated away from the ships by 8 px
Reports the mean absolute on/off difference (0..255) inside each mask and the
ratio. A sharp ship has ship_diff close to 0 while world_diff is large.

usage: python3 tools/dev/mb_metrics.py <dir> [name ...]
       (no names: every *_noship.png in <dir>)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def load(p):
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)


def morph(mask, px, grow):
    img = Image.fromarray((mask * 255).astype(np.uint8))
    f = ImageFilter.MaxFilter if grow else ImageFilter.MinFilter
    for _ in range(px):
        img = img.filter(f(3))
    return np.asarray(img) > 127


def main():
    d = Path(sys.argv[1])
    names = sys.argv[2:] or sorted(p.name[: -len("_noship.png")] for p in d.glob("*_noship.png"))
    print(f"{'shot':24s} {'ship px':>8s} {'ship diff':>9s} {'world diff':>10s} {'ratio':>6s}")
    for n in names:
        on, noship = d / f"{n}_on.png", d / f"{n}_noship.png"
        off = d / f"{n}_off.png"
        if not (on.exists() and noship.exists() and off.exists()):
            print(f"{n:24s} missing images")
            continue
        a_on, a_ns, ref = load(on), load(noship), load(off)
        ship = np.abs(ref - a_ns).max(axis=2) > 12.0
        core = morph(ship, 2, grow=False)
        world = ~morph(ship, 8, grow=True)
        diff = np.abs(a_on - ref).mean(axis=2)
        sd = float(diff[core].mean()) if core.any() else float("nan")
        wd = float(diff[world].mean())
        print(f"{n:24s} {int(core.sum()):8d} {sd:9.2f} {wd:10.2f} {sd / max(wd, 1e-6):6.2f}")


if __name__ == "__main__":
    main()
