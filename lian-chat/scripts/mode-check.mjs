/* Checks for the 1.9.17 module work: bottom「模块」page, the assistant
 * conversation page and the roleplay script page (no avatars, no fake-chat
 * bubbles).
 *
 *   node scripts/mode-check.mjs
 *
 * Drives the real page over CDP, no network. Writes docs/module-*.png.
 */
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ROLEPLAY_PRESETS } from "../js/roleplay.js";

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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-mode-"));
const debugPort = 9620 + Math.floor(Math.random() * 60);
const child = spawn(edge, [
  "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
  "--mute-audio", `--user-data-dir=${profile}`, `--remote-debugging-port=${debugPort}`, "about:blank",
], { stdio: "ignore" });

const started = Date.now();
let targets;
while (Date.now() - started < 15000) {
  try {
    targets = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
    if (targets?.length) break;
  } catch { /* not up yet */ }
  await sleep(150);
}
const page = targets.find((t) => t.type === "page");
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
let id = 0;
const pending = new Map();
const consoleErrors = [];
ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message.result);
    return;
  }
  if (message.method === "Runtime.exceptionThrown") {
    consoleErrors.push(message.params?.exceptionDetails?.exception?.description || "exception");
  } else if (message.method === "Runtime.consoleAPICalled" && message.params?.type === "error") {
    consoleErrors.push(message.params.args.map((arg) => arg.value ?? arg.description ?? "").join(" "));
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

const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};
const capture = async (name) => {
  const shot = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
  fs.writeFileSync(path.join(ROOT, "docs", name), Buffer.from(shot.data, "base64"));
};

const now = Date.now();
const chatMessages = [
  { id: "m1", role: "assistant", kind: "text", text: "*把门推开，雪落进来* 老位置。", ts: now - 3600000 },
  { id: "m2", role: "user", kind: "text", text: "今天有热的吗？", ts: now - 3500000 },
  { id: "m3", role: "assistant", kind: "text", text: "*把茶推到你面前*\n喝吧。\n（火盆里的炭轻轻响了一声）", ts: now - 3400000 },
];
const codeMessages = [
  { id: "a1", role: "user", kind: "text", text: "帮我写一个防抖函数", ts: now - 900000 },
  {
    id: "a2", role: "assistant", kind: "text", ts: now - 880000,
    text: "用 `setTimeout` 记下最后一次调用即可：\n\n```js\nfunction debounce(fn, wait = 300) {\n  let timer = 0;\n  return (...args) => {\n    clearTimeout(timer);\n    timer = setTimeout(() => fn(...args), wait);\n  };\n}\n```\n\n注意：组件卸载时要 `clearTimeout`，否则会留下悬挂的定时器。",
  },
];
const seedFor = (mode, messages) => ({
  onboarded: true,
  settings: {
    provider: "custom", apiKey: "seed", baseUrl: "http://127.0.0.1:1/v1", model: "m",
    aiName: "沈砚", userName: "小满", relationship: "客栈老板与常来的刀客", persona: "话少。",
    greeting: "（推门进来）老位置。", theme: mode === "assistant" ? "assistant" : "paper", layout: "line", mode,
  },
  chats: [{
    id: "c1", name: "沈砚", relationship: "客栈老板与常来的刀客", keyId: "k1",
    createdAt: now - 86400000, updatedAt: now, messages,
  }],
  keys: [{ id: "k1", name: "Mock", provider: "custom", apiKey: "seed", baseUrl: "http://127.0.0.1:1/v1", model: "m", createdAt: now }],
  activeChatId: "c1", activeKeyId: "k1",
  messages, memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
});

async function boot(mode = "companion", messages = chatMessages) {
  await send("Page.navigate", { url: base });
  await sleep(450);
  await evaluate(`(async () => {
    localStorage.clear();
    await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
    localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(seedFor(mode, messages)))});
    return true;
  })()`);
  await send("Page.reload");
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (await evaluate(`!document.querySelector("#boot") || !!document.querySelector("#boot.is-done")`)) break;
    await sleep(110);
  }
  await sleep(320);
}

const openChat = async () => {
  await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
  await sleep(500);
};

await boot("companion");
/* the 陪伴 page keeps the fake-human look */
await openChat();
let page1 = await evaluate(`(() => {
  const avatar = document.querySelector(".msg .avatar");
  const bubble = document.querySelector(".msg.ai .bubble");
  return {
    mode: document.body.dataset.mode,
    avatar: avatar ? getComputedStyle(avatar).display : "missing",
    name: document.querySelector(".msg-name") ? getComputedStyle(document.querySelector(".msg-name")).display : "missing",
    bg: bubble ? getComputedStyle(bubble).backgroundColor : "",
    time: document.querySelector(".msg-time") ? getComputedStyle(document.querySelector(".msg-time")).display : "missing",
  };
})()`);
check("companion still shows avatars", page1.avatar !== "none", page1.avatar);
check("companion bubbles keep a background", page1.bg !== "rgba(0, 0, 0, 0)", page1.bg);
check("companion shows timestamps", page1.time !== "none", page1.time);

/* ---------- the bottom「模块」page ---------- */
const tabs = await evaluate(`Array.from(document.querySelectorAll("#tabBar [data-tab]")).map((node) => node.dataset.tab)`);
check("the bottom bar has a module tab", tabs.includes("module"), tabs.join(","));
check("the bottom bar keeps four entries", tabs.length === 4, String(tabs.length));

await evaluate(`document.querySelector('[data-tab="module"]').click()`);
await sleep(500);
let modulePage = await evaluate(`(() => ({
  screen: document.body.dataset.screen,
  visible: !document.querySelector("#moduleScreen").hidden,
  cards: Array.from(document.querySelectorAll("[data-module-pick]")).map((node) => node.dataset.modulePick),
  current: document.querySelector(".module-card.is-on")?.dataset.modulePick || "",
  lead: (document.querySelector(".module-lead") || {}).innerText || "",
}))()`);
check("the module page opens from the bottom bar", modulePage.screen === "module" && modulePage.visible, modulePage.screen);
check("it offers assistant / roleplay / companion", modulePage.cards.join(",") === "assistant,roleplay,companion", modulePage.cards.join(","));
check("it marks the current module", modulePage.current === "companion", modulePage.current);
await capture("module-home.png");

/* ---------- roleplay: script page ---------- */
await evaluate(`document.querySelector('[data-module-pick="roleplay"]').click()`);
await sleep(800);
page1 = await evaluate(`(() => ({
  screen: document.body.dataset.screen,
  mode: document.body.dataset.mode,
  avatar: document.querySelector(".msg .avatar") ? getComputedStyle(document.querySelector(".msg .avatar")).display : "missing",
  headerAvatar: getComputedStyle(document.querySelector("#headerAvatar")).display,
  time: document.querySelector(".msg-time") ? getComputedStyle(document.querySelector(".msg-time")).display : "missing",
  bubbleBg: getComputedStyle(document.querySelector(".msg.ai .bubble")).backgroundColor,
  name: document.querySelector(".msg-name") ? getComputedStyle(document.querySelector(".msg-name")).display : "missing",
  actions: document.querySelectorAll(".rp-action").length,
  narrations: document.querySelectorAll(".rp-narration").length,
  lines: document.querySelectorAll(".rp-line").length,
  text: Array.from(document.querySelectorAll(".msg .bubble")).map((node) => node.innerText).join(" | "),
}))()`);
check("the roleplay card opens the chat", page1.screen === "chat" && page1.mode === "roleplay", `${page1.screen}/${page1.mode}`);
check("roleplay hides every avatar", page1.avatar === "none" && page1.headerAvatar === "none", `${page1.avatar}/${page1.headerAvatar}`);
check("roleplay hides timestamps", page1.time === "none", page1.time);
check("roleplay has no bubble background", page1.bubbleBg === "rgba(0, 0, 0, 0)", page1.bubbleBg);
check("roleplay shows a speaker label", page1.name !== "none", page1.name);
check("actions and narration are separate blocks", page1.actions >= 2 && page1.narrations >= 1 && page1.lines >= 2, `${page1.actions}/${page1.narrations}/${page1.lines}`);
check("no action markers are printed", !page1.text.includes("*"), page1.text.slice(0, 60));
await capture("module-roleplay.png");

/* ---------- the scenario cards still fill the form ---------- */
await evaluate(`document.querySelector("#btnChatBack").click()`);
await sleep(450);
await evaluate(`document.querySelector("#btnNewChat").click()`);
await sleep(450);
const chips = await evaluate(`Array.from(document.querySelectorAll("#newChatPresets [data-preset]")).map((node) => node.dataset.preset)`);
check("roleplay offers the scenario cards", chips.length === ROLEPLAY_PRESETS.length, `${chips.length}`);
await evaluate(`document.querySelector('[data-preset="jianghu"]').click()`);
await sleep(200);
const filled = await evaluate(`document.querySelector("#newChatName").value`);
check("picking a card fills the form", filled === "沈砚", filled);
await evaluate(`document.querySelector("[data-close-sheet]").click()`);
await sleep(250);

/* ---------- assistant: modern AI page ---------- */
await boot("assistant", codeMessages);
await openChat();
page1 = await evaluate(`(() => ({
  mode: document.body.dataset.mode,
  theme: document.body.dataset.theme,
  avatar: document.querySelector(".msg .avatar") ? getComputedStyle(document.querySelector(".msg .avatar")).display : "missing",
  headerAvatar: getComputedStyle(document.querySelector("#headerAvatar")).display,
  time: document.querySelector(".msg-time") ? getComputedStyle(document.querySelector(".msg-time")).display : "missing",
  aiBg: getComputedStyle(document.querySelector(".msg.ai .bubble")).backgroundColor,
  userBg: getComputedStyle(document.querySelector(".msg.user .bubble")).backgroundColor,
  code: document.querySelectorAll(".msg-code").length,
  copy: document.querySelectorAll("[data-copy-code]").length,
  lang: (document.querySelector(".msg-code-head span") || {}).textContent || "",
  lines: document.querySelectorAll(".as-line").length,
  stickerBtn: getComputedStyle(document.querySelector("#btnSticker")).display,
}))()`);
check("assistant page opens in assistant mode", page1.mode === "assistant", page1.mode);
check("assistant page uses the assistant theme", page1.theme === "assistant", page1.theme);
check("assistant hides avatars", page1.avatar === "none" && page1.headerAvatar === "none", `${page1.avatar}/${page1.headerAvatar}`);
check("assistant hides timestamps", page1.time === "none", page1.time);
check("assistant answers have no bubble", page1.aiBg === "rgba(0, 0, 0, 0)", page1.aiBg);
check("assistant questions keep a light card", page1.userBg !== "rgba(0, 0, 0, 0)", page1.userBg);
check("a fenced block becomes a code block", page1.code === 1 && page1.lang === "js", `${page1.code}/${page1.lang}`);
check("the code block has a copy button", page1.copy === 1, String(page1.copy));
check("assistant text is laid out as paragraphs", page1.lines >= 2, String(page1.lines));
check("assistant hides the sticker button", page1.stickerBtn === "none", page1.stickerBtn);

const copied = await evaluate(`(() => {
  const button = document.querySelector("[data-copy-code]");
  if (!button) return "missing";
  try { button.click(); return "clicked"; } catch (error) { return "threw:" + error.message; }
})()`);
check("the copy button is clickable", copied === "clicked", copied);
await capture("module-assistant.png");

/* ---------- back to companion through the module page ---------- */
await evaluate(`document.querySelector("#btnChatBack").click()`);
await sleep(400);
await evaluate(`document.querySelector('[data-tab="module"]').click()`);
await sleep(450);
await evaluate(`document.querySelector('[data-module-pick="companion"]').click()`);
await sleep(700);
const back = await evaluate(`(() => ({
  mode: document.body.dataset.mode,
  theme: document.body.dataset.theme,
  avatar: document.querySelector(".msg.ai .avatar") ? getComputedStyle(document.querySelector(".msg.ai .avatar")).display : "missing",
}))()`);
check("companion restores the fake-human page", back.mode === "companion", back.mode);
check("companion restores the old theme", back.theme === "paper", back.theme);
check("companion shows avatars again", back.avatar !== "none", back.avatar);

check("no console errors", consoleErrors.length === 0, consoleErrors.slice(0, 2).join(" | "));

const failed = results.filter((item) => !item.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
ws.close();
child.kill("SIGKILL");
server.close();
await sleep(150);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
process.exit(failed.length ? 1 : 0);
