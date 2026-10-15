# -*- coding: utf-8 -*-
"""uu 免密钥像素精灵流水线 v2

v1 的三个问题:
  1. 去背用全局阈值 -> 带渐变的背景去不干净，底部残留地面条
  2. 从 512 直接降到 32 -> 细节全丢，形状糊成一团
  3. 提示词没约束画风 -> 模型画了"写实渲染"而不是"扁平像素"

v2 的修法:
  1. 边缘洪水填充（BFS）去背，只删与画布边缘连通的同色区域 -> 保留主体内部同色部分
  2. 先降到 96 做形状保留，再降到 32 -> 两段式降采样
  3. 提示词强化: flat colors / thick outline / limited palette / no shading
"""
import io, os, sys, time, urllib.parse, urllib.request
from collections import deque
from PIL import Image, ImageFilter

OUT = r"D:\UU的办公室\小牧场日记\assets\sprites\animals"
os.makedirs(OUT, exist_ok=True)

def generate(prompt, w=512, h=512, seed=1, model="turbo", timeout=150, retries=4):
    url = ("https://image.pollinations.ai/prompt/" + urllib.parse.quote(prompt)
           + f"?width={w}&height={h}&nologo=true&seed={seed}&model={model}")
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return Image.open(io.BytesIO(r.read())).convert("RGBA")
        except Exception as e:
            last = e
            print(f"     重试 {i+1}/{retries}: {e}")
            time.sleep(6 + i * 5)          # 402 是限流，退避等一下
    raise last

def strip_watermark(im, frac=0.14):
    w, h = im.size
    return im.crop((0, 0, w, int(h * (1 - frac))))

def flood_remove_bg(im, tol=42):
    """从四边洪水填充，只删与边缘连通的背景。主体内部的同色像素得以保留。"""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    # 边缘采样取背景基准色
    edge = []
    for x in range(0, w, max(1, w // 40)):
        edge.append(px[x, 1]); edge.append(px[x, h - 2])
    for y in range(0, h, max(1, h // 40)):
        edge.append(px[1, y]); edge.append(px[w - 2, y])
    bg = tuple(sorted(c[i] for c in edge)[len(edge) // 2] for i in range(3))

    def near(c):
        return abs(c[0]-bg[0]) <= tol and abs(c[1]-bg[1]) <= tol and abs(c[2]-bg[2]) <= tol

    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not seen[y*w+x] and near(px[x, y]):
                seen[y*w+x] = 1; q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not seen[y*w+x] and near(px[x, y]):
                seen[y*w+x] = 1; q.append((x, y))
    while q:
        x, y = q.popleft()
        px[x, y] = (px[x, y][0], px[x, y][1], px[x, y][2], 0)
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            nx, ny = x+dx, y+dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny*w+nx] and near(px[nx, ny]):
                seen[ny*w+nx] = 1; q.append((nx, ny))
    return im, bg

def autocrop(im, pad=2):
    bbox = im.getbbox()
    if not bbox: return im
    x0, y0, x1, y1 = bbox
    return im.crop((max(0,x0-pad), max(0,y0-pad), min(im.width,x1+pad), min(im.height,y1+pad)))

def to_pixel_art(im, size=32, mid=96, colors=14):
    side = max(im.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side-im.width)//2, (side-im.height)//2), im)
    # 两段式：先到 mid 保留轮廓，再到目标尺寸
    step = canvas.resize((mid, mid), Image.BOX)
    step = step.filter(ImageFilter.SMOOTH)
    small = step.resize((size, size), Image.BOX)
    rgb = small.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGBA")
    a = small.getchannel("A").point(lambda v: 255 if v >= 120 else 0)
    rgb.putalpha(a)
    return rgb

STYLE = ("flat pixel art game sprite, thick black outline, limited color palette, "
         "no shading, no gradient, crisp pixels, centered, plain white background, ")

TARGETS = {
    "cow":     STYLE + "a brown and white dairy cow, side view facing left",
    "chicken": STYLE + "a small white chicken with red comb, side view facing left",
}

def build(name, prompt, seed=1, size=32):
    print(f"--- {name} ---")
    raw = generate(prompt, seed=seed)
    print(f"  1. 生图     {raw.size}")
    im = strip_watermark(raw)
    im, bg = flood_remove_bg(im)
    print(f"  2. 洪水去背  bg={bg}")
    im = autocrop(im)
    print(f"  3. 裁边     {im.size}")
    sp = to_pixel_art(im, size=size)
    prev = sp.resize((size*8, size*8), Image.NEAREST)
    sp.save(os.path.join(OUT, f"{name}_{size}.png"))
    prev.save(os.path.join(OUT, f"{name}_{size}_preview.png"))
    print(f"  4. 产出     {name}_{size}.png")

if __name__ == "__main__":
    which = sys.argv[1:] or list(TARGETS)
    for n in which:
        if n in TARGETS:
            try:
                build(n, TARGETS[n], seed={"cow":42,"chicken":7}.get(n,1))
            except Exception as e:
                print(f"  [失败] {n}: {e}")
            time.sleep(8)      # 限流间隔
