# Lian 1.9.12 交接备忘录

> 交接时间：2026-11-21
> 当前版本：**1.9.12**（网页 / PWA / **APK 已重新打包**，versionCode **18**）
> 工作目录：`D:\UU的办公室`　应用目录：`D:\UU的办公室\lian-chat`
> 上一版：`Lian-1.9.11-交接备忘录.md`（八种版式 + 三套页面重做 + 输入栏工具盘）

---

## 0. 一句话状态

工具盘的表情从「一排 24 个平铺」改成 **「最近 + 五组」**：点过的自动进「最近」并按使用时间倒序，
最多 12 个；分组是 笑脸 / 撒娇 / 心意 / 手势 / 日常，共 36 个。顺手做了一轮 bug 排查，
修了 **1 个真 bug**（demo 模式会把示例状态写进真实存储）、**2 个体验问题**、**2 个测试护栏问题**。

单测 111 → **118**，模块审计 19 个 0/0，页面上跑出 **0 报错**。
新增两个脚本：`tray-check.mjs`（21 项）与 `audit-check.mjs`（**254 项**，是这轮排查的主力）。

---

## 1. 这一版加了什么

### 1.1 表情分组

| 分组 | 内容 | 数量 |
|---|---|---|
| 最近 | 用过的表情，按最后一次使用时间倒序 | ≤ 12 |
| 笑脸 | 😊 😂 🥰 😌 😴 🙂 😉 🥹 | 8 |
| 撒娇 | 🥺 😭 😳 😤 🙃 😢 | 6 |
| 心意 | ❤️ 🫶 💕 💗 💌 🌸 | 6 |
| 手势 | 👍 🙌 👏 ✌️ 🤝 👉 | 6 |
| 日常 | ☕ 🍰 🌙 ✨ 💤 🎉 🐱 🌱 💬 🫧 | 10 |

- 分组定义在 `js/config.js` 的 `EMOJI_GROUPS`，`EMOJIS` 仍然是它们的并集（表情面板的九宫格继续用它，
  所以面板里也从 24 个变成 36 个）。
- 工具盘多了一排小胶囊 `#trayEmojiHead` 切组，选中态用强调色；切组只换下面那排，**工具盘不收起**。
- 没点过任何表情时「最近」这一格**不出现**，点第一个之后才长出来并自动排在最前。
- 使用记录存 `state.emojiUsage = [{ e, n, at }]`，`store.js` 负责清洗：去重、按 `at` 倒序、截 12 条、
  `n` 限 1–999、脏条目（不是对象、没有 `e`、`null`）直接丢。
- 英文界面下分组显示 Faces / Soft / Hearts / Hands / Daily（`emojiGroupLabel()`，跟 `themeLabel()` 一样的写法）。

### 1.2 顺带修的

| # | 问题 | 修法 |
|---|---|---|
| 1 | 记录表情使用原本直接 `scheduleSave(state)`，**绕过了 demo 模式的保护**——在 demo 里点一下表情，示例状态就会写进 IndexedDB，下次打开看到的是示例聊天 | 改走 `persist()`（它会 `if (demoMode) return`）；单测断言这段代码里**不许再出现 `scheduleSave`** |
| 2 | 从聊天里打开设置时工具盘不收，从设置返回后还张着 | `openSettings()` 开头 `setComposerTray(false)` |
| 3 | `#trayEmoji` 标了 `role="listbox"`，里面却是一排普通 `button`，角色不匹配（读屏会念错） | 改成 `role="group"`，分组条补 `aria-label`（`composer.emojiGroups` / `chat.emoji`） |
| 4 | `scripts/sticker-check.mjs` 把表情面板数量写死 24，表情一多就误报 | 改成长度下限 24 + 每个格子必须有 `data-emoji` |
| 5 | `sw.js` 里 `15-themes.css` 那行少了缩进 | 对齐 |

---

## 2. 这轮 bug 排查做了什么

### 2.1 `scripts/audit-check.mjs`（254 项）

| 阶段 | 查什么 |
|---|---|
| A. 8 种版式 | 每种都开工具盘，量：是否出屏、是否挡住输入框、盘高 ≤ 屏高 45%、表情按钮 ≥ 32px、分组胶囊 ≥ 20px、分组数 = 5 |
| B. 15 套主题 | 气泡文字的**实际对比度**（用 `getComputedStyle` 取色算 WCAG），AI 气泡最低 15.2，自己的最低 4.5 |
| C. 三个页面 | 列表 / 主页 / 通讯录：横向溢出、重复 id、< 24px 的点击区、控制台报错 |
| D. 零聊天 + 全新安装 | 确认 onboarded 后不会出现空列表（`ensureChatState()` 会补一个聊天）；全新安装落在设置引导页而不是白屏 |
| E. 损坏状态 | 消息缺 `text`、`text: null`、缺 sticker、image 没有 `dataUrl`、未知 `kind`、没有 `role`、`null` 条目、4000 字长消息——一条都不白屏，坏的丢掉、其余照常渲染 |
| F. 两种屏幕 | 320×568 与 430×932：工具盘仍不出屏、输入框仍可见、胶囊和表情仍可点 |

### 2.2 `scripts/tray-check.mjs`（21 项）

分组切换、点表情插入、工具盘保持张开、最近排序（新的在前 / 重复用跳最前 / 无重复）、
刷新后「最近」还在、草稿没丢、切 tab 收起、设置返回、英文分组名。

### 2.3 结论

- 8 种版式的工具盘都不出屏，最紧的是 320×568 的泡泡版，输入框仍完整可见；
- 15 套主题里对比度最低的是浅色主题下「自己的气泡」（4.5，刚好过 AA 小字线），没有低到看不清的；
- 损坏的消息状态只会少渲染，不会白屏——这条以前没专门测过，现在有回归了；
- 排序里两次「误报」记一下，免得下次又怀疑自己：零聊天时列表是空的**不是 bug**（会补一个聊天），
  `#boot` 引导层淡出后是 `remove()` 的，等 `.is-done` 不如等「元素不见了」。

---

## 3. 验证

| 项 | 命令 | 结果 |
|---|---|---|
| 单测 | `node --test tests/*.test.js` | **118 / 118** |
| 模块审计 | `node scripts/check-modules.mjs` | 19 模块 **0 error / 0 warning** |
| 工具盘 | `node scripts/tray-check.mjs` | **21 / 21** |
| 全量体检 | `node scripts/audit-check.mjs` | **254 / 254** |
| 启动 | `node scripts/boot-check.mjs` | 全过（含亮/暗、报错分支） |
| 交互 | `node scripts/ux-check.mjs` | **14 / 14** |
| 表情包 | `node scripts/sticker-check.mjs` | **20 / 20** |
| 画面 | `node scripts/drawing-check.mjs` | **14 / 14** |
| 重来 | `node scripts/regen-check.mjs` | **10 / 10** |
| 截图 | `node scripts/theme-gallery.mjs screens` | 8 张页面图，控制台 **0 报错** |

新截图：`docs/tray-grid.png`（三格对比）、`docs/test-1.9.12-tray.png`（最近组）、
`docs/test-1.9.12-audit.png`、`docs/test-1.9.12-boot.png`，另外 `docs/screen-composer*.png` 已重拍。

---

## 4. APK

| 项 | 值 |
|---|---|
| 文件 | `Lian-1.9.12.apk`（仓库根目录，约 1.39 MB） |
| 包名 / 版本 | `com.lian.chat` · versionName **1.9.12** · versionCode **18** |
| minSdk / targetSdk | 24 / 34 |
| 签名 | 同一个 `lian-release.jks`（SHA-256 `78c2b53b…0f0b18`），可直接覆盖安装 1.9.10/1.9.11 |
| 打包 | `robocopy` 同步 `lian-chat` → `D:\lianbuild\app\assets\www`（排除 `scripts` `tests` `docs` `*.md` `*.bat`），
再跑 `powershell -ExecutionPolicy Bypass -File D:\lianbuild\build.ps1` |

> 踩坑记录：第一次同步把仓库根目录的 `start-Lian.bat` / `启动-Lian.bat` 一起塞进了 `assets/www`，
> `aapt2 link` 直接报 `failed to open file`（中文文件名）。同步时已经排除 `*.bat` / `.gitignore` / `package.json`。

改版本号一共 8 处：`package.json`、`sw.js VERSION`、`app.js` 主页脚注、`settings.js` 令牌行、
`AndroidManifest.xml`、`build.ps1`（versionCode / versionName / 输出名 / Get-Item）、
`ProactiveWorker.java` 的 UA、`scripts/boot-check.mjs` 的截图名。

---

## 5. 还没做的（按优先级）

1. **真机验证**：版式、工具盘、状态栏、流式回复都只在 headless Edge（390×844）上验过，没在手机上滑过。
2. **工具盘在横屏 / 小键盘弹出时的高度**：只测了 320×568 与 430×932 两种竖屏。
3. **「常用」排序**：现在「最近」只按时间，`n`（次数）存了但没用；可以再给一个「最常用」的排序或置顶。
4. **语音 / 按住说话**：仍然没做——没有真实录音链路，不想放假按钮。
5. **深色令牌**：15 套主题里只有 `paper` 有真正的深色版，其余在系统深色模式下只是压暗。
6. 首页「今日一问」目前 8 道题固定轮换，可以扩题库或按聊天关系挑题。
