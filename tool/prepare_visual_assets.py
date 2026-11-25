"""Prépare les visuels fournis dans akiba_spec/.

1. `akiba_spec/argent.jpg` devient l'avatar système par défaut
   (`assets/profile/avatar_default.jpg`).
2. Le cauri officiel (`akiba_spec/cauris.png`) est détouré et recadré sur le
   dessin : c'est l'objet qui tombe dans la tirelire (`assets/brand/cauri.png`).
3. La tirelire **sans cauri** vient de `akiba_spec/Logo/preview.png` (le cochon
   seul, entier, fente comprise) et devient `assets/brand/cochon.png`.

Le fond n'est plus retiré « à la couleur » : un blanc interne (l'œil, les
stries du cauri) doit rester blanc. Seul le blanc **relié au bord** est rendu
transparent, par diffusion (flood fill).

Usage : python tool/prepare_visual_assets.py
"""

from __future__ import annotations

import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "akiba_spec")
BRAND = os.path.join(ROOT, "assets", "brand")


def _cut_background(image: Image.Image, threshold: int = 238) -> Image.Image:
    """Rend transparent le fond clair relié aux bords, sans toucher aux blancs
    internes (œil du cochon, stries du cauri)."""
    image = image.convert("RGBA")
    width, height = image.size
    pixels = image.load()
    seen = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def light(x: int, y: int) -> bool:
        r, g, b, a = pixels[x, y]
        return a > 0 and r >= threshold and g >= threshold and b >= threshold

    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if x < 0 or y < 0 or x >= width or y >= height:
            continue
        index = y * width + x
        if seen[index]:
            continue
        seen[index] = 1
        if not light(x, y):
            continue
        r, g, b, _ = pixels[x, y]
        pixels[x, y] = (r, g, b, 0)
        queue.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return image


def _trim(image: Image.Image, margin: int = 4) -> Image.Image:
    box = image.getchannel("A").getbbox()
    if not box:
        return image
    left, top, right, bottom = box
    return image.crop(
        (
            max(0, left - margin),
            max(0, top - margin),
            min(image.width, right + margin),
            min(image.height, bottom + margin),
        )
    )


def _save(image: Image.Image, path: str, height: int) -> None:
    width = max(1, round(image.width * height / image.height))
    image.resize((width, height), Image.LANCZOS).save(path, "PNG")
    print("écrit", path, (width, height))


def build_default_avatar() -> None:
    source = os.path.join(SPEC, "argent.jpg")
    out_dir = os.path.join(ROOT, "assets", "profile")
    os.makedirs(out_dir, exist_ok=True)
    image = Image.open(source).convert("RGB")
    side = min(image.width, image.height)
    left = (image.width - side) // 2
    top = (image.height - side) // 2
    image = image.crop((left, top, left + side, top + side)).resize(
        (512, 512), Image.LANCZOS
    )
    path = os.path.join(out_dir, "avatar_default.jpg")
    image.save(path, "JPEG", quality=90)
    print("écrit", path)


def build_cauri() -> None:
    """Le cauri fourni par le porteur : `akiba_spec/cauris.png`."""
    source = os.path.join(SPEC, "cauris.png")
    image = _trim(_cut_background(Image.open(source)))
    _save(image, os.path.join(BRAND, "cauri.png"), 360)


def build_piggy() -> None:
    """La tirelire seule, entière : `akiba_spec/Logo/preview.png`."""
    source = os.path.join(SPEC, "Logo", "preview.png")
    image = _trim(_cut_background(Image.open(source)))
    os.makedirs(BRAND, exist_ok=True)
    _save(image, os.path.join(BRAND, "cochon.png"), 260)


def main() -> None:
    build_default_avatar()
    build_cauri()
    build_piggy()


if __name__ == "__main__":
    main()
