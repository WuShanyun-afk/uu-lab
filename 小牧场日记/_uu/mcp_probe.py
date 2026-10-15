# -*- coding: utf-8 -*-
"""uu 的 MCP stdio 探针 v2
修复: 不再同步 read stderr（子进程不退出会永久阻塞）。
改用: 一次性灌入 JSON-RPC 请求 -> 关 stdin -> communicate(timeout) -> 解析。
用法: python mcp_probe.py <命令> [参数...]
结果同时写盘到 %TEMP%\\uu_install\\probe_<名字>.txt
"""
import json, subprocess, sys, os, re, time

def probe(cmd, args, timeout=60):
    env = dict(os.environ)
    env["NO_COLOR"] = "1"
    env["PYTHONUNBUFFERED"] = "1"
    payload = "".join([
        json.dumps({"jsonrpc":"2.0","id":1,"method":"initialize","params":{
            "protocolVersion":"2024-11-05","capabilities":{},
            "clientInfo":{"name":"uu-probe","version":"1.0"}}}) + "\n",
        json.dumps({"jsonrpc":"2.0","method":"notifications/initialized","params":{}}) + "\n",
        json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}) + "\n",
    ])
    t0 = time.time()
    try:
        p = subprocess.Popen([cmd] + args, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    except FileNotFoundError as e:
        return {"error": f"命令不存在: {e}", "elapsed": 0}
    try:
        out, err = p.communicate(payload.encode(), timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
        return {"error": f"超时 {timeout}s 未响应", "stdout": out.decode("utf-8","replace")[:2000],
                "stderr": err.decode("utf-8","replace")[:2000], "elapsed": time.time()-t0}
    msgs = []
    for line in out.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if not line: continue
        try: msgs.append(json.loads(line))
        except Exception: pass
    return {"msgs": msgs, "stderr": err.decode("utf-8","replace")[:2000],
            "elapsed": time.time()-t0, "rc": p.returncode}

def render(cmd, args, r):
    L = []
    L.append("=" * 66)
    L.append(f"探针: {cmd} {' '.join(args)}")
    L.append("=" * 66)
    if "error" in r:
        L.append("  [失败] " + r["error"])
        for k in ("stdout","stderr"):
            if r.get(k, "").strip():
                L.append(f"  --- {k} ---")
                L += ["     " + x for x in r[k].strip().splitlines()[:15]]
        return L
    L.append(f"  用时 {r['elapsed']:.1f}s  returncode={r['rc']}")
    init  = next((m for m in r["msgs"] if m.get("id") == 1), None)
    tools = next((m for m in r["msgs"] if m.get("id") == 2), None)
    if init:
        res = init.get("result") or {}
        si = res.get("serverInfo") or {}
        L.append(f"  [握手 OK] {si.get('name')} v{si.get('version')}  protocol={res.get('protocolVersion')}")
    else:
        L.append("  [握手失败] 未收到 initialize 响应")
    if tools:
        tl = (tools.get("result") or {}).get("tools") or []
        L.append(f"  [工具 {len(tl)} 个]")
        for t in tl:
            L.append(f"     - {t.get('name')}")
    elif tools and tools.get("error"):
        L.append("  [工具列表报错] " + json.dumps(tools["error"], ensure_ascii=False))
    else:
        L.append("  [工具列表失败]")
    if r.get("stderr","").strip():
        L.append("  --- stderr ---")
        L += ["     " + x for x in r["stderr"].strip().splitlines()[:12]]
    return L

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python mcp_probe.py <命令> [参数...]"); sys.exit(2)
    cmd, args = sys.argv[1], sys.argv[2:]
    timeout = 60
    r = probe(cmd, args, timeout)
    lines = render(cmd, args, r)
    txt = "\n".join(lines)
    print(txt)
    safe = re.sub(r"[^\w.-]", "_", os.path.basename(cmd) + "_" + "_".join(args))[:60]
    d = os.path.join(os.environ["TEMP"], "uu_install")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, f"probe_{safe}.txt"), "w", encoding="utf-8") as f:
        f.write(txt)
