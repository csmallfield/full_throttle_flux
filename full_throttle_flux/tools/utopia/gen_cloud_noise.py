#!/usr/bin/env python3
"""Tileable cloud noise volumes for the Utopia sky (numpy; no Godot needed).

Writes raw 8-bit volumes next to the sky shader:
  sky/cloud_shape_128.raw   128^3  Perlin-Worley  (billowy cumulus shape)
  sky/cloud_detail_64.raw    64^3  Worley FBM     (edge erosion)
tools/utopia/bake_cloud_noise.gd turns them into ImageTexture3D .res files.
Every octave uses an integer lattice period that divides the volume, so the
volumes tile perfectly in all three axes.
    python3 tools/utopia/gen_cloud_noise.py
"""
import numpy as np, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SKY = os.path.join(HERE, "..", "..", "scenes", "tracks", "utopia", "sky")

def fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)

def perlin(n, period, rng):
    """Periodic gradient noise, `period` cells across an n^3 volume. Range ~[-1,1]."""
    g = rng.normal(size=(period, period, period, 3))
    g /= np.linalg.norm(g, axis=-1, keepdims=True)
    c = (np.arange(n) + 0.5) * period / n
    x, y, z = np.meshgrid(c, c, c, indexing="ij")
    xi, yi, zi = np.floor(x).astype(int), np.floor(y).astype(int), np.floor(z).astype(int)
    xf, yf, zf = x - xi, y - yi, z - zi
    out = np.zeros((n, n, n))
    u, v, w = fade(xf), fade(yf), fade(zf)
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                gg = g[(xi + dx) % period, (yi + dy) % period, (zi + dz) % period]
                dot = gg[..., 0] * (xf - dx) + gg[..., 1] * (yf - dy) + gg[..., 2] * (zf - dz)
                wt = (u if dx else 1 - u) * (v if dy else 1 - v) * (w if dz else 1 - w)
                out += wt * dot
    return out * 1.6

def worley(n, period, rng):
    """Periodic Worley F1, one feature point per cell. Returns inverted [0,1] (1 = cell centre)."""
    pts = rng.random((period, period, period, 3))
    c = (np.arange(n) + 0.5) * period / n
    x, y, z = np.meshgrid(c, c, c, indexing="ij")
    xi, yi, zi = np.floor(x).astype(int), np.floor(y).astype(int), np.floor(z).astype(int)
    best = np.full((n, n, n), 9.0)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                cx, cy, cz = xi + dx, yi + dy, zi + dz
                p = pts[cx % period, cy % period, cz % period]
                d = (cx + p[..., 0] - x) ** 2 + (cy + p[..., 1] - y) ** 2 + (cz + p[..., 2] - z) ** 2
                best = np.minimum(best, d)
    return 1.0 - np.clip(np.sqrt(best), 0.0, 1.0)

def fbm(fn, n, base, octaves, rng, gain=0.5):
    acc, amp, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        acc = acc + amp * fn(n, base * (2 ** o), rng)
        tot += amp
        amp *= gain
    return acc / tot

def remap(v, lo, hi, nlo=0.0, nhi=1.0):
    return nlo + (v - lo) / np.maximum(hi - lo, 1e-6) * (nhi - nlo)

def save(vol, name):
    vol = np.clip(vol, 0.0, 1.0)
    vol = (vol - vol.min()) / max(vol.max() - vol.min(), 1e-6)
    data = (vol * 255.0 + 0.5).astype(np.uint8)
    # Godot ImageTexture3D: slices along z, each slice row-major (y, x)
    data = np.transpose(data, (2, 1, 0)).copy()
    path = os.path.join(SKY, name)
    data.tofile(path)
    print("wrote", os.path.relpath(path), data.shape)
    return data

def main():
    rng = np.random.default_rng(7)
    # SHAPE: Perlin FBM dilated by Worley FBM (Schneider/HZD "Perlin-Worley")
    n = 128
    p = fbm(perlin, n, 4, 4, rng) * 0.5 + 0.5
    w = fbm(worley, n, 4, 3, rng, gain=0.6)
    pw = np.clip(remap(p, w - 1.0, 1.0), 0.0, 1.0)
    shape = save(pw * 0.65 + w * 0.35, "cloud_shape_128.raw")
    # DETAIL: higher-frequency Worley FBM
    d = fbm(worley, 64, 4, 3, rng, gain=0.55)
    detail = save(d, "cloud_detail_64.raw")
    if "--preview" in sys.argv:
        from PIL import Image
        Image.fromarray(shape[64]).resize((384, 384)).save("/tmp/shape_slice.png")
        Image.fromarray(detail[32]).resize((384, 384)).save("/tmp/detail_slice.png")

main()
