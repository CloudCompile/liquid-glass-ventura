#!/usr/bin/env python3
"""Tile docs/screenshots/*.png into one contact sheet.

Requires Pillow. Usage: scripts/make-contact-sheet.py
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "docs", "screenshots")

files = sorted(
    f for f in glob.glob(os.path.join(SHOTS, "*.png"))
    if "contact-sheet" not in f
)
if not files:
    sys.exit("no screenshots found; run liquidglass-render --all first")

cols, cell_w, label_h, pad = 3, 620, 26, 18
rows = (len(files) + cols - 1) // cols

thumbs = []
cell_h = 0
for path in files:
    image = Image.open(path).convert("RGB")
    height = int(image.size[1] * cell_w / image.size[0])
    thumbs.append((os.path.basename(path)[:-4], image.resize((cell_w, height), Image.LANCZOS)))
    cell_h = max(cell_h, height)

sheet = Image.new(
    "RGB",
    (cols * cell_w + pad * (cols + 1), rows * (cell_h + label_h) + pad * (rows + 1)),
    (14, 16, 22),
)
draw = ImageDraw.Draw(sheet)
for index, (name, thumb) in enumerate(thumbs):
    row, col = divmod(index, cols)
    x = pad + col * (cell_w + pad)
    y = pad + row * (cell_h + label_h + pad)
    sheet.paste(thumb, (x, y + label_h))
    draw.text((x + 2, y + 6), name, fill=(215, 225, 245))

out = os.path.join(SHOTS, "contact-sheet.png")
sheet.save(out)
print("wrote %s (%dx%d, %d scenes)" % (out, sheet.size[0], sheet.size[1], len(thumbs)))
