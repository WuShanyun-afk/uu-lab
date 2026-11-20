/* Drive a real conversation through the app UI and capture screenshots.
 *
 *   LIAN_API_KEY=sk-... node scripts/chat-demo.mjs
 *
 * Writes docs/chat-live-*.png. The key is only read from the environment and
 * never written to disk.
 */
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { THEMES } from "../js/config.js";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const KEY = process.env.LIAN_API_KEY || process.env.MIMO_API_KEY || "";
const EXPR = process.env.DEMO_STYLE || ""; // optional CSS injected before shots
const THEME = process.env.DEMO_THEME || "line";
if (!KEY) {
  console.error("SKIP: set LIAN_API_KEY");
  process.exit(2);
}

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8", ".svg": "image/svg+xml",
  ".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp", ".woff2": "font/woff2",
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
  process.exit(2);
}

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-chatdemo-"));
const debugPort = 9600 + Math.floor(Math.random() * 200);
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
  } catch { /* not up */ }
  await sleep(150);
}
const page = targets.find((t) => t.type === "page");
const ws = new WebSocket(page.webSocketDebuggerUrl);
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
const shot = async (name) => {
  const result = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
  const file = path.join(ROOT, "docs", name);
  fs.writeFileSync(file, Buffer.from(result.data, "base64"));
  console.log("shot:", file);
};
const waitFor = async (expression, timeout, label) => {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if (await evaluate(expression)) return true;
    await sleep(150);
  }
  throw new Error(`timeout: ${label}`);
};

const now = Date.now();
const seed = {
  onboarded: true,
  settings: {
    provider: "mimo", apiKey: KEY, baseUrl: "https://api.xiaomimimo.com/v1",
    model: "mimo-v2.6-flash", aiName: "沈言", userName: "小满",
    relationship: "认识三年的恋人",
    persona: "话少，克制，习惯先问对方有没有吃饭。偶尔嘴硬，但很会照顾人。",
    greeting: "你来啦。今天过得怎么样？",
    theme: THEME,
    accent: THEMES.find((item) => item.id === THEME)?.accent || "#06C755",
  },
  chats: [{
    id: "c1", name: "沈言", relationship: "认识三年的恋人", keyId: "k1",
    createdAt: now - 86400000, updatedAt: now,
    messages: [{ id: "g1", role: "assistant", kind: "text", text: "你来啦。今天过得怎么样？", ts: now - 3600000 }],
  }],
  keys: [{ id: "k1", name: "MiMo", provider: "mimo", apiKey: KEY, baseUrl: "https://api.xiaomimimo.com/v1", model: "mimo-v2.6-flash", createdAt: now }],
  activeChatId: "c1", activeKeyId: "k1",
  messages: [{ id: "g1", role: "assistant", kind: "text", text: "你来啦。今天过得怎么样？", ts: now - 3600000 }],
  memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
};

await send("Page.navigate", { url: base });
await sleep(600);
await evaluate(`(async () => {
  localStorage.clear();
  await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
  localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(seed))});
  return true;
})()`);
await send("Page.reload");
await waitFor(`!!document.querySelector("#boot.is-done")`, 15000, "boot");
await sleep(300);
await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
await waitFor(`!!document.querySelector("#messageInput")`, 8000, "composer");

if (EXPR) {
  await evaluate(`(() => { const s = document.createElement("style"); s.textContent = ${JSON.stringify(EXPR)}; document.head.appendChild(s); return true; })()`);
  await sleep(300);
}

const turns = [
  { text: "今天降温了，我出门忘了带外套。", file: "chat-live-1.png" },
  { text: "晚上吃了碗热汤面，还加了个蛋。", file: "chat-live-2.png" },
  { text: "发张表情包给我，然后早点睡吧。", file: "chat-live-3.png" },
];

for (const turn of turns) {
  const before = await evaluate(`document.querySelectorAll(".msg.ai").length`);
  await evaluate(`(() => {
    const input = document.querySelector("#messageInput");
    input.value = ${JSON.stringify(turn.text)};
    input.dispatchEvent(new Event("input", { bubbles: true }));
    document.querySelector("#composer").requestSubmit();
    return true;
  })()`);
  await waitFor(`document.querySelectorAll(".msg.user").length >= 1`, 15000, "user bubble");
  await waitFor(
    `document.querySelectorAll(".msg.ai").length > ${before} || !!document.querySelector("#errorBar:not([hidden])")`,
    120000,
    "assistant reply",
  );
  await sleep(1800); // let the typing animation and bubbles settle
  const state = await evaluate(`(() => {
    const ai = [...document.querySelectorAll(".msg.ai")].at(-1);
    return {
      text: ai ? ai.innerText.trim().replace(/\\s+/g, " ").slice(0, 120) : "",
      sticker: !!document.querySelector(".msg.ai .msg-sticker"),
      error: (document.querySelector("#errorBar:not([hidden])") || {}).innerText || "",
    };
  })()`);
  console.log(`${turn.file}: ${JSON.stringify(state)}`);
  await shot(turn.file);
}

// Sticker panel, for the look of the picker.
await evaluate(`document.querySelector("#btnSticker")?.click()`);
await sleep(700);
await shot("chat-live-stickers.png");

ws.close();
child.kill("SIGKILL");
server.close();
await sleep(200);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
