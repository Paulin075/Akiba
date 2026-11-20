"""Prépare les visuels fournis dans akiba_spec/.

1. `akiba_spec/argent.jpg` devient l'avatar système par défaut
   (`assets/profile/avatar_default.jpg`).
2. Le cauri de l'emblème officiel est détouré depuis
   `akiba_spec/Logo/akiba_mark_light.png` et enregistré en PNG transparent
   (`assets/brand/cauri.png`) pour l'animation d'ouverture.

Usage : python tool/prepare_visual_assets.py
"""

from __future__ import annotations

import os

from PIL import Image, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "akiba_spec")


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
    source = os.path.join(SPEC, "Logo", "akiba_mark_light.png")
    image = Image.open(source).convert("RGBA")
    # Le cauri occupe la partie haute de l'emblème ; le cochon commence plus bas.
    head = image.crop((0, 0, image.width, int(image.height * 0.44)))

    # Rend le fond blanc transparent, puis recadre sur le dessin.
    pixels = head.load()
    for y in range(head.height):
        for x in range(head.width):
            r, g, b, a = pixels[x, y]
            if r > 240 and g > 240 and b > 240:
                pixels[x, y] = (r, g, b, 0)

    alpha = head.getchannel("A")
    box = alpha.getbbox()
    if box:
        head = head.crop(box)

    out_dir = os.path.join(ROOT, "assets", "brand")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "cauri.png")
    head.save(path, "PNG")
    print("écrit", path)


def main() -> None:
    build_default_avatar()
    build_cauri()


if __name__ == "__main__":
    main()
