# -*- coding: utf-8 -*-
"""LPC 素材预取 —— 修 lpc-character-mcp 的「0 字节静默失败」坑。

背景：render.py 的 _download() 一旦 urlopen 抛异常就写一个**空文件**占位，
     并且因为 `if not local.exists()` 永远不再重试。
     → 女性 body / head / 发型的 walk.png 全被烧成 0 字节，
       于是 female 角色渲染直接报 "no layers found for this combination"。

本脚本：按官方 jsDelivr 文件清单，把需要的目录整段重新拉一遍（跳过非空文件）。
源顺序：jsDelivr → ghfast.top → raw(带代理)。
"""
import os
import sys
import urllib.request
import concurrent.futures as cf

CACHE = r"C:\Users\32265\AppData\Local\lpc-character-mcp\cache"
LIST = os.path.join(CACHE, "_files_58ce1aa479e4df32845a73a5d0afc221c3a893c2.txt")
REPO = "LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator"
# 实测顺序（2026-10-13，机场代理没开、raw.githubusercontent.com 被 DNS 投毒）：
#   ghfast.top / gh-proxy.com 直连可用；cdn.jsdelivr.net 本机 python 解析失败。
MIRRORS = [
    "https://ghfast.top/https://raw.githubusercontent.com/%s/master/" % REPO,
    "https://gh-proxy.com/https://raw.githubusercontent.com/%s/master/" % REPO,
    "https://cdn.jsdelivr.net/gh/%s@master/" % REPO,
    "https://raw.githubusercontent.com/%s/master/" % REPO,
]
PROXY = "http://127.0.0.1:7892"

# 女角色（可爱农家妹）用到的所有目录
PREFIXES = [
    "spritesheets/body/bodies/female/",
    "spritesheets/head/heads/human/female/",
    "spritesheets/hair/bangs_bun/adult/",
    "spritesheets/torso/clothes/longsleeve/longsleeve/female/",
    "spritesheets/torso/aprons/overalls/female/",
    "spritesheets/legs/cuffed/thin/",     # legs/cuffed 没有 female 目录，女性走 thin
    "spritesheets/feet/boots/basic/thin/",  # 同上
]
# 背带裤是按颜色分文件的，只取用得到的两种，别把 24 色全拖下来
OVERALLS_KEEP = {"navy", "blue"}


def wanted(rel: str) -> bool:
    if not rel.startswith(tuple(PREFIXES)):
        return False
    if rel.startswith("spritesheets/torso/aprons/overalls/female/"):
        return os.path.basename(rel)[:-4] in OVERALLS_KEEP
    return True


def fetch(rel: str) -> str:
    dest = os.path.join(CACHE, rel.replace("spritesheets/", "", 1).replace("/", os.sep))
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return "skip"
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    last = ""
    for i, m in enumerate(MIRRORS):
        try:
            # ⚠️ 别用 "raw.githubusercontent" in m 判断：ghfast.top 的 URL 里也含这段，
            #    会把请求塞给没开的 127.0.0.1:7892 → WinError 10061。
            use_proxy = m.startswith("https://raw.githubusercontent.com")
            opener = urllib.request.build_opener(
                urllib.request.ProxyHandler({"http": PROXY, "https": PROXY})
                if use_proxy else urllib.request.ProxyHandler({})
            )
            data = opener.open(m + rel, timeout=40).read()
            if data[:8] != b"\x89PNG\r\n\x1a\n":
                last = "not-png(%d)" % len(data)
                continue
            with open(dest, "wb") as f:
                f.write(data)
            return "ok#%d" % (i + 1)
        except Exception as e:  # noqa: BLE001
            last = "%s(%s)" % (type(e).__name__, str(e)[:60])
    # 失败也留痕，方便下一轮重试时不再当成"已存在"
    try:
        if os.path.exists(dest):
            os.remove(dest)
    except OSError:
        pass
    return "FAIL:" + last


def main() -> int:
    if not os.path.exists(LIST):
        print("缺文件清单:", LIST)
        return 2
    with open(LIST, "r", encoding="utf-8") as f:
        rels = [ln.strip() for ln in f if ln.strip()]
    todo = [r for r in rels if wanted(r)]
    print("清单 %d 行，命中 %d 个文件" % (len(rels), len(todo)))
    stats = {}
    with cf.ThreadPoolExecutor(max_workers=12) as pool:
        for rel, res in zip(todo, pool.map(fetch, todo)):
            key = res.split(":")[0].split("#")[0]
            stats[key] = stats.get(key, 0) + 1
            if res.startswith("FAIL"):
                print("  x", rel, res)
    print("结果:", stats)
    return 0


if __name__ == "__main__":
    sys.exit(main())
