/* Per-module visual + metric check for the 1.9.4 UI modules.
 *
 *   node scripts/module-shots.mjs --out m1 --theme line
 *   node scripts/module-shots.mjs --out m9 --theme paper --dark
 *
 * No network, no API key: seeds a fixed conversation into the localStorage
 * fallback store, opens it, and writes docs/mod-<out>-{chat,home,list}.png
 * plus a JSON block of computed metrics on stdout.
 */
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { THEMES } from "../js/config.js";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8", ".svg": "image/svg+xml",
  ".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp", ".woff2": "font/woff2",
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const argv = process.argv.slice(2);
const arg = (name, fallback = "") => {
  const hit = argv.find((item) => item.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};
const theme = arg("theme", "line");
const out = arg("out", "check");
const dark = argv.includes("--dark");
const label = arg("label", `${theme}${dark ? "-dark" : ""}`);

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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-mod-"));
const debugPort = 9600 + Math.floor(Math.random() * 300);
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
if (argv.includes("--dark")) {
  await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] });
}
if (argv.includes("--bridge")) {
  await send("Page.addScriptToEvaluateOnNewDocument", {
    source: "window.__barCalls = []; window.LianNative = { setSystemBars: function (c, d) { window.__barCalls.push([c, !!d]); } };",
  });
}
const evaluate = async (expression) => {
  const result = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true, userGesture: true });
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || "eval failed");
  return result.result?.value;
};
const shot = async (view) => {
  const result = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
  const file = path.join(ROOT, "docs", `mod-${out}-${view}.png`);
  fs.writeFileSync(file, Buffer.from(result.data, "base64"));
  return `docs/mod-${out}-${view}.png`;
};

const now = Date.now();
const messages = [
  { id: "m1", role: "assistant", kind: "text", text: "你来啦。今天过得怎么样？", ts: now - 5400000 },
  { id: "m2", role: "user", kind: "text", text: "今天降温了，我出门忘了带外套。", ts: now - 5280000 },
  { id: "m3", role: "assistant", kind: "text", text: "那你现在在哪儿，我去给你送。", ts: now - 5220000 },
  { id: "m4", role: "user", kind: "text", text: "晚上吃了碗热汤面，还加了个蛋。", ts: now - 600000 },
  { id: "m5", role: "assistant", kind: "text", text: "吃了热的就行。地方发我，我去送。多一点字，看看换行和气泡宽度是不是顶到边上了。", ts: now - 540000 },
  { id: "m6", role: "assistant", kind: "text", text: "记得把地址发我。", ts: now - 520000 },
  { id: "m7", role: "assistant", kind: "text", text: "我先出门了。", ts: now - 500000 },
  { id: "m8", role: "user", kind: "text", text: "发张表情包给我，然后早点睡吧。", ts: now - 480000 },
  { id: "m9", role: "assistant", kind: "text", text: "那你等着，我送完再说。", ts: now - 420000 },
  { id: "m10", role: "assistant", kind: "sticker", stickerId: "mk_shy", ts: now - 360000 },
];
const seed = {
  onboarded: true,
  settings: {
    provider: "mimo", apiKey: "seed", baseUrl: "https://api.xiaomimimo.com/v1",
    model: "mimo-v2.6-flash", aiName: "沈言", userName: "小满",
    relationship: "认识三年的恋人", persona: "话少，克制。", greeting: "你来啦。",
    theme,
    accent: THEMES.find((item) => item.id === theme)?.accent || "#06C755",
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
for (let attempt = 0; attempt < 120; attempt += 1) {
  if (await evaluate(`!!document.querySelector("#boot.is-done")`)) break;
  await sleep(100);
}
await sleep(450);

const METRICS = String.raw`(() => {
  const one = (sel) => document.querySelector(sel);
  const all = (sel) => Array.from(document.querySelectorAll(sel));
  const cs = (sel, prop) => { const el = one(sel); if (!el) return null; const v = getComputedStyle(el)[prop]; return v === undefined ? null : v; };
  const num = (sel, prop) => { const v = cs(sel, prop); return v ? Math.round(parseFloat(v) * 10) / 10 : null; };
  const rootStyle = getComputedStyle(document.documentElement);
  const msgAvatars = all(".msg.ai .avatar").filter((el) => {
    const s = getComputedStyle(el);
    return s.visibility !== "hidden" && s.display !== "none" && el.getBoundingClientRect().width > 1;
  }).length;
  const userBubbles = all(".msg.user .bubble");
  const aiBubbles = all(".msg.ai .bubble");
  const widest = userBubbles.concat(aiBubbles).reduce((max, el) => Math.max(max, el.getBoundingClientRect().width), 0);
  const innerWidth = (one("#messageList") || { clientWidth: 1 }).clientWidth || 1;
  const chatScreen = one(".chat-screen");
  return {
    theme: document.body.dataset.theme || "",
    screen: document.body.dataset.screen || "",
    darkQuery: window.matchMedia("(prefers-color-scheme: dark)").matches,
    fontSize: {
      msgTime: num(".msg-time", "fontSize"),
      bubble: num(".msg .bubble", "fontSize"),
      peerName: num(".peer-name", "fontSize"),
      peerStatus: num(".peer-status", "fontSize"),
      dateSep: num(".date-sep span", "fontSize"),
      tabItem: num(".tab-item", "fontSize"),
      input: num("#messageInput", "fontSize"),
    },
    homeFontSize: {
      eyebrow: num(".home-eyebrow", "fontSize"),
      foot: num(".home-foot", "fontSize"),
      statSmall: num(".home-stats small", "fontSize"),
      quickSmall: num(".home-quick small", "fontSize"),
      rowSmall: num(".home-row-copy small", "fontSize"),
      panelSmall: num(".home-panel-head small", "fontSize"),
    },
    radius: {
      bubble: num(".msg .bubble", "borderTopLeftRadius"),
      bubbleTailAi: num(".msg.ai .bubble", "borderBottomLeftRadius"),
      bubbleTailUser: num(".msg.user .bubble", "borderBottomRightRadius"),
      card: num(".home-user-card", "borderTopLeftRadius"),
    },
    vars: {
      accent: rootStyle.getPropertyValue("--accent").trim(),
      bubbleMine: rootStyle.getPropertyValue("--bubble-mine").trim(),
      bubbleMineInk: rootStyle.getPropertyValue("--bubble-mine-ink").trim(),
      userBubble: rootStyle.getPropertyValue("--user-bubble").trim(),
      chatBg: rootStyle.getPropertyValue("--chat-bg").trim(),
    },
    bubbles: {
      bg: cs(".msg.ai .bubble", "backgroundColor"),
      image: String(cs(".msg.ai .bubble", "backgroundImage") || "").slice(0, 60),
      userBg: cs(".msg.user .bubble", "backgroundColor"),
      widestPct: Math.round((widest / innerWidth) * 1000) / 10,
      padding: cs(".msg .bubble", "padding"),
    },
    counts: {
      msgs: all(".msg").length,
      grouped: all(".msg.is-grouped").length,
      aiAvatars: msgAvatars,
      stickers: all(".msg-sticker").length,
    },
    stickerWidth: num(".msg-sticker", "width"),
    chatBackground: chatScreen ? String(getComputedStyle(chatScreen).backgroundImage).slice(0, 80) : null,
    chatBaseColor: chatScreen ? getComputedStyle(chatScreen).backgroundColor : null,
    input: {
      bg: cs("#messageInput", "backgroundColor"),
      radius: num("#messageInput", "borderTopLeftRadius"),
      card: cs(".composer-row", "backgroundColor"),
      cardRadius: num(".composer-row", "borderTopLeftRadius"),
      cardShadow: String(cs(".composer-row", "boxShadow") || "").slice(0, 40),
      composerBg: String(cs(".composer", "backgroundImage") || "").slice(0, 50),
    },
    quickIconBg: cs(".home-quick-icon", "backgroundColor"),    quickIconRadius: num(".home-quick-icon", "borderRadius"),
    rowIconBg: cs(".home-row-icon", "backgroundColor"),
    rowIconRadius: num(".home-row-icon", "borderRadius"),
    bodyBg: getComputedStyle(document.body).backgroundColor,
    reducedMotion: window.matchMedia("(prefers-reduced-motion: reduce)").matches,
    metaThemeColor: (document.querySelector('meta[name="theme-color"]') || {}).content || "",
    barCalls: Array.isArray(window.__barCalls) ? window.__barCalls.slice(-3) : null,
    colorScheme: getComputedStyle(document.body).colorScheme,
    smallText: (() => {
      let count = 0;
      let min = Infinity;
      let sample = "";
      const offenders = [];
      for (const el of document.querySelectorAll("body *")) {
        const s = getComputedStyle(el);
        if (s.display === "none" || s.visibility === "hidden") continue;
        const text = (el.textContent || "").trim();
        if (!text) continue;
        if (el.children.length && Array.from(el.children).some((c) => (c.textContent || "").trim())) continue;
        const size = parseFloat(s.fontSize);
        if (!size) continue;
        if (size < min) { min = size; sample = (typeof el.className === "string" ? el.className : el.tagName).slice(0, 40); }
        if (size < 10) {
          count += 1;
          if (offenders.length < 6) {
            offenders.push({
              tag: el.tagName.toLowerCase(),
              cls: (typeof el.className === "string" ? el.className : "").slice(0, 40),
              size,
              text: text.slice(0, 16),
            });
          }
        }
      }
      return { count, min: min === Infinity ? null : min, sample, offenders };
    })(),
  };
})()`;

const chatMetrics = await evaluate(`document.querySelector("[data-chat-open]") ? true : false`);
if (!chatMetrics) throw new Error("chat row not found");
await evaluate(`document.querySelector("[data-chat-open]").click()`);
await sleep(700);
const metrics = await evaluate(METRICS);
const chatShot = await shot("chat");

await evaluate(`document.querySelector("#btnChatBack").click()`);
await sleep(350);
const listShot = await shot("list");
await evaluate(`document.querySelector('[data-tab="home"]').click()`);
await sleep(450);
const homeMetrics = await evaluate(METRICS);
const homeShot = await shot("home");

await evaluate(`document.querySelector('.home-row[data-home-action="appearance"]')?.click()`);
await sleep(550);
const settingsShot = await shot("settings");

console.log(JSON.stringify({ label, out, theme, dark, shots: { chatShot, homeShot, listShot, settingsShot }, chat: metrics, home: homeMetrics }, null, 2));

ws.close();
child.kill("SIGKILL");
server.close();
await sleep(150);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
