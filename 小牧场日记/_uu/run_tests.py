# -*- coding: utf-8 -*-
"""跑全部测试套件（headless），汇总通过/失败。

用法：  python _uu/run_tests.py
"""
import os
import re
import subprocess
import sys

GODOT = r"C:\Users\32265\.godot-mcp\godot\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe"
PROJ = r"D:\UU的办公室\小牧场日记"
SUITES = [
    ("时间/昼夜", "res://tests/test_milestone1.tscn"),
    ("玩家精灵", "res://tests/test_player_sprite.tscn"),
    ("农场", "res://tests/test_farm.tscn"),
    ("动物", "res://tests/test_animals.tscn"),
    ("地块图集", "res://tests/test_tileset.tscn"),
    ("模块1 核心框架", "res://tests/test_module1.tscn"),
    ("模块2 时间天气", "res://tests/test_weather.tscn"),
    ("模块3 种植系统", "res://tests/test_module3.tscn"),
    ("模块4 动物系统", "res://tests/test_module4.tscn"),
    ("模块5 动物进阶", "res://tests/test_module5.tscn"),
    ("模块6 棚舍与美术", "res://tests/test_module6.tscn"),
    ("模块7 经济与背包", "res://tests/test_module7.tscn"),
    ("模块8 存档系统", "res://tests/test_module8.tscn"),
    ("模块9 建造扩建", "res://tests/test_module9.tscn"),
    ("模块10 NPC剧情", "res://tests/test_module10.tscn"),
    ("模块11 存档场景", "res://tests/test_module11.tscn"),
]

def main() -> int:
    env = dict(os.environ, GODOT_MCP_UPDATE_CHECK="false")
    total_ok = 0
    bad = []
    for name, scene in SUITES:
        p = subprocess.run([GODOT, "--headless", "--path", PROJ, scene],
                           capture_output=True, env=env, timeout=600)
        out = (p.stdout + p.stderr).decode("utf-8", "replace")
        ok = len(re.findall(r"\[OK\]", out))
        fail = len(re.findall(r"\[FAIL\]", out))
        total_ok += ok
        flag = "OK " if p.returncode == 0 and fail == 0 else "FAIL"
        print("[%s] %-14s 通过 %3d  失败 %d" % (flag, name, ok, fail))
        if fail or p.returncode != 0:
            bad.append(name)
            for line in out.splitlines():
                if "[FAIL]" in line or "ERROR" in line:
                    print("      " + line.strip())
    print("-" * 46)
    print("合计 %d 项断言通过" % total_ok)
    if bad:
        print("失败套件: " + ", ".join(bad))
        return 1
    print("全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
