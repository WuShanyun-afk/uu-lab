# LPC 角色生成 · 使用笔记

> 留给下次的我。2026-10-14 首次跑通。

## 一、最大的坑：stdio EOF 会杀死工具调用

**症状**：`initialize` 有响应，`tools/call` **完全没有响应**，进程 `rc=0`、`stderr` 空。

**原因**：用 `subprocess.communicate(payload)` 会在发完请求后**关闭 stdin**。
server 读到 EOF 就退出主循环，把还在异步执行的工具调用一起带走了。

**为什么 `list_categories` 能成功**：它是纯内存操作，几毫秒返回，赶在 EOF 处理前就写完了响应。
`search_items` / `get_item` / `generate_character` 都要读素材索引或下载 PNG，来不及。

**正确姿势**（见 `lpc_client.py`）：
```python
p = subprocess.Popen(SERVER, stdin=PIPE, stdout=PIPE, stderr=PIPE, env=env)
p.stdin.write(payload.encode()); p.stdin.flush()   # ← 不要 close！
# 开线程逐行 readline，直到读到 id == N 的响应，再 p.kill()
```

**推论**：任何 MCP stdio server 都可能踩这个。写客户端时永远不要 `communicate()`。

## 二、其他坑

| 坑 | 说明 |
|---|---|
| `@@` 在 PowerShell 里是 splatting 语法 | 传分隔符要写成 `"@@"` 加引号 |
| 一次会话只发一条 `tools/call` | 同一个 server 进程连发多条，只有第一条能回（同样是 EOF 时序问题）。每个工具调用起独立进程最稳 |
| PowerShell stdout 是 GBK | Python 脚本 `print()` 含非 ASCII（如 `ö`）会 `UnicodeEncodeError`。**先落盘再打印**，或重定向到文件读 |
| `search_items` 返回两条路径 | `content[0].text`（每项一个 JSON 字符串）和 `structuredContent.result`（真正的数组）。优先用后者 |
| `watering` 动画会被静默忽略 | 请求里带上它，返回的 `animations` 里没有。工具类动画要另外带 `tool_watering_can` 之类的 item |

## 三、可用工具（11 个）

`list_categories` / `search_items` / `get_item` / `generate_character` /
`from_site_url` / `to_site_url` / `random_character` / `generate_batch` /
`preview_character` / `clear_cache` / `update_definitions`

## 四、主角素材参数（已落盘）

```jsonc
{
  "items": [
    {"id": "body/body"},
    {"id": "head/heads/human/heads_human_male"},
    {"id": "hair/short/hair_plain", "color": "dark_brown"},
    {"id": "torso/shirts/longsleeve/torso_clothes_longsleeve", "color": "white"},
    {"id": "torso/aprons/torso_aprons_overalls", "color": "leather"},
    {"id": "legs/pants/legs_cuffed", "color": "navy"},
    {"id": "feet/boots/feet_boots_basic", "color": "brown"}
  ],
  "body_type": "male",
  "animations": ["walk", "idle", "slash", "run"],
  "layout": "standard",          // ← Godot/Unity 导入器期望的布局，别用 compact
  "export": ["godot"],           // 产出 player.tres (SpriteFrames)
  "licenses": ["CC0", "OGA-BY"],
  "output_dir": "D:/UU的办公室/小牧场日记/assets/characters/",
  "filename": "player.png",
  "prefer_complete": false       // ← 开了会换素材改外观，必须用户同意
}
```

**产出**：`player.png` (832×3456, 64px 帧) + `player.tres` (16 动画) + `player_credits.{txt,csv}`

## 五、⚠️ 许可证（发布前必读）

- 本次生成的素材实际许可：**CC-BY-SA 3.0 / GPL 2.0 / GPL 3.0 / OGA-BY 3.0**
- `license_check.drm_safe = true`、`share_alike_required = false`
  → **Steam / App Store 可用**（因为实际用到的部件都允许 CC0 或 OGA-BY）
- 但**必须**在游戏致谢页粘贴 `player_credits.txt` 里的 statement。这是许可证强制要求。
- 每次生成都会写 `<name>_credits.txt` / `_credits.csv`，**别删**。

## 六、角色尺寸与地块的关系

- LPC 帧 = **64×64**；我们的地块 = **32×32**
- 角色本体约占帧的 45px 高 → 世界里约 1.4 格
- 星露谷是 16×32 角色 + 16×16 地块（角色 2 格高），比例接近，可接受
- 精灵 `position = (0, -32)` 让帧底对齐节点原点，碰撞盒只取脚部 20×10
