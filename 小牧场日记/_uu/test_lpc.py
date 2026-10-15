# -*- coding: utf-8 -*-
"""逐个工具探测：谁返回、谁静默死。每个工具独立进程。
用法: python test_lpc.py
"""
import json, subprocess, os

SERVER = ["C:\\Users\\32265\\.local\\bin\\uvx.exe", "lpc-character-mcp"]

TESTS = [
    ("list_categories", {}),
    ("search_items", {"category": "body", "limit": 5}),
    ("search_items", {"query": "body", "limit": 5}),
    ("search_items", {"limit": 5}),
    ("get_item", {"item_id": "body/body"}),
    ("random_character", {"body_type": "male", "seed": 20261014}),
]


def run(tool, args, env):
    payload = "".join([
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "t", "version": "1.0"}}}) + "\n",
        json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized",
                    "params": {}}) + "\n",
        json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                    "params": {"name": tool, "arguments": args}}) + "\n",
    ])
    p = subprocess.Popen(SERVER, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, env=env)
    try:
        out, err = p.communicate(payload.encode(), timeout=120)
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
        return None, "TIMEOUT", err.decode("utf-8", "replace")
    msgs = []
    for line in out.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            msgs.append(json.loads(line))
        except Exception:
            pass
    resp = next((m for m in msgs if m.get("id") == 2), None)
    return resp, len(out), err.decode("utf-8", "replace")


def main():
    env = dict(os.environ)
    env["NO_COLOR"] = "1"
    env["PYTHONUNBUFFERED"] = "1"

    for tool, args in TESTS:
        resp, n, err = run(tool, args, env)
        tag = "OK" if resp else "NO-RESPONSE"
        print("=== %s %s -> %s  (stdout %s bytes)" % (
            tool, json.dumps(args, ensure_ascii=False), tag, n))
        if resp:
            r = resp.get("result") or {}
            if r.get("isError"):
                print("    isError=True")
            sc = r.get("structuredContent")
            if sc is not None:
                print("    structuredContent keys: %s" % list(sc.keys()))
            try:
                txt = r["content"][0]["text"]
                print("    text[0..300]: " + txt[:300].replace("\n", " "))
            except Exception:
                print("    (no content text)")
        elif err.strip():
            print("    stderr: " + err.strip()[:400])


main()
