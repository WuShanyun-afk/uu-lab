# Lian 1.9.13 交接备忘录

> 交接时间：2026-11-21
> 当前版本：**1.9.13**（网页 / PWA / **APK 已重新打包**，versionCode **19**）
> 工作目录：`D:\UU的办公室`　应用目录：`D:\UU的办公室\lian-chat`
> 上一版：`Lian-1.9.12-交接备忘录.md`（工具盘分组 + 最近使用）

---

## 0. 一句话状态

真机上发现的两处「源码漏进界面」都修了，根因是同一类：**模型回复被截断后，兜底逻辑把原始文本当正文显示**。
一个在聊天里（半张 SVG 的源码），一个在日常报备里（没写完的 JSON）。
单测 118 → **129**，新增 `scripts/leak-check.mjs`（13 项，同源 mock 端点跑真实链路），其余检查全绿。

---

## 1. 截图里的两个问题

### 1.1 聊天气泡里出现 ```svg + `<svg …>`

手机截图：Cat 说完「在睡觉。拍糊了。」，下一个气泡整段是 SVG 源码。

三个原因叠在一起：

1. **回复额度不够**：聊天请求 `maxTokens` 是 **720**。带渐变和 path 的 SVG 轻松上千 token，请求在 `<svg>` 中间被截断；
   而且流式请求失败时 `api.js` 会把半截内容当 `finish: "partial"` **正常返回**，App 并不知道这条是残缺的；
2. **只认「有头有尾」的围栏**：`extractDrawings()` 的正则要求 ` ```svg … ``` ` 成对，并且内容必须以 `</svg>` 结尾；
   少一个反引号 → 整段留在文字里；
3. **被切成第二个气泡**：`splitSegments()` 按空行分段，源码成了第二段，转义后原样显示。

修法（`js/drawing.js` / `js/prompt.js` / `js/app.js`）：

- 画面开关打开时，聊天 `maxTokens` **720 → 2000**；
- 新增「没闭合围栏」匹配：` ```svg ` 之后直到结尾都算这张画，抽不出来就**整段删掉**并计入 `broken`；
- `</svg>` 后面再跟注释 / 说明也能认（按**最后一个** `</svg>` 截断，`svgTail()`）；
- 抽不出来的画**永不显示源码**；如果整条回复只有这张坏图，就补一句「（这张没画完，等下再画给你）」（`chat.drawingBroken`）；
- 画面开关**关着**时不动代码内容，只去掉 ``` 围栏行——用户可能就是要看代码。

### 1.2 日常报备里出现 `{"title":"凌晨一点的日常","summary":"改代码…`

手机截图：报备页正文是半截 JSON，下面一大片空白。

三个原因：

1. **额度不够**：报备 `maxTokens` 是 **1400**，5 段 blocks + 场景 id 很容易顶满，JSON 在 `"summary"` 中间断掉；
2. **兜底把原文当 HTML**：`parseJsonReply()` 失败后 `generateReport()` 走
   `buildReportFromRaw({ html: result.content })`，而 `sanitizeReportHtml()` 会把 JSON 当**普通文本**保留；
3. **viewer 直接照搬**：`openReportViewer()` 用这段「html」当正文，于是源码上屏、下面没有段落，只剩空白。

修法（`js/report.js` / `js/prompt.js` / `js/app.js`）：

- 报备 `maxTokens` **1400 → 2400**；
- `parseJsonReply()` 增加**截断修复** `repairJson()`：补全没闭合的字符串和括号、丢掉没写完的键；
- 新增 `salvageReport()`：从坏 JSON 里按字段抠 `title` / `summary` / `blocks`（含最后一段没写完的），
  抠不到任何字段就把纯文本按段落排；如果整段是 JSON 但一个字段都读不出，**返回空**让页面走干净兜底；
- `buildReportFromRaw()` 明确**拒绝把 JSON 当 html**（先判断、再进 DOMParser）；
- 报备页把 **title + summary 显示在正文上方**（以前只渲染 blocks，标题只出现在聊天卡片里）。

> 空白本身不是 bug：短报备放在整屏弹层里就会留白。现在标题、摘要、正文都在，视觉上不再是「一句话 + 一大片空白」。

---

## 2. 新增的回归脚本 `scripts/leak-check.mjs`（13 项）

同源 mock 端点（`/mock/v1/chat/completions`），走**真实** fetch → 流式 → 解析 → 渲染，不碰真模型：

| 用例 | 断言 |
|---|---|
| 回复被截断在 `<svg>` 中间 | 气泡只剩「在睡觉。拍糊了。」，不含 `<svg` / ```，不渲染半张图，不弹错误条 |
| 整条回复只有坏图 | 出现「（这张没画完，等下再画给你）」 |
| 完整 SVG | 仍然渲染成 `data:image/svg+xml` 的图片，`naturalWidth > 0` |
| 画面开关关着 + 代码围栏 | 代码还在，围栏行没了 |
| 报备 JSON 截断 | 读到标题「凌晨一点的日常」+ 摘要，正文不含 `{"` |

---

## 3. 验证

| 项 | 结果 |
|---|---|
| 单测 | **129 / 129**（118 → 129，新增 11 条：截断围栏、`</svg>` 带注释、坏 JSON 修复、salvage 边界、JSON 不进 html） |
| 模块审计 | 19 模块 **0 error / 0 warning** |
| 源码泄漏 | `leak-check.mjs` **13 / 13** |
| 全量体检 | `audit-check.mjs` **254 / 254** |
| 启动 / 交互 / 表情包 | 全过 · **14/14** · **20/20** |
| 画面 / 重来 | **14 / 14** · **10 / 10** |
| 工具盘 | `tray-check.mjs` **21 / 21**（本轮未改输入栏，回归确认） |

新截图：`docs/test-1.9.13-report.png`（修复后的报备页：标题 + 摘要 + 段落 + 场景插画）。

---

## 4. APK

| 项 | 值 |
|---|---|
| 文件 | `Lian-1.9.13.apk`（仓库根目录） |
| 包名 / 版本 | `com.lian.chat` · versionName **1.9.13** · versionCode **19** |
| 签名 | 同一个 `lian-release.jks`，可直接覆盖安装 1.9.10 / 1.9.11 / 1.9.12 |
| 打包 | `robocopy` 同步 `lian-chat` → `D:\lianbuild\app\assets\www`（排除 `scripts` `tests` `docs` `*.md` `*.bat` `.gitignore` `package.json`），再跑 `build.ps1` |

版本号 8 处：`package.json`、`sw.js VERSION`、`app.js` 主页脚注、`settings.js` 令牌行、
`AndroidManifest.xml`、`build.ps1`（versionCode / versionName / 输出名 / Get-Item）、
`ProactiveWorker.java` UA、`scripts/boot-check.mjs` 截图名。

---

## 5. 还没做的 / 建议下一步

1. **真机回归**：这次的两个 bug 都来自真机，请在手机上再走一遍「画一张」和「生成日常报备」。
2. **半张图画不出来时**：现在只给一句话。如果希望「补画一张」，需要把半成品补全成合法 SVG（要写补标签的解析器），风险大于收益，暂不做。
3. **`finish: "partial"` 的提示**：流式中断时 App 目前完全静默（把半截当正常回复）。可以在气泡角上标一个「（断了）」。
4. **模型不按 JSON 输出**：现在能 salvage 标题/摘要/段落；如果它输出的是 markdown 小标题，也只会变成纯文本段落，不会显示源码。
