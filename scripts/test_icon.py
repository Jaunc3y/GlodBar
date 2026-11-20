"""Verify the packaged app references a real multi-resolution ICNS."""
from pathlib import Path
import plistlib
import struct
root = Path(__file__).resolve().parents[1]
app = root / 'dist/积存金.app/Contents'
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info.get('CFBundleIconFile') == 'AppIcon.icns', 'App icon is not registered in Info.plist'
data = (app / 'Resources/AppIcon.icns').read_bytes()
assert data[:4] == b'icns' and struct.unpack('>I', data[4:8])[0] == len(data)
assert len(data) <= 60 * 1024, f'Icon exceeds 60 KiB budget: {len(data)} bytes'
assert b'ic08' in data, 'Missing 256px icon representation'
from PIL import Image
from io import BytesIO
pos = 8
while pos < len(data):
    kind, size = struct.unpack('>4sI', data[pos:pos+8])
    image = Image.open(BytesIO(data[pos+8:pos+size])).convert('RGBA')
    assert image.getpixel((0, 0))[3] == 0, f'{kind}: outer background must be transparent'
    assert image.getpixel((image.width//2, image.height//2))[3] == 255, f'{kind}: center must stay opaque'
    pos += size
assert info['LSUIElement'] is True, 'Menu-bar-only behavior must remain unchanged'
print('PASS: ICNS resource, 256px representation and <=60 KiB size, Info.plist registration and menu-bar mode')
