# -*- coding: utf-8 -*-
"""把 data/crops.csv 导出成一份「给策划看的」JSON 作物表（模块 3 交付物之一）。

游戏运行时**不读这个 JSON** —— CropDB 读的是 crops.csv（唯一真相来源）。
这份 JSON 只是把派生值（品质价、回本天数、一季总收益、施肥后的成熟天数）算好，
方便设计评审和后续做数值平衡，避免手算。

用法：  python _uu/export_crop_json.py
输出：  _uu/作物数据表.json
"""
import csv
import json
import os
import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_PATH = os.path.join(ROOT, "data", "crops.csv")
OUT_PATH = os.path.join(ROOT, "_uu", "作物数据表.json")

SEASON_NAME = ["春", "夏", "秋", "冬"]
SEASON_DAYS = 28
QUALITY_MULT = {"normal": 1.0, "silver": 1.5, "gold": 2.0}
# 与 scripts/data/fertilizer.gd 的 PRICE / QUALITY_BONUS / growth_delta 保持一致
FERT = {
    "basic": {"name": "基础肥", "price": 100, "bonus_silver": [0.05, 0.10, 0.15], "bonus_gold": [0.0, 0.0, 0.0]},
    "high": {"name": "高级肥", "price": 300, "bonus_silver": [0.12, 0.20, 0.28], "bonus_gold": [0.03, 0.05, 0.08]},
}
BASE_CHANCE = [0.05, 0.00]
AFFINITY_NAME = ["低", "中", "高"]


def quality_price(sell: int, q: str) -> int:
    return int(round(sell * QUALITY_MULT[q]))


def grow_days_with(grow: int, affinity: int, level: str) -> int:
    if level == "none":
        return grow
    if level == "basic":
        return grow
    return grow + (0 if affinity >= 2 else 1)


def chance(affinity: int, level: str):
    if level == "none":
        return BASE_CHANCE
    f = FERT[level]
    return [BASE_CHANCE[0] + f["bonus_silver"][affinity],
            BASE_CHANCE[1] + f["bonus_gold"][affinity]]


def main() -> int:
    rows = []
    with open(CSV_PATH, encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            if not r.get("id"):
                continue
            rows.append(r)

    crops = []
    for r in rows:
        grow = int(r["grow_days"])
        regrow = int(r["regrow_days"])
        seed = int(r["seed_price"])
        sell = int(r["sell_price"])
        aff = int(r["fertilize"])

        harvests = 1
        if regrow > 0:
            harvests = 1 + max(0, SEASON_DAYS - grow) // regrow
        season_income = sell * harvests

        crops.append({
            "id": r["id"],
            "name": r["name"],
            "season": int(r["season"]),
            "season_name": SEASON_NAME[int(r["season"])],
            "grow_days": grow,
            "seed_price": seed,
            "sell_price": sell,
            "regrow_days": regrow,
            "regrow_text": "一次性" if regrow == 0 else "每 %d 天再生" % regrow,
            "fertilize": aff,
            "fertilize_name": AFFINITY_NAME[aff],
            "color": r["color"],
            "quality_price": {q: quality_price(sell, q) for q in QUALITY_MULT},
            "profit_per_plant": sell - seed,
            "profit_per_day": round((sell - seed) / max(1, grow), 2),
            "harvests_per_season": harvests,
            "season_income": season_income,
            "season_profit": season_income - seed,
            "grow_days_by_fertilizer": {
                "none": grow_days_with(grow, aff, "none"),
                "basic": grow_days_with(grow, aff, "basic"),
                "high": grow_days_with(grow, aff, "high"),
            },
            "quality_chance": {lv: chance(aff, lv) for lv in ("none", "basic", "high")},
        })

    by_season = {}
    for s in range(4):
        ids = [c["id"] for c in crops if c["season"] == s]
        by_season[SEASON_NAME[s]] = {"season": s, "count": len(ids), "crops": ids}

    out = {
        "meta": {
            "source": "data/crops.csv",
            "generated_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
            "note": "游戏运行时读 crops.csv（CropDB）；本文件是导出报告，不参与运行。",
            "season_days": SEASON_DAYS,
            "quality_mult": QUALITY_MULT,
            "base_quality_chance": BASE_CHANCE,
            "fertilizer": FERT,
        },
        "seasons": by_season,
        "crops": crops,
    }

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)

    print("导出 %d 种作物 → %s" % (len(crops), OUT_PATH))
    for name, info in by_season.items():
        print("  %s季 %d 种：%s" % (name, info["count"], "、".join(info["crops"])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
