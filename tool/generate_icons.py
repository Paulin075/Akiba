"""Génère l'icône AKIBA pour Android et Windows.

Source : assets/brand/akiba_mark_light.png (emblème cochon + cauri).
Fond : **blanc pur (#FFFFFF)**, cochon agrandi (90 % du canevas) pour rester
lisible dans la barre des tâches et le tiroir d'applications.

Android 8+ (API 26) : icône **adaptative** composée de
  - `drawable-*/ic_launcher_foreground.png` (108 dp, emblème dans la zone sûre),
  - `values/colors.xml` → `ic_launcher_background` (#FFFFFF),
  - `mipmap-anydpi-v26/ic_launcher.xml` et `ic_launcher_round.xml`.
Les icônes héritées (`mipmap-*/ic_launcher.png`) restent pour les anciens
appareils.

Le logo du splash natif est écrit dans `drawable-*/akiba_launch_logo.png` :
un `<bitmap>` ne peut pas référencer une icône adaptative (XML), sinon le
lancement Android 8+ échoue.

Usage : python tool/generate_icons.py
"""

from __future__ import annotations

import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "assets", "brand", "akiba_mark_light.png")
CANVAS = 1024
BACKGROUND = (255, 255, 255, 255)  # #FFFFFF, demandé explicitement
FOREGROUND_RATIO = 0.90
# Zone sûre de l'icône adaptative : 66 dp sur 108 dp. L'emblème tient dans
# 56 % du canevas pour ne jamais être rogné par le masque du lanceur.
ADAPTIVE_MARK_RATIO = 0.56

ANDROID_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# 108 dp de canevas adaptatif, une densité par dossier.
ADAPTIVE_SIZES = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}

# Logo centré du splash natif (128 dp, même rendu que l'ancien mipmap).
LAUNCH_SIZES = {
    "drawable-mdpi": 128,
    "drawable-hdpi": 192,
    "drawable-xhdpi": 256,
    "drawable-xxhdpi": 384,
    "drawable-xxxhdpi": 512,
}

WINDOWS_SIZES = [16, 24, 32, 48, 64, 128, 256]

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""


def _trim(mark: Image.Image) -> Image.Image:
    """Retire la marge autour de l'emblème."""
    rgba = mark.convert("RGBA")
    alpha = rgba.getchannel("A")
    if alpha.getextrema()[0] != 255:
        box = alpha.getbbox()
        if box:
            return rgba.crop(box)
    # Fond opaque : on détoure le blanc.
    from PIL import ImageChops

    rgb = rgba.convert("RGB")
    bg = Image.new("RGB", rgb.size, (255, 255, 255))
    diff = ImageChops.difference(rgb, bg).convert("L").point(
        lambda v: 255 if v > 12 else 0
    )
    box = diff.getbbox()
    return rgba.crop(box) if box else rgba


def _scaled_mark(canvas: int, ratio: float) -> Image.Image:
    mark = _trim(Image.open(SOURCE))
    target = int(canvas * ratio)
    factor = target / max(mark.width, mark.height)
    return mark.resize(
        (max(1, round(mark.width * factor)), max(1, round(mark.height * factor))),
        Image.LANCZOS,
    )


def build_master() -> Image.Image:
    mark = _scaled_mark(CANVAS, FOREGROUND_RATIO)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), BACKGROUND)
    canvas.alpha_composite(
        mark,
        ((CANVAS - mark.width) // 2, (CANVAS - mark.height) // 2),
    )
    return canvas


def build_foreground(size: int) -> Image.Image:
    """Avant-plan adaptatif : emblème transparent, sans fond."""
    mark = _scaled_mark(size, ADAPTIVE_MARK_RATIO)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(
        mark,
        ((size - mark.width) // 2, (size - mark.height) // 2),
    )
    return canvas


def write_adaptive_icon(res: str) -> None:
    anydpi = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        path = os.path.join(anydpi, name)
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(ADAPTIVE_XML)
        print("écrit", path)

    for folder, size in ADAPTIVE_SIZES.items():
        directory = os.path.join(res, folder)
        os.makedirs(directory, exist_ok=True)
        path = os.path.join(directory, "ic_launcher_foreground.png")
        build_foreground(size).save(path, "PNG")
        print("écrit", path)


def main() -> None:
    master = build_master()
    mark = Image.open(SOURCE).convert("RGBA")
    mark = _trim(mark)

    brand_path = os.path.join(ROOT, "assets", "brand", "app_icon.png")
    master.save(brand_path, "PNG")
    print("écrit", brand_path)

    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    for folder, size in ANDROID_SIZES.items():
        directory = os.path.join(res, folder)
        os.makedirs(directory, exist_ok=True)
        icon = master.resize((size, size), Image.LANCZOS)
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            path = os.path.join(directory, name)
            icon.save(path, "PNG")
            print("écrit", path)

    write_adaptive_icon(res)

    for folder, size in LAUNCH_SIZES.items():
        directory = os.path.join(res, folder)
        os.makedirs(directory, exist_ok=True)
        logo = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        # 90 % du canevas : l'emblème respire, sans être rogné au lancement.
        inner = int(size * 0.9)
        scaled = mark.resize(
            (inner, round(inner * mark.height / mark.width)),
            Image.LANCZOS,
        )
        if scaled.height > inner:
            scaled = mark.resize(
                (
                    round(inner * mark.width / mark.height),
                    inner,
                ),
                Image.LANCZOS,
            )
        logo.alpha_composite(
            scaled,
            ((size - scaled.width) // 2, (size - scaled.height) // 2),
        )
        path = os.path.join(directory, "akiba_launch_logo.png")
        logo.save(path, "PNG")
        print("écrit", path)

    ico_path = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    master.save(ico_path, format="ICO", sizes=[(s, s) for s in WINDOWS_SIZES])
    print("écrit", ico_path)


if __name__ == "__main__":
    main()
