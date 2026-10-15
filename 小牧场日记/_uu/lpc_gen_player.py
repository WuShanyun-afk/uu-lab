# -*- coding: utf-8 -*-
"""生成主角正式资源（落盘 + Godot SpriteFrames）。
用法: python lpc_gen_player.py
"""
import json, os, sys

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

OUT_DIR = "D:/UU的办公室/小牧场日记/assets/characters/"

ARGS = {
    "items": ITEMS,
    "body_type": "male",
    "animations": ["walk", "idle", "slash", "watering", "run"],
    "layout": "standard",
    "export": ["godot"],
    "licenses": ["CC0", "OGA-BY"],
    "output_dir": OUT_DIR,
    "filename": "player.png",
    "prefer_complete": False,
    "zip": False,
}


def main():
    resp, n, err = call("generate_character", ARGS, timeout=1800)
    d = os.path.join(os.environ["TEMP"], "uu_mcp")
    os.makedirs(d, exist_ok=True)

    if not resp:
        print("NO RESPONSE. stderr=" + err[:1500])
        return

    with open(os.path.join(d, "gen_player_resp.json"), "w", encoding="utf-8") as f:
        json.dump(resp, f, ensure_ascii=False, indent=2)

    r = resp.get("result") or {}
    print("isError = %s" % r.get("isError"))
    for blk in (r.get("content") or []):
        if isinstance(blk, dict) and blk.get("type") == "text":
            print(blk.get("text", "")[:2500])

    print("--- 落盘检查 ---")
    base = os.path.normpath(OUT_DIR.replace("/", "\\"))
    if os.path.isdir(base):
        for root, dirs, files in os.walk(base):
            for fn in files:
                fp = os.path.join(root, fn)
                print("  %-70s %d bytes" % (fp.replace(base, "."), os.path.getsize(fp)))
    else:
        print("  目录不存在: " + base)


main()
