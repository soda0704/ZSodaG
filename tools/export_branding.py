"""Export the approved NorthernLab emblem without changing the source artwork."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/ui/branding/northernlab-emblem-square-v1.png'
DEST = ROOT / 'assets/ui/branding/releases/northernlab-logo-v1'
DEST.mkdir(parents=True, exist_ok=True)
im = Image.open(SOURCE).convert('RGBA')
assert im.width == im.height and im.getchannel('A').getextrema() == (0, 255)

shutil.copyfile(SOURCE, DEST / 'northernlab-master.png')
im.save(DEST / 'northernlab-master.webp', lossless=True, quality=100, method=6, exact=True)
im.save(DEST / 'northernlab-master.tiff', compression='tiff_deflate')
for size in (1024, 512, 256, 128, 64, 48, 32, 16):
    icon = im.resize((size, size), Image.Resampling.LANCZOS)
    icon.save(DEST / f'northernlab-{size}.png', optimize=True)
im.save(DEST / 'northernlab-windows.ico', sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
im.resize((1024, 1024), Image.Resampling.LANCZOS).save(DEST / 'northernlab-macos.icns')
preview = Image.new('RGB', im.size, '#151b23')
preview.paste(im, mask=im.getchannel('A'))
preview.save(DEST / 'northernlab-preview-dark.jpg', quality=98, subsampling=0)

readme = '''NorthernLab — основной логотип, версия 1

Утверждённая квадратная эмблема без надписи.
Исходное разрешение: 1254 × 1254 px, RGBA, прозрачный фон.

northernlab-master.png — точная копия оригинала, основной файл для игры и дизайна.
northernlab-master.webp — сжатие без потерь, прозрачность сохранена.
northernlab-master.tiff — TIFF без потерь с альфа-каналом для графических редакторов.
northernlab-{размер}.png — размеры 1024, 512, 256, 128, 64, 48, 32, 16 px.
northernlab-windows.ico — Windows: 16, 24, 32, 48, 64, 128, 256 px в одном файле.
northernlab-macos.icns — macOS, максимальный размер 1024 px.
northernlab-preview-dark.jpg — предпросмотр на тёмном фоне; JPEG не поддерживает прозрачность.

Все размеры получены из оригинала без увеличения. Мелкие версии сохраняют
исходную композицию; фактура и мелкие детали при уменьшении теряются.
Это растровая графика. SVG/EPS не включены: для настоящего масштабируемого
вектора требуется отдельная перерисовка, а вложенный PNG не добавляет качества.
Экранная графика RGB; для крупной полиграфии требуется отдельная подготовка.

Пересоздание набора: python tools/export_branding.py (требуется Pillow).
'''
(DEST / 'README.txt').write_text(readme, encoding='utf-8-sig')

assert (DEST / 'northernlab-master.png').read_bytes() == SOURCE.read_bytes()
for name in ('northernlab-master.webp', 'northernlab-master.tiff'):
    with Image.open(DEST / name) as check:
        assert check.convert('RGBA').tobytes() == im.tobytes(), name
with Image.open(DEST / 'northernlab-windows.ico') as check:
    assert check.ico.sizes() == {(s, s) for s in (16, 24, 32, 48, 64, 128, 256)}
for path in DEST.glob('*'):
    if path.suffix.lower() in ('.png', '.webp', '.tiff', '.ico', '.icns', '.jpg'):
        with Image.open(path) as check:
            check.load()
manifest = {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
            for p in sorted(DEST.iterdir()) if p.is_file() and p.name != 'manifest.json'}
(DEST / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
archive = DEST.parent / 'northernlab-logo-v1.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as out:
    for path in sorted(DEST.iterdir()):
        out.write(path, arcname=f'{DEST.name}/{path.name}')
with zipfile.ZipFile(archive) as check:
    assert check.testzip() is None
print(f'Exported and verified {len(manifest)} files plus manifest: {archive}')
