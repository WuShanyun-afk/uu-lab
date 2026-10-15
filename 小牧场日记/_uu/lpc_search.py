# -*- coding: utf-8 -*-
"""批量查 LPC 素材 id（用 lpc_client 的正确姿势）。
用法: python lpc_search.py
输出: %TEMP%\\uu_mcp\\lpc_items.json
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lpc_client import call, unwrap

CATS = [
    "body",
    "head/heads/human",
    "hair/short",
    "torso/shirts/longsleeve",
    "torso/aprons",
    "legs/pants",
    "feet/boots",
    "tools",
]
LIMIT = 60


def main():
    env = dict(os.environ)
    env["NO_COLOR"] = "1"
    out_map = {}

    for cat in CATS:
        resp, n, err = call("search_items", {"category": cat, "limit": LIMIT}, env=env)
        items = unwrap(resp)
        if isinstance(items, dict):
            items = items.get("result")
        out_map[cat] = items
        cnt = len(items) if isinstance(items, list) else "ERR"
        print("### %s  (%s)" % (cat, cnt))
        if isinstance(items, list):
            for it in items:
                if isinstance(it, dict):
                    print("    %-56s complete=%-5s drm=%s" % (
                        it.get("id", "?"), it.get("complete"), it.get("drm_safe")))
        elif err.strip():
            print("    ERR: " + err.strip()[:300])

    d = os.path.join(os.environ["TEMP"], "uu_mcp")
    os.makedirs(d, exist_ok=True)
    fp = os.path.join(d, "lpc_items.json")
    with open(fp, "w", encoding="utf-8") as f:
        json.dump(out_map, f, ensure_ascii=False, indent=2)
    print("[落盘] " + fp)


main()
