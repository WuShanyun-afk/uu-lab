/* Render a fixed conversation twice: current theme vs. a proposed refresh.
 *
 *   node scripts/style-mock.mjs
 *
 * No API calls. Writes docs/style-{before,after}-{chat,home}.png
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
  ".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp", ".woff2": "font/woff2",
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const PROPOSAL = `
/* ---- proposed refresh: warmer paper, deeper green, softer depth ---- */
:root {
  --accent: #0d8b4d;
  --page: #f5f3ec;
  --chat-bg: #eef0e8;
  --radius: 20px;
  --shadow-sm: 0 1px 2px rgba(30, 25, 15, 0.05);
}
body { background: var(--page); }
.chat-screen {
  background:
    radial-gradient(120% 70% at 50% -20%, #ffffff 0%, rgba(255, 255, 255, 0) 55%),
    linear-gradient(180deg, #f2f1e9 0%, #e5e7de 100%);
}
.chat-screen::after {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  opacity: 0.5;
  background-image: radial-gradient(rgba(80, 70, 40, 0.055) 0.6px, transparent 0.6px);
  background-size: 3px 3px;
}
.chat-header {
  height: calc(60px + var(--safe-top));
  background: linear-gradient(180deg, rgba(252, 251, 246, 0.97), rgba(252, 251, 246, 0.84));
  border-bottom: 1px solid rgba(40, 35, 20, 0.06);
  box-shadow: 0 12px 30px -28px rgba(30, 25, 15, 0.7);
  backdrop-filter: blur(20px) saturate(1.05);
}
.peer-name { font-size: 15.5px; font-weight: 600; letter-spacing: 0.005em; }
.peer-status { font-size: 11px; color: #7c8172; }
.peer .avatar-40 { width: 42px; height: 42px; border-radius: 13px; }
.chat-inner { padding-top: 10px; }
.msg { padding: 4px 0; }
.msg .avatar { width: 30px; height: 30px; border-radius: 10px; }
.msg-time { font-size: 10.5px; color: rgba(56, 52, 40, 0.46); margin-bottom: 4px; }
.bubble { padding: 10px 13px; border-radius: 20px; font-size: 15px; line-height: 1.55; }
.msg.ai .bubble {
  background: linear-gradient(180deg, #fffefb, #fffdf8);
  border: 1px solid rgba(70, 60, 35, 0.07);
  box-shadow: 0 2px 4px rgba(40, 35, 20, 0.04), 0 14px 26px -22px rgba(40, 35, 20, 0.5);
  border-bottom-left-radius: 7px;
}
.msg.user .bubble {
  background: linear-gradient(165deg, #149b57, #0a7f45);
  box-shadow: 0 10px 22px -14px rgba(10, 127, 69, 0.8);
  border-bottom-right-radius: 7px;
}
.date-sep span {
  background: rgba(255, 255, 255, 0.72);
  border: 1px solid rgba(60, 55, 35, 0.06);
  color: #86847a;
  font-size: 10.5px;
  padding: 4px 12px;
  border-radius: 999px;
}
.composer {
  background: linear-gradient(180deg, rgba(247, 246, 240, 0), rgba(247, 246, 240, 0.92) 42%);
}
.composer-row {
  background: #fffefb;
  border: 1px solid rgba(60, 55, 35, 0.08);
  box-shadow: 0 12px 26px -22px rgba(40, 35, 20, 0.6);
}
#messageInput { font-size: 15px; }
.send-btn { background: linear-gradient(160deg, #149b57, #0a7f45); }
.msg-sticker { width: 132px; height: 132px; }
/* home */
.home-user-card {
  background: linear-gradient(165deg, #ffffff, #fbf9f2);
  border: 1px solid rgba(70, 60, 35, 0.06);
  box-shadow: 0 2px 6px rgba(40, 35, 20, 0.04), 0 24px 40px -34px rgba(40, 35, 20, 0.6);
}
.home-quick {
  background: linear-gradient(170deg, #fffefb, #f8f5ec);
  border: 1px solid rgba(70, 60, 35, 0.06);
}
.home-quick-icon { border-radius: 14px; }
.home-panel-head b { letter-spacing: 0.01em; }
.home-menu { background: #fffefb; border-color: rgba(70, 60, 35, 0.06); }
.home-eyebrow { font-size: 9.5px; letter-spacing: 0.14em; color: #9a978b; }
.tabbar {
  background: rgba(253, 252, 247, 0.94);
  border-top: 1px solid rgba(60, 55, 35, 0.06);
  box-shadow: 0 -14px 30px -28px rgba(30, 25, 15, 0.8);
}
.tab-item { font-size: 10px; }
`;

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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-style-"));
const debugPort = 9400 + Math.floor(Math.random() * 200);
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

const now = Date.now();
const messages = [
  { id: "m1", role: "assistant", kind: "text", text: "你来啦。今天过得怎么样？", ts: now - 5400000 },
  { id: "m2", role: "user", kind: "text", text: "今天降温了，我出门忘了带外套。", ts: now - 5280000 },
  { id: "m3", role: "assistant", kind: "text", text: "那你现在在哪儿，我去给你送。", ts: now - 5220000 },
  { id: "m4", role: "user", kind: "text", text: "晚上吃了碗热汤面，还加了个蛋。", ts: now - 600000 },
  { id: "m5", role: "assistant", kind: "text", text: "吃了热的就行。地方发我，我去送。", ts: now - 540000 },
  { id: "m6", role: "user", kind: "text", text: "发张表情包给我，然后早点睡吧。", ts: now - 480000 },
  { id: "m7", role: "assistant", kind: "text", text: "那你等着，我送完再说。", ts: now - 420000 },
  { id: "m8", role: "assistant", kind: "sticker", stickerId: "mk_shy", ts: now - 360000 },
];
const seed = {
  onboarded: true,
  settings: {
    provider: "mimo", apiKey: "seed", baseUrl: "https://api.xiaomimimo.com/v1",
    model: "mimo-v2.6-flash", aiName: "沈言", userName: "小满",
    relationship: "认识三年的恋人", persona: "话少，克制。", greeting: "你来啦。",
  },
  chats: [{
    id: "c1", name: "沈言", relationship: "认识三年的恋人", keyId: "k1",
    createdAt: now - 86400000, updatedAt: now, messages,
  }],
  keys: [{ id: "k1", name: "MiMo", provider: "mimo", apiKey: "seed", baseUrl: "https://api.xiaomimimo.com/v1", model: "mimo-v2.6-flash", createdAt: now }],
  activeChatId: "c1", activeKeyId: "k1", messages,
  memories: [{ id: "mm1", text: "小满喝咖啡不加糖。", createdAt: now }],
  memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
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
for (let attempt = 0; attempt < 100; attempt += 1) {
  if (await evaluate(`!!document.querySelector("#boot.is-done")`)) break;
  await sleep(120);
}
await sleep(400);

await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
await sleep(600);
await shot("style-before-chat.png");
await evaluate(`document.querySelector("#btnChatBack")?.click(); document.querySelector('[data-tab="home"]')?.click()`);
await sleep(400);
await shot("style-before-home.png");

await evaluate(`(() => { const s = document.createElement("style"); s.id = "proposal"; s.textContent = ${JSON.stringify(PROPOSAL)}; document.head.appendChild(s); return true; })()`);
await sleep(400);
await shot("style-after-home.png");
await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
await sleep(600);
await shot("style-after-chat.png");

ws.close();
child.kill("SIGKILL");
server.close();
await sleep(200);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
