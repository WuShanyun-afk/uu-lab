# -*- coding: utf-8 -*-
"""把 LPC 立绘图集拼成好看的预览图（每套动画 = 4 行：上/左/下/右）。

用法： python _uu/preview_sheets.py
产物： _uu/preview_player.png   _uu/preview_player_can.png
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARS = os.path.join(ROOT, "assets", "characters")
OUT = os.path.join(ROOT, "_uu")
F = 64
BG = (44, 46, 56, 255)
SEP = (86, 92, 110, 255)

# (标题, 起始 y, 每帧起点 x, 帧数)  —— 行顺序固定为 up / left / down / right
PLAIN = [
    ("idle", 1408, 0, 3),
    ("walk", 512, 64, 8),
    ("run", 2432, 0, 8),
    ("slash", 768, 0, 6),
]
CAN = [
    ("walk", 512, 64, 8),
    ("thrust", 256, 0, 8),
    ("watering", 256, 0, 7),
]


def block(im, y, x0, n):
    """一行 4 个方向（每方向 n 帧）"""
    w = x0 + n * F
    row = Image.new("RGBA", (w, 4 * F), (0, 0, 0, 0))
    for d in range(4):
        row.alpha_composite(im.crop((0, y + d * F, w, y + (d + 1) * F)), (0, d * F))
    return row


def build(png, spec, scale=2):
    im = Image.open(os.path.join(CHARS, png)).convert("RGBA")
    blocks = [(name, block(im, y, x0, n)) for name, y, x0, n in spec]
    w = max(b.width for _, b in blocks) + 8
    h = sum(b.height for _, b in blocks) + 8 * len(blocks)
    out = Image.new("RGBA", (w, h), BG)
    yy = 4
    for name, b in blocks:
        out.alpha_composite(b, (4, yy))
        yy += b.height + 8
    out = out.resize((out.width * scale, out.height * scale), Image.NEAREST)
    path = os.path.join(OUT, "preview_" + png.replace(".png", "") + ".png")
    out.save(path)
    print("%-46s %dx%d" % (path, out.width, out.height))


build("player.png", PLAIN)
build("player_can.png", CAN)
