# -*- coding: utf-8 -*-
"""打印某个动画每一帧的图集坐标 —— 排查 watering 到底画在哪一行。"""
import re
import sys

path, want = sys.argv[1], sys.argv[2]
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
    if name != want:
        continue
    start = names[i - 1][0] if i else 0
    seg = [(p, r) for p, r in marks if start <= p < pos]
    print(name, "帧数", len(seg))
    print("  " + "  ".join("(%d,%d)" % tuple(regions[r][:2]) for _, r in seg))
