# -*- coding: utf-8 -*-
"""主角造型预览：把 MCP 返回的 image content 解码存成 PNG。
用法: python lpc_preview.py
"""
import json, os, sys, base64

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lpc_client import call

ITEMS = [
    {"id": "body/body"},
    {"id": "head/heads/human/heads_human_male"},
    {"id": "hair/short/hair_plain", "color": "dark_brown"},
    {"id": "torso/shirts/longsleeve/torso_clothes_longsleeve", "color": "white"},
    {"id": "torso/aprons/torso_aprons_overalls", "color": "leather"},
    {"id": "legs/pants/legs_cuffed", "color": "navy"},
    {"id": "feet/boots/feet_boots_basic", "color": "brown"},
]

OUT = os.path.join(os.environ["TEMP"], "uu_mcp")


def save_images(resp, prefix):
    """把 content 里的 image 块解码存盘，返回文件路径列表"""
    paths = []
    r = (resp or {}).get("result") or {}
    for i, blk in enumerate(r.get("content") or []):
        if not isinstance(blk, dict):
            continue
        if blk.get("type") == "image" and blk.get("data"):
            mt = blk.get("mimeType", "image/png")
            ext = ".gif" if "gif" in mt else ".png"
            fp = os.path.join(OUT, "%s_%d%s" % (prefix, i, ext))
            with open(fp, "wb") as f:
                f.write(base64.b64decode(blk["data"]))
            paths.append(fp)
        elif blk.get("type") == "text":
            print("  [text] " + str(blk.get("text"))[:600].replace("\n", " "))
    return paths


def main():
    os.makedirs(OUT, exist_ok=True)

    print("=== preview_character (静态, walk) ===")
    resp, n, err = call("preview_character", {
        "items": ITEMS,
        "body_type": "male",
        "animation": "walk",
        "animated": False,
    }, timeout=600)
    if not resp:
        print("NO RESPONSE. stderr=" + err[:800])
        return
    r = resp.get("result") or {}
    print("  isError=%s" % r.get("isError"))
    for p in save_images(resp, "preview_still"):
        print("  [img] " + p)

    print("=== preview_character (动图, walk) ===")
    resp2, n2, err2 = call("preview_character", {
        "items": ITEMS,
        "body_type": "male",
        "animation": "walk",
        "animated": True,
    }, timeout=600)
    if resp2:
        for p in save_images(resp2, "preview_anim"):
            print("  [img] " + p)
    else:
        print("NO RESPONSE. stderr=" + err2[:800])


main()
