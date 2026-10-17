# -*- coding: utf-8 -*-
"""9 种动物 32×32 精灵 —— 确定性像素绘制（零密钥 · 零网络）

为什么放弃 AI 生图：
  Pollinations 出的是 512×512「插画」，降到 32×32 后细节全糊成一团，
  山羊/羊驼认不出，火鸡连背景都没去干净。32px 这个尺度上，
  **画法比算力重要** —— 直接按像素坐标摆形状，反而稳定、可复现、风格统一。

画法约定（和 AnimalNode 的锚点对齐）：
  · 32×32 画布，动物**脚踩在第 30 行**，描边外扩 1px 后正好填到 31
  · 统一 INK 描边，统一 12 色调色板 —— 九只放在一起才像一套
  · 全部侧视朝左（和玩家默认朝向一致）
  · 头顶/左右留 1px 安全边距，否则描边会被裁

用法：
    python _uu/animal_sprites.py            # 全 9 种 + 拼图
    python _uu/animal_sprites.py cow pig    # 只做指定几种
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = r"D:\UU的办公室\小牧场日记\assets\sprites\animals"
SHEET = r"D:\UU的办公室\小牧场日记\_uu\animal_sheet_preview.png"
SIZE = 32
GROUND = 30            # 脚底所在行

# ---------------- 统一调色板 ----------------
INK = (38, 32, 30, 255)          # 描边
WHITE = (250, 248, 242, 255)
CREAM = (236, 226, 202, 255)
SHADOW = (208, 200, 184, 255)
BLACK = (56, 50, 48, 255)
GRAY = (178, 174, 166, 255)
DGRAY = (124, 120, 114, 255)
BROWN = (150, 106, 68, 255)
DBROWN = (104, 70, 44, 255)
TAN = (210, 172, 124, 255)
PINK = (240, 166, 174, 255)
DPINK = (204, 124, 134, 255)
RED = (198, 64, 56, 255)
ORANGE = (242, 170, 60, 255)
YELLOW = (246, 202, 78, 255)
WOOL = (246, 242, 232, 255)
WING = (228, 240, 252, 255)


class Sprite:
    """32×32 逻辑画布 + 1px 安全边（描边外扩不会顶到画布边缘被裁）。

    所有绘制坐标按 0..31 写，内部自动 +PAD；`finalize()` 描边后裁回 32×32。
    """

    PAD = 1

    def __init__(self, size=SIZE):
        self.size = size
        self.img = Image.new("RGBA", (size + self.PAD * 2, size + self.PAD * 2), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def _box(self, b):
        return (b[0] + self.PAD, b[1] + self.PAD, b[2] + self.PAD, b[3] + self.PAD)

    # 两种调用都收：rect((x0,y0,x1,y1), c) 或 rect(x0,y0,x1,y1, c)
    def rect(self, *a):
        box, c = (a[0], a[1]) if len(a) == 2 else (a[:4], a[4])
        self.d.rectangle(self._box(box), fill=c)

    def ell(self, *a):
        box, c = (a[0], a[1]) if len(a) == 2 else (a[:4], a[4])
        self.d.ellipse(self._box(box), fill=c)

    def poly(self, pts, c):
        self.d.polygon([(x + self.PAD, y + self.PAD) for x, y in pts], fill=c)

    def px(self, x, y, c):
        if 0 <= x < self.size and 0 <= y < self.size:
            self.img.putpixel((x + self.PAD, y + self.PAD), c)

    def legs(self, xs, top, c, w=2):
        for x in xs:
            self.rect(x, top, x + w - 1, GROUND, c)

    def outline(self, c=INK):
        """对整个剪影外扩 1px 画描边（内部同色区域不会出现分割线）。"""
        a = self.img.getchannel("A")
        grown = a.filter(ImageFilter.MaxFilter(3))
        edge = ImageChops.subtract(grown, a)
        layer = Image.new("RGBA", self.img.size, c)
        self.img.paste(layer, (0, 0), edge)
        self.d = ImageDraw.Draw(self.img)

    def finalize(self):
        """描边 + 裁回 32×32（安全边正好被描边吃掉）。"""
        self.outline()
        p = self.PAD
        return self.img.crop((p, p, p + self.size, p + self.size))


# ---------------- 9 种动物 ----------------

def cow() -> Sprite:
    """白底黑斑奶牛，身体占右侧、头在左前，四条短腿。"""
    s = Sprite()
    s.legs([6, 11, 20, 25], 23, DGRAY)
    s.ell((4, 11, 27, 24), WHITE)                 # 身体
    s.ell((14, 12, 21, 18), BLACK)                # 黑斑
    s.ell((22, 16, 26, 22), BLACK)
    s.rect(27, 13, 28, 21, BLACK)                 # 尾
    s.rect(27, 21, 28, 23, INK)
    s.ell((1, 8, 12, 19), WHITE)                  # 头
    s.poly([(5, 9), (3, 4), (9, 8)], WHITE)       # 耳
    s.poly([(9, 9), (11, 5), (13, 9)], WHITE)
    s.ell((1, 13, 6, 18), PINK)                   # 口鼻
    s.px(3, 15, DPINK)
    s.px(4, 12, INK)                              # 眼
    s.px(5, 12, INK)
    return s


def sheep() -> Sprite:
    """蓬松羊毛 + 深灰脸，腿短得几乎看不见。"""
    s = Sprite()
    s.legs([8, 13, 19, 24], 25, BLACK)
    s.ell((4, 13, 27, 25), WOOL)                  # 身体
    s.ell((6, 10, 17, 19), WOOL)                  # 上层羊毛
    s.ell((15, 10, 26, 19), WOOL)
    s.ell((9, 17, 21, 24), SHADOW)                # 腹部阴影
    s.ell((1, 12, 11, 21), DGRAY)                 # 黑脸
    s.poly([(2, 13), (1, 9), (6, 11)], DGRAY)     # 耳
    s.px(4, 15, WHITE)                            # 眼
    s.px(5, 15, WHITE)
    s.px(4, 17, BLACK)                            # 鼻
    s.rect(27, 15, 28, 19, WOOL)                  # 尾
    return s


def goat() -> Sprite:
    """浅灰瘦羊 + 后弯的角 + 山羊胡。"""
    s = Sprite()
    s.legs([9, 13, 20, 24], 23, DGRAY)
    s.ell((5, 13, 26, 23), GRAY)                  # 身体
    s.ell((17, 14, 23, 19), SHADOW)               # 斑
    s.rect(26, 13, 27, 17, GRAY)                  # 尾
    s.rect(3, 10, 9, 18, GRAY)                    # 脖
    s.ell((1, 6, 10, 15), GRAY)                    # 头
    s.poly([(3, 7), (1, 3), (6, 5)], CREAM)       # 角
    s.poly([(6, 6), (8, 2), (10, 6)], CREAM)
    s.ell((1, 11, 5, 15), SHADOW)                 # 口鼻
    s.px(3, 9, INK)                               # 眼
    s.rect(3, 15, 4, 18, CREAM)                   # 胡子
    return s


def alpaca() -> Sprite:
    """长脖子 + 一身蓬松绒毛，九只里最高的一只。"""
    s = Sprite()
    s.legs([11, 15, 22, 26], 23, DBROWN)
    s.ell((7, 13, 29, 24), TAN)                   # 身体
    s.ell((9, 10, 20, 18), TAN)                   # 背上绒毛
    s.ell((20, 10, 29, 18), TAN)
    s.rect(6, 5, 12, 17, TAN)                     # 长脖子
    s.ell((3, 2, 12, 11), TAN)                    # 头
    s.poly([(4, 4), (2, 1), (8, 3)], TAN)         # 耳
    s.poly([(8, 4), (10, 1), (12, 4)], TAN)
    s.ell((2, 7, 6, 11), CREAM)                   # 口鼻
    s.px(5, 6, INK)                               # 眼
    s.rect(29, 14, 30, 18, TAN)                   # 尾
    return s


def pig() -> Sprite:
    """粉猪：圆身 + 猪鼻 + 卷尾。"""
    s = Sprite()
    s.legs([8, 12, 20, 24], 24, DPINK)
    s.ell((4, 13, 27, 25), PINK)                  # 身体
    s.ell((15, 15, 23, 21), DPINK)                # 侧影
    s.ell((1, 12, 11, 23), PINK)                  # 头
    s.poly([(5, 13), (3, 8), (10, 11)], PINK)     # 耳
    s.ell((1, 16, 5, 21), DPINK)                  # 猪鼻
    s.px(2, 18, INK)                              # 鼻孔
    s.px(4, 18, INK)
    s.px(4, 14, INK)                              # 眼
    s.px(5, 14, INK)
    s.px(28, 16, PINK)                            # 卷尾
    s.px(29, 17, PINK)
    s.px(28, 18, PINK)
    s.px(27, 18, PINK)
    return s


def chicken() -> Sprite:
    """白母鸡：红冠 + 橙嘴 + 翘尾。"""
    s = Sprite()
    s.rect(11, 26, 12, GROUND, ORANGE)            # 腿
    s.rect(18, 26, 19, GROUND, ORANGE)
    s.ell((19, 13, 31, 25), WOOL)                  # 蓬松尾羽
    s.ell((7, 13, 24, 27), WOOL)                  # 身体
    s.ell((13, 16, 22, 25), SHADOW)               # 翅膀
    s.ell((3, 7, 14, 18), WOOL)                   # 头
    s.rect(5, 4, 6, 7, RED)                       # 冠
    s.rect(7, 3, 8, 7, RED)
    s.rect(9, 5, 10, 7, RED)
    s.poly([(1, 12), (4, 14), (1, 16)], ORANGE)   # 嘴
    s.px(4, 11, INK)                              # 眼
    s.rect(6, 17, 8, 20, RED)                     # 肉垂
    return s


def duck() -> Sprite:
    """白鸭：橙扁嘴 + 橙脚 + 上翘尾。"""
    s = Sprite()
    s.rect(12, 26, 13, GROUND, ORANGE)            # 腿
    s.rect(18, 26, 19, GROUND, ORANGE)
    s.ell((20, 15, 31, 25), WOOL)                  # 尾
    s.ell((7, 14, 25, 27), WOOL)                  # 身体
    s.ell((13, 17, 22, 25), SHADOW)               # 翅
    s.rect(5, 9, 12, 19, WOOL)                    # 脖
    s.ell((2, 5, 13, 16), WOOL)                   # 头
    s.ell((1, 10, 6, 14), ORANGE)                 # 扁嘴
    s.px(2, 11, DPINK)
    s.px(4, 8, INK)                               # 眼
    return s


def turkey() -> Sprite:
    """棕色火鸡：竖起的尾扇 + 红肉冠 + 红肉垂。"""
    s = Sprite()
    s.rect(12, 26, 13, GROUND, ORANGE)            # 腿
    s.rect(18, 26, 19, GROUND, ORANGE)
    # 尾扇：两个同心椭圆，身体盖掉左半边 → 露出扇形
    s.ell((21, 10, 31, 27), DBROWN)
    s.ell((23, 13, 30, 25), BROWN)
    s.rect(25, 14, 26, 27, DBROWN)
    s.ell((7, 13, 24, 27), BROWN)                 # 身体
    s.ell((12, 16, 21, 25), DBROWN)               # 翅
    s.rect(4, 8, 11, 18, BROWN)                   # 脖
    s.ell((1, 4, 12, 15), BROWN)                  # 头
    s.rect(3, 2, 5, 5, RED)                       # 头顶肉冠
    s.poly([(1, 10), (4, 12), (1, 14)], ORANGE)   # 嘴
    s.rect(2, 14, 4, 18, RED)                     # 肉垂
    s.px(5, 8, INK)                               # 眼
    return s


def bee() -> Sprite:
    """胖蜜蜂：黄黑条纹 + 半透翅膀 + 尾针。"""
    s = Sprite()
    s.ell((8, 15, 25, 27), YELLOW)                # 身体
    s.rect(13, 15, 15, 27, INK)                   # 黑条纹
    s.rect(19, 15, 21, 27, INK)
    s.ell((7, 14, 12, 20), BLACK)                 # 头
    s.px(8, 17, WHITE)                            # 眼
    s.px(10, 17, WHITE)
    s.rect(9, 10, 10, 14, INK)                    # 触角
    s.rect(6, 9, 7, 13, INK)
    s.ell((11, 7, 17, 14), WING)                  # 翅膀
    s.ell((17, 8, 23, 15), WING)
    s.rect(25, 19, 27, 20, INK)                   # 尾针
    return s


ART = {
    "cow": cow,
    "goat": goat,
    "sheep": sheep,
    "alpaca": alpaca,
    "pig": pig,
    "chicken": chicken,
    "duck": duck,
    "turkey": turkey,
    "bee": bee,
}


def edge_warning(img, name):
    """上/左/右边缘有像素 = 描边会被裁掉，提前喊一声。"""
    a = img.getchannel("A")
    px = a.load()
    n = 0
    for i in range(SIZE):
        for x, y in ((i, 0), (0, i), (SIZE - 1, i)):
            if px[x, y] > 0:
                n += 1
    if n:
        print(f"  [警告] {name} 顶到画布边缘 {n} px（描边会被裁）")


def make_sheet(names):
    cell = SIZE * 6
    sheet = Image.new("RGBA", (cell * 3, cell * 3), (46, 52, 62, 255))
    for i, n in enumerate(names):
        p = os.path.join(OUT, f"{n}_{SIZE}.png")
        if not os.path.exists(p):
            continue
        sp = Image.open(p).resize((cell, cell), Image.NEAREST)
        sheet.paste(sp, ((i % 3) * cell, (i // 3) * cell), sp)
    sheet.save(SHEET)
    print(f"[sheet] {SHEET}")


if __name__ == "__main__":
    which = sys.argv[1:] or list(ART)
    for n in which:
        if n not in ART:
            print(f"[跳过] 不认识 {n}")
            continue
        sp = ART[n]()
        img = sp.finalize()
        img.save(os.path.join(OUT, f"{n}_{SIZE}.png"))
        img.resize((SIZE * 8, SIZE * 8), Image.NEAREST).save(
            os.path.join(OUT, f"{n}_{SIZE}_preview.png"))
        print(f"[ok] {n}_{SIZE}.png")
        edge_warning(img, n)
    make_sheet(list(ART))
