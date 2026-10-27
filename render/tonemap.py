"""HDR-буфер трассировщика -> PNG.

1. Денойз: à-trous вейвлет-фильтр по освещённости (цвет / альбедо) с удержанием
   краёв по нормалям, глубине, альбедо и яркости. Металл, стекло, светильники
   и зеркальные поверхности не фильтруются.
2. Экспозиция, ACES filmic, sRGB.

usage: python3 tonemap.py in.bin out.png [EV] [--raw]
"""
import sys

import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
ev = float(sys.argv[3]) if len(sys.argv) > 3 and not sys.argv[3].startswith("--") else 0.0
raw_only = "--raw" in sys.argv

w, h = (int(v) for v in np.fromfile(src, dtype=np.int32, count=2))
data = np.fromfile(src, dtype=np.float32, offset=8)
color = np.nan_to_num(data[: h * w * 3].reshape(h, w, 3), nan=0.0, posinf=0.0)
aux = data[h * w * 3:].reshape(h, w, 8)
alb, nrm, depth, filt = aux[..., 0:3], aux[..., 3:6], aux[..., 6], aux[..., 7] > 0.5

LUM = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


def shifted(a, dy, dx):
    """Сдвиг с повтором краёв (без заворачивания)."""
    pad = max(abs(dy), abs(dx))
    p = np.pad(a, ((pad, pad), (pad, pad)) + ((0, 0),) * (a.ndim - 2), mode="edge")
    return p[pad + dy: pad + dy + h, pad + dx: pad + dx + w]


def local_std(lum):
    m = np.zeros_like(lum)
    m2 = np.zeros_like(lum)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            s = shifted(lum, dy, dx)
            m += s
            m2 += s * s
    m /= 9
    return np.sqrt(np.maximum(m2 / 9 - m * m, 0))


def atrous(irr):
    k = [1 / 16, 1 / 4, 3 / 8, 1 / 4, 1 / 16]
    out = irr.copy()
    for it in range(5):
        step = 1 << it
        lum = out @ LUM
        sigma = 3.0 * local_std(lum) + 1e-4
        acc = np.zeros_like(out)
        wsum = np.zeros((h, w), dtype=np.float32)
        for j, ky in enumerate(k):
            for i, kx in enumerate(k):
                dy, dx = (j - 2) * step, (i - 2) * step
                q = shifted(out, dy, dx)
                wn = np.clip(np.sum(nrm * shifted(nrm, dy, dx), axis=-1), 0, 1) ** 64
                wd = np.exp(-np.abs(depth - shifted(depth, dy, dx)) / (0.015 * depth * step + 1e-3))
                wa = np.exp(-np.sum((alb - shifted(alb, dy, dx)) ** 2, axis=-1) / 0.004)
                wl = np.exp(-np.abs(lum - q @ LUM) / sigma)
                wgt = ky * kx * wn * wd * wa * wl * shifted(filt, dy, dx)
                acc += q * wgt[..., None]
                wsum += wgt
        out = np.where(filt[..., None], acc / np.maximum(wsum, 1e-8)[..., None], out)
    return out


img = color
if not raw_only:
    a = np.maximum(alb, 1e-3)
    img = np.where(filt[..., None], atrous(color / a) * a, color)

# автоэкспозиция по среднему логарифму яркости + ручная поправка в EV
lumi = img @ LUM
key = np.exp(np.mean(np.log(lumi + 1e-4)))
x = img * (0.20 / key) * 2.0 ** ev


def aces(v):
    a, b, c, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    return np.clip(v * (a * v + b) / (v * (c * v + d) + e), 0, 1)


y = aces(x)
y = np.where(y <= 0.0031308, 12.92 * y, 1.055 * np.power(y, 1 / 2.4) - 0.055)
Image.fromarray((np.clip(y, 0, 1) * 255 + 0.5).astype(np.uint8)).save(dst)
print(f"{dst}: {w}x{h}, key={key:.4f}")
