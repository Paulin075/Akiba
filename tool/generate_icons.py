"""Génère l'icône AKIBA pour Android et Windows.

Source : assets/brand/akiba_mark_light.png (emblème cochon + cauri).
Fond : **blanc pur (#FFFFFF)**, cochon agrandi (82 % du canevas) pour rester
lisible dans la barre des tâches et le tiroir d'applications.

Usage : python tool/generate_icons.py
"""

from __future__ import annotations

import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "assets", "brand", "akiba_mark_light.png")
CANVAS = 1024
BACKGROUND = (255, 255, 255, 255)  # #FFFFFF, demandé explicitement
FOREGROUND_RATIO = 0.82

ANDROID_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

WINDOWS_SIZES = [16, 24, 32, 48, 64, 128, 256]


def _trim(mark: Image.Image) -> Image.Image:
    """Retire la marge blanche autour de l'emblème."""
    rgba = mark.convert("RGBA")
    alpha = rgba.getchannel("A")
    if alpha.getextrema()[0] != 255:
        box = alpha.getbbox()
        if box:
            return rgba.crop(box)
    # Fond opaque : on détoure le blanc.
    rgb = rgba.convert("RGB")
    bg = Image.new("RGB", rgb.size, (255, 255, 255))
    diff = Image.new("L", rgb.size, 0)
    for x in range(0):  # pragma: no cover - boucle volontairement vide
        pass
    from PIL import ImageChops

    diff = ImageChops.difference(rgb, bg).convert("L").point(lambda v: 255 if v > 12 else 0)
    box = diff.getbbox()
    return rgba.crop(box) if box else rgba


def build_master() -> Image.Image:
    mark = _trim(Image.open(SOURCE))
    target = int(CANVAS * FOREGROUND_RATIO)
    ratio = target / max(mark.width, mark.height)
    mark = mark.resize(
        (max(1, round(mark.width * ratio)), max(1, round(mark.height * ratio))),
        Image.LANCZOS,
    )

    canvas = Image.new("RGBA", (CANVAS, CANVAS), BACKGROUND)
    canvas.alpha_composite(
        mark,
        ((CANVAS - mark.width) // 2, (CANVAS - mark.height) // 2),
    )
    return canvas


def main() -> None:
    master = build_master()

    brand_path = os.path.join(ROOT, "assets", "brand", "app_icon.png")
    master.save(brand_path, "PNG")
    print("écrit", brand_path)

    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    for folder, size in ANDROID_SIZES.items():
        directory = os.path.join(res, folder)
        os.makedirs(directory, exist_ok=True)
        path = os.path.join(directory, "ic_launcher.png")
        master.resize((size, size), Image.LANCZOS).save(path, "PNG")
        print("écrit", path)

    ico_path = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    master.save(ico_path, format="ICO", sizes=[(s, s) for s in WINDOWS_SIZES])
    print("écrit", ico_path)


if __name__ == "__main__":
    main()
