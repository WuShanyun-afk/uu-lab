# -*- coding: utf-8 -*-
"""uu 的 MCP 工具调用器（stdio JSON-RPC 一次性会话）

用法:
  python mcp_call.py <server命令> [server参数...] @@ <工具名> <JSON参数>

示例:
  python mcp_call.py uvx lpc-character-mcp @@ generate_character "{\"body_type\":\"male\"}"

结果同时写盘到 %TEMP%\\uu_mcp\\<tool>_<ts>.json
"""
import json, subprocess, sys, os, time


def main():
    argv = sys.argv[1:]
    if "@@" not in argv:
        print(__doc__)
        sys.exit(2)
    i = argv.index("@@")
    server_cmd = argv[:i]
    tool = argv[i + 1]
    args = {}
    if len(argv) > i + 2:
        raw = argv[i + 2]
        if raw.startswith("--file="):
            with open(raw[7:], "r", encoding="utf-8-sig") as f:
                args = json.load(f)
        else:
            args = json.loads(raw)

    env = dict(os.environ)
    env["NO_COLOR"] = "1"
    env["PYTHONUNBUFFERED"] = "1"

    payload = "".join([
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "uu-call", "version": "1.0"}}}) + "\n",
        json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized",
                    "params": {}}) + "\n",
        json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                    "params": {"name": tool, "arguments": args}}) + "\n",
    ])

    t0 = time.time()
    p = subprocess.Popen(server_cmd, stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        out, err = p.communicate(payload.encode(), timeout=600)
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
        print("[超时]")
        print(err.decode("utf-8", "replace")[:3000])
        sys.exit(1)

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
    print("--- 用时 %.1fs  rc=%s ---" % (time.time() - t0, p.returncode))
    print(json.dumps(resp, ensure_ascii=False, indent=2) if resp else "(无响应)")
    if err.strip():
        print("--- stderr ---")
        print(err.decode("utf-8", "replace")[:3000])

    d = os.path.join(os.environ["TEMP"], "uu_mcp")
    os.makedirs(d, exist_ok=True)
    fp = os.path.join(d, "%s_%d.json" % (tool, int(time.time())))
    with open(fp, "w", encoding="utf-8") as f:
        json.dump({"tool": tool, "args": args, "resp": resp,
                   "stderr": err.decode("utf-8", "replace")}, f,
                  ensure_ascii=False, indent=2)
    print("[落盘] " + fp)


main()
