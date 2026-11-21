/* Checks for 1.9.16: roleplay mode (narration + scenario cards) and the pure
 * assistant mode (assistant theme, no stickers).
 *
 *   node scripts/mode-check.mjs
 *
 * Drives the real page over CDP, no network. Writes docs/mode-*.png.
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
const messages = [
  { id: "m1", role: "assistant", kind: "text", text: "*把门推开，雪落进来* 老位置。", ts: now - 3600000 },
  { id: "m2", role: "user", kind: "text", text: "今天有热的吗？", ts: now - 3500000 },
  { id: "m3", role: "assistant", kind: "text", text: "*把茶推到你面前*\n喝吧。\n（火盆里的炭轻轻响了一声）", ts: now - 3400000 },
];
const seed = {
  onboarded: true,
  settings: {
    provider: "custom", apiKey: "seed", baseUrl: "http://127.0.0.1:1/v1", model: "m",
    aiName: "沈砚", userName: "小满", relationship: "客栈老板与常来的刀客", persona: "话少。",
    greeting: "（推门进来）老位置。", theme: "paper", layout: "line", mode: "companion",
  },
  chats: [{
    id: "c1", name: "沈砚", relationship: "客栈老板与常来的刀客", keyId: "k1",
    createdAt: now - 86400000, updatedAt: now, messages,
  }],
  keys: [{ id: "k1", name: "Mock", provider: "custom", apiKey: "seed", baseUrl: "http://127.0.0.1:1/v1", model: "m", createdAt: now }],
  activeChatId: "c1", activeKeyId: "k1",
  messages, memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
};

await send("Page.navigate", { url: base });
await sleep(450);
await evaluate(`(async () => {
  localStorage.clear();
  await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
  localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(seed))});
  return true;
})()`);
await send("Page.reload");
for (let attempt = 0; attempt < 120; attempt += 1) {
  if (await evaluate(`!document.querySelector("#boot") || !!document.querySelector("#boot.is-done")`)) break;
  await sleep(110);
}
await sleep(320);
await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
await sleep(500);

/* ---------- 1. companion keeps the plain bubbles ---------- */
let state = await evaluate(`(() => ({
  mode: document.body.dataset.mode,
  theme: document.body.dataset.theme,
  actions: document.querySelectorAll(".msg-action").length,
  narration: document.querySelectorAll(".msg-narration").length,
  stickerBtn: getComputedStyle(document.querySelector("#btnSticker")).display,
}))()`);
check("companion is the default mode", state.mode === "companion", state.mode);
check("companion does not style actions", state.actions === 0 && state.narration === 0, JSON.stringify(state));
check("companion keeps the sticker button", state.stickerBtn !== "none", state.stickerBtn);

/* ---------- 2. switch to roleplay from settings ---------- */
await evaluate(`document.querySelector('[data-tab="home"]').click()`);
await sleep(400);
await evaluate(`document.querySelector('[data-home-action="persona"]').click()`);
await sleep(600);
await evaluate(`(() => { const group = document.querySelector('[data-group="persona"]'); if (group) group.open = true; return true; })()`);
await sleep(250);
const picker = await evaluate(`(() => ({
  cards: Array.from(document.querySelectorAll(".mode-card[data-mode]")).map((node) => node.dataset.mode),
  active: document.querySelector(".mode-card.is-on")?.dataset.mode || "",
}))()`);
check("settings offers three chat modes", picker.cards.join(",") === "companion,roleplay,assistant", picker.cards.join(","));
check("companion is selected in settings", picker.active === "companion", picker.active);
await capture("mode-picker.png");

await evaluate(`document.querySelector('[data-mode="roleplay"]').click()`);
await sleep(500);
await evaluate(`document.querySelector("#btnSettingsDone").click()`);
await sleep(650);
state = await evaluate(`(() => ({
  mode: document.body.dataset.mode,
  theme: document.body.dataset.theme,
  actions: document.querySelectorAll(".msg-action").length,
  narration: document.querySelectorAll(".msg-narration").length,
  text: Array.from(document.querySelectorAll(".msg .bubble")).map((node) => node.innerText).join(" | "),
}))()`);
check("roleplay mode is on", state.mode === "roleplay", state.mode);
check("roleplay keeps the colour theme", state.theme === "paper", state.theme);
check("roleplay styles *actions*", state.actions >= 2, String(state.actions));
check("roleplay styles （narration）", state.narration >= 1, String(state.narration));
check("the stars are gone from the bubble text", !state.text.includes("*"), state.text.slice(0, 60));

/* show the styled chat itself in the screenshot */
await evaluate(`document.querySelector('[data-tab="list"]').click()`);
await sleep(400);
await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
await sleep(500);
await capture("mode-roleplay.png");

/* ---------- 3. the scenario cards fill the new-chat form ---------- */
await evaluate(`document.querySelector("#btnChatBack").click()`);
await sleep(450);
await evaluate(`document.querySelector("#btnNewChat").click()`);
await sleep(500);
const presetUi = await evaluate(`(() => ({
  chips: Array.from(document.querySelectorAll("#newChatPresets [data-preset]")).map((node) => node.dataset.preset),
  hint: document.querySelector("#newChatPresets")?.parentElement?.innerText?.slice(0, 40) || "",
}))()`);
check("roleplay offers the scenario cards", presetUi.chips.length === ROLEPLAY_PRESETS.length, `${presetUi.chips.length} chips`);
check("the first card is the inn scene", presetUi.chips[0] === "jianghu", presetUi.chips[0]);
await evaluate(`document.querySelector('[data-preset="jianghu"]').click()`);
await sleep(250);
const filled = await evaluate(`(() => ({
  name: document.querySelector("#newChatName").value,
  relation: document.querySelector("#newChatRelation").value,
  persona: document.querySelector("#newChatPersona").value.length,
  greeting: document.querySelector("#newChatGreeting").value,
  on: document.querySelector(".preset-chip.is-on")?.dataset.preset || "",
}))()`);
check("picking a card fills the form", filled.name === "沈砚" && filled.persona > 20 && filled.greeting.length > 0, JSON.stringify(filled).slice(0, 90));
check("the picked card is highlighted", filled.on === "jianghu", filled.on);
await capture("mode-presets.png");
await evaluate(`document.querySelector("[data-close-sheet]").click()`);
await sleep(300);

/* ---------- 4. assistant mode: theme + no stickers ---------- */
await evaluate(`document.querySelector('[data-tab="home"]').click()`);
await sleep(350);
await evaluate(`document.querySelector('[data-home-action="persona"]').click()`);
await sleep(600);
await evaluate(`(() => { const group = document.querySelector('[data-group="persona"]'); if (group) group.open = true; return true; })()`);
await sleep(200);
await evaluate(`document.querySelector('[data-mode="assistant"]').click()`);
await sleep(700);
state = await evaluate(`(() => ({
  mode: document.body.dataset.mode,
  theme: document.body.dataset.theme,
  accent: getComputedStyle(document.documentElement).getPropertyValue("--accent").trim(),
  stickerBtn: getComputedStyle(document.querySelector("#btnSticker")).display,
  actions: document.querySelectorAll(".msg-action").length,
}))()`);
check("assistant mode is on", state.mode === "assistant", state.mode);
check("assistant mode switches to the assistant theme", state.theme === "assistant", state.theme);
check("assistant mode hides the sticker button", state.stickerBtn === "none", state.stickerBtn);
check("assistant mode stops styling actions", state.actions === 0, String(state.actions));

await evaluate(`document.querySelector("#btnSettingsDone").click()`);
await sleep(400);
await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
await sleep(450);
await evaluate(`document.querySelector("#btnAttach").click()`);
await sleep(300);
const tray = await evaluate(`(() => ({
  stickerAction: getComputedStyle(document.querySelector('[data-tray="sticker"]')).display,
  emojiHead: getComputedStyle(document.querySelector("#trayEmojiHead")).display,
  emojiRow: getComputedStyle(document.querySelector("#trayEmoji")).display,
  actions: Array.from(document.querySelectorAll("[data-tray]")).filter((node) => getComputedStyle(node).display !== "none").map((node) => node.dataset.tray),
}))()`);
check("the tray has no sticker entry", tray.stickerAction === "none", JSON.stringify(tray.actions));
check("the tray has no emoji row", tray.emojiHead === "none" && tray.emojiRow === "none");
check("the tray keeps photo / file / recap / more", tray.actions.join(",") === "image,file,report,more", tray.actions.join(","));
await capture("mode-assistant.png");

/* ---------- 5. back to companion restores the theme ---------- */
await evaluate(`document.querySelector("#btnSettingsBack") ? document.querySelector("#btnSettingsBack").click() : document.querySelector("#btnChatBack").click()`);
await sleep(400);
await evaluate(`document.querySelector('[data-tab="home"]').click()`);
await sleep(350);
await evaluate(`document.querySelector('[data-home-action="persona"]').click()`);
await sleep(550);
await evaluate(`(() => { const group = document.querySelector('[data-group="persona"]'); if (group) group.open = true; return true; })()`);
await sleep(200);
await evaluate(`document.querySelector('[data-mode="companion"]').click()`);
await sleep(700);
const back = await evaluate(`({ mode: document.body.dataset.mode, theme: document.body.dataset.theme })`);
check("switching back restores companion", back.mode === "companion", back.mode);
check("switching back restores the old theme", back.theme === "paper", back.theme);

check("no console errors", consoleErrors.length === 0, consoleErrors.slice(0, 2).join(" | "));

const failed = results.filter((item) => !item.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
ws.close();
child.kill("SIGKILL");
server.close();
await sleep(150);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
process.exit(failed.length ? 1 : 0);
