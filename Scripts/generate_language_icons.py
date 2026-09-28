#!/usr/bin/env python3
"""
Generate smoothed macOS squircle app icons for all supported languages:
- English (EN) -> default neon blue/purple (also used for main AppIcon.appiconset)
- Italian (IT) -> green / white / red
- Ukrainian (UK) -> blue / yellow

Each icon is cropped from the ChatGPT source images, anti-aliased with a high-resolution
supersampled macOS squircle mask, and exported in Retina and standard resolutions.
"""

import os
import json
from PIL import Image, ImageDraw, ImageFilter

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS_DIR = os.path.join(PROJECT_ROOT, "Docs")
ASSETS_DIR = os.path.join(PROJECT_ROOT, "SystemEQ for Mac", "Assets.xcassets")

SOURCES = {
    "uk": {
        "file": os.path.join(DOCS_DIR, "Immagine ChatGPT 28 set 2026, 21_14_55.png"),
        "crop": (12, 8, 12 + 1228, 8 + 1228),
    },
    "it": {
        "file": os.path.join(DOCS_DIR, "Immagine ChatGPT 28 set 2026, 21_16_19.png"),
        "crop": (12, 7, 12 + 1228, 7 + 1228),
    },
    "en": {
        "file": os.path.join(DOCS_DIR, "Immagine ChatGPT 28 set 2026, 21_20_03.png"),
        "crop": (12, 8, 12 + 1228, 8 + 1228),
    }
}

APPICON_SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

def make_squircle_mask(size: int, radius: int) -> Image.Image:
    # 4x supersampled mask for sub-pixel anti-aliasing
    hi_size = size * 4
    mask_hi = Image.new("L", (hi_size, hi_size), 0)
    draw = ImageDraw.Draw(mask_hi)
    draw.rounded_rectangle([(0, 0), (hi_size - 1, hi_size - 1)], radius=radius * 4, fill=255)
    return mask_hi.resize((size, size), Image.Resampling.LANCZOS)

def process_master_image(config: dict) -> Image.Image:
    """
    Produce standard macOS Xcode-like 1024x1024 icon canvas:
    - 864x864 squircle body (84.4% presence, matching Xcode / developer tools)
    - Squarer corners (radius=160px)
    - Ambient drop shadow (dy=12px, blur=20px, 38% black)
    """
    src_path = config["file"]
    crop_box = config["crop"]

    img = Image.open(src_path)
    cropped = img.crop(crop_box)

    canvas_size = 1024
    body_size = 864
    radius = 160

    # 1. Mask and resize body squircle
    mask = make_squircle_mask(body_size, radius)
    body_img = cropped.resize((body_size, body_size), Image.Resampling.LANCZOS).convert("RGBA")
    body_img.putalpha(mask)

    # 2. Compute placement (centered horizontally, top margin 72px)
    x_pos = (canvas_size - body_size) // 2  # 80px margin left/right
    y_pos = 72
    dy = 12

    # 3. Create drop shadow layer
    shadow_color = (0, 0, 0, int(255 * 0.38))
    shadow_hi = Image.new("RGBA", (canvas_size * 2, canvas_size * 2), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_hi)
    shadow_draw.rounded_rectangle(
        [
            (x_pos * 2, (y_pos + dy) * 2),
            ((x_pos + body_size - 1) * 2, (y_pos + dy + body_size - 1) * 2)
        ],
        radius=radius * 2,
        fill=shadow_color
    )
    shadow_layer = shadow_hi.resize((canvas_size, canvas_size), Image.Resampling.LANCZOS)
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=20))

    # 4. Composite final icon: canvas -> shadow -> squircle
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    canvas.alpha_composite(shadow_layer)
    canvas.alpha_composite(body_img, dest=(x_pos, y_pos))

    return canvas

def generate_appiconset(master_en: Image.Image, out_dir: str):
    os.makedirs(out_dir, exist_ok=True)
    for filename, size in APPICON_SIZES:
        scaled = master_en.resize((size, size), Image.Resampling.LANCZOS)
        scaled.save(os.path.join(out_dir, filename), "PNG", optimize=True)
        print(f"  ✓ {filename} ({size}x{size})")

def generate_imageset(master_img: Image.Image, out_dir: str, prefix: str):
    os.makedirs(out_dir, exist_ok=True)
    img_512 = master_img.resize((512, 512), Image.Resampling.LANCZOS)
    img_1024 = master_img

    fn_1x = f"{prefix}_512x512.png"
    fn_2x = f"{prefix}_512x512@2x.png"

    img_512.save(os.path.join(out_dir, fn_1x), "PNG", optimize=True)
    img_1024.save(os.path.join(out_dir, fn_2x), "PNG", optimize=True)

    contents = {
        "images": [
            {
                "idiom": "universal",
                "scale": "1x",
                "filename": fn_1x
            },
            {
                "idiom": "universal",
                "scale": "2x",
                "filename": fn_2x
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1
        }
    }

    with open(os.path.join(out_dir, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2)
    print(f"  ✓ {out_dir} generated")

def main():
    print("🎨 Processing icons for EN, IT, UK...")
    masters = {}
    for lang, cfg in SOURCES.items():
        print(f"Processing {lang.upper()} master...")
        masters[lang] = process_master_image(cfg)

    # 1. Update AppIcon.appiconset with English (default)
    print("\n📦 Updating AppIcon.appiconset (Default / EN)...")
    appiconset_dir = os.path.join(ASSETS_DIR, "AppIcon.appiconset")
    generate_appiconset(masters["en"], appiconset_dir)

    # 2. Update language-specific imagesets
    for lang in ["en", "it", "uk"]:
        print(f"\n📦 Updating AppIcon_{lang.upper()}.imageset...")
        imageset_dir = os.path.join(ASSETS_DIR, f"AppIcon_{lang.upper()}.imageset")
        generate_imageset(masters[lang], imageset_dir, f"icon_{lang}")

    print("\n✅ All icons successfully created and placed in Assets.xcassets!")

if __name__ == "__main__":
    main()
