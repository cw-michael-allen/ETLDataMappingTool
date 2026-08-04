"""
One-off asset-prep script (not a runtime dependency of app.py). Converts the
bundled logo JPEGs -- which have a solid black background baked into the
pixels, not real transparency -- into proper transparent PNGs.

Chroma-keys out pixels close to the actual sampled background color (not a
naive "anything dark" luminance cutoff, which would incorrectly eat into the
dark-blue wordmark's anti-aliased edges). A soft-edge tolerance band avoids
jagged cutouts. Wordmark pixel colors are left completely unchanged -- only
the alpha channel is added/modified -- so this doesn't recolor or distort
the logo art itself.
"""

import sys
from PIL import Image


def sample_background(img, size=6):
    """Average a small corner block as the background reference color."""
    corner = img.crop((0, 0, size, size)).convert("RGB")
    pixels = list(corner.getdata())
    n = len(pixels)
    r = sum(p[0] for p in pixels) / n
    g = sum(p[1] for p in pixels) / n
    b = sum(p[2] for p in pixels) / n
    return (r, g, b)


def make_transparent(src_path, dst_path, inner=40, outer=75):
    img = Image.open(src_path).convert("RGB")
    bg = sample_background(img)
    print(f"{src_path}: sampled background RGB = {tuple(round(c) for c in bg)}")

    rgba = img.convert("RGBA")
    px = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            dist = ((r - bg[0]) ** 2 + (g - bg[1]) ** 2 + (b - bg[2]) ** 2) ** 0.5
            if dist <= inner:
                alpha = 0
            elif dist >= outer:
                alpha = 255
            else:
                alpha = round(255 * (dist - inner) / (outer - inner))
            px[x, y] = (r, g, b, alpha)

    rgba.save(dst_path)
    print(f"  -> saved {dst_path}")


if __name__ == "__main__":
    make_transparent("caseworthy-corporate.jpg", "caseworthy-corporate.png")
    make_transparent("servtracker.jpg", "servtracker.png")
