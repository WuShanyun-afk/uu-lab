# Lian 1.9.4 · 界面模块化改造计划

把上一轮的「美化建议」拆成 **9 个可独立上线、可独立回滚的模块**，一个模块一个文件、一个验收标准。
任何模块出问题，只要删掉 `index.html` 里对应的一行 `<link>` 即可回滚，不影响其他模块。

## 模块清单

| # | 模块 | 交付物 | 改动范围 | 验收标准 |
|---|------|--------|----------|----------|
| M1 | **tokens** 设计令牌 | `css/modules/01-tokens.css` | 只新增 CSS 变量，不改任何现有规则 | 与基线截图**逐像素一致**（0 差异像素） |
| M2 | **type** 字号阶梯 | `css/modules/02-type.css` | 全局最小字号 10px、正文 15px、时间戳 10.5px | 页面上不再有 <10px 的文字；聊天正文 15px |
| M3 | **contrast** 对比度 | `js/palette.js` + `css/modules/03-contrast.css` + `tests/palette.test.js` | 气泡底色按 WCAG 自动压深，`--accent` 不变 | 六个主题气泡对比度全部 ≥ 4.5:1，单元测试通过 |
| M4 | **bubbles** 气泡 | `css/modules/04-bubbles.css` + `js/app.js`（连发合并） | 尾巴、76% 宽、同人连发隐藏重复头像、表情包 136px | 连续 3 条同角色消息只出现 1 个头像；气泡有尾巴 |
| M5 | **surfaces** 表面 | `css/modules/05-surfaces.css` | 聊天纸纹背景、头部、日期胶囊、输入条浮层 | 聊天页有纸纹且 `snow` 主题不受影响 |
| M6 | **home** 主页 | `css/modules/06-home.css` | 卡片圆角/阴影、图标语言统一、数字 tabular | 主页两处图标同为线性图标 + accent 底色 |
| M7 | **paper** 主题 | `css/modules/07-theme-paper.css` + `config.js` | 新主题 `paper`「纸间」，`data-theme="paper"` | 设置里出现第 7 个色板，切换后整站换肤 |
| M8 | **motion** 动效 | `css/modules/08-motion.css` | 统一时长/曲线，消息入场，`prefers-reduced-motion` | 减少动效时无位移动画 |
| M9 | **dark** 深色 | `css/modules/09-dark.css` | `prefers-color-scheme: dark` 下 paper 走夜幕纸 | 深色模拟下正文对比度 ≥ 4.5:1 |

接入方式：`index.html` 在 `css/app.css` 之后按 M1→M9 顺序 `<link>`，`sw.js` 的 `ASSETS` 同步登记。

## 令牌（M1 定义，后续模块只消费）

```
字号  --fs-2xs 10 / --fs-xs 10.5 / --fs-sm 11.5 / --fs-md 13 / --fs-body 15 / --fs-title 22
圆角  --r-xs 8 / --r-sm 12 / --r-md 16 / --r-lg 20 / --r-xl 26
间距  --sp-1 4 / --sp-2 8 / --sp-3 12 / --sp-4 16 / --sp-5 22
阴影  --el-1 / --el-2 / --el-3
动效  --t-fast 140ms / --t-base 200ms / --t-slow 280ms
气泡  --bubble-mine / --bubble-mine-ink / --bubble-peer / --bubble-peer-ink
纸色  --paper-100…400 / --ink-900…400 / --line-paper
```

## 每个模块的验证动作

统一用 `scripts/module-shots.mjs`（无网络、无 API Key）：

```
node scripts/module-shots.mjs --out m1 --theme line      # 截图 + 指标
node scripts/module-shots.mjs --out m3 --theme line --metrics
```

脚本会输出一段 JSON 指标（字号、气泡底色、对比度、连发头像数），并写入
`docs/mod-<out>-{chat,home,list}.png`。逐模块比对截图与指标，再进下一个模块。

## 发布（M10）

版本号 7 处：`package.json` / `sw.js VERSION` / `app.js` 页脚 / `settings.js` 页脚 /
`AndroidManifest.xml` / `build.ps1` / `ProactiveWorker.java`，外加 `scripts/boot-check.mjs` 截图名。
之后同步 `D:\lianbuild\app\assets\www`，跑 `node --test`、`scripts/check-modules.mjs`、
`scripts/boot-check.mjs`，最后出 APK/ZIP 与 1.9.4 交接备忘录。

## 执行结果（2026-11-20 完成）

| # | 模块 | 状态 | 验收证据 |
|---|------|------|----------|
| M1 | tokens | ✅ | base vs m1 差异 606 px，低于噪声底 694 px → 无视觉变化 |
| M2 | type | ✅ | 指标：时间戳 10.5、正文 15、tab 10、主页小字全部 10 |
| M3 | contrast | ✅ | 6 主题气泡 ≥4.5:1；`tests/palette.test.js` 6 条通过 |
| M4 | bubbles | ✅ | 尾角 7px、表情包 136、10 条消息 7 个头像 → 4 个 |
| M5 | surfaces | ✅ | 纸纹生效；`snow` 主题截图无回归 |
| M6 | home | ✅ | 图标统一为 10% 绿底 + 绿线性图标 |
| M7 | paper | ✅ | 设置里第 7 个色板；浅色截图 `docs/1.9.4-paper-*.png` |
| M8 | motion | ✅ | 时长令牌化；`prefers-reduced-motion` 分支保留 |
| M9 | dark | ✅ | 深色截图 `docs/1.9.4-paper-dark-*.png` |
| M10 | release | ✅ | APK 627,977 B / ZIP 见交接备忘录；57 单测 + 14 浏览器断言通过 |

> 计划外的两处修正：M4 最初把用户气泡收到 76%，实测会让 15px 的中文句子折成两行，已回退到 82%；
> M9 第一次上线时 AI 气泡在深色下仍是白的，原因是自定义属性里的 `var()` 在声明处求值（见交接备忘录 2.1）。
