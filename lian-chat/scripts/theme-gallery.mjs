/* Theme / layout gallery for the 2.0 appearance work.
 *
 *   node scripts/theme-gallery.mjs            # everything
 *   node scripts/theme-gallery.mjs themes     # only the theme grid
 *   node scripts/theme-gallery.mjs variants   # only bubble / density / avatar
 *
 * No API calls, no network beyond 127.0.0.1. Writes docs/theme-*.png.
 */
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { THEMES } from "../js/config.js";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MODE = process.argv[2] || "all";
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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-gallery-"));
const debugPort = 9500 + Math.floor(Math.random() * 200);
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
const shot = async (name) => {
  const result = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
  const file = path.join(ROOT, "docs", name);
  fs.writeFileSync(file, Buffer.from(result.data, "base64"));
  console.log("shot:", name);
};

const now = Date.now();
const messages = [
  { id: "m1", role: "assistant", kind: "text", text: "你来啦。外面比昨天冷。", ts: now - 5400000 },
  { id: "m2", role: "user", kind: "text", text: "今天降温了，我出门忘了带外套。", ts: now - 5280000 },
  { id: "m3", role: "assistant", kind: "text", text: "那你现在在哪儿，我去给你送。", ts: now - 5220000 },
  { id: "m4", role: "user", kind: "text", text: "晚上吃了碗热汤面，还加了个蛋。", ts: now - 600000 },
  { id: "m5", role: "assistant", kind: "text", text: "吃了热的就行。地方发我，我去送。", ts: now - 540000 },
  {
    id: "m6", role: "user", kind: "text", text: "发张表情包给我，然后早点睡吧。", ts: now - 480000,
    quote: { role: "assistant", text: "吃了热的就行。地方发我，我去送。", name: "沈言" },
  },
  { id: "m7", role: "assistant", kind: "text", text: "那你等着，我送完再说。", ts: now - 420000 },
  { id: "m8", role: "assistant", kind: "sticker", stickerId: "mk_shy", ts: now - 360000 },
];
const seed = {
  onboarded: true,
  settings: {
    provider: "mimo", apiKey: "seed", baseUrl: "https://api.xiaomimimo.com/v1",
    model: "mimo-v2.6-flash", aiName: "沈言", userName: "小满",
    relationship: "认识三年的恋人", persona: "话少，克制。", greeting: "你来啦。",
    theme: "line", accent: "#06C755", font: "sans",
    layout: "line",
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

async function bootWith(settings, { openChat = true } = {}) {
  const next = { ...seed, settings: { ...seed.settings, ...settings } };
  if (settings.theme) {
    const theme = THEMES.find((t) => t.id === settings.theme);
    if (theme) next.settings.accent = theme.accent;
  }
  await send("Page.navigate", { url: base });
  await sleep(600);
  await evaluate(`(async () => {
    localStorage.clear();
    await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
    localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(next))});
    return true;
  })()`);
  await send("Page.reload");
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (await evaluate(`!!document.querySelector("#boot.is-done")`)) break;
    await sleep(120);
  }
  await sleep(350);
  if (!openChat) {
    await sleep(400);
    return;
  }
  await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
  for (let attempt = 0; attempt < 60; attempt += 1) {
    if (await evaluate(`!!document.querySelector("#messageInput")`)) break;
    await sleep(100);
  }
  await sleep(450);
  await evaluate(`(() => { const s = document.querySelector("#chatScroll"); if (s) s.scrollTop = s.scrollHeight; return true; })()`);
  await sleep(250);
}

if (MODE === "all" || MODE === "themes") {
  for (const theme of THEMES) {
    await bootWith({ theme: theme.id });
    await shot(`theme-${theme.id}.png`);
  }
}

if (MODE === "all" || MODE === "layouts") {
  /* one shot per layout, each paired with a colour theme that suits it */
  for (const [layout, theme] of [
    ["line", "paper"],
    ["imessage", "sky"],
    ["letter", "dawn"],
    ["bubble", "lilac"],
    ["plain", "mono"],
    ["journal", "butter"],
    ["timeline", "ocean"],
    ["comic", "sakura"],
  ]) {
    await bootWith({ theme, layout });
    if (layout === "letter") {
      /* the crest only lives at the very top of the sheet */
      await evaluate(`(() => { const s = document.querySelector("#chatScroll"); if (s) s.scrollTop = 0; return true; })()`);
      await sleep(300);
      await shot("layout-letter-top.png");
      await evaluate(`(() => { const s = document.querySelector("#chatScroll"); if (s) s.scrollTop = s.scrollHeight; return true; })()`);
      await sleep(300);
    }
    await shot(`layout-${layout}.png`);
  }
}
if (MODE === "all" || MODE === "settings") {
  await bootWith({ theme: "berry" });
  await evaluate(`document.querySelector("#btnChatBack")?.click(); document.querySelector('[data-tab="home"]')?.click()`);
  await sleep(500);
  await evaluate(`document.querySelector('[data-home-action="persona"]')?.click()`);
  await sleep(700);
  await evaluate(`(() => {
    const group = document.querySelector('[data-group="appearance"]');
    if (!group) return false;
    group.open = true;
    group.scrollIntoView({ block: "start" });
    return true;
  })()`);
  await sleep(600);
  await shot("theme-settings.png");
}

if (MODE === "all" || MODE === "pick") {
  await bootWith({ theme: "paper" });
  await evaluate(`document.querySelector("#btnChatBack")?.click(); document.querySelector('[data-tab="home"]')?.click()`);
  await sleep(450);
  await evaluate(`document.querySelector('[data-home-action="persona"]')?.click()`);
  await sleep(650);
  const picked = await evaluate(`(() => {
    const group = document.querySelector('[data-group="appearance"]');
    if (!group) return { ok: false, why: "no appearance group" };
    group.open = true;
    group.scrollIntoView({ block: "start" });
    const chip = group.querySelector('[data-layout="letter"]');
    if (!chip) return { ok: false, why: "layout chip missing" };
    chip.click();
    return { ok: true, why: "", layout: document.body.dataset.layout, crest: !document.querySelector("#chatCrest")?.hidden };
  })()`);
  console.log("picked:", JSON.stringify(picked));
  await sleep(400);
  await shot("theme-settings-picked.png");
  await evaluate(`document.querySelector("#btnSettingsBack")?.click()`);
  await sleep(350);
  await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
  await sleep(700);
  await shot("layout-letter-picked.png");
  /* reload: the choice must come back from storage, not just the live class */
  await send("Page.reload");
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (await evaluate(`!!document.querySelector("#boot.is-done")`)) break;
    await sleep(120);
  }
  const after = await evaluate(`(() => ({
    layout: document.body.dataset.layout,
    crest: !document.querySelector("#chatCrest")?.hidden,
    names: [...document.querySelectorAll(".msg-name")].slice(0, 2).map((el) => el.textContent),
  }))()`);
  console.log("after reload:", JSON.stringify(after));
  if (!picked.ok || after.layout !== "letter" || !after.crest) {
    console.log("FAIL: layout choice did not persist");
    process.exitCode = 1;
  }
}

if (MODE === "all" || MODE === "screens") {
  /* 列表 / 主页 / 通讯录 / 色号：需要几条真实一点的数据 */
  const t0 = Date.now();
  const days = (n) => t0 - n * 86400000;
  const line = (id, role, text, ts) => ({ id, role, kind: "text", text, ts });
  seed.chats = [
    {
      id: "s1", name: "沈言", relationship: "认识三年的恋人", keyId: "k1",
      createdAt: days(40), updatedAt: t0 - 6 * 60000, unread: 0,
      messages: [
        line("s1a", "assistant", "你来啦。外面比昨天冷。", days(2)),
        line("s1b", "user", "今天降温了，我出门忘了带外套。", days(1)),
        line("s1c", "assistant", "那你现在在哪儿，我去给你送。", days(1)),
        line("s1d", "user", "晚上吃了碗热汤面，还加了个蛋。", t0 - 3600000),
        line("s1e", "assistant", "吃了热的就行。地方发我，我去送。", t0 - 6 * 60000),
      ],
      memories: [{ id: "m1", text: "小满喝咖啡不加糖。", createdAt: days(30) }],
    },
    {
      id: "s2", name: "夏目", relationship: "同校的学弟", keyId: "k1",
      createdAt: days(12), updatedAt: t0 - 3 * 3600000, unread: 2,
      messages: [
        line("s2a", "assistant", "学姐，图书馆那本借我一下可以吗？", t0 - 4 * 3600000),
        line("s2b", "assistant", "我明天就还你。", t0 - 3 * 3600000),
      ],
      memories: [],
    },
    {
      id: "s3", name: "老周", relationship: "开面馆的邻居", keyId: "k1",
      createdAt: days(60), updatedAt: days(2), unread: 0,
      messages: [line("s3a", "assistant", "汤底今天熬得久，来一碗？", days(2))],
      memories: [],
    },
  ];
  seed.activeChatId = "s1";
  seed.messages = seed.chats[0].messages;

  await bootWith({ theme: "paper" }, { openChat: false });
  await shot("screen-list.png");
  await evaluate(`document.querySelector('[data-list-filter="unread"]')?.click()`);
  await sleep(350);
  await shot("screen-list-unread.png");

  await evaluate(`document.querySelector('[data-tab="home"]')?.click()`);
  await sleep(600);
  await shot("screen-home.png");
  await evaluate(`document.querySelector('[data-daily-shuffle]')?.click()`);
  await sleep(350);
  await shot("screen-home-daily.png");
  await evaluate(`document.querySelector('[data-daily-ask]')?.click()`);
  await sleep(700);
  const draft = await evaluate(`(() => { const el = document.querySelector("#messageInput"); return el ? el.value : ""; })()`);
  console.log("daily draft:", draft.slice(0, 40));
  await shot("screen-daily-draft.png");

  /* 输入栏工具盘：张开 + 点一个表情，确认真的插进了草稿 */
  await evaluate(`document.querySelector("#btnAttach")?.click()`);
  await sleep(420);
  await shot("screen-composer.png");
  const composed = await evaluate(`(() => {
    const btn = document.querySelector("#trayEmoji [data-emoji]");
    btn?.click();
    const el = document.querySelector("#messageInput");
    return { value: el ? el.value : "", trayHidden: document.querySelector("#composerTray")?.hidden };
  })()`);
  console.log("composer emoji:", JSON.stringify({ len: composed.value.length, trayHidden: composed.trayHidden }));
  if (!composed.value.includes("😊") && !composed.value.includes("🥺")) {
    console.log("FAIL: tapping a tray emoji did not reach the input");
    process.exitCode = 1;
  }
  await shot("screen-composer-emoji.png");
  await evaluate(`document.querySelector("#btnAttach")?.click()`);
  await sleep(250);

  await evaluate(`document.querySelector("#btnChatBack")?.click(); document.querySelector('[data-tab="contacts"]')?.click()`);
  await sleep(500);
  await shot("screen-contacts.png");

  await evaluate(`document.querySelector('[data-tab="home"]')?.click()`);
  await sleep(400);
  await evaluate(`document.querySelector('[data-home-action="persona"]')?.click()`);
  await sleep(650);
  await evaluate(`(() => {
    const group = document.querySelector('[data-group="appearance"]');
    if (!group) return false;
    group.open = true;
    const editor = document.querySelector(".accent-editor");
    if (editor) editor.scrollIntoView({ block: "center" });
    return true;
  })()`);
  await sleep(500);
  await evaluate(`(() => { const el = document.querySelector("#accentHex"); if (el) { el.value = "#C86B4A"; el.dispatchEvent(new Event("input", { bubbles: true })); } return true; })()`);
  await sleep(450);
  const accentState = await evaluate(`(() => ({
    accent: getComputedStyle(document.documentElement).getPropertyValue("--accent").trim(),
    chip: document.querySelector("#accentChip")?.style.background || "",
    invalid: document.querySelector("#accentHex")?.classList.contains("is-invalid") || false,
  }))()`);
  console.log("accent typed:", JSON.stringify(accentState));
  await shot("screen-accent.png");
  await evaluate(`(() => { const el = document.querySelector("#accentHex"); if (el) { el.value = "#C86"; el.dispatchEvent(new Event("input", { bubbles: true })); } return true; })()`);
  await sleep(300);
  const accentShort = await evaluate(`(() => getComputedStyle(document.documentElement).getPropertyValue("--accent").trim())()`);
  console.log("accent 3-digit:", accentShort);
  if (!String(accentShort).toUpperCase().includes("CC8866")) {
    console.log("FAIL: 3-digit hex was not expanded to #CC8866");
    process.exitCode = 1;
  }
}

console.log(`gallery done · console errors: ${consoleErrors.length}`);
for (const line of consoleErrors.slice(0, 5)) console.log("  !", line.slice(0, 200));
if (consoleErrors.length) process.exitCode = 1;

ws.close();
child.kill("SIGKILL");
server.close();
await sleep(200);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
