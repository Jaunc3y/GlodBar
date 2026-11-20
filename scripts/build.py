#!/usr/bin/env python3
"""Build a universal macOS 15 application and a drag-to-install DMG."""
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
APP = DIST / "积存金.app"

def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)

DIST.mkdir(exist_ok=True)
for arch in ("arm64", "x86_64"):
    run("swift", "build", "-c", "release", "--product", "GoldBar", "--triple", f"{arch}-apple-macosx15.0")
macos = APP / "Contents" / "MacOS"
macos.mkdir(parents=True, exist_ok=True)
resources = APP / "Contents" / "Resources"
resources.mkdir(exist_ok=True)
# Compact icon: native PNG-backed ICNS elements, capped at 256px.
# Pillow is required only when rebuilding, never at application runtime.
from PIL import Image, ImageDraw
from io import BytesIO
import struct
source = Image.open(ROOT / "assets/GoldBar-icon.png").convert("RGBA")
# Remove only the light exterior connected to the canvas edge, not gold highlights.
mask = source.convert("L").point(lambda value: 255 if value > 120 else 0)
ImageDraw.floodfill(mask, (0, 0), 128, thresh=0)
alpha = mask.point(lambda value: 0 if value == 128 else 255)
source.putalpha(alpha)
source.save(ROOT / "assets/GoldBar-icon-transparent.png", optimize=True)
elements = []
for pixels, kind in ((16, b"icp4"), (32, b"icp5"), (64, b"icp6"), (128, b"ic07"), (256, b"ic08")):
    image = source.resize((pixels, pixels), Image.Resampling.LANCZOS)
    image = image.quantize(colors=128, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    buffer = BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    png = buffer.getvalue()
    elements.append(kind + struct.pack(">I", len(png) + 8) + png)
body = b"".join(elements)
icon = b"icns" + struct.pack(">I", len(body) + 8) + body
assert len(icon) <= 60 * 1024, f"Icon exceeds 60 KiB: {len(icon)}"
(resources / "AppIcon.icns").write_bytes(icon)
print(f"Compact icon: {len(icon):,} bytes")
run("lipo", "-create", str(ROOT / ".build/arm64-apple-macosx/release/GoldBar"), str(ROOT / ".build/x86_64-apple-macosx/release/GoldBar"), "-output", str(macos / "GoldBar"))
(macos / "GoldBar").chmod(0o755)
info = {
    "CFBundleExecutable": "GoldBar",
    "CFBundleIdentifier": "com.junchao.goldbar",
    "CFBundleName": "积存金",
    "CFBundleDisplayName": "积存金",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "1.0.0",
    "CFBundleVersion": "4",
    "CFBundleIconFile": "AppIcon.icns",
    "LSMinimumSystemVersion": "15.0",
    "LSUIElement": True,
    "NSHighResolutionCapable": True,
    "NSPrincipalClass": "NSApplication",
    "CFBundleDevelopmentRegion": "zh_CN",
    "NSHumanReadableCopyright": "Independent utility. Not affiliated with ICBC."
}
with (APP / "Contents" / "Info.plist").open("wb") as f:
    plistlib.dump(info, f)
run("codesign", "--force", "--sign", "-", "--options", "runtime", str(APP))
run("codesign", "--verify", "--deep", "--strict", "--verbose=2", str(APP))
stage = ROOT / ".build" / "dmg-stage"
if stage.exists():
    shutil.rmtree(stage)
stage.mkdir()
shutil.copytree(APP, stage / APP.name)
(stage / "Applications").symlink_to("/Applications")
if (ROOT / "使用说明.txt").exists():
    shutil.copy2(ROOT / "使用说明.txt", stage / "使用说明.txt")
run("hdiutil", "create", "-volname", "积存金", "-srcfolder", str(stage), "-format", "UDZO", "-ov", str(DIST / "GoldBar-1.0.0-universal.dmg"))
run("hdiutil", "verify", str(DIST / "GoldBar-1.0.0-universal.dmg"))
print(f"APP={APP}\nDMG={DIST / 'GoldBar-1.0.0-universal.dmg'}")
