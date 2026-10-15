# -*- coding: utf-8 -*-
"""dump 某个 MCP server 的工具 schema
用法: python mcp_schema.py <server命令> [参数...] [@@ 工具名过滤]
写盘到 %TEMP%\\uu_mcp\\schema_<工具名或all>.json
"""
import json, subprocess, sys, os


def main():
    argv = sys.argv[1:]
    only = None
    if "@@" in argv:
        i = argv.index("@@")
        only = argv[i + 1] if len(argv) > i + 1 else None
        argv = argv[:i]
    if not argv:
        print(__doc__)
        sys.exit(2)

    env = dict(os.environ)
    env["NO_COLOR"] = "1"
    payload = "".join([
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "uu-schema", "version": "1.0"}}}) + "\n",
        json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized",
                    "params": {}}) + "\n",
        json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list",
                    "params": {}}) + "\n",
    ])
    p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, env=env)
    out, err = p.communicate(payload.encode(), timeout=600)

    tools = []
    for line in out.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        if m.get("id") == 2:
            tools = (m.get("result") or {}).get("tools") or []

    if only:
        tools = [t for t in tools if t.get("name") == only]

    d = os.path.join(os.environ["TEMP"], "uu_mcp")
    os.makedirs(d, exist_ok=True)
    fp = os.path.join(d, "schema_%s.json" % (only or "all"))
    with open(fp, "w", encoding="utf-8") as f:
        json.dump(tools, f, ensure_ascii=False, indent=2)

    print("工具数 %d" % len(tools))
    for t in tools:
        print("  - " + t.get("name", "?"))
    print("[落盘] " + fp)
    if err.strip():
        print("--- stderr ---")
        print(err.decode("utf-8", "replace")[:1500])


main()
