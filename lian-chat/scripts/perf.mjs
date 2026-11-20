/* Front-end performance probe.
 *
 *   node scripts/perf.mjs
 *
 * Reports first-load weight, boot timings, long tasks, and how long it takes to
 * switch into a 400-message chat. Numbers are from headless Edge on this
 * machine, so treat them as relative, not absolute.
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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-perf-"));
const debugPort = 9700 + Math.floor(Math.random() * 120);
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
await send("Page.addScriptToEvaluateOnNewDocument", {
  source: `window.__longTasks = [];
    window.__bootDone = 0;
    try {
      new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) window.__longTasks.push(Math.round(entry.duration));
      }).observe({ entryTypes: ["longtask"] });
    } catch {}
    new MutationObserver(() => {
      const boot = document.getElementById("boot");
      if (boot && boot.classList.contains("is-done") && !window.__bootDone) window.__bootDone = Math.round(performance.now());
    }).observe(document, { subtree: true, attributes: true, attributeFilter: ["class"] });`,
});
const evaluate = async (expression) => {
  const result = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true, userGesture: true });
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || "eval failed");
  return result.result?.value;
};

const now = Date.now();
const messages = Array.from({ length: 400 }, (_, index) => ({
  id: `m${index}`,
  role: index % 2 ? "assistant" : "user",
  kind: "text",
  text: index % 7 === 0 ? "这句话稍长一点，用来模拟真实聊天里那种两三行的消息，看看渲染成本。" : `第 ${index} 条消息。`,
  ts: now - (400 - index) * 60000,
}));
const seed = {
  onboarded: true,
  settings: {
    provider: "mimo", apiKey: "seed", baseUrl: "https://api.xiaomimimo.com/v1",
    model: "mimo-v2.6-flash", aiName: "沈言", userName: "小满",
    relationship: "认识三年的恋人", persona: "话少，克制。", greeting: "你来啦。",
  },
  chats: [
    { id: "c1", name: "沈言", relationship: "恋人", keyId: "k1", createdAt: now - 86400000, updatedAt: now, messages },
    { id: "c2", name: "阿岚", relationship: "大学同学", keyId: "k1", createdAt: now - 172800000, updatedAt: now - 7200000, messages: [] },
  ],
  keys: [{ id: "k1", name: "MiMo", provider: "mimo", apiKey: "seed", baseUrl: "https://api.xiaomimimo.com/v1", model: "mimo-v2.6-flash", createdAt: now }],
  activeChatId: "c1", activeKeyId: "k1", messages,
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
const navStart = Date.now();
await send("Page.reload");
for (let attempt = 0; attempt < 200; attempt += 1) {
  if (await evaluate(`!!document.querySelector("#boot.is-done")`)) break;
  await sleep(60);
}
await sleep(600);

const report = await evaluate(`(() => {
  const nav = performance.getEntriesByType("navigation")[0] || {};
  const paint = Object.fromEntries(performance.getEntriesByType("paint").map((p) => [p.name, Math.round(p.startTime)]));
  const resources = performance.getEntriesByType("resource");
  const total = resources.reduce((sum, r) => sum + (r.transferSize || 0), 0);
  const byType = {};
  for (const r of resources) {
    const ext = (r.name.split("?")[0].match(/\\.[a-z0-9]+$/i) || ["?"])[0];
    byType[ext] = byType[ext] || { count: 0, bytes: 0 };
    byType[ext].count += 1;
    byType[ext].bytes += r.transferSize || 0;
  }
  const heaviest = resources
    .map((r) => ({ name: r.name.split("/").pop(), bytes: r.transferSize || 0, ms: Math.round(r.duration) }))
    .sort((a, b) => b.bytes - a.bytes)
    .slice(0, 8);
  return {
    domContentLoaded: Math.round(nav.domContentLoadedEventEnd || 0),
    load: Math.round(nav.loadEventEnd || 0),
    bootDone: window.__bootDone,
    paint,
    totalTransfer: total,
    requestCount: resources.length,
    byType,
    heaviest,
    longTasks: window.__longTasks,
  };
})()`);

const switchCost = await evaluate(`(async () => {
  const once = (fn) => {
    const t0 = performance.now();
    fn();
    document.body.offsetHeight; // force layout
    return performance.now() - t0;
  };
  const median = (fn) => {
    const runs = [];
    for (let i = 0; i < 5; i += 1) runs.push(once(fn));
    runs.sort((a, b) => a - b);
    return Math.round(runs[2] * 10) / 10;
  };
  const chatRow = () => [...document.querySelectorAll('[data-chat-open]')].find((el) => el.textContent.includes("沈言"));
  const otherRow = () => [...document.querySelectorAll('[data-chat-open]')].find((el) => el.textContent.includes("阿岚"));
  const back = () => document.querySelector("#btnChatBack");
  const home = () => document.querySelector('[data-tab="home"]');
  const list = () => document.querySelector('[data-tab="list"]');
  const out = {};
  // Cold open: the first time this chat is rendered after boot.
  out.firstOpen = Math.round(once(() => chatRow().click()) * 10) / 10;
  // Coming back to the same chat: the DOM is already there.
  out.reopenSame = median(() => { back().click(); chatRow().click(); });
  // Switching between two chats forces a rebuild of the window.
  out.switchChat = median(() => { back().click(); otherRow().click(); back().click(); chatRow().click(); });
  out.chatToList = median(() => { back().click(); });
  out.homeFirst = median(() => { list().click(); home().click(); });
  out.openSettings = median(() => { list().click(); home().click(); document.querySelector('[data-home-action="persona"]').click(); });
  out.closeSettings = median(() => { document.querySelector("#btnSettingsBack").click(); });
  const dom = document.querySelectorAll("#messageList .msg").length;
  return { ...out, renderedMessages: dom, listNodes: document.querySelector("#messageList").childElementCount };
})()`);

const stateBytes = await evaluate(`(async () => {
  const value = await new Promise((resolve) => {
    const req = indexedDB.open("lian-chat", 2);
    req.onsuccess = () => {
      const db = req.result;
      const get = db.transaction("state", "readonly").objectStore("state").get("main");
      get.onsuccess = () => resolve(get.result || null);
      get.onerror = () => resolve(null);
    };
    req.onerror = () => resolve(null);
  });
  if (!value) return null;
  return { jsonKB: Math.round(JSON.stringify(value).length / 1024), messages: (value.chats || []).reduce((n, c) => n + (c.messages || []).length, 0) };
})()`);

console.log("first load (390x844, fresh profile)");
console.log(`  DOMContentLoaded      ${report.domContentLoaded} ms`);
console.log(`  load                  ${report.load} ms`);
console.log(`  splash gone           ${report.bootDone} ms`);
console.log(`  first paint           ${report.paint["first-paint"] ?? "-"} ms / contentful ${report.paint["first-contentful-paint"] ?? "-"} ms`);
console.log(`  transferred           ${(report.totalTransfer / 1024).toFixed(1)} KB in ${report.requestCount} requests`);
console.log("  by type:              " + Object.entries(report.byType).map(([k, v]) => `${k} ${v.count}/${(v.bytes / 1024).toFixed(0)}KB`).join(", "));
console.log("  heaviest:");
for (const item of report.heaviest) console.log(`    ${String(item.bytes / 1024).padStart(7)} KB  ${String(item.ms).padStart(4)} ms  ${item.name}`);
console.log(`  long tasks (>50ms)    ${report.longTasks.length}: ${report.longTasks.join(", ") || "none"}`);
console.log("interaction (render + layout, 400-message chat)");
for (const [key, value] of Object.entries(switchCost)) {
  if (typeof value === "number") console.log(`  ${key.padEnd(20)} ${value} ms`);
}
console.log(`  rendered messages     ${switchCost.renderedMessages} nodes`);
console.log(`  persisted state       ${stateBytes ? stateBytes.jsonKB + " KB (" + stateBytes.messages + " messages)" : "not saved yet"}`);

const earlier = await evaluate(`(() => {
  const button = document.querySelector("[data-load-earlier]");
  if (!button) return { hasButton: false, rendered: document.querySelectorAll("#messageList .msg").length };
  const before = document.querySelectorAll("#messageList .msg").length;
  const t0 = performance.now();
  button.click();
  document.body.offsetHeight;
  return {
    hasButton: true,
    ms: Math.round((performance.now() - t0) * 10) / 10,
    before,
    after: document.querySelectorAll("#messageList .msg").length,
  };
})()`);
console.log(`  load earlier          ${earlier.hasButton ? `${earlier.ms} ms, ${earlier.before} → ${earlier.after} messages` : "no button (all rendered)"}`);

ws.close();
child.kill("SIGKILL");
server.close();
await sleep(300);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
