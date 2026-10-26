#!/usr/bin/env python3
"""Bake the wall scrape-mark decal textures (v35 Phase 3).

    python3 tools/env/bake_scuff.py [--preview preview.png]

Writes, 512 x 128 (scrape direction = +X):
  assets/fx/scuff_albedo.png    dark scorch + streaks, bright bare-metal
                                scratch lines; alpha = soft, ragged mark
  assets/fx/scuff_emission.png  the hot part: the scratch lines and the scorch
                                core, for the fresh-scrape glow that cools off

Deterministic (seed 35). Needs numpy and Pillow.
"""
import sys
import numpy as np
from PIL import Image

W, H = 512, 128
SEED = 35


def value_noise(rng, w, h, cx, cy):
    lattice = rng.random((cy + 3, cx + 3)).astype(np.float32)
    img = Image.fromarray((lattice * 255).astype(np.uint8), "L")
    big = img.resize((w * (cx + 3) // cx, h * (cy + 3) // cy), Image.BICUBIC)
    a = np.asarray(big, dtype=np.float32) / 255.0
    ox, oy = w // cx, h // cy
    return a[oy:oy + h, ox:ox + w]


def fbm(rng, w, h, cx, cy, octaves=4):
    total = np.zeros((h, w), np.float32)
    amp = norm = 0.0
    amp = 1.0
    for _ in range(octaves):
        total += value_noise(rng, w, h, cx, cy) * amp
        norm += amp
        amp *= 0.5
        cx *= 2
        cy *= 2
    return total / norm


def main():
    rng = np.random.default_rng(SEED)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    u = xx / (W - 1) * 2 - 1          # along the scrape
    v = yy / (H - 1) * 2 - 1          # across

    # Ragged lozenge: long along X, tapering at both ends, wobbly edges.
    edge_n = fbm(rng, W, H, 12, 2)
    across = np.abs(v) + (edge_n - 0.5) * 0.5
    width = 1.0 - np.abs(u) ** 2.2 * 0.55   # mild taper: bridged marks join up
    body = np.clip((width - across) / 0.35, 0, 1)
    body = body * body * (3 - 2 * body)

    # Streaks along the scrape: noise stretched hard along X.
    streak = fbm(rng, W, H, 3, 24)
    streak2 = fbm(rng, W, H, 6, 48)
    scorch = body * (0.45 + 0.55 * streak) * (0.7 + 0.3 * streak2)

    # Bare-metal scratch lines: a few thin bright lines, broken along their length.
    scratch = np.zeros((H, W), np.float32)
    for _ in range(14):
        y0 = rng.uniform(-0.55, 0.55)
        thick = rng.uniform(0.008, 0.025)
        slope = rng.uniform(-0.04, 0.04)
        line = np.exp(-((v - y0 - slope * u) / thick) ** 2)
        broken = (fbm(rng, W, H, rng.integers(4, 10), 1, 3) > rng.uniform(0.35, 0.55)).astype(np.float32)
        scratch = np.maximum(scratch, line * broken * rng.uniform(0.5, 1.0))
    scratch *= body

    # Albedo: scorch is dark brown-black, scratches bright grey metal.
    dark = np.array([0.06, 0.05, 0.045])
    soot = np.array([0.16, 0.13, 0.10])
    metal = np.array([0.78, 0.78, 0.80])
    col = dark * scorch[..., None] + soot * (1 - scorch[..., None])
    col = col * (1 - scratch[..., None]) + metal * scratch[..., None]
    alpha = np.clip(scorch * 1.4 + scratch, 0, 1)

    albedo = np.concatenate([col, alpha[..., None]], axis=-1)
    Image.fromarray((np.clip(albedo, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save("assets/fx/scuff_albedo.png")

    # Emission: scratches hot, scorch core warm.
    core = np.clip((scorch - 0.45) / 0.4, 0, 1) * body
    emis = np.clip(scratch * 1.0 + core * 0.35, 0, 1)
    rgb = np.stack([emis, emis * 0.45, emis * 0.12], axis=-1)   # orange-hot
    Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), "RGB").save("assets/fx/scuff_emission.png")
    print("bake_scuff: assets/fx/scuff_albedo.png, assets/fx/scuff_emission.png (%d x %d)" % (W, H))

    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        wall = np.full((H, W, 3), 0.32)
        a = alpha[..., None]
        cold = wall * (1 - a) + col * a
        hot = np.clip(cold + rgb * 1.5, 0, 1)
        Image.fromarray((np.concatenate([cold, hot], axis=0) * 255).astype(np.uint8), "RGB").save(out)
        print("bake_scuff: preview %s (top: cold, bottom: fresh/hot)" % out)


if __name__ == "__main__":
    main()
