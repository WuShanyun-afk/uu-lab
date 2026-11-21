/* Checks for the module work: bottom「模块」page, the assistant conversation
 * page, the roleplay script page, and 1.9.18's per-module threads (each module
 * keeps its own messages, so switching never mixes them).
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
/* 三条会话各自的关键词，用来验证切换时消息没有串过去。 */
const chatMessages = [
  { id: "m1", role: "assistant", kind: "text", text: "*把门推开，雪落进来* 老位置。", ts: now - 3600000 },
  { id: "m2", role: "user", kind: "text", text: "今天有热的吗？", ts: now - 3500000 },
  { id: "m3", role: "assistant", kind: "text", text: "*把茶推到你面前*\n喝吧。\n（火盆里的炭轻轻响了一声）", ts: now - 3400000 },
];
const sceneMessages = [
  { id: "r1", role: "assistant", kind: "text", text: "（渡口的风把灯吹得晃了一下）\n*把伞收起来靠在门边*", ts: now - 3000000 },
  { id: "r2", role: "user", kind: "text", text: "今晚还走吗？", ts: now - 2900000 },
  { id: "r3", role: "assistant", kind: "text", text: "不走了。*在你对面坐下*\n炉子还有炭吗。", ts: now - 2800000 },
];
const codeMessages = [
  { id: "a1", role: "user", kind: "text", text: "帮我写一个防抖函数", ts: now - 900000 },
  {
    id: "a2", role: "assistant", kind: "text", ts: now - 880000,
    text: "用 `setTimeout` 记下最后一次调用即可：\n\n```js\nfunction debounce(fn, wait = 300) {\n  let timer = 0;\n  return (...args) => {\n    clearTimeout(timer);\n    timer = setTimeout(() => fn(...args), wait);\n  };\n}\n```\n\n注意：组件卸载时要 `clearTimeout`，否则会留下悬挂的定时器。",
  },
];

/* `withThreads: false` 模拟 1.9.18 之前的老数据：只有一个会话，另外两个模块还没建。 */
const seedState = ({ mode = "companion", withThreads = true } = {}) => {
  const baseChat = (extra) => ({
    avatar: "", keyId: "k1", memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
    block: null, blockFollowUp: null, createdAt: now - 86400000, updatedAt: now, ...extra,
  });
  const chats = [
    baseChat({
      id: "c1", mode: "companion", kind: "", name: "沈砚",
      relationship: "客栈老板与常来的刀客", persona: "话少。", greeting: "（推门进来）老位置。", messages: chatMessages,
    }),
  ];
  if (withThreads) {
    chats.push(
      baseChat({ id: "c2", mode: "roleplay", kind: "module", name: "沈砚", relationship: "客栈老板与常来的刀客", persona: "话少。", messages: sceneMessages }),
      baseChat({ id: "c3", mode: "assistant", kind: "module", name: "沈砚", relationship: "", persona: "", messages: codeMessages }),
    );
  }
  return {
    onboarded: true,
    settings: {
      provider: "custom", apiKey: "seed", baseUrl: "http://127.0.0.1:1/v1", model: "m",
      aiName: "沈砚", userName: "小满", relationship: "客栈老板与常来的刀客", persona: "话少。",
      greeting: "（推门进来）老位置。", theme: "paper", layout: "line", mode,
    },
    chats,
    keys: [{ id: "k1", name: "Mock", provider: "custom", apiKey: "seed", baseUrl: "http://127.0.0.1:1/v1", model: "m", createdAt: now }],
    activeChatId: "c1",
    activeByMode: withThreads ? { companion: "c1", roleplay: "c2", assistant: "c3" } : { companion: "c1", roleplay: "", assistant: "" },
    messages: chatMessages, memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
  };
};

async function waitBoot() {
  for (let attempt = 0; attempt < 140; attempt += 1) {
    if (await evaluate(`!document.querySelector("#boot") || !!document.querySelector("#boot.is-done")`)) break;
    await sleep(110);
  }
  await sleep(320);
}

async function boot(seed) {
  await send("Page.navigate", { url: base });
  await sleep(450);
  await evaluate(`(async () => {
    localStorage.clear();
    await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
    localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(seed))});
    return true;
  })()`);
  await send("Page.reload");
  await waitBoot();
}

const openChat = async () => {
  await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
  await sleep(500);
};
const openModuleTab = async () => {
  await evaluate(`document.querySelector('[data-tab="module"]').click()`);
  await sleep(420);
};
const cardText = `(() => {
  const card = (id) => document.querySelector('[data-module-pick="' + id + '"]');
  const thread = (id) => (card(id)?.querySelector(".module-card-thread")?.innerText || "").trim();
  const state = (id) => (card(id)?.querySelector(".module-card-state")?.innerText || "").trim();
  return { companion: thread("companion"), roleplay: thread("roleplay"), assistant: thread("assistant"),
    roleplayState: state("roleplay"), assistantState: state("assistant") };
})()`;

/* ================= 陪伴页还是真人聊天 ================= */
await boot(seedState());
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

/* ================= 底部「模块」页 ================= */
const tabs = await evaluate(`Array.from(document.querySelectorAll("#tabBar [data-tab]")).map((node) => node.dataset.tab)`);
check("the bottom bar has a module tab", tabs.includes("module"), tabs.join(","));
check("the bottom bar keeps four entries", tabs.length === 4, String(tabs.length));
const moduleLabel = await evaluate(`document.querySelector('[data-tab="module"] span')?.textContent || ""`);
check("the module tab label is localised", moduleLabel === "模块" || moduleLabel === "Modules", moduleLabel);

await openModuleTab();
let modulePage = await evaluate(`(() => ({
  screen: document.body.dataset.screen,
  visible: !document.querySelector("#moduleScreen").hidden,
  cards: Array.from(document.querySelectorAll("[data-module-pick]")).map((node) => node.dataset.modulePick),
  current: document.querySelector(".module-card.is-on")?.dataset.modulePick || "",
}))()`);
check("the module page opens from the bottom bar", modulePage.screen === "module" && modulePage.visible, modulePage.screen);
check("it offers assistant / roleplay / companion", modulePage.cards.join(",") === "assistant,roleplay,companion", modulePage.cards.join(","));
check("it marks the current module", modulePage.current === "companion", modulePage.current);
let cards = await evaluate(cardText);
check("each module shows its own thread size", cards.companion.includes("3") && cards.roleplay.includes("3") && cards.assistant.includes("2"), JSON.stringify(cards));
check("a module with a thread says 切换", cards.roleplayState.length > 0 && cards.assistantState.length > 0, `${cards.roleplayState}/${cards.assistantState}`);
await capture("module-home.png");

/* ================= 角色扮演：剧本页 + 自己的消息 ================= */
await evaluate(`document.querySelector('[data-module-pick="roleplay"]').click()`);
await sleep(700);
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
check("roleplay shows its own scene", page1.text.includes("今晚还走吗"), page1.text.slice(0, 40));
check("roleplay does not borrow the companion thread", !page1.text.includes("今天有热的吗"), page1.text.slice(0, 60));
check("roleplay does not borrow the assistant thread", !page1.text.includes("debounce"), page1.text.slice(0, 60));
await capture("module-roleplay.png");

/* ================= AI 助理：现代对话页 + 自己的消息 ================= */
await openModuleTab();
await evaluate(`document.querySelector('[data-module-pick="assistant"]').click()`);
await sleep(700);
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
  text: document.querySelector("#messageList").innerText,
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
check("assistant shows its own thread", page1.text.includes("debounce"), page1.text.slice(0, 40));
check("assistant does not borrow the companion thread", !page1.text.includes("今天有热的吗"), page1.text.slice(0, 60));
check("assistant has no roleplay narration blocks", page1.text.includes("今晚还走吗") === false, page1.text.slice(0, 60));

const copied = await evaluate(`(() => {
  const button = document.querySelector("[data-copy-code]");
  if (!button) return "missing";
  try { button.click(); return "clicked"; } catch (error) { return "threw:" + error.message; }
})()`);
check("the copy button is clickable", copied === "clicked", copied);
await capture("module-assistant.png");

/* ================= 切回陪伴：原会话原封不动 ================= */
await evaluate(`document.querySelector("#btnChatBack").click()`);
await sleep(350);
await openModuleTab();
await evaluate(`document.querySelector('[data-module-pick="companion"]').click()`);
await sleep(700);
const back = await evaluate(`(() => ({
  mode: document.body.dataset.mode,
  theme: document.body.dataset.theme,
  avatar: document.querySelector(".msg.ai .avatar") ? getComputedStyle(document.querySelector(".msg.ai .avatar")).display : "missing",
  text: document.querySelector("#messageList").innerText,
}))()`);
check("companion restores the fake-human page", back.mode === "companion", back.mode);
check("companion restores the old theme", back.theme === "paper", back.theme);
check("companion shows avatars again", back.avatar !== "none", back.avatar);
check("companion still has its own messages", back.text.includes("今天有热的吗"), back.text.slice(0, 40));
check("companion never received the assistant's code", !back.text.includes("debounce"), back.text.slice(0, 60));

/* ================= 在剧本里新建场景：只有剧本变多 ================= */
await openModuleTab();
await evaluate(`document.querySelector('[data-module-pick="roleplay"]').click()`);
await sleep(600);
await evaluate(`document.querySelector("#btnChatBack").click()`);
await sleep(350);
await evaluate(`document.querySelector("#btnNewChat").click()`);
await sleep(450);
const chips = await evaluate(`Array.from(document.querySelectorAll("#newChatPresets [data-preset]")).map((node) => node.dataset.preset)`);
check("roleplay offers the scenario cards", chips.length === ROLEPLAY_PRESETS.length + 1 && chips.includes("custom"), `${chips.length}`);
await evaluate(`document.querySelector('[data-preset="orbit"]').click()`);
await sleep(200);
const filled = await evaluate(`document.querySelector("#newChatName").value`);
check("picking a card fills the form", filled === "K", filled);
await evaluate(`document.querySelector("#newChatForm").requestSubmit()`);
await sleep(700);
const scene = await evaluate(`(() => ({
  mode: document.body.dataset.mode,
  name: (document.querySelector("#peerName") || {}).textContent || "",
  text: document.querySelector("#messageList").innerText,
}))()`);
check("a new scene is created inside the roleplay module", scene.mode === "roleplay", scene.mode);
check("the new scene starts from its preset greeting", scene.name === "K" && scene.text.includes("呼吸阀"), `${scene.name} / ${scene.text.slice(0, 30)}`);
check("the new scene does not inherit the old scene", !scene.text.includes("今晚还走吗"), scene.text.slice(0, 50));

await openModuleTab();
cards = await evaluate(cardText);
check("the roleplay module now counts the new scene", cards.roleplay.includes("1"), cards.roleplay);
check("the companion thread is untouched", cards.companion.includes("3"), cards.companion);
check("the assistant thread is untouched", cards.assistant.includes("2"), cards.assistant);

/* ================= 列表里能分清哪条是模块会话 ================= */
await evaluate(`document.querySelector('[data-tab="list"]').click()`);
await sleep(450);
const list = await evaluate(`(() => ({
  badges: Array.from(document.querySelectorAll(".chat-mode-badge")).map((node) => node.innerText),
  rows: document.querySelectorAll("[data-chat-open]").length,
}))()`);
check("the list marks assistant and script threads", list.badges.length === 3, list.badges.join(","));
check("the list keeps every thread", list.rows === 4, String(list.rows));
await capture("module-threads.png");

/* ================= 老数据（只有一个会话）：助理会自己开一条 ================= */
await boot(seedState({ withThreads: false }));
await openModuleTab();
cards = await evaluate(cardText);
check("an old profile shows empty module threads", cards.assistant.includes("还没") || cards.assistantState.length > 0, JSON.stringify(cards));
await evaluate(`document.querySelector('[data-module-pick="assistant"]').click()`);
await sleep(750);
const fresh = await evaluate(`(() => ({
  mode: document.body.dataset.mode,
  text: document.querySelector("#messageList").innerText,
  count: document.querySelectorAll(".msg").length,
}))()`);
check("opening an empty module creates its own thread", fresh.mode === "assistant", fresh.mode);
check("the assistant thread opens with a neutral hello", fresh.text.includes("你好，需要什么帮助吗？"), fresh.text.slice(0, 40));
check("it holds only that hello", fresh.count === 1, String(fresh.count));
check("it did not copy the companion history", !fresh.text.includes("今天有热的吗"), fresh.text.slice(0, 60));

/* 重新加载后仍然停在助理会话里（activeByMode 存下来了） */
await send("Page.reload");
await waitBoot();
const afterReload = await evaluate(`(() => ({ mode: document.body.dataset.mode, theme: document.body.dataset.theme }))()`);
check("the active module survives a reload", afterReload.mode === "assistant", `${afterReload.mode}/${afterReload.theme}`);
await openModuleTab();
await evaluate(`document.querySelector('[data-module-pick="assistant"]').click()`);
await sleep(650);
const restored = await evaluate(`(() => ({
  mode: document.body.dataset.mode,
  text: document.querySelector("#messageList")?.innerText || "",
}))()`);
check("its messages survive the reload too", restored.mode === "assistant" && restored.text.includes("你好，需要什么帮助吗？"), restored.text.slice(0, 40));

/* 切回陪伴，历史还在 */
await openModuleTab();
await evaluate(`document.querySelector('[data-module-pick="companion"]').click()`);
await sleep(700);
const legacyBack = await evaluate(`(() => ({
  mode: document.body.dataset.mode,
  text: document.querySelector("#messageList").innerText,
}))()`);
check("the old single chat stays in companion", legacyBack.mode === "companion" && legacyBack.text.includes("今天有热的吗"), legacyBack.mode);

/* ================= 设置里的人设卡也能切模块 ================= */
await evaluate(`document.querySelector("#btnPeer")?.click()`);
await sleep(650);
const settingsHint = await evaluate(`(() => {
  const hints = Array.from(document.querySelectorAll("#settingsBody .field-hint")).map((node) => node.innerText).join(" | ");
  return { opened: document.body.dataset.screen, hints };
})()`);
check("settings explains the separate threads", /自己的对话记录|独立/.test(settingsHint.hints), settingsHint.hints.slice(0, 70));
await evaluate(`document.querySelector('.mode-card[data-mode="roleplay"]')?.click()`);
await sleep(600);
const viaSettings = await evaluate(`(() => ({ mode: document.body.dataset.mode, text: document.querySelector("#messageList").innerText }))()`);
check("the settings picker switches the thread too", viaSettings.mode === "roleplay", viaSettings.mode);
check("that thread is a fresh script, not the companion chat", !viaSettings.text.includes("今天有热的吗"), viaSettings.text.slice(0, 40));

check("no console errors", consoleErrors.length === 0, consoleErrors.slice(0, 2).join(" | "));

const failed = results.filter((item) => !item.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
ws.close();
child.kill("SIGKILL");
server.close();
await sleep(150);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
process.exit(failed.length ? 1 : 0);
