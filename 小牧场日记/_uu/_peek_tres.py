# -*- coding: utf-8 -*-
"""打印 SpriteFrames .tres 里每套动画的：帧数 + 第一帧图集 y 坐标。

tres 的写法是 frames 在前、name 在后：
    {"frames": [{"duration":..,"texture": SubResource("AtlasTexture_7")}, ...],
     "loop": false, "name": &"walk_down", "speed": 5.0}
所以按 name 出现的位置切段，每段里的第一个 AtlasTexture 就是该动画的首帧。
"""
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()

regions = {}
for block in text.split("[sub_resource"):
    m = re.match(r'\s*type="AtlasTexture" id="([^"]+)"', block)
    r = re.search(r"region = Rect2\(([^)]+)\)", block)
    if m and r:
        regions[m.group(1)] = [int(float(v)) for v in r.group(1).split(",")]

names = [(m.start(), m.group(1)) for m in re.finditer(r'"name": &"([A-Za-z0-9_]+)"', text)]
marks = [(m.start(), m.group(1)) for m in re.finditer(r'SubResource\("(AtlasTexture_\d+)"\)', text)]

for i, (pos, name) in enumerate(names):
    start = names[i - 1][0] if i else 0
    seg = [(p, r) for p, r in marks if start <= p < pos]
    if not seg:
        continue
    frames = len(seg)
    x, y = regions.get(seg[0][1], [0, 0])[:2]
    print("%-16s 帧数 %2d   首帧 (%d, %d)" % (name, frames, x, y))
