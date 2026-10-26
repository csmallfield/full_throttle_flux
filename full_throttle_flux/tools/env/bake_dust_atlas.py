#!/usr/bin/env python3
"""Bake the dust / spray / powder puff atlas (v35).

    python3 tools/env/bake_dust_atlas.py [out.png] [--preview preview.png]

8 x 8 tiles of 128 px (1024 x 1024 RGBA), each a different puff:
  R, G  normal x, y (0.5 = flat), from the puff's own height field
  B     thickness 0..1 (thick core = 1); the shader dissolves thin parts first
        and darkens thick parts for a self-shadowed, volumetric read
  A     density (opacity)

A puff is a lumpy cluster of soft blobs (cauliflower silhouette) carved by
domain-warped fractal noise, with an irregular, noise-eroded edge that is
always zero at the tile border (no square cut-offs). Deterministic: same seed,
same atlas. Needs numpy and Pillow.
"""
import sys
import numpy as np
from PIL import Image

TILE = 128
GRID = 8
SEED = 35


def value_noise(rng, size, cells):
    """Smooth value noise on a size x size grid with `cells` lattice cells."""
    lattice = rng.random((cells + 3, cells + 3)).astype(np.float32)
    img = Image.fromarray((lattice * 255).astype(np.uint8), "L")
    big = img.resize((size * (cells + 3) // cells, size * (cells + 3) // cells), Image.BICUBIC)
    a = np.asarray(big, dtype=np.float32) / 255.0
    o = size // cells
    return a[o:o + size, o:o + size]


def fbm(rng, size, base_cells=3, octaves=5, gain=0.5):
    total = np.zeros((size, size), np.float32)
    amp, norm = 1.0, 0.0
    cells = base_cells
    for _ in range(octaves):
        total += value_noise(rng, size, cells) * amp
        norm += amp
        amp *= gain
        cells *= 2
    return total / norm


def warp(field, dx, dy, strength):
    """Sample `field` at coordinates displaced by dx, dy (in pixels * strength)."""
    h, w = field.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    sx = np.clip(xx + (dx - 0.5) * strength, 0, w - 1)
    sy = np.clip(yy + (dy - 0.5) * strength, 0, h - 1)
    x0, y0 = np.floor(sx).astype(int), np.floor(sy).astype(int)
    x1, y1 = np.minimum(x0 + 1, w - 1), np.minimum(y0 + 1, h - 1)
    fx, fy = sx - x0, sy - y0
    return (field[y0, x0] * (1 - fx) * (1 - fy) + field[y0, x1] * fx * (1 - fy)
            + field[y1, x0] * (1 - fx) * fy + field[y1, x1] * fx * fy)


def blur(a, passes=2):
    for _ in range(passes):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5.0
    return a


def puff(rng):
    n = TILE
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    u = (xx + 0.5) / n * 2.0 - 1.0
    v = (yy + 0.5) / n * 2.0 - 1.0

    # Cluster of soft blobs inside the tile. A quarter of the puffs are wispy:
    # stretched along a random direction (dust streaming off the hull).
    wispy = rng.random() < 0.25
    stretch = rng.uniform(1.6, 2.6) if wispy else rng.uniform(1.0, 1.25)
    theta = rng.random() * np.pi
    ca, sa = np.cos(theta), np.sin(theta)
    ru = (u * ca + v * sa) / stretch
    rv = -u * sa + v * ca
    blobs = np.zeros((n, n), np.float32)
    count = rng.integers(6, 13)
    for _ in range(count):
        ang = rng.random() * np.pi * 2
        dist = rng.random() ** 0.6 * 0.46
        cx, cy = np.cos(ang) * dist, np.sin(ang) * dist
        r = rng.uniform(0.24, 0.46)
        d2 = ((ru - cx / stretch) ** 2 + (rv - cy) ** 2) / (r * r)
        blobs += np.exp(-d2 * 1.2) * rng.uniform(0.55, 1.0)
    blobs /= blobs.max()
    # Domain-warped fractal detail.
    detail = fbm(rng, n, base_cells=4, octaves=5)
    wx, wy = fbm(rng, n, 3, 3), fbm(rng, n, 3, 3)
    detail = warp(detail, wx, wy, n * 0.18)
    billow = 1.0 - np.abs(fbm(rng, n, 6, 4) * 2.0 - 1.0)   # puffy ridges

    # Detail carves holes and wisps through the cluster rather than tinting it.
    dens = blobs * (0.2 + 1.1 * detail) * (0.55 + 0.6 * billow) - 0.18 * (1.0 - blobs)

    # Irregular edge, guaranteed zero at the border.
    r = np.sqrt(u * u + v * v)
    edge_noise = fbm(rng, n, 5, 4)
    edge = np.clip((1.02 - r - (edge_noise - 0.5) * 0.4) / 0.3, 0.0, 1.0)
    edge = edge * edge * (3 - 2 * edge)
    dens *= edge
    border = np.clip(np.minimum.reduce([xx, yy, n - 1 - xx, n - 1 - yy]) / 6.0, 0, 1)
    dens *= border

    dens = np.clip((dens - 0.035) / 0.68, 0.0, 1.0)
    dens = dens ** 1.4

    # Thickness and normals from a smoothed height field.
    height = blur(dens, 3)
    height /= max(height.max(), 1e-4)
    gy, gx = np.gradient(height)
    k = 6.0
    nx, ny, nz = -gx * k, -gy * k, np.ones_like(height)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny = nx / ln, ny / ln
    return np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, height, dens], axis=-1)


def main():
    out = "assets/fx/dust_puffs.png"
    preview = None
    args = sys.argv[1:]
    if "--preview" in args:
        i = args.index("--preview")
        preview = args[i + 1]
        args = args[:i] + args[i + 2:]
    if args:
        out = args[0]
    rng = np.random.default_rng(SEED)
    atlas = np.zeros((TILE * GRID, TILE * GRID, 4), np.float32)
    for gy in range(GRID):
        for gx in range(GRID):
            atlas[gy * TILE:(gy + 1) * TILE, gx * TILE:(gx + 1) * TILE] = puff(rng)
    img = Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    img.save(out)
    print("bake_dust_atlas: %s (%d x %d, %d puffs)" % (out, img.width, img.height, GRID * GRID))
    if preview:
        # Density over dark grey, lit by the normals from the top-left.
        a = atlas[..., 3:4]
        lam = np.clip((atlas[..., 0] - 0.5) * -1.2 + (atlas[..., 1] - 0.5) * -1.2 + 0.75, 0, 1)[..., None]
        shade = (0.55 + 0.45 * atlas[..., 2:3]) * lam
        col = np.array([0.72, 0.6, 0.45]) * shade
        bg = np.full_like(col, 0.12)
        rgb = bg * (1 - a) + col * a
        Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB").save(preview)
        print("bake_dust_atlas: preview %s" % preview)


if __name__ == "__main__":
    main()
