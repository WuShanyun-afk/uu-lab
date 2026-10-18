# 用 MCP 音频工具生成 16-bit 音效 —— 《小牧场日记》实操指南

> 面向：已经会用命令行、但没碰过 MCP 音频工具的开发者。
> 项目：`D:\UU的办公室\小牧场日记`（Godot 4.7.2）
> 调研/实测日期：**2026-10-18**。文中「✅ 已核实」= 我亲自查了 npm registry / GitHub API / 包源码，或在本机跑过命令；「⚠️ 未核实」= 只看到文档描述、没亲手跑通。
> 本篇只写这一个文件，不改 `scripts/`、`project.godot`、`data/audio.csv`。

---

## 0. 结论先行（一句话版）

**两个包都不是「装上一键出 31 条素材」的银弹：`@pixelbananas/mcp` 真实存在、能装上、MCP 握手成功，但它只有 7 个工具、按 credits 计费（免费 20/月，不够本项目用），且真实生成要 token + 它的 API 域名在本机目前连不上；`sfx-gen-mcp` 真实存在，但只是 GitHub 仓库（不是 npm 包、PyPI 也没有），要本地跑 Stable Audio Open（约 10GB 模型 + GPU），而且它只做 SFX、不做 BGM。** 所以现实的用法是：**BGM 继续用 `_uu/gen_audio.py`（已经生成好 7 首、24/28s、无缝循环），SFX 选几条用 MCP 重做对比听感**，而不是全量替换。

| 包 | 存在？ | 形态 | 要 key？ | 能力 | 本项目可用性 |
|---|---|---|---|---|---|
| `@pixelbananas/mcp` | ✅ 存在，npm 公共包 **0.2.0**（2026-04-27 发布，MIT） | Node MCP server（stdio） | 要 `PIXELBANANAS_TOKEN`（`pba_live_...`） | 8-bit/chiptune SFX、BGM、整套 kit；**共 7 个工具** | ⚠️ 能握手，但免费 20 credits/月 ≪ 本项目需求；API 端点本机超时；SFX/BGM 都不能指定精确时长 |
| `sfx-gen-mcp` | ✅ 存在，但**只有 GitHub 仓库**（`JimCline/sfx-gen-mcp`，Python，MIT）；npm 搜索无此包、PyPI `/pypi/sfx-gen-mcp/json` 返回 **404** | Python MCP server，本地 Stable Audio Open | 不要 API key，但要 HF gated 模型许可 | `generate_sfx`：SFX（0.5–47s，支持 seed/negative_prompt/variations）；**不做 BGM** | ⚠️ 适合逐条打磨 SFX，但吃 ~10GB 磁盘 + ~12GB 内存，短于 0.5s 的音效必须后期裁 |
| `elevenlabs-mcp`（替代） | ✅ 存在，官方 PyPI 包 `elevenlabs-mcp` 0.12.2 | Python MCP server | 要 `ELEVENLABS_API_KEY` | `text_to_sound_effects`（0.5–5s，`loop` 参数）+ `compose_music`（**3000–600000ms 精确长度 + seed**） | 目前最接近「能凑齐 SFX+BGM」的商用方案，但按 ElevenLabs 订阅计费 |

三条硬结论：

1. **BGM 不要指望这两个包。** `sfx-gen-mcp` 没有 BGM 工具；`@pixelbananas/mcp` 有 `generate_bgm`，但时长由 `bars`（只有 8/16/32）和 prompt 里的 BPM 决定，**没有 duration/BPM/loop/seed 参数**，命中本项目 24–28s 只能靠后期裁（详见 §3.3 的时长估算）。而 `_uu/gen_audio.py` 已经能精确生成 24/28s、环形缓冲无缝循环的 BGM（✅ 本机已验证：7 个 wav，24.000s ×6 + 28.000s ×1，立体声 44.1k/16bit，峰值 −12 dBFS）。
2. **SFX 是 MCP 唯一真正值得试的地方。** 尤其 `sfx-gen-mcp` 对「踩草 / 锄地 / 挤奶 / 动物叫」这类需要物理质感的音效比程序合成更像样；代价是环境重、短音效要裁。
3. **当前项目不缺素材，缺的是「升级路径」。** `audio/sfx/`、`audio/bgm/` 已经有全套 31+4 条底稿（✅ 本机实测存在，格式正确）。MCP 是「逐条替换、A/B 试听」的可选项，不是阻塞项。

> 今天在本机实测到的两条硬证据（细节见 §2.4）：
> - 把 `@pixelbananas/mcp@0.2.0` 的 tarball 下载、装依赖、用**假 token** 起 server：握手 OK，`serverInfo = pixelbananas-mcp v0.2.0`，`tools/list` 返回 7 个工具（`generate_sfx` / `generate_bgm` / `generate_kit` / `list_generations` / `get_generation` / `share_patch` / `download_audio`）。说明**启动阶段不校验 token**，token 只在真正调 API 生成时生效。
> - `https://pixelbananas.pages.dev/` 返回 200，但 `https://pixelbananas-api.nano122090.workers.dev/api/generations` 在本机 20s 超时。**所以「它到底能不能在这台机器上真生成」是本文最大的不确定性**（需要挂着可用代理再验一次）。

---

## 1. 调研结果：逐个核实，不编造

### 1.1 `@pixelbananas/mcp` —— ✅ 存在

- npm registry 元数据（✅ 已核实）：包名 `@pixelbananas/mcp`，`dist-tags.latest = 0.2.0`，`bin = pixelbananas-mcp → dist/index.js`，`engines.node >= 18`，`license: MIT`，作者 `PixelBananas`，依赖 `@modelcontextprotocol/sdk ^1.0.0`、`node-web-audio-api`、`lamejs`、`zod`。
- 它是什么：**MCP stdio server**，把 PixelBananas 的 AI 音频 API 包成工具给任意 MCP 客户端（Claude Code / Claude Desktop / Cursor 等）调用。前端站点：`https://pixelbananas.pages.dev`。
- 暴露的工具（✅ 从包内 `dist/index.js` + `dist/tools.js` 源码核实，不是 README 抄的）：

| 工具 | 参数（真实 schema） | 说明 |
|---|---|---|
| `generate_sfx` | `prompt`(1–500 字) `effort`(1\|2\|4，默认1) `save`(默认true) `format`("wav"\|"mp3"\|"both"，默认wav) `outputDir` `filename` | 文本→音效，自动存盘；**没有 duration、没有 seed、没有 loop** |
| `generate_bgm` | `prompt` `effort`(1\|2\|4) `bars`(8\|16\|32，默认16) `save` `format` `outputDir` `filename` `includeMidi`(默认true) | 文本→chiptune BGM + `.mid`；**没有 BPM、没有时长、没有 seed** |
| `generate_kit` | `template` `theme?` | 整套音效包 ZIP（Studio 档） |
| `list_generations` | `kind?` `limit?` `before?` | 免费 |
| `get_generation` | `id` | 免费 |
| `share_patch` | `kind` `prompt` `payload` | 免费 |
| `download_audio` | `generationId`(12位hex) `format` `outputDir` `filename` `includeMidi` | 免费 |

- 计费/限速（README 写明）：免费档 **20 credits/月**；`generate_sfx` 1/2/4 credits，`generate_bgm` 5–20 credits；限速 5 次/分钟（SFX）、3 次/分钟（BGM）。**按本项目 27 条 SFX + 7 条 BGM，免费额度一条都覆盖不了** → 必须付费或只挑几条。
- 输出规格（✅ 读源码核实，比 README 准）：`dist/render/sfx.js` 与 `dist/render/song.js` 都用 `OfflineAudioContext({numberOfChannels: 1, sampleRate: 44100})`，`dist/encode/wav.js` 固定 **16-bit** → 输出是**单声道 44.1kHz/16bit WAV**，正好符合本项目「44.1k/16bit」要求，但 BGM 也是单声道。另外 SFX 会在目标时长后加 `max(0.2s, release+0.05)` 的尾巴，BGM 固定加 **1.0s 尾巴**（`TAIL_S`）→ 想完美循环必须自己裁掉尾巴。
- 文件名规则（README）：prompt 的 slug，冲突时 `-2`、`-3`；**用 `filename` 参数强制成 `<id>`**，否则文件名对不上 `data/audio.csv`。
- key：必须有 `PIXELBANANAS_TOKEN`，在 `https://pixelbananas.pages.dev/settings/tokens` 创建，形如 `pba_live_...`。没有 token 时 server 直接退出并打印提示。
- 许可：包本体 MIT；**生成音频的商用授权 README 没写**（⚠️ 未核实，我没找到它的 ToS 链接）→ 商用前必须自己去站点确认，不要默认可用。
- 与 README 的出入（⚠️ 提醒）：README 示例写了 `effort=2` 但没提 `outputDir` 的优先级——源码里的优先级是「工具参数 `outputDir` > 环境变量 `PIXELBANANAS_OUTPUT_DIR` > 进程 cwd 下 `./pixelbananas-audio/`」。

### 1.2 `sfx-gen-mcp` —— ✅ 存在，但**不是 npm 包**

- 核实方式：`https://registry.npmjs.org/sfx-gen-mcp` → **HTTP 404**；`https://pypi.org/pypi/sfx-gen-mcp/json` → **HTTP 404**；npm search `sfx-gen-mcp` 无同名结果；GitHub API `repos/JimCline/sfx-gen-mcp` → **HTTP 200**（Python，MIT，1 star，2026-07-24 创建，最后 push 2026-08-02，commit `f6ba5616f1ad99d0e72869d9b471b147ebf4d6e4`）。
- 它是什么：**本地** SFX 生成 MCP server，用 Stability AI 的 Stable Audio Open（`stabilityai/stable-audio-open-1.0`）。README 原话：「Not yet on PyPI — install from this repo」。
- 工具（✅ 来自 README + `pyproject.toml`）：
  - `generate_sfx`：`prompt`、`duration_seconds`（**0.5–47**）、`steps`、`cfg_scale`、`seed`、`negative_prompt`、`variations`（1–4）、`output_dir`、`filename`。返回保存路径 + 实际使用的 seed。
  - `sfx_server_status`：模型/设备/加载状态。
  - 另一个 server `sfx-gen-ctl`（stdio）提供 `sfx_ensure_server` / `sfx_status` / `sfx_troubleshoot`，用于把常驻 daemon 拉起来。
- 安装与运行（README，✅ 命令原文；本机没实跑，因为要下 10GB 模型）：
  ```bash
  uv tool install "git+https://github.com/JimCline/sfx-gen-mcp"
  # 或 pip install "git+https://github.com/JimCline/sfx-gen-mcp"
  # 常驻 daemon（推荐，避免每次调用重新加载模型）
  PYTHON_ENABLE_MPS_FALLBACK=1 sfx-gen-mcp --transport http --port 8756
  ```
- 依赖与门槛：Python ≥ 3.10、`mcp>=1.9,<2`（**不能装 mcp 2.x**，作者专门 pin 过，见 commit message）、`stable-audio-tools>=0.0.19`、`torch>=2.5`、`torchaudio`、`numpy`、`soundfile`；**~10GB 模型权重、~12GB 内存**，GPU（CUDA / Apple MPS）强烈建议；首次调用懒加载模型约 **20–40s**；空闲 1800s 自动退出释放显存（`SFX_IDLE_TIMEOUT`）。
- 环境变量（README 列出）：`SFX_MODEL`（默认 `stabilityai/stable-audio-open-1.0`）、`SFX_OUTPUT_DIR`（默认 `<cwd>/sfx-output`）、`SFX_IDLE_TIMEOUT`（默认 1800，0 关闭）。
- 输出格式：⚠️ **未核实**。README/源码目录我没读到编码细节，Stable Audio Open 常规输出是 44.1kHz 立体声 float→wav，**大概率不是单声道**，落地后要自己转单声道/裁时长。
- 许可：脚本 MIT；模型权重受 **Stability AI Community License** 约束——README 明文：年收入 < $1M 的组织可用于商业项目，超出要另谈。
- 与「sfx-gen-mcp 是 npm 包」的说法：**错误，别照着 `npx sfx-gen-mcp` 去装。** 另：`sfxgen`、`audio-gen-mcp` 这类名字在 npm 上也没有对应包（✅ npm search 实测），别被相近名误导；`@reaatech/media-pipeline-mcp-audio-gen` 是另一个东西（多 provider 的媒体管线，不是本地生成），本文不推荐。

### 1.3 替代方案（这两个不可用时）

| 方案 | 形态 | 关键工具/参数 | 许可/成本 | 适用 |
|---|---|---|---|---|
| **ElevenLabs 官方 MCP** | PyPI `elevenlabs-mcp` 0.12.2（✅ 存在，MIT 包） | `text_to_sound_effects(text, duration_seconds 0.5–5, loop, output_format, output_directory)`；`compose_music(prompt, music_length_ms 3000–600000, model_id music_v1/v2, force_instrumental, seed, output_directory)` | 要 `ELEVENLABS_API_KEY`，按订阅计费（README 提到免费档 10k credits/月）；**免费档通常要求署名**（⚠️ 以官网条款为准） | 唯一能「SFX + 精确时长 BGM」一起做的商用方案 |
| **Freesound MCP** | npm `@mushan_bit/freesound-mcp` 1.0.2（✅ 存在，ISC） | `freesound_search(query, maxDuration?, license?)`、`freesound_download(soundId, quality?, downloadDir?)` | 要 `FREESOUND_API_KEY`；音频按各自 CC 协议（选 CC0 最稳） | 雨声/环境音这类「录制素材」比生成更像；只搜/下，不生成 |
| `jsfxr`（软件库） | npm `jsfxr` 1.4.1（✅ 存在，8-bit SFX 合成库） | 代码调用，参数是 sfxr 的波形/包络 | 免费 | 纯 chiptune SFX 兜底，不用 AI |

许可小结：**`@pixelbananas/mcp` 生成物的商用条款未核实 → 不要默认可商用；`sfx-gen-mcp` 的输出在年收入 <$1M 时可商用（README 明文）；ElevenLabs / Freesound 各按自己的条款。** 项目如果只是本地/学习用途，这三条都不构成阻塞。

---

## 2. 安装与配置

### 2.1 本机现状：配置该加在哪

- `_uu/mcp-config.json`（78 行）是**带注释的配置汇总**，不是任何客户端会自动读的文件；客户端读的是它自己的配置文件（Claude Desktop 是 `%APPDATA%\Claude\claude_desktop_config.json`，Kelivo 的路径 ⚠️ 未核实）。
- 它里面已经有 `mcpServers` 对象，现有 5 个 server：`godot`（第 11–25 行）、`pixelart`（26–35）、`lpc`（36–47）、`pixelforge`（48–58）、**`pixelbananas`（59–69）**。
- **新增音频 MCP 就加在 `mcpServers` 里，与 `godot` / `pixelart` / `lpc` 平级**，逗号别漏。`_uu/mcp-import.json` 是「可粘贴版」（只有 3 个 server、`command` 已换成 `npx.cmd` / `uvx.exe` 绝对路径），要粘到客户端也可以从这里长出来。
- 现有 `pixelbananas` 那段有 **3 个问题**，照抄会踩：
  1. `PIXELBANANAS_TOKEN` 还是 `pba_live_REPLACE_ME`（要真 token）；
  2. `PIXELBANANAS_OUTPUT_DIR` 指向 `assets/audio`，**但 `data/audio.csv` 的路径是 `res://audio/sfx/...`、`res://audio/bgm/...`** → 必须改成 `D:/UU的办公室/小牧场日记/audio/sfx`（BGM 则在调用时用 `outputDir` 参数覆盖，别把两坨混在一个目录）；
  3. 它没配代理之外的超时/重试，也别把 token 写进要提交的仓库文件（用系统环境变量或客户端配置里的 `env`，仓库里留占位符）。
- `_windows_note` 的坑是真的：Windows 上客户端报 `spawn npx ENOENT` 时，`command` 换成 `C:\Users\32265\AppData\Local\Programs\nodejs\npx.cmd`（`npx` 是 `.ps1`，不能直接 spawn）。

### 2.2 可直接粘贴的 `mcpServers` 片段

> 版本号 / 路径不确定处已用占位符标出：`REPLACE_ME` = 你填；`<...>` = 需要你确认。

```json
{
  "mcpServers": {
    "pixelbananas": {
      "command": "C:\\Users\\32265\\AppData\\Local\\Programs\\nodejs\\npx.cmd",
      "args": ["-y", "@pixelbananas/mcp@0.2.0"],
      "env": {
        "PIXELBANANAS_TOKEN": "pba_live_REPLACE_ME",
        "PIXELBANANAS_OUTPUT_DIR": "D:/UU的办公室/小牧场日记/audio/sfx",
        "HTTP_PROXY": "http://127.0.0.1:7892",
        "HTTPS_PROXY": "http://127.0.0.1:7892",
        "NO_PROXY": "localhost,127.0.0.1,::1,registry.npmmirror.com"
      }
    },
    "sfx-gen": {
      "command": "C:\\Users\\32265\\.local\\bin\\sfx-gen-mcp.exe",
      "args": [],
      "env": {
        "SFX_MODEL": "stabilityai/stable-audio-open-1.0",
        "SFX_OUTPUT_DIR": "D:/UU的办公室/小牧场日记/audio/sfx",
        "SFX_IDLE_TIMEOUT": "1800",
        "HF_HOME": "C:\\Users\\32265\\.cache\\huggingface",
        "HTTP_PROXY": "http://127.0.0.1:7892",
        "HTTPS_PROXY": "http://127.0.0.1:7892"
      },
      "_note": "<sfx-gen-mcp.exe 的完整路径在 uv tool install 后用 `Get-Command sfx-gen-mcp` 确认；若已进 PATH，command 可直接写 sfx-gen-mcp>"
    },
    "elevenlabs": {
      "command": "C:\\Users\\32265\\.local\\bin\\uvx.exe",
      "args": ["elevenlabs-mcp"],
      "env": {
        "ELEVENLABS_API_KEY": "REPLACE_ME",
        "ELEVENLABS_MCP_BASE_PATH": "D:/UU的办公室/小牧场日记/audio",
        "ELEVENLABS_MCP_OUTPUT_MODE": "files",
        "HTTP_PROXY": "http://127.0.0.1:7892",
        "HTTPS_PROXY": "http://127.0.0.1:7892",
        "NO_PROXY": "localhost,127.0.0.1,::1,pypi.tuna.tsinghua.edu.cn"
      }
    }
  }
}
```

字段说明（避免瞎填）：
- `command` 必须是真实可执行文件。Windows 上 `npx` 用 `npx.cmd`、`uvx` 用 `uvx.exe` 的**绝对路径**最稳（本机：`C:\Users\32265\.local\bin\uvx.exe`、`C:\Users\32265\AppData\Local\Programs\nodejs\npx.cmd`，✅ 实测存在）。
- `@pixelbananas/mcp` 建议**锁 0.2.0**（`args` 里 `@pixelbananas/mcp@0.2.0`），避免哪天 breaking change 把工具参数改了。
- `sfx-gen-mcp` 只能从 git 装，所以 `mcpServers` 里不能写 `npx`；装完命令名是 `sfx-gen-mcp`（`pyproject.toml` 的 `[project.scripts]` 核实）。
- 代理：本机 npm/uv 默认会读用户级 `HTTP_PROXY/HTTPS_PROXY=127.0.0.1:7892`，**代理没开时 npm 直接 `ECONNREFUSED`（今天实测）**。要么先把代理开起来，要么临时清掉代理变量。`sfx-gen-mcp` 本身不联网（模型在本地），但**首次下 HF 模型要代理**。

### 2.3 Windows PowerShell 安装命令

```powershell
# 0) 前置检查
node -v          # 本机 v24.20.0
uv --version     # 本机 0.13.1
python --version # 本机 3.14（注意：没有 numpy，见 §6）

# 1) @pixelbananas/mcp —— 不需要全局安装，npx 现取现用；先验证能下载
#    （代理没开时先清：Remove-Item Env:HTTP_PROXY,Env:HTTPS_PROXY; $env:npm_config_proxy=""）
npx -y @pixelbananas/mcp@0.2.0
# 没有 PIXELBANANAS_TOKEN 会立刻打印错误并退出，这是预期行为；
# 能看到 "Error: PIXELBANANAS_TOKEN env var is required." 就说明包下载/执行正常。

# 2) sfx-gen-mcp —— 只能从 git 装（不要 npx！）
uv tool install "git+https://github.com/JimCline/sfx-gen-mcp@f6ba5616f1ad99d0e72869d9b471b147ebf4d6e4"
Get-Command sfx-gen-mcp        # 确认入口存在

# 3) 模型许可 + 下载（很慢，~10GB）
#    先去 https://huggingface.co/stabilityai/stable-audio-open-1.0 点同意许可
uvx --from huggingface_hub hf auth login
# 旧版 huggingface_hub 没有 hf 命令时用：uvx --from huggingface_hub huggingface-cli login
$env:SFX_OUTPUT_DIR = "D:/UU的办公室/小牧场日记/audio/sfx"
sfx-gen-mcp --transport http --port 8756   # 常驻；建议单独开一个窗口

# 4) ElevenLabs（可选替代）
uvx elevenlabs-mcp    # 首次会下载依赖；需要 ELEVENLABS_API_KEY
```

### 2.4 重启 / 验证「工具挂上了」

改完客户端配置后**重启客户端**（Claude Desktop 从托盘退出再开；Kelivo 同理）。然后用下面三种方式验证，任选：

**方式 A：用仓库里现成的探针（推荐，最干净）**

```powershell
# 在项目根目录
cd "D:\UU的办公室\小牧场日记"
$env:PIXELBANANAS_TOKEN = "pba_live_xxx"

# pixelbananas：期望看到 7 个工具
python _uu/mcp_probe.py "C:\Users\32265\AppData\Local\Programs\nodejs\npx.cmd" -y "@pixelbananas/mcp@0.2.0"

# sfx-gen：期望看到 generate_sfx / sfx_server_status
python _uu/mcp_probe.py "C:\Users\32265\.local\bin\sfx-gen-mcp.exe"

# 想看完整参数 schema（不是只有名字）：
python _uu/mcp_schema.py "C:\Users\32265\.local\bin\sfx-gen-mcp.exe"
# 落盘在 %TEMP%\uu_mcp\schema_all.json
```

**今天实测输出（假 token，✅ 有效）**：
```
[握手 OK] pixelbananas-mcp v0.2.0  protocol=2024-11-05
[工具 7 个]
   - generate_sfx
   - generate_bgm
   - generate_kit
   - list_generations
   - get_generation
   - share_patch
   - download_audio
```

**方式 B：LLM 侧自然语言验证**
重启后在对话里说「列出你当前挂载的音频相关 MCP 工具及参数」，正常应能报出 `generate_sfx` 等；如果模型说没有，说明客户端没加载成功。

**方式 C：真实调用一次（花钱最少）**
```powershell
# 用仓库里的调用器，真正生成一条最短的测试音效
python _uu/mcp_call.py "C:\Users\32265\AppData\Local\Programs\nodejs\npx.cmd" -y "@pixelbananas/mcp@0.2.0" "@@" generate_sfx "{\"prompt\":\"single UI click, dry, 8-bit\",\"effort\":1,\"format\":\"wav\",\"outputDir\":\"D:/UU的办公室/小牧场日记/audio/sfx\",\"filename\":\"_mcp_test\"}"
```
成功标志：返回 JSON 里有 `generationId`、`creditsRemaining`、`savedFiles`，并且 `audio/sfx/_mcp_test.wav` 真的出现。

**⚠️ 当前最大风险（实测）**：`pixelbananas-api.nano122090.workers.dev` 在本机 20s 超时（`pixelbananas.pages.dev` 本身 200）。如果方式 C 报超时/网络错误，先挂好代理再试；这属于网络问题，不是配置写错。

### 2.5 已知坑速查

| 现象 | 原因 | 处理 |
|---|---|---|
| `spawn npx ENOENT` | Windows 下 `npx` 是 `.ps1` | `command` 写 `...\nodejs\npx.cmd` |
| npm `ECONNREFUSED 127.0.0.1:7892` | 用户级代理变量在、代理没开 | 开代理，或 `Remove-Item Env:HTTP_PROXY,Env:HTTPS_PROXY` + 清 `npm_config_proxy` |
| pixelbananas 启动即退出 | 没给 `PIXELBANANAS_TOKEN` | 填 `pba_live_...` |
| `insufficient_credits` | 免费 20 credits/月用完了 | `list_generations` 查消耗；付费或改用 `gen_audio.py` |
| sfx-gen 报 `No module named 'mcp.server.fastmcp'` | 装了 mcp 2.x | 按 README pin `mcp>=1.9,<2`（作者 2026-08-02 的 commit 就是修这个） |
| sfx-gen 首次调用卡 30s+ | 模型懒加载 | 正常；用 HTTP daemon 模式可避免每次重载 |
| 生成文件名不是 `<id>` | 默认按 prompt slug 命名 | 一律传 `filename`（pixelbananas/sfx-gen 都有）或 `output_dir`+后改名 |

---

## 3. 逐条 Prompt 表

### 3.1 先讲清楚：参数名按真实 schema 写，不要照抄网上的

三家工具的**参数不通用**，下表是「同一条需求在不同工具里怎么写」：

| 需求 | `@pixelbananas/mcp` | `sfx-gen-mcp` | `elevenlabs-mcp` |
|---|---|---|---|
| 提示词 | `prompt` | `prompt` | `text`（SFX）/ `prompt`（音乐） |
| 时长 | ❌ 无，靠 prompt 描述 | ✅ `duration_seconds`（0.5–47） | ✅ `duration_seconds`（0.5–5）/ `music_length_ms`（3000–600000） |
| 风格 | 模型固定 8-bit chiptune，prompt 里写「8-bit」 | 用「物理描述」写，例：`footsteps on gravel, slow` | 同左 |
| 循环 | ❌ 无 `loop` 参数 | ❌ 无 | ✅ SFX 有 `loop: true`；音乐无 loop 保证 |
| seed | ❌ 无 | ✅ `seed` | 音乐 `music_v2` 有 `seed`；SFX 无 |
| 格式 | `format: "wav"`（输出 44.1k/16bit **单声道**） | ❌ 无参数，输出格式由模型/库决定（⚠️ 未核实） | `output_format`，默认 `mp3_44100_128`；PCM 44.1k 需 Pro 档（工具描述原文） |
| 负面提示 | ❌ 无 | ✅ `negative_prompt` | ❌ 无 |
| 存盘目录 | `outputDir` | `output_dir` | `output_directory` |
| 文件名 | `filename`（无扩展名） | `filename` | 输出目录 + 自动命名（⚠️ 具体规则未核实） |

**本项目统一目标规格**（与 `_uu/gen_audio.py` 产物一致，便于 A/B 替换）：
- SFX：**单声道 44.1kHz/16bit WAV，峰值 −6 dBFS**，时长严格等于 `data/audio.csv` 对应值（0.07–0.90s）
- ambience `rain_loop`：**单声道 44.1k/16bit，4.000s，首尾无缝**
- BGM：**立体声 44.1k/16bit，24.000s（`bgm_night` 28.000s），峰值 −12 dBFS，首尾无缝**

> 下面 prompt 列**可直接复制**。给 `sfx-gen-mcp` 时建议再加 `negative_prompt: "music, voice, reverb tail, background noise"`；给 `@pixelbananas/mcp` 时在 prompt 前加 `8-bit chiptune SFX:`。给 ElevenLabs 时不需要加风格词。

### 3.2 SFX：27 条 + rain_loop

`data/audio.csv` 里实际是 **31 行 SFX（含 4 条任务单没列的：goat/alpaca/pig/turkey）+ 1 条 ambience + 7 条 BGM**。下表全部覆盖，方便你整表替换。

**短于 0.5s 的条目（`step_*`、`hoe`、`plant`、`shears`、`coin`、`ui_*`、`eat`、`craft`、`build_place`、`animal_*` 中 <0.5s 的）**：`sfx-gen-mcp` / ElevenLabs SFX 的**最短 0.5s**，所以要先生成 0.5s 再裁到目标时长（脚本见 §4.4）。`@pixelbananas/mcp` 时长不可控，只能生成后裁——裁之前先听整条，找能量最集中的 0.1s，别硬切。

| # | id | 目标时长 | prompt（英文，直接复制） | seed | 备注 |
|---|---|---|---|---|---|
| 1 | `step_grass` | 0.12s | `single soft footstep on short grass, light organic crunch, close-mic, dry, no echo` | 2001 | 生成 0.5s → 裁 0.12s，尾部 8ms 淡出 |
| 2 | `step_dirt` | 0.12s | `single footstep on dry dirt path, small gravel crunch, muted low thud, dry` | 2002 | 同上 |
| 3 | `step_wood` | 0.12s | `single footstep on wooden floorboard, hollow wooden knock, indoor, dry` | 2003 | 同上 |
| 4 | `hoe` | 0.28s | `metal hoe striking soil, short dull impact with a soil scrape, no metallic ring` | 2004 | 生成 0.5s → 裁 0.28s |
| 5 | `water` | 0.70s | `watering can pouring water onto soil, gentle splash and trickle, wet and close` | 2005 | 可直接 0.7s |
| 6 | `plant` | 0.30s | `hand patting soil after planting a seed, soft muffled pat and tiny soil rustle` | 2006 | 裁到 0.30s |
| 7 | `milk` | 0.55s | `milking a cow into a metal bucket, three rhythmic squirts with thin metallic pings` | 2007 | 0.55s |
| 8 | `egg` | 0.40s | `hand picking an egg out of straw, soft straw rustle and light ceramic clink` | 2008 | 0.5s→0.40s |
| 9 | `shears` | 0.30s | `sheep shears snipping wool, two sharp metallic snips close together` | 2009 | 裁到 0.30s |
| 10 | `coin` | 0.35s | `retro coin pickup, bright two-note chime, crisp, dry, no reverb` | 2010 | 裁到 0.35s |
| 11 | `ui_open` | 0.18s | `UI panel opening whoosh, soft airy rising swipe, short and dry` | 2011 | 裁到 0.18s |
| 12 | `ui_close` | 0.18s | `UI panel closing whoosh, soft airy descending swipe, short and dry` | 2012 | 裁到 0.18s |
| 13 | `ui_click` | 0.07s | `tiny UI button click, single dry tick, high frequency, no tail` | 2013 | 裁到 0.07s（极短，见 §6 建议） |
| 14 | `animal_cow` | 0.90s | `one cow moo, low and mellow, close, no barn ambience, dry` | 2014 | 0.9s |
| 15 | `animal_sheep` | 0.70s | `one sheep baa, wobbly mid-range bleat, close, dry` | 2015 | 0.7s |
| 16 | `animal_chicken` | 0.45s | `one chicken cluck, short bright squawk, close` | 2016 | 0.5s→0.45s |
| 17 | `animal_duck` | 0.45s | `one duck quack, nasal short quack, close` | 2017 | 0.5s→0.45s |
| 18 | `animal_bee` | 0.40s | `single bee buzzing past the microphone, fast wing drone, short, close` | 2018 | 0.5s→0.40s |
| 19 | `build_place` | 0.35s | `wooden building block placed on the ground, hollow wooden thunk with dirt` | 2019 | 裁到 0.35s |
| 20 | `build_done` | 0.80s | `construction finished, two wooden hammer taps then a warm rising chime` | 2020 | 0.8s |
| 21 | `save` | 0.45s | `save game confirmation, soft digital swish then two bright short notes` | 2021 | 0.5s→0.45s |
| 22 | `eat` | 0.35s | `eating a crunchy vegetable, two quick crunches, close-mic` | 2022 | 裁到 0.35s |
| 23 | `craft` | 0.45s | `crafting at a wooden workbench, wood clacks and one small metal tick` | 2023 | 0.5s→0.45s |
| 24 | `animal_goat` | 0.70s | `one goat bleat, raspy mid-high baa, close, dry` | 2024 | csv 里多出的条目 |
| 25 | `animal_alpaca` | 0.60s | `one alpaca soft humming snort, quiet and gentle, close` | 2025 | csv 里多出的条目 |
| 26 | `animal_pig` | 0.50s | `one pig grunt, short low oink, close, dry` | 2026 | csv 里多出的条目 |
| 27 | `animal_turkey` | 0.60s | `one turkey gobble, short rattling gobble, close` | 2027 | csv 里多出的条目 |
| A | `rain_loop` | 4.000s | `steady medium rain falling on grass and a wooden roof, no thunder, no birds, even level, seamless loop` | 2028 | **必须让生成时头尾等响度**；做不到就后期交叉淡化（§5.3） |

### 3.3 BGM：7 条（24–28s）

先记账：**`@pixelbananas/mcp` 的 BGM 时长 = `bars × 16 × (60 / BPM / 4) + 1.0s`（源码 `render/song.js` 核实）**。按本项目 BPM 代入：

| id | BPM | 目标时长 | `generate_bgm` 用 `bars=8` 实际约 | `bars=16` 实际约 | 能否直接命中 24–28s |
|---|---|---|---|---|---|
| `bgm_morning` | 104 | 24s | **19.5s** | 37.9s | ❌ 8 太短、16 太长 → 只能 8 生成后补/裁 |
| `bgm_day` | 92 | 24s | **21.9s** | 42.7s | ❌ 同上 |
| `bgm_dusk` | 76 | 24s | **26.3s** | 51.5s | ✅ 8 bars 接近（26.3s），再裁到 24s |
| `bgm_night` | 68 | 28s | **29.2s** | 57.2s | ⚠️ 8 bars 略长，裁掉 1.2s |
| `bgm_rain` | 80 | 24s | **25.0s** | 49.0s | ✅ 8 bars 接近 |
| `bgm_snow` | 72 | 24s | **27.7s** | 54.3s | ⚠️ 8 bars 偏长，裁到 24s |
| `bgm_indoor` | 84 | 24s | **23.9s** | 46.9s | ✅ 8 bars 基本命中 |

结论：**pixelbananas 做 BGM 只能算「风格参考」**，而且它是 chiptune 近似渲染、单声道、尾部固定加 1s 静音尾巴，必须裁 + 循环处理。真要 MCP 生成 BGM，**优先用 ElevenLabs `compose_music`**：`music_length_ms` 直接给 24000/28000，`seed` 可复现，`force_instrumental=true` 去人声；但它**不保证无缝循环**，仍要后期裁到整小节 + 交叉淡化。

| id | BPM | 目标 | prompt（直接复制） | ElevenLabs `music_length_ms` | seed | pixelbananas 建议 |
|---|---|---|---|---|---|---|
| `bgm_morning` | 104 | 24s | `cheerful 16-bit farm morning theme, 104 BPM, bright major key, bouncy square lead, gentle bass, light shaker, seamless loop, instrumental, no vocals` | `24000` | 3001 | `bars=8`（≈19.5s，偏短） |
| `bgm_day` | 92 | 24s | `relaxed daytime farm theme, 92 BPM, warm major key, mellow triangle bass, soft arpeggio, laid-back, seamless loop, instrumental` | `24000` | 3002 | `bars=8`（≈21.9s） |
| `bgm_dusk` | 76 | 24s | `calm dusk theme, 76 BPM, gentle minor key, slow melodic lead, warm pads, nostalgic, seamless loop, instrumental` | `24000` | 3003 | `bars=8`（≈26.3s→裁 24s） |
| `bgm_night` | 68 | 28s | `ethereal night theme, 68 BPM, sparse minor key, airy bells, deep soft bass, quiet and mysterious, seamless loop, instrumental` | `28000` | 3004 | `bars=8`（≈29.2s→裁 28s） |
| `bgm_rain` | 80 | 24s | `melancholic rainy day theme, 80 BPM, minor key, soft piano-like lead, rain-noise texture, seamless loop, instrumental` | `24000` | 3005 | `bars=8`（≈25.0s→裁 24s） |
| `bgm_snow` | 72 | 24s | `winter snow theme, 72 BPM, slow minor key, delicate bell melody, cold airy pad, seamless loop, instrumental` | `24000` | 3006 | `bars=8`（≈27.7s→裁 24s） |
| `bgm_indoor` | 84 | 24s | `warm cozy indoor theme, 84 BPM, major key, soft woodwind-like lead, gentle bass, intimate, seamless loop, instrumental` | `24000` | 3007 | `bars=8`（≈23.9s，最接近） |

> `bgm_night` 用 28s、其余 24s 是**沿用现有 `_uu/gen_audio.py` 的实测产物**（✅ 本机校验：6 首 24.000s + `bgm_night` 28.000s），这样替换时不用改 `data/audio.csv`/测试。

### 3.4 参数模板（复制后只改 prompt / filename）

**A. `@pixelbananas/mcp` → `generate_sfx`**
```json
{
  "prompt": "8-bit chiptune SFX: single soft footstep on short grass, light organic crunch, dry",
  "effort": 1,
  "format": "wav",
  "outputDir": "D:/UU的办公室/小牧场日记/audio/sfx",
  "filename": "step_grass"
}
```
预算提醒：27 条 SFX × 1 credit = 27 credits > 免费 20/月；BGM 一条 5 credits 起。**免费档只够做 10–15 条 SFX 的试听样本**，全量必须付费。

**B. `@pixelbananas/mcp` → `generate_bgm`**
```json
{
  "prompt": "cheerful chiptune farm morning theme, 104 BPM, bright major, bouncy lead, seamless loop",
  "bars": 8,
  "effort": 1,
  "format": "wav",
  "outputDir": "D:/UU的办公室/小牧场日记/audio/bgm",
  "filename": "bgm_morning",
  "includeMidi": false
}
```

**C. `sfx-gen-mcp` → `generate_sfx`**
```json
{
  "prompt": "single soft footstep on short grass, light organic crunch, close-mic, dry",
  "duration_seconds": 0.5,
  "seed": 2001,
  "negative_prompt": "music, voice, reverb tail, background noise",
  "variations": 2,
  "output_dir": "D:/UU的办公室/小牧场日记/audio/sfx",
  "filename": "step_grass"
}
```
`steps`/`cfg_scale` 的合法范围 README 没写（⚠️ 未核实），先不传用默认；要调就从默认值上下浮动试。

**D. `elevenlabs-mcp` → `text_to_sound_effects`**
```json
{
  "text": "single soft footstep on short grass, light organic crunch, close-mic, dry",
  "duration_seconds": 0.5,
  "loop": false,
  "output_format": "pcm_44100",
  "output_directory": "D:/UU的办公室/小牧场日记/audio/sfx"
}
```
注意 `pcm_44100` 按工具描述需要 Pro 档以上（⚠️ 以账号实际权限为准）；免费档先用默认 `mp3_44100_128` 试听，最终素材再用 44.1k PCM 重生成。

**E. `elevenlabs-mcp` → `compose_music`**
```json
{
  "prompt": "cheerful 16-bit farm morning theme, 104 BPM, major key, square lead, light shaker, instrumental, seamless loop",
  "music_length_ms": 24000,
  "model_id": "music_v2",
  "force_instrumental": true,
  "seed": 3001,
  "output_directory": "D:/UU的办公室/小牧场日记/audio/bgm"
}
```

---

## 4. 批量生成工作流

### 4.1 命名与落盘（硬约定）

| 类型 | 落盘位置 | 文件名 | 来源 |
|---|---|---|---|
| SFX | `audio/sfx/` | `<id>.wav` | `data/audio.csv` 的 `id` 列 + `res://audio/sfx/...` |
| ambience | `audio/sfx/` | `rain_loop.wav` | 同上（`kind=ambience` 但路径在 sfx 下） |
| BGM | `audio/bgm/` | `<id>.wav` | `res://audio/bgm/...` |

- 一律**小写 + 下划线 + `.wav`**，不要中文、不要空格、不要 `-2` 后缀（MCP 自动加 `-2` 时手动改回 `<id>`）。
- **`assets/audio` 是错的**：`_uu/mcp-config.json` 里 `PIXELBANANAS_OUTPUT_DIR` 现在指向那里，但 `data/audio.csv` 用的是 `res://audio/...`（即项目根 `audio/`）。改成 `D:/UU的办公室/小牧场日记/audio/sfx`，BGM 调用时用 `outputDir` 单独指到 `audio/bgm`。
- 生成前先备份现有底稿：`Copy-Item -Recurse audio audio_baseline_gen_audio`（大小约 30MB，值得留）。
- **放进去后 Godot 必须重新 import**（见 §4.5），否则 `ResourceLoader.exists()` 还是 false，`AudioDef.is_available()` 会判缺失。

### 4.2 清单文件

建议把「id / 目标时长 / prompt / seed」写进 `_uu/audio-manifest.json`（示例，按 §3 表补全）：

```json
{
  "sfx": [
    {"id": "step_grass", "seconds": 0.12, "seed": 2001, "prompt": "single soft footstep on short grass, light organic crunch, close-mic, dry"},
    {"id": "step_dirt",  "seconds": 0.12, "seed": 2002, "prompt": "single footstep on dry dirt path, small gravel crunch, muted low thud, dry"},
    {"id": "coin",       "seconds": 0.35, "seed": 2010, "prompt": "retro coin pickup, bright two-note chime, crisp, dry, no reverb"}
  ],
  "bgm": [
    {"id": "bgm_morning", "seconds": 24.0, "seed": 3001, "bpm": 104, "prompt": "cheerful 16-bit farm morning theme, 104 BPM, bright major, bouncy lead, seamless loop"}
  ]
}
```

### 4.3 批量循环写法（一次 5–10 条）

**方案 A：命令行循环（适合 `@pixelbananas/mcp`，用仓库现成 `_uu/mcp_call.py`）**

```powershell
cd "D:\UU的办公室\小牧场日记"
$env:PIXELBANANAS_TOKEN = "pba_live_REPLACE_ME"   # 只在本会话生效，不写进文件
$root = "D:/UU的办公室/小牧场日记"
$manifest = Get-Content "$root/_uu/audio-manifest.json" -Raw | ConvertFrom-Json

# 只做前 6 条试听：限速 5 次/分钟 → 每次 sleep 13s
$batch = $manifest.sfx | Select-Object -First 6
foreach ($it in $batch) {
  $arg = @{
    prompt    = "8-bit chiptune SFX: " + $it.prompt
    effort    = 1
    format    = "wav"
    outputDir = "$root/audio/sfx"
    filename  = $it.id
  } | ConvertTo-Json -Compress -Depth 4
  Write-Host ">>> $($it.id)"
  python "$root/_uu/mcp_call.py" `
    "C:\Users\32265\AppData\Local\Programs\nodejs\npx.cmd" -y "@pixelbananas/mcp@0.2.0" `
    "@@" generate_sfx $arg
  Start-Sleep -Seconds 13
}
```
- 每调用一次起一个 server 进程（`mcp_call.py` 的设计），对 API 型 server 无所谓；
- `mcp_call.py` 会把结果 JSON 落盘到 `%TEMP%\uu_mcp\`，并继承当前 PowerShell 的环境变量（token/代理）；
- 想跑 BGM：把 `generate_sfx` 换成 `generate_bgm`，参数换成 §3.4-B，`sleep` 改 21s（3 次/分钟）。

**方案 B：让 MCP 客户端里的 agent 循环（适合 `sfx-gen-mcp`，避免反复加载 10GB 模型）**

在客户端里贴这段（一次 5–10 条，agent 会自己逐条调用）：
```
用 sfx-gen-mcp 的 generate_sfx 逐条生成以下音效，一条生成完再下一条：
1) step_grass, duration_seconds=0.5, seed=2001, prompt="single soft footstep on short grass..."
2) step_dirt,  duration_seconds=0.5, seed=2002, ...
...
所有文件 output_dir="D:/UU的办公室/小牧场日记/audio/sfx"、filename 用 id、negative_prompt 用
"music, voice, reverb tail, background noise"、variations=1（先各来一条试听）。
每生成完一条把 "实际时长 / seed / 是否成功" 列成表，失败不要重试超过 1 次，直接报告。
```
更省显存的做法：先起 `sfx-gen-mcp --transport http --port 8756` 常驻 daemon，再让 agent 通过它批量调；否则 stdio 模式下每次连接都会重新加载模型（20–40s/次）。

**方案 C：`elevenlabs-mcp` 批量**——同方案 B，把工具名换成 `text_to_sound_effects` / `compose_music`，`duration_seconds` 或 `music_length_ms` 直接给目标值，不需要裁时长（SFX 下限 0.5s 仍需裁）。

### 4.4 后处理：裁时长 / 转单声道 / 归一化

本机**没有 ffmpeg / ffprobe / sox（✅ 实测 `Get-Command` 均 NOT FOUND）**，先别写依赖它们的脚本。两个选择：

**(a) 装 ffmpeg（推荐，一条命令）**
```powershell
winget install --id Gyan.FFmpeg -e
# 之后：裁到 0.12s + 单声道 + 峰值 -6dBFS
ffmpeg -y -i in.wav -t 0.12 -ac 1 -ar 44100 -af "afade=t=out:st=0.112:d=0.008,volume=0dB" -sample_fmt s16 out.wav
```
**(b) 纯 Python 标准库脚本（不装任何东西，保存为 `_uu/fit_wav.py` 备用；不要放进 `scripts/`）**

```python
# 用法: python _uu/fit_wav.py in.wav out.wav 0.12 [--mono] [--peak -6]
import sys, wave, struct, math, array

def main():
    src, dst, seconds = sys.argv[1], sys.argv[2], float(sys.argv[3])
    mono = "--mono" in sys.argv
    peak_db = -6.0
    if "--peak" in sys.argv:
        peak_db = float(sys.argv[sys.argv.index("--peak") + 1])
    with wave.open(src, "rb") as w:
        ch, sr, width, n = w.getnchannels(), w.getframerate(), w.getsampwidth(), w.getnframes()
        raw = w.readframes(n)
    if width != 2:
        sys.exit("只处理 16-bit wav（当前 %d bit）" % (width * 8))
    if sr != 44100:
        sys.exit("采样率 %d != 44100，需要 ffmpeg/sox 重采样，别硬改" % sr)
    s = list(struct.unpack("<%dh" % (len(raw) // 2), raw))
    if ch == 2:
        s = [(s[i] + s[i + 1]) // 2 for i in range(0, len(s), 2)]
    elif ch != 1:
        sys.exit("只支持 1/2 声道")
    want = max(1, int(round(seconds * sr)))
    s = s[:want] + [0] * max(0, want - len(s))
    fade = max(1, int(0.005 * sr))            # 头尾各 5ms 淡入淡出，防爆音
    for i in range(min(fade, len(s))):
        g = i / fade
        s[i] = int(s[i] * g)
        s[-1 - i] = int(s[-1 - i] * g)
    pk = max(1, max(abs(x) for x in s))
    target = int(32767 * (10.0 ** (peak_db / 20.0)))
    s = [max(-32768, min(32767, int(x * target / pk))) for x in s]
    with wave.open(dst, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes(struct.pack("<%dh" % len(s), *s))
    print("OK", dst, "%.3fs" % (len(s) / sr), "peak %.1fdB" % peak_db)

main()
```
> 注意：这是**裁剪/降混/归一化**用的，不做重采样。源文件必须是 44.1k；`@pixelbananas/mcp` 输出已经是 44.1k 单声道（✅ 源码核实），能直接用；`sfx-gen-mcp` / ElevenLabs 的输出采样率要先确认（用 §5.2 的检查脚本读头）。

### 4.5 Godot 重新 import

```powershell
$godot = "C:\Users\32265\.godot-mcp\godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --import --path "D:\UU的办公室\小牧场日记"
# 检查：每个 wav 旁边应出现 .import 文件
Get-ChildItem "audio\sfx","audio\bgm" -Filter *.wav.import | Measure-Object   # 期望 35
```
- 若 `--import` 报错或新文件没进项目，**用编辑器打开一次项目**（`& $godot --path ...`）让它扫一遍，比命令行稳。
- **循环设置**：Godot 4 的 WAV 导入默认不循环。给 `rain_loop` 和 7 首 BGM 两种做法：
  1. Import 面板 → `Loop Mode = Forward`（写进 `.import` 的 `edit/loop_mode=1`）；
  2. 或运行时给 `AudioStreamWAV.loop_mode = AudioStreamWAV.LOOP_FORWARD`。
  `data/audio.csv` 已经有 `loop` 列，若 `AudioManager` 按该列设置 `loop_mode`，则 `.import` 保持默认即可——**以实现为准，替换后一定试听循环点**。
- 改完素材后**必须重新跑一次 import**，否则运行的是旧缓存（`.godot/imported/` 里的旧文件）。

---

## 5. 验收清单

### 5.1 硬指标（与现有底稿对齐）

| 项 | 标准 | 检测方法 |
|---|---|---|
| 时长 | SFX = `data/audio.csv` 对应目标值（±10ms）；`rain_loop`=4.000s；BGM 24.000s（`bgm_night` 28.000s） | §5.2 脚本 / ffprobe |
| 采样率/位深 | 44100 Hz / 16-bit | 读 WAV 头 |
| 声道 | SFX 单声道；BGM 立体声（MCP 生成的 BGM 多为单声道，可接受但不加立体声处理也可） | 读 WAV 头 |
| 峰值 | SFX −6 dBFS；`rain_loop` −9 dBFS；BGM −12 dBFS（允许 ±2dB，绝对不许 ≥ −0.5 dBFS 削波） | 峰值计算 |
| 循环 | `rain_loop` / BGM 首尾接缝无「咔哒」、无音量跳变；BGM 循环点落在整小节 | §5.3 |
| 命名 | 小写+下划线+`.wav`，与 `data/audio.csv` 的 `id` 完全一致，无 `-2`/`(1)` 后缀 | §5.2 对表脚本 |
| 导入 | 每个 wav 有对应 `.import`；Godot 里 `ResourceLoader.exists("res://audio/...")` 为 true | §4.5 + 运行日志 |
| 授权 | 用于分发的版本必须确认生成物的商用条款（见 §1.3） | 人工 |

### 5.2 一键自检脚本（纯标准库，保存为 `_uu/check_audio.py`）

```python
# 用法: python _uu/check_audio.py
import os, csv, wave, struct, math
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def info(p):
    with wave.open(p, "rb") as w:
        ch, sr, width, n = w.getnchannels(), w.getframerate(), w.getsampwidth(), w.getnframes()
        data = w.readframes(n)
    vals = struct.unpack("<%dh" % (len(data) // 2), data) if data else (0,)
    peak = max(abs(v) for v in vals) / 32768.0
    return ch, sr, width * 8, n / sr, (20 * math.log10(peak) if peak else -999)

rows = list(csv.DictReader(open(os.path.join(ROOT, "data", "audio.csv"), encoding="utf-8")))
bad = 0
for r in rows:
    rel = r["file"].replace("res://", "").replace("/", os.sep)
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        print("[缺文件]", r["id"], p); bad += 1; continue
    ch, sr, bits, dur, peak = info(p)
    print("%-16s %5.3fs ch=%d sr=%d %2dbit peak=%6.1fdB" % (r["id"], dur, ch, sr, bits, peak))
    if sr != 44100 or bits != 16:
        print("   [格式不对]", r["id"]); bad += 1
    if peak > -0.5:
        print("   [削波风险]", r["id"]); bad += 1
print("缺失/不合格:", bad)
```

### 5.3 「循环无缝」到底怎么验

1. **看接缝样本**：首尾样本差应接近 0（绝对值 ≤ 满量程 0.5%，即 ≤ 164）；更稳的是比较**尾部最后 100 个样本的 RMS** 和**头部前 100 个样本的 RMS**，两者差不应超过 3 倍。现有底稿实测：`bgm_rain` 首= −253 / 尾= −242（跳变 11），`bgm_dusk` 跳变 55，都在安全范围；`bgm_morning`/`bgm_day` 尾部 2.3ms 淡到 0，属于可接受的收尾。
2. **听**：在 Godot 里用循环播放的 `AudioStreamPlayer` 连听 20 遍，重点听「每圈接缝」是否有咔哒/呼吸感。
3. **AI 生成的循环**（尤其 ElevenLabs 音乐、pixelbananas 带 1s 尾巴的 BGM）**基本不可能天然无缝**，标准做法：裁掉尾部静音 → 找到第一小节长度 → 在 Audacity 里做 20–50ms 交叉淡化，或直接回头用 `gen_audio.py` 的环形缓冲版本（它的循环是按整样本周期算出来的，数学上无缝）。

### 5.4 在 Godot 里试听

- **编辑器内**：FileSystem 面板点 `audio/sfx/coin.wav`，Inspector 里点播放（左下 Audio 面板）即可，不用跑游戏。
- **最小试听场景**（一次换一个文件，听感 A/B）：

```gdscript
extends Node
# 挂到任意空场景的根节点；改 PATH 反复运行 F6 即可对比
const PATH := "res://audio/sfx/coin.wav"

func _ready() -> void:
    var p := AudioStreamPlayer.new()
    p.stream = load(PATH)
    add_child(p)
    p.play()

    # BGM 循环试听：把 PATH 换成 bgm，并在 Import 面板开 Loop Mode=Forward
    # p.finished.connect(p.play)  # 若未开循环，用它手动循环
```
- **比听感更可靠的量**：同一命名文件替换前后跑 §5.2 脚本，看时长/峰值是否保持；`data/audio.csv` 的 `volume`（0.35–0.70）是按现有底稿调过的，**换了素材要重调音量**（MCP 生成物响度差异很大）。

---

## 6. 回退方案（MCP 全都不可用时）

### 6.1 现状：项目已有底稿，且是精确规格

`_uu/gen_audio.py` **已经存在并已跑出全套素材**（✅ 本机 2026-10-18 实测）：

- 脚本 1353 行、纯标准库 + **numpy**，不联网、不调用 ffmpeg；
- 跑一次**覆盖重写**全部输出（随机种子固定，重复运行字节一致）：
  ```
  python _uu/gen_audio.py
  ```
- 产物（✅ 已逐个读 WAV 头验证）：
  - `audio/sfx/*.wav`：27 条 SFX + `rain_loop`，**单声道 44100Hz 16-bit**，峰值 **−6 dBFS**（`rain_loop` −9），时长与 `data/audio.csv` 完全一致（`ui_click` 0.070s … `animal_cow` 0.900s）；
  - `audio/bgm/*.wav`：7 首，**立体声 44100Hz 16-bit**，**24.000s ×6 + `bgm_night` 28.000s**，峰值 **−12 dBFS**，环形缓冲合成 → 首尾天然无缝。
- **一个现成的坑（✅ 实测）**：本机默认 `python` 是 3.14，**没有 numpy**，直接跑会
  `ModuleNotFoundError: No module named 'numpy'`。先 `python -m pip install numpy`（或
  `python -m pip install numpy -i https://pypi.tuna.tsinghua.edu.cn/simple`），或用装了 numpy 的解释器。
- 脚本没有命令行参数（`--help` 也会先撞 numpy 导入），**只能整批生成**；要单条重生成就改脚本里的 `SFX_SPEC` 再跑（会覆盖全部文件，建议先备份）。

### 6.2 「先用它兜底，再用 MCP 逐条替换」的具体做法

1. **固定底稿**：`Copy-Item -Recurse audio audio_baseline_gen_audio`（或 git commit 一次）。后面任何 MCP 产物不合格，直接从备份拷回。
2. **先验收底稿**：跑 §5.2 脚本 + 进 Godot 听 3 条（`coin`、`step_grass`、`bgm_morning`），确认「可玩版本」成立。**这一步过了，MCP 就只是优化，不是风险。**
3. **按优先级替换**（建议顺序，收益从高到低）：
   - ① `animal_cow/sheep/chicken/duck`：动物叫是程序合成最不像的；
   - ② `milk`、`water`、`hoe`：需要物理质感；
   - ③ `coin`、`ui_*`、`save`：短促反馈，AI 反而不一定比 chiptune 好；
   - BGM **最后动**，且只在 ElevenLabs 精确长度那一档试。
4. **一次只换 1–3 条**，文件名不变 → 不用改 `data/audio.csv` → 不用改代码 → 直接 F6 试听。
5. **不合格就回退**：`Copy-Item audio_baseline_gen_audio\sfx\coin.wav audio\sfx\coin.wav`，重新 import。
6. **留记录**：在本文末尾或 issue 里记「id / 工具 / seed / 结论（采用/弃用）」，否则两个月后没人知道哪条是 AI 的。

### 6.3 其它免费兜底

| 场景 | 兜底 |
|---|---|
| 完全没网、没 key、包也下架 | `gen_audio.py`（已验证可用；只缺 numpy） |
| 雨声等环境音不够真 | Freesound（CC0）手动下载，或 `@mushan_bit/freesound-mcp` 搜/下（⚠️ 该包能否直接 npx 运行未实测） |
| 只想改几条 chiptune 短音效 | `jsfxr`（npm 库）或 BFXR 离线工具，导出 44.1k/16bit |
| 想用 AI 但不想本地跑模型 | ElevenLabs 免费档（10k credits/月，需署名，⚠️ 以条款为准）或 PixelBananas 付费 credits |

---

## 7. 参考链接

**本次调研核实的入口**
- npm 包页：[@pixelbananas/mcp](https://www.npmjs.com/package/@pixelbananas/mcp)
- npm registry 元数据（版本/依赖/许可）：[registry.npmjs.org/@pixelbananas/mcp](https://registry.npmjs.org/@pixelbananas%2Fmcp)
- PixelBananas 站点：[pixelbananas.pages.dev](https://pixelbananas.pages.dev)
- sfx-gen-mcp 仓库：[github.com/JimCline/sfx-gen-mcp](https://github.com/JimCline/sfx-gen-mcp)
- sfx-gen-mcp 在 Glama 的目录页（配置/环境变量）：[glama.ai/mcp/servers/JimCline/sfx-gen-mcp](https://glama.ai/mcp/servers/JimCline/sfx-gen-mcp)
- Stable Audio Open 模型与许可：[huggingface.co/stabilityai/stable-audio-open-1.0](https://huggingface.co/stabilityai/stable-audio-open-1.0)
- `sfx-gen-mcp` 确认「npm 无此包」：[registry.npmjs.org/sfx-gen-mcp（404）](https://registry.npmjs.org/sfx-gen-mcp)；PyPI 同样 404：[pypi.org/pypi/sfx-gen-mcp/json](https://pypi.org/pypi/sfx-gen-mcp/json)

**替代方案**
- ElevenLabs 官方 MCP（PyPI）：[pypi.org/project/elevenlabs-mcp](https://pypi.org/project/elevenlabs-mcp/)
- ElevenLabs MCP 的 27 个工具与参数（含 `text_to_sound_effects` / `compose_music`）：[glama.ai/mcp/servers/elevenlabs/elevenlabs-mcp/schema](https://glama.ai/mcp/servers/elevenlabs/elevenlabs-mcp/schema)
- ElevenLabs 仓库：[github.com/elevenlabs/elevenlabs-mcp](https://github.com/elevenlabs/elevenlabs-mcp)
- Freesound MCP（npm）：[@mushan_bit/freesound-mcp](https://www.npmjs.com/package/@mushan_bit/freesound-mcp)
- Freesound API 文档（key 申请）：[freesound.org/docs/api](https://freesound.org/docs/api/)
- jsfxr（8-bit 音效合成库）：[npmjs.com/package/jsfxr](https://www.npmjs.com/package/jsfxr)

**工具与文档**
- MCP 协议：[modelcontextprotocol.io](https://modelcontextprotocol.io)
- Godot 4 音频导入：[Importing audio samples](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_audio_samples.html)
- Godot `AudioStreamWAV`（loop_mode 枚举）：[AudioStreamWAV 文档](https://docs.godotengine.org/en/stable/classes/class_audiostreamwav.html)
- ffmpeg 音频滤镜（`afade` / `volume` / `volumedetect`）：[ffmpeg-filters 文档](https://ffmpeg.org/ffmpeg-filters.html)

**仓库内相关文件（只读，不在本文修改）**
- `_uu/mcp-config.json` —— 现有 MCP 配置（含 pixelbananas 占位）
- `_uu/mcp-import.json` —— 可粘贴版配置（绝对路径）
- `_uu/mcp_probe.py` / `_uu/mcp_schema.py` / `_uu/mcp_call.py` —— 握手、导 schema、调工具的三个现成小工具
- `_uu/gen_audio.py` —— 程序化合成底稿（27 SFX + rain_loop + 7 BGM）
- `data/audio.csv` —— 音频契约表（id / 路径 / 音量 / 循环）
- `scripts/audio/audio_def.gd`、`sfx_pool.gd`、`bgm_director.gd` —— 音频元数据与选曲逻辑
