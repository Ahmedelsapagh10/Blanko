#!/usr/bin/env python3
import json
import os
import subprocess

WORKSPACE = "/Users/ahmedelsapagh/Downloads/whiteboard"
LIGHT_ICON_1024 = os.path.join(WORKSPACE, "design/brand/icons/blanko_app_icon_light_1024.png")
SYMBOL_TRANSPARENT_4096 = os.path.join(WORKSPACE, "design/brand/icons/blanko_symbol_transparent_4096.png")

def sips_resize(src, dst, width, height):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    subprocess.run(["sips", "-z", str(height), str(width), src, "--out", dst], check=True, stdout=subprocess.DEVNULL)

def sips_pad(src, dst, pad_w, pad_h):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    subprocess.run(["sips", "-p", str(pad_h), str(pad_w), src, "--out", dst], check=True, stdout=subprocess.DEVNULL)

def generate_android_icons():
    densities = {
        "mdpi": (48, 108, 72),
        "hdpi": (72, 162, 108),
        "xhdpi": (96, 216, 144),
        "xxhdpi": (144, 324, 216),
        "xxxhdpi": (192, 432, 288),
    }
    for density, (legacy_size, adaptive_size, symbol_size) in densities.items():
        # Legacy full icon
        legacy_path = os.path.join(WORKSPACE, f"android/app/src/main/res/mipmap-{density}/ic_launcher.png")
        sips_resize(LIGHT_ICON_1024, legacy_path, legacy_size, legacy_size)

        # Foreground for adaptive icon (symbol size padded to adaptive size)
        temp_sym = f"/tmp/sym_{density}.png"
        sips_resize(SYMBOL_TRANSPARENT_4096, temp_sym, symbol_size, symbol_size)
        foreground_path = os.path.join(WORKSPACE, f"android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png")
        sips_pad(temp_sym, foreground_path, adaptive_size, adaptive_size)
        if os.path.exists(temp_sym):
            os.remove(temp_sym)

    # Adaptive icon xml
    anydpi_dir = os.path.join(WORKSPACE, "android/app/src/main/res/mipmap-anydpi-v26")
    os.makedirs(anydpi_dir, exist_ok=True)
    with open(os.path.join(anydpi_dir, "ic_launcher.xml"), "w") as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''')

    # Colors xml for launcher background
    values_dir = os.path.join(WORKSPACE, "android/app/src/main/res/values")
    colors_path = os.path.join(values_dir, "colors.xml")
    with open(colors_path, "w") as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
''')

def generate_ios_icons():
    ios_dir = os.path.join(WORKSPACE, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    contents_path = os.path.join(ios_dir, "Contents.json")
    with open(contents_path) as f:
        contents = json.load(f)
    
    for item in contents.get("images", []):
        size_str = item["size"]
        scale_str = item["scale"].replace("x", "")
        w, h = [float(x) for x in size_str.split("x")]
        scale = float(scale_str)
        pixel_w = int(round(w * scale))
        pixel_h = int(round(h * scale))
        filename = item["filename"]
        dst = os.path.join(ios_dir, filename)
        sips_resize(LIGHT_ICON_1024, dst, pixel_w, pixel_h)

def generate_macos_icons():
    macos_dir = os.path.join(WORKSPACE, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
    contents_path = os.path.join(macos_dir, "Contents.json")
    with open(contents_path) as f:
        contents = json.load(f)

    for item in contents.get("images", []):
        size_str = item["size"]
        scale_str = item["scale"].replace("x", "")
        w, h = [float(x) for x in size_str.split("x")]
        scale = float(scale_str)
        pixel_w = int(round(w * scale))
        pixel_h = int(round(h * scale))
        filename = item["filename"]
        dst = os.path.join(macos_dir, filename)
        sips_resize(LIGHT_ICON_1024, dst, pixel_w, pixel_h)

def generate_web_icons():
    web_dir = os.path.join(WORKSPACE, "web")
    sips_resize(LIGHT_ICON_1024, os.path.join(web_dir, "favicon.png"), 32, 32)
    icons_dir = os.path.join(web_dir, "icons")
    os.makedirs(icons_dir, exist_ok=True)
    sips_resize(LIGHT_ICON_1024, os.path.join(icons_dir, "Icon-192.png"), 192, 192)
    sips_resize(LIGHT_ICON_1024, os.path.join(icons_dir, "Icon-512.png"), 512, 512)
    sips_resize(LIGHT_ICON_1024, os.path.join(icons_dir, "Icon-maskable-192.png"), 192, 192)
    sips_resize(LIGHT_ICON_1024, os.path.join(icons_dir, "Icon-maskable-512.png"), 512, 512)

if __name__ == "__main__":
    print("Generating Android icons...")
    generate_android_icons()
    print("Generating iOS icons...")
    generate_ios_icons()
    print("Generating macOS icons...")
    generate_macos_icons()
    print("Generating Web icons...")
    generate_web_icons()
    print("All icons successfully generated!")
