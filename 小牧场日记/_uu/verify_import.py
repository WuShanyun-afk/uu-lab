# -*- coding: utf-8 -*-
"""按 mcp-import.json 里的真实配置，逐个握手验证。

和 mcp_probe.py 的区别：这里读的是「用户将要导入的那份 JSON」，
把每个 server 的 env 原样注入子进程 —— 验证的是**导入后的真实行为**，不是猜想。

用法: python verify_import.py
"""
import json, os, subprocess, sys, time

CFG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mcp-import.json")

def probe(command, args, extra_env, timeout=90):
    env = dict(os.environ)
    env.update(extra_env or {})
    env["NO_COLOR"] = "1"
    payload = "".join([
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "uu-verify", "version": "1.0"}}}) + "\n",
        json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}) + "\n",
        json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}) + "\n",
    ])
    t0 = time.time()
    try:
        p = subprocess.Popen([command] + list(args), stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    except FileNotFoundError as e:
        return {"error": "命令不存在: %s" % e}
    try:
        out, err = p.communicate(payload.encode(), timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
        return {"error": "超时 %ds" % timeout, "stderr": err.decode("utf-8", "replace")[:800]}
    msgs = []
    for line in out.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            msgs.append(json.loads(line))
        except Exception:
            pass
    return {"msgs": msgs, "stderr": err.decode("utf-8", "replace")[:800],
            "elapsed": time.time() - t0, "rc": p.returncode}


def main():
    with open(CFG, encoding="utf-8") as f:
        raw = f.read()
    if raw.startswith("\ufeff"):
        print("!! 文件带 BOM，Kelivo 可能解析失败")
    cfg = json.loads(raw)
    servers = cfg.get("mcpServers", {})
    print("配置文件: %s" % CFG)
    print("server 数: %d  ->  %s\n" % (len(servers), ", ".join(servers)))

    ok = 0
    for name, s in servers.items():
        cmd = s.get("command", "")
        args = s.get("args", [])
        env = s.get("env", {})
        print("=" * 70)
        print("[%s]  %s %s" % (name, cmd, " ".join(args)))
        if not os.path.exists(cmd):
            print("   [失败] 命令路径不存在: %s" % cmd)
            continue
        r = probe(cmd, args, env)
        if "error" in r:
            print("   [失败] %s" % r["error"])
            if r.get("stderr", "").strip():
                print("   --- stderr ---")
                for l in r["stderr"].strip().splitlines()[:8]:
                    print("      " + l)
            continue
        init = next((m for m in r["msgs"] if m.get("id") == 1), None)
        tools = next((m for m in r["msgs"] if m.get("id") == 2), None)
        if init and init.get("result"):
            si = init["result"].get("serverInfo") or {}
            print("   [握手 OK] %s v%s   %.1fs" % (si.get("name"), si.get("version"), r["elapsed"]))
            ok += 1
        else:
            print("   [握手失败]  %.1fs" % r["elapsed"])
        if tools and tools.get("result"):
            tl = tools["result"].get("tools") or []
            print("   [工具 %d 个] %s" % (len(tl), ", ".join(t.get("name", "") for t in tl[:6]) + (" ..." if len(tl) > 6 else "")))
    print("=" * 70)
    print("结论: %d/%d 个 server 握手成功" % (ok, len(servers)))
    return 0 if ok == len(servers) else 1


if __name__ == "__main__":
    sys.exit(main())
