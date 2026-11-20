/* 1.9.12 bug sweep: geometry, console errors, broken state.
 *
 *   node scripts/audit-check.mjs
 *
 * Walks all 8 layouts and all 15 themes, then the list / home / contacts
 * screens, an empty install and a deliberately corrupted state. Anything that
 * throws, overflows sideways, loses a tap target or prints to the console is
 * reported as FAIL. Writes docs/test-1.9.12-audit.png.
 */
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { CHAT_LAYOUTS, THEMES } from "../js/config.js";

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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-audit-"));
const debugPort = 9800 + Math.floor(Math.random() * 90);
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
let consoleErrors = [];
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
const check = (scope, name, ok, detail = "") => {
  results.push({ scope, name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} [${scope}] ${name}${detail ? ` — ${detail}` : ""}`);
};

const now = Date.now();
const messages = [
  { id: "m1", role: "assistant", kind: "text", text: "你来啦。外面比昨天冷。", ts: now - 5400000 },
  { id: "m2", role: "user", kind: "text", text: "今天降温了，我出门忘了带外套。", ts: now - 5280000 },
  { id: "m3", role: "assistant", kind: "text", text: "那你现在在哪儿，我去给你送。", ts: now - 5220000 },
  {
    id: "m4", role: "user", kind: "text", text: "晚上吃了碗热汤面，还加了个蛋。", ts: now - 600000,
    quote: { role: "assistant", text: "那你现在在哪儿，我去给你送。", name: "沈言" },
  },
  { id: "m5", role: "assistant", kind: "sticker", stickerId: "mk_shy", ts: now - 540000 },
  { id: "m6", role: "assistant", kind: "text", text: "吃了热的就行。", ts: now - 480000 },
];
const baseSeed = {
  onboarded: true,
  settings: {
    provider: "custom", apiKey: "seed", baseUrl: "http://127.0.0.1:1/v1", model: "m",
    aiName: "沈言", userName: "小满", relationship: "认识三年的恋人", persona: "话少，克制。",
    greeting: "你来啦。", theme: "paper", layout: "line",
  },
  chats: [{
    id: "c1", name: "沈言", relationship: "认识三年的恋人", keyId: "k1",
    createdAt: now - 86400000, updatedAt: now, messages,
  }],
  keys: [{ id: "k1", name: "Mock", provider: "custom", apiKey: "seed", baseUrl: "http://127.0.0.1:1/v1", model: "m", createdAt: now }],
  activeChatId: "c1", activeKeyId: "k1",
  messages,
  memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
};

/* the splash is removed 240ms after it fades, so "gone" also counts as booted */
const BOOTED = `!document.querySelector("#boot") || !!document.querySelector("#boot.is-done")`;

async function seedAndBoot(state, { openChat = true } = {}) {
  await send("Page.navigate", { url: base });
  await sleep(450);
  consoleErrors = [];
  await evaluate(`(async () => {
    localStorage.clear();
    await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
    localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(state))});
    return true;
  })()`);
  await send("Page.reload");
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (await evaluate(BOOTED)) break;
    await sleep(110);
  }
  await sleep(320);
  if (openChat) {
    await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
    await sleep(470);
  }
}

/* everything that is cheap to measure on the current screen */
const audit = () => evaluate(`(() => {
  const ids = Array.from(document.querySelectorAll("[id]")).map((node) => node.id);
  const dupes = [...new Set(ids.filter((value, index) => ids.indexOf(value) !== index))];
  const root = document.documentElement;
  const small = [];
  for (const node of document.querySelectorAll(".composer-btn, .send-btn, .tray-action, .tray-emoji-btn, .tray-emoji-tab, .icon-btn, .text-btn")) {
    const rect = node.getBoundingClientRect();
    if (!rect.width || !rect.height) continue;
    if (rect.height < 24 || rect.width < 24) small.push((node.id || node.className || node.tagName) + " " + Math.round(rect.width) + "x" + Math.round(rect.height));
  }
  const nameless = Array.from(document.querySelectorAll("button")).filter((node) => {
    const label = (node.getAttribute("aria-label") || node.innerText || "").trim();
    const hasIconText = node.querySelector("[data-i18n], .icon, svg");
    return !label && !hasIconText;
  }).length;
  return {
    overflow: root.scrollWidth - root.clientWidth,
    dupes,
    small,
    nameless,
    ids: ids.length,
    theme: document.body.dataset.theme || "",
    layout: document.body.dataset.layout || "",
    messages: document.querySelectorAll(".msg").length,
    accent: getComputedStyle(document.body).getPropertyValue("--accent").trim(),
  };
})()`);

/* text-on-bubble contrast, resolved from the live computed styles */
const bubbleContrast = () => evaluate(`(() => {
  const parse = (value) => {
    const rgb = String(value).match(/rgba?\\(([^)]+)\\)/);
    if (rgb) {
      const p = rgb[1].split(/[,\\s/]+/).filter(Boolean).map(Number);
      return [p[0], p[1], p[2], p[3] ?? 1];
    }
    const srgb = String(value).match(/color\\(srgb\\s+([^)]+)\\)/);
    if (srgb) {
      const p = srgb[1].split(/\\s+/).map(Number);
      return [p[0] * 255, p[1] * 255, p[2] * 255, p[3] ?? 1];
    }
    return null;
  };
  const lum = ([r, g, b]) => {
    const f = (c) => {
      const v = c / 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };
  const ratio = (a, b) => {
    const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
  };
  const out = {};
  for (const [key, selector] of [["ai", ".msg.ai .bubble"], ["user", ".msg.user .bubble"]]) {
    const node = document.querySelector(selector);
    if (!node) { out[key] = null; continue; }
    const style = getComputedStyle(node);
    const ink = parse(style.color);
    let bg = parse(style.backgroundColor);
    if (!bg || bg[3] < 0.5) {
      /* a transparent bubble (letter / plain layouts) sits on the chat sheet */
      const sheet = parse(getComputedStyle(document.querySelector("#chatScroll") || document.body).backgroundColor);
      bg = sheet;
    }
    out[key] = ink && bg ? Math.round(ratio(ink, bg) * 10) / 10 : null;
  }
  return out;
})()`);

/* tray geometry on the current chat screen */
const trayGeometry = () => evaluate(`(() => {
  const tray = document.querySelector("#composerTray");
  const input = document.querySelector("#composerRow");
  const box = document.querySelector("#trayEmoji");
  if (!tray || !input) return { missing: true };
  const t = tray.getBoundingClientRect();
  const i = input.getBoundingClientRect();
  const buttons = Array.from(box.querySelectorAll("[data-emoji]")).map((node) => node.getBoundingClientRect());
  const tabs = Array.from(document.querySelectorAll(".tray-emoji-tab")).map((node) => node.getBoundingClientRect());
  return {
    hidden: tray.hidden,
    trayTop: Math.round(t.top),
    trayBottom: Math.round(t.bottom),
    trayHeight: Math.round(t.height),
    inputBottom: Math.round(i.bottom),
    viewport: window.innerHeight,
    minEmoji: buttons.length ? Math.round(Math.min(...buttons.map((r) => Math.min(r.width, r.height)))) : 0,
    minTab: tabs.length ? Math.round(Math.min(...tabs.map((r) => r.height))) : 0,
    tabs: tabs.length,
  };
})()`);

function judge(scope, metrics, { expectLayout, expectTheme } = {}) {
  check(scope, "no sideways overflow", metrics.overflow <= 1, `overflow ${metrics.overflow}px`);
  check(scope, "no duplicate element ids", metrics.dupes.length === 0, metrics.dupes.join(","));
  check(scope, "no tap target under 24px", metrics.small.length === 0, metrics.small.slice(0, 3).join(" | "));
  check(scope, "console is clean", consoleErrors.length === 0, consoleErrors.slice(0, 2).join(" | "));
  if (expectLayout) check(scope, `layout is ${expectLayout}`, metrics.layout === expectLayout, metrics.layout);
  if (expectTheme) check(scope, `theme is ${expectTheme}`, metrics.theme === expectTheme, metrics.theme);
}

/* ---------- A. eight layouts, with the tray open ---------- */
for (const layout of CHAT_LAYOUTS.map((item) => item.id)) {
  await seedAndBoot({ ...baseSeed, settings: { ...baseSeed.settings, theme: "paper", layout } });
  const metrics = await audit();
  judge(`layout:${layout}`, metrics, { expectLayout: layout });
  await evaluate(`document.querySelector("#btnAttach").click()`);
  await sleep(240);
  const tray = await trayGeometry();
  check(`layout:${layout}`, "tray fits on screen", !tray.hidden && tray.trayTop >= 0 && tray.trayBottom <= tray.viewport, JSON.stringify(tray));
  check(`layout:${layout}`, "tray leaves the input on screen", tray.inputBottom <= tray.viewport + 1, `${tray.inputBottom}/${tray.viewport}`);
  check(`layout:${layout}`, "tray is not a wall of buttons", tray.trayHeight <= Math.round(tray.viewport * 0.45), `${tray.trayHeight}px`);
  check(`layout:${layout}`, "emoji buttons stay tappable", tray.minEmoji >= 32, `${tray.minEmoji}px`);
  check(`layout:${layout}`, "group chips stay tappable", tray.minTab >= 20, `${tray.minTab}px`);
  check(`layout:${layout}`, "group chips are there", tray.tabs === 5, String(tray.tabs));
  await evaluate(`document.querySelector("#btnAttach").click()`);
  await sleep(150);
}

/* ---------- B. fifteen themes ---------- */
for (const theme of THEMES) {
  await seedAndBoot({
    ...baseSeed,
    settings: { ...baseSeed.settings, theme: theme.id, accent: theme.accent, layout: "line" },
  });
  const metrics = await audit();
  judge(`theme:${theme.id}`, metrics, { expectTheme: theme.id });
  check(`theme:${theme.id}`, "accent token resolves", metrics.accent.length > 0, metrics.accent);
  const contrast = await bubbleContrast();
  for (const [side, value] of Object.entries(contrast)) {
    check(`theme:${theme.id}`, `${side} bubble text is readable`, value === null || value >= 3, `contrast ${value}`);
  }
}

/* ---------- C. list / home / contacts ---------- */
const threeChats = {
  ...baseSeed,
  chats: [0, 1, 2].map((index) => ({
    ...baseSeed.chats[0],
    id: `c${index}`,
    name: `沈言${index}`,
    unread: index,
    updatedAt: now - index * 3600000,
  })),
  activeChatId: "c0",
};
await seedAndBoot(threeChats, { openChat: false });
for (const [tab, label] of [["list", "chat list"], ["home", "home"], ["contacts", "contacts"]]) {
  await evaluate(`document.querySelector('[data-tab="${tab}"]').click()`);
  await sleep(420);
  const metrics = await audit();
  judge(`screen:${tab}`, metrics, {});
  check(`screen:${tab}`, `${label} actually rendered`, metrics.ids > 20, `${metrics.ids} ids`);
}

/* ---------- D. no chats at all, and a fresh install ---------- */
/* an onboarded install always keeps one chat: ensureChatState() rebuilds it */
await seedAndBoot({ ...baseSeed, chats: [], messages: [], activeChatId: "" }, { openChat: false });
await evaluate(`document.querySelector('[data-tab="list"]').click()`);
await sleep(450);
let metrics = await audit();
judge("no-chats", metrics, {});
const noChats = await evaluate(`(() => ({
  hero: !!document.querySelector("#listHero"),
  rows: document.querySelectorAll(".chat-row").length,
  empty: !!document.querySelector(".chat-list-empty"),
}))()`);
check("no-chats", "the hero renders", noChats.hero);
check("no-chats", "one chat is rebuilt instead of an empty list", noChats.rows === 1, JSON.stringify(noChats));
await evaluate(`document.querySelector('[data-tab="contacts"]').click()`);
await sleep(400);
metrics = await audit();
judge("no-chats:contacts", metrics, {});

/* a brand new install has to land on the setup screen, not a blank page */
await seedAndBoot({ ...baseSeed, onboarded: false, chats: [], messages: [], activeChatId: "" }, { openChat: false });
await sleep(500);
metrics = await audit();
judge("fresh", metrics, {});
const fresh = await evaluate(`(() => ({
  setup: !!document.querySelector("#setupScreen") && !document.querySelector("#setupScreen").hidden,
  booted: ${BOOTED},
  text: (document.body.innerText || "").trim().length,
}))()`);
check("fresh", "a new install opens on setup", fresh.setup && fresh.booted, JSON.stringify(fresh));
check("fresh", "setup is not a blank screen", fresh.text > 30, `${fresh.text} chars`);

/* ---------- E. corrupted state ---------- */
const broken = {
  ...baseSeed,
  messages: [
    { id: "b1", role: "user", kind: "text" }, // text missing
    { id: "b2", role: "assistant", kind: "text", text: null }, // null text
    { id: "b3", role: "assistant", kind: "sticker" }, // sticker missing
    { id: "b4", role: "assistant", kind: "image", image: {} }, // image without dataUrl
    { id: "b5", role: "user", kind: "file", file: { name: "a.pdf" } },
    { id: "b6", role: "assistant", kind: "nonsense", text: "??" }, // unknown kind
    { id: "b7", text: "no role", ts: now }, // no role at all
    { id: "b8", role: "user", kind: "text", text: "x".repeat(4000), ts: now },
    null, // null message
    { id: "b9", role: "assistant", kind: "text", text: "没事的。", ts: now },
  ],
};
await seedAndBoot({ ...broken, chats: [{ ...baseSeed.chats[0], messages: broken.messages }] });
metrics = await audit();
judge("corrupt", metrics, {});
check("corrupt", "the app still renders messages", metrics.messages > 0, `${metrics.messages} messages`);

/* ---------- F. a small phone and a tall one ---------- */
for (const [width, height, label] of [[320, 568, "320x568"], [430, 932, "430x932"]]) {
  await send("Emulation.setDeviceMetricsOverride", {
    width, height, deviceScaleFactor: 2, mobile: true, screenWidth: width, screenHeight: height,
  });
  await seedAndBoot({ ...baseSeed, settings: { ...baseSeed.settings, theme: "berry", layout: "imessage" } });
  const small = await audit();
  check(`screen:${label}`, "no sideways overflow", small.overflow <= 1, `overflow ${small.overflow}px`);
  await evaluate(`document.querySelector("#btnAttach").click()`);
  await sleep(240);
  const tray = await trayGeometry();
  check(`screen:${label}`, "tray fits on screen", tray.trayTop >= 0 && tray.trayBottom <= tray.viewport, JSON.stringify(tray));
  check(`screen:${label}`, "input stays visible", tray.inputBottom <= tray.viewport + 1, `${tray.inputBottom}/${tray.viewport}`);
  check(`screen:${label}`, "group chips stay tappable", tray.minTab >= 20, `${tray.minTab}px`);
  check(`screen:${label}`, "emoji buttons stay tappable", tray.minEmoji >= 32, `${tray.minEmoji}px`);
}
await send("Emulation.setDeviceMetricsOverride", {
  width: 390, height: 844, deviceScaleFactor: 2, mobile: true, screenWidth: 390, screenHeight: 844,
});
await seedAndBoot(baseSeed);
await evaluate(`document.querySelector("#btnAttach").click()`);
await sleep(260);

const shot = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
fs.writeFileSync(path.join(ROOT, "docs", "test-1.9.12-audit.png"), Buffer.from(shot.data, "base64"));

const failed = results.filter((item) => !item.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
if (failed.length) console.log(failed.map((item) => `- [${item.scope}] ${item.name} ${item.detail}`).join("\n"));
ws.close();
child.kill("SIGKILL");
server.close();
await sleep(150);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
process.exit(failed.length ? 1 : 0);
