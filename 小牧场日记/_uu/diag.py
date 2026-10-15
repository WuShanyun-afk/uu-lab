# -*- coding: utf-8 -*-
"""单次 MCP 调用全量诊断：把 stdout / stderr 原样吐出来。
用法: python diag.py [工具名] [JSON参数]
"""
import json, subprocess, os, sys

env = dict(os.environ)
env["NO_COLOR"] = "1"
env["PYTHONUNBUFFERED"] = "1"

SERVER = ["C:\\Users\\32265\\.local\\bin\\uvx.exe", "lpc-character-mcp"]
tool = sys.argv[1] if len(sys.argv) > 1 else "search_items"
args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {"category": "body", "limit": 5}

payload = "".join([
    json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2024-11-05", "capabilities": {},
        "clientInfo": {"name": "diag", "version": "1.0"}}}) + "\n",
    json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized",
                "params": {}}) + "\n",
    json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": {"name": tool, "arguments": args}}) + "\n",
])

p = subprocess.Popen(SERVER, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.PIPE, env=env)
out, err = p.communicate(payload.encode(), timeout=180)

print("tool=%s args=%s rc=%s" % (tool, json.dumps(args, ensure_ascii=False), p.returncode))
print("=== STDOUT (%d bytes) ===" % len(out))
print(out.decode("utf-8", "replace"))
print("=== STDERR (%d bytes) ===" % len(err))
print(err.decode("utf-8", "replace"))
