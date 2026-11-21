/* Design shots for the assistant page (1.9.20).
 *
 *   node scripts/assistant-shots.mjs
 *
 * Seeds three states into the localStorage fallback store and writes
 * docs/assistant-welcome.png, assistant-answer.png, assistant-thinking.png.
 * No network: the thinking state uses a delayed mock completion.
 */
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8", ".svg": "image/svg+xml",
  ".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp",
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const server = createServer((req, res) => {
  const raw = decodeURIComponent((req.url || "/").split("?")[0]);
  let file = path.join(ROOT, raw === "/" ? "index.html" : raw);
  if (!file.startsWith(ROOT)) return res.writeHead(403).end("forbidden");
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, "index.html");
  if (!fs.existsSync(file)) return res.writeHead(404).end("not found");
  res.writeHead(200, {
    "content-type": MIME[path.extname(file).toLowerCase()] || "application/octet-stream",
    "content-length": fs.statSync(file).size,
    "cache-control": "no-store",
  });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}/`;

const edge = [
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
].find((p) => fs.existsSync(p));
if (!edge) {
  console.error("SKIP: Microsoft Edge not found");
  server.close();
  process.exit(2);
}

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-shot-"));
const debugPort = 10320 + Math.floor(Math.random() * 60);
const child = spawn(edge, [
  "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
  "--mute-audio", `--user-data-dir=${profile}`, `--remote-debugging-port=${debugPort}`, "about:blank",
], { stdio: "ignore" });

let targets;
const started = Date.now();
while (Date.now() - started < 15000) {
  try {
    targets = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
    if (targets?.length) break;
  } catch { /* not up yet */ }
  await sleep(150);
}
const ws = new WebSocket(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
let id = 0;
const pending = new Map();
ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message.result);
  }
};
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const messageId = ++id;
  pending.set(messageId, { resolve, reject });
  ws.send(JSON.stringify({ id: messageId, method, params }));
});
await send("Runtime.enable");
await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", {
  width: 390, height: 844, deviceScaleFactor: 2, mobile: true, screenWidth: 390, screenHeight: 844,
});
const evaluate = async (expression) => {
  const result = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true, userGesture: true });
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || "eval failed");
  return result.result?.value;
};

const now = Date.now();
const msg = (id, role, text, ts) => ({ id, role, kind: "text", text, ts });
const settings = {
  provider: "mimo", apiKey: "seed", baseUrl: "https://api.xiaomimimo.com/v1", model: "mimo-v2.6-flash",
  aiName: "沈砚", userName: "小满", relationship: "客栈老板与常来的刀客", persona: "话少。",
  theme: "assistant", accent: "#2F6BFF", layout: "line", mode: "assistant",
  realism: { enabled: false }, optimize: { streaming: false, quotes: false, segments: false },
};
const chat = (messages) => ({
  id: "c3", mode: "assistant", kind: "module", name: "沈砚", keyId: "k1", avatar: "",
  relationship: "", persona: "", greeting: "你好，需要什么帮助吗？", messages, memories: [],
  memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 }, block: null, blockFollowUp: null,
  createdAt: now - 86400000, updatedAt: now,
});
const key = { id: "k1", name: "MiMo", provider: "mimo", apiKey: "seed", baseUrl: "https://api.xiaomimimo.com/v1", model: "mimo-v2.6-flash", createdAt: now };
const wrap = (messages, override = null) => ({
  onboarded: true,
  settings: override?.settings || settings,
  chats: [chat(messages)],
  keys: [override?.key || key],
  activeChatId: "c3", activeKeyId: "k1", activeByMode: { companion: "", roleplay: "", assistant: "c3" },
  messages, memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
});

async function waitBoot() {
  for (let attempt = 0; attempt < 150; attempt += 1) {
    if (await evaluate(`!document.querySelector("#boot") || !!document.querySelector("#boot.is-done")`)) break;
    await sleep(110);
  }
  await sleep(380);
}
async function boot(state) {
  await send("Page.navigate", { url: base });
  await sleep(420);
  await evaluate(`(async () => {
    localStorage.clear();
    await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
    localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(state))});
    return true;
  })()`);
  await send("Page.reload");
  await waitBoot();
  await evaluate(`document.querySelector('[data-chat-open="c3"]')?.click()`);
  await sleep(700);
}
async function shot(name) {
  const result = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
  fs.writeFileSync(path.join(ROOT, "docs", name), Buffer.from(result.data, "base64"));
  console.log("wrote docs/" + name);
}

/* ---- 1. welcome (greeting only) ---- */
await boot(wrap([{ ...msg("g1", "assistant", "你好，需要什么帮助吗？", now - 60000), greeting: true }]));
await shot("assistant-welcome.png");
console.log("welcome:", await evaluate(`({ welcome: !!document.querySelector("#asWelcome"), prompts: document.querySelectorAll(".as-prompt").length, mark: document.querySelector("#peerMark")?.textContent, sub: document.querySelector("#peerSub")?.textContent })`));

/* ---- 1b. DeepSeek: D monogram + both native capabilities on ---- */
const deepseekSettings = {
  ...settings,
  provider: "deepseek",
  baseUrl: "https://api.deepseek.com/v1",
  model: "deepseek-flash",
};
const deepseekKey = { id: "k1", name: "DeepSeek", provider: "deepseek", apiKey: "seed", baseUrl: "https://api.deepseek.com/v1", model: "deepseek-flash", createdAt: now };
await boot(wrap([{ ...msg("g1", "assistant", "你好，需要什么帮助吗？", now - 60000), greeting: true }], { settings: deepseekSettings, key: deepseekKey }));
await evaluate(`(() => {
  document.querySelector('[data-assistant-tool="web"]')?.click();
  document.querySelector('[data-assistant-tool="thinking"]')?.click();
})()`);
await sleep(240);
await shot("assistant-deepseek.png");
console.log("deepseek:", await evaluate(`({ mark: document.querySelector("#peerMark")?.textContent, provider: document.querySelector("#peerMark")?.dataset.provider, meta: document.querySelector(".as-welcome-meta")?.textContent, pressed: [...document.querySelectorAll("[data-assistant-tool]")].map((b) => b.getAttribute("aria-pressed")) })`));

/* ---- 2. a rich answer ---- */
const answer = [
  "## 结论",
  "",
  "这段代码有两个问题：",
  "",
  "1. **定时器没有清理**：组件卸载后还会触发。",
  "2. `wait` 没有兜底值，传 `undefined` 会变成 0。",
  "",
  "### 改法",
  "",
  "```js",
  "function debounce(fn, wait = 300) {",
  "  let timer = 0;",
  "  return (...args) => {",
  "    clearTimeout(timer);",
  "    timer = setTimeout(() => fn(...args), wait);",
  "  };",
  "}",
  "```",
  "",
  "| 问题 | 风险 | 修法 |",
  "|---|---|---|",
  "| 未清理定时器 | 内存泄漏 | 返回 cancel |",
  "| wait 缺失 | 立即执行 | 默认值 300 |",
  "",
  "> 小提示：组件卸载时记得 `clearTimeout`。",
].join("\n");
const rich = [
  msg("u1", "user", "帮我看看这个防抖，顺便列一下问题和改法", now - 200000),
  {
    ...msg("a1", "assistant", answer, now - 190000),
    reasoning: "先判断这段防抖的问题：定时器没清理、wait 没有默认值。再给出改法和一张对照表，最后提醒卸载时 clearTimeout。",
    sources: [{ url: "https://developer.mozilla.org/zh-CN/docs/Web/API/setTimeout", title: "setTimeout - MDN", siteName: "MDN" }],
  },
  msg("u2", "user", "返回 cancel 那版也给我看看", now - 60000),
  msg("a2", "assistant", "可以，在 `debounce` 里暴露一个 `cancel` 就行：\n\n```js\nexport function debounce(fn, wait = 300) {\n  let timer = 0;\n  const run = (...args) => {\n    clearTimeout(timer);\n    timer = setTimeout(() => fn(...args), wait);\n  };\n  run.cancel = () => clearTimeout(timer);\n  return run;\n}\n```", now - 50000),
];
await boot(wrap(rich));
await evaluate(`(() => { const scroll = document.querySelector("#chatScroll"); if (scroll) scroll.scrollTop = 0; })()`);
await sleep(320);
await shot("assistant-answer-top.png");
await evaluate(`(() => {
  const think = document.querySelector(".as-think");
  if (think) think.open = true;
  think?.scrollIntoView({ block: "start" });
})()`);
await sleep(320);
await shot("assistant-reasoning.png");
await evaluate(`(() => { const scroll = document.querySelector("#chatScroll"); if (scroll) scroll.scrollTop = scroll.scrollHeight; })()`);
await sleep(320);
await shot("assistant-answer.png");
console.log("answer:", await evaluate(`({ meta: document.querySelectorAll(".as-meta").length, actions: document.querySelectorAll(".as-actions").length, lists: document.querySelectorAll(".as-list").length, tables: document.querySelectorAll(".as-table").length, quotes: document.querySelectorAll(".as-quote").length, heads: document.querySelectorAll(".as-h").length, code: document.querySelectorAll(".msg-code").length })`));
console.log("inline:", await evaluate(`(() => {
  const el = document.querySelector(".as-inline");
  if (!el) return null;
  const cs = getComputedStyle(el);
  return { bg: cs.backgroundColor, color: cs.color, accent: getComputedStyle(document.body).getPropertyValue("--accent").trim(), theme: document.body.dataset.theme };
})()`));

/* ---- 3. waiting for an answer (deep thinking on) ---- */
await boot(wrap([{ ...msg("g1", "assistant", "你好，需要什么帮助吗？", now - 60000), greeting: true }]));
await evaluate(`document.querySelector('[data-assistant-tool="thinking"]')?.click()`);
await sleep(200);
await evaluate(`(() => {
  const real = window.fetch;
  window.fetch = (url, opts) => {
    if (String(url).includes("/chat/completions")) {
      return new Promise((resolve) => setTimeout(() => resolve(new Response(JSON.stringify({
        id: "x", choices: [{ index: 0, message: { role: "assistant", content: "先看这段代码的边界条件。" }, finish_reason: "stop" }],
        usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 },
      }), { status: 200, headers: { "content-type": "application/json" } })), 6000));
    }
    return real(url, opts);
  };
  const input = document.querySelector("#messageInput");
  input.value = "这段防抖为什么在卸载后还会触发？";
  input.dispatchEvent(new Event("input", { bubbles: true }));
  document.querySelector("#btnSend").click();
})()`);
await sleep(900);
await shot("assistant-thinking.png");
console.log("thinking:", await evaluate(`({ thinking: !!document.querySelector("#asThinking"), label: document.querySelector("#asThinking")?.innerText })`));

ws.close();
child.kill("SIGKILL");
server.close();
await sleep(150);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
