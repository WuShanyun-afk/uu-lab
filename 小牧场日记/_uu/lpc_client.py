# -*- coding: utf-8 -*-
"""LPC MCP 客户端（正确姿势）

踩坑记录：
  用 subprocess.communicate() 会在发完请求后关闭 stdin，
  server 读到 EOF 立刻退出，把还在跑的工具调用一起带走 ——
  表现是"initialize 回了，tools/call 没有响应，rc=0，stderr 空"。
  只有纯内存的 list_categories 够快，能在 EOF 前写完。
  正确做法：保持 stdin 打开，读到 id==N 的响应再 kill。

用法: python lpc_client.py [工具名] [JSON参数文件]
"""
import json, subprocess, os, sys, threading

SERVER = ["C:\\Users\\32265\\.local\\bin\\uvx.exe", "lpc-character-mcp"]


def call(tool, args, timeout=300, env=None):
    """调一次工具，返回 (响应dict, 原始行数, stderr文本)"""
    env = env or dict(os.environ)
    env["NO_COLOR"] = "1"
    env["PYTHONUNBUFFERED"] = "1"

    payload = "".join([
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "uu-client", "version": "1.0"}}}) + "\n",
        json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized",
                    "params": {}}) + "\n",
        json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                    "params": {"name": tool, "arguments": args}}) + "\n",
    ])

    p = subprocess.Popen(SERVER, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, env=env)
    box = {"resp": None, "lines": [], "err": ""}

    def rd_out():
        try:
            while True:
                raw = p.stdout.readline()
                if not raw:
                    break
                s = raw.decode("utf-8", "replace").strip()
                if not s:
                    continue
                box["lines"].append(s)
                try:
                    m = json.loads(s)
                except Exception:
                    continue
                if m.get("id") == 2:
                    box["resp"] = m
                    break
        except Exception as e:
            box["err"] += "stdout:%s " % e

    def rd_err():
        try:
            box["err"] += p.stderr.read().decode("utf-8", "replace")
        except Exception:
            pass

    t1 = threading.Thread(target=rd_out, daemon=True)
    t2 = threading.Thread(target=rd_err, daemon=True)
    t1.start()
    t2.start()

    try:
        p.stdin.write(payload.encode())
        p.stdin.flush()
    except Exception as e:
        box["err"] += "stdin:%s " % e

    t1.join(timeout=timeout)
    try:
        p.kill()
    except Exception:
        pass
    return box["resp"], len(box["lines"]), box["err"]


def unwrap(resp):
    """把 MCP 响应拆成 Python 对象（优先 structuredContent，其次 content[0].text）"""
    if not resp:
        return None
    r = resp.get("result") or {}
    sc = r.get("structuredContent")
    if isinstance(sc, dict) and "result" in sc:
        return sc["result"]
    try:
        return json.loads(r["content"][0]["text"])
    except Exception:
        return None


if __name__ == "__main__":
    tool = sys.argv[1] if len(sys.argv) > 1 else "list_categories"
    args = {}
    if len(sys.argv) > 2:
        with open(sys.argv[2], "r", encoding="utf-8-sig") as f:
            args = json.load(f)
    resp, n, err = call(tool, args)
    print("tool=%s  lines=%d  got=%s" % (tool, n, resp is not None))
    if resp:
        print(json.dumps(resp, ensure_ascii=False, indent=2)[:4000])
    else:
        print("STDERR: " + err[:1500])
