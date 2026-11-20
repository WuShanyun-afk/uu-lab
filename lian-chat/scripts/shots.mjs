/* Capture the current screens (list / contacts / home / chat) as PNGs.
 *
 *   node scripts/shots.mjs [outDir]
 *
 * Reuses the boot-check harness style: static server + headless Edge + CDP.
 * Screenshots are written to docs/shots-*.png by default.
 */
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT = process.argv[2] ? path.resolve(process.argv[2]) : path.join(ROOT, "docs");
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
    "cache-control": "no-store",
  });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;
const base = `http://127.0.0.1:${port}/`;

const edge = [
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
].find((p) => fs.existsSync(p));
if (!edge) {
  console.error("SKIP: Microsoft Edge not found");
  process.exit(2);
}

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-shots-"));
const debugPort = 9800 + Math.floor(Math.random() * 150);
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
await send("Page.addScriptToEvaluateOnNewDocument", {
  source: `window.__bootDone = 0;
    new MutationObserver(() => {
      const boot = document.getElementById("boot");
      if (boot && boot.classList.contains("is-done") && !window.__bootDone) {
        window.__bootDone = Math.round(performance.now());
      }
    }).observe(document, { subtree: true, attributes: true, attributeFilter: ["class"] });`,
});
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
  const file = path.join(OUT, name);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, Buffer.from(result.data, "base64"));
  console.log(file);
};

const now = Date.now();
const seed = {
  onboarded: true,
  settings: {
    provider: "mimo", apiKey: "seed", baseUrl: "https://api.xiaomimimo.com/v1",
    model: "mimo-v2.6-flash", aiName: "沈言", userName: "小满",
    relationship: "认识三年的恋人", persona: "话少，克制，习惯先问对方有没有吃饭。",
    greeting: "你来啦。",
  },
  chats: [
    { id: "c1", name: "沈言", relationship: "认识三年的恋人", keyId: "k1", createdAt: now - 86400000, updatedAt: now - 60000,
      messages: [
        { id: "m1", role: "assistant", kind: "text", text: "会开完了，窗外的光很好。", ts: now - 3600000 },
        { id: "m2", role: "user", kind: "text", text: "今天有点累。", ts: now - 3000000 },
        { id: "m3", role: "assistant", kind: "text", text: "那就早点睡，手机放一边。", ts: now - 60000 },
        { id: "m4", role: "assistant", kind: "report", ts: now - 30000, report: {
          title: "窗边的下午",
          summary: "煎了两个蛋，窗外下了点雨。",
          blocks: [
            { text: "下午煎了两个蛋，蛋黄还是流心的。", scene: "egg" },
            { text: "吃完把窗推开，外面在下雨，风有点凉。", scene: "rain" },
            { text: "耳机里放着旧歌，忽然想起你说过的话。", scene: "music" },
          ],
          createdAt: now - 30000,
        } },
      ] },
    { id: "c2", name: "阿岚", relationship: "大学同学", keyId: "k1", createdAt: now - 172800000, updatedAt: now - 7200000,
      messages: [{ id: "n1", role: "assistant", kind: "text", text: "周末那家店我订好了。", ts: now - 7200000 }] },
    { id: "c3", name: "小满的树洞", relationship: "自言自语", keyId: "k1", createdAt: now - 259200000, updatedAt: now - 86400000, messages: [] },
  ],
  keys: [{ id: "k1", name: "MiMo", provider: "mimo", apiKey: "seed", baseUrl: "https://api.xiaomimimo.com/v1", model: "mimo-v2.6-flash", createdAt: now }],
  activeChatId: "c1",
  activeKeyId: "k1",
  messages: [],
  memories: [{ id: "mm1", text: "小满喝咖啡不加糖。", createdAt: now }],
  memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
};
// Keep chats in sync with the active chat requirement of the app.
seed.messages = seed.chats[0].messages;

await send("Page.navigate", { url: base });
await sleep(700);
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
console.log("boot to splash-gone:", await evaluate(`Math.round(window.__bootDone || 0)`), "ms (navigationStart → #boot.is-done)");

await evaluate(`document.querySelector('[data-tab="list"]')?.click()`);
await sleep(350);
await shot("shots-list.png");

await evaluate(`document.querySelector('[data-tab="contacts"]')?.click()`);
await sleep(350);
await shot("shots-contacts.png");

await evaluate(`document.querySelector('[data-tab="home"]')?.click()`);
await sleep(350);
await shot("shots-home.png");
const clip = await evaluate(`(() => {
  const el = document.querySelector(".home-scroll");
  const r = el.getBoundingClientRect();
  return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(el.scrollHeight), scale: 1 };
})()`);
const full = await send("Page.captureScreenshot", { format: "png", fromSurface: true, captureBeyondViewport: true, clip });
fs.writeFileSync(path.join(OUT, "shots-home-full.png"), Buffer.from(full.data, "base64"));
console.log(path.join(OUT, "shots-home-full.png"), `${clip.width}x${clip.height}`);

// Home must not rebuild its whole DOM when the tab is re-opened.
const cacheCheck = await evaluate(`(() => {
  window.__homeCard = document.querySelector(".home-user-card");
  document.querySelector('[data-tab="list"]').click();
  document.querySelector('[data-tab="home"]').click();
  const again = document.querySelector(".home-user-card");
  return { sameNode: again === window.__homeCard, childCount: document.querySelector("#homeBody").childElementCount };
})()`);
await sleep(250);
console.log("home DOM reused on re-entry:", JSON.stringify(cacheCheck));

await evaluate(`document.querySelector('[data-chat-open]')?.click()`);
await sleep(450);
await shot("shots-chat.png");

if (await evaluate(`!!document.querySelector("[data-report]")`)) {
  await evaluate(`document.querySelector("[data-report]").click()`);
  await sleep(700);
  await shot("shots-report.png");
  await evaluate(`document.querySelector("#reportDone")?.click()`);
}

ws.close();
child.kill("SIGKILL");
server.close();
await sleep(300);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
