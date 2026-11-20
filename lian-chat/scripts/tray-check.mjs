/* Composer tray checks for 1.9.12: 最近 group, per-group switching, persistence.
 *
 *   node scripts/tray-check.mjs
 *
 * Drives the real page over CDP. No network, no API calls.
 * Writes docs/test-1.9.12-tray.png at the end.
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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-tray-"));
const debugPort = 9700 + Math.floor(Math.random() * 100);
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

const now = Date.now();
const messages = [
  { id: "m1", role: "assistant", kind: "text", text: "你来啦。今天过得怎么样？", ts: now - 3600000 },
  { id: "m2", role: "user", kind: "text", text: "今天降温了，我出门忘了带外套。", ts: now - 3480000 },
  { id: "m3", role: "assistant", kind: "text", text: "外套我拿着了，路上小心点。", ts: now - 3420000 },
];
const seed = {
  onboarded: true,
  settings: {
    provider: "custom", apiKey: "seed", baseUrl: "http://127.0.0.1:1/v1", model: "m",
    aiName: "沈言", userName: "小满", relationship: "认识三年的恋人", persona: "话少。",
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

async function seedAndBoot(state = seed) {
  await send("Page.navigate", { url: base });
  await sleep(500);
  await evaluate(`(async () => {
    localStorage.clear();
    await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
    localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(state))});
    return true;
  })()`);
  await reload();
}

/* plain reload: keeps IndexedDB, so this is the real "did it save?" test */
async function reload() {
  await send("Page.reload");
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (await evaluate(`!!document.querySelector("#boot.is-done")`)) break;
    await sleep(120);
  }
  await sleep(350);
  await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
  await sleep(500);
}

const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};

const trayState = () => evaluate(`(() => {
  const tray = document.querySelector("#composerTray");
  const head = document.querySelector("#trayEmojiHead");
  const box = document.querySelector("#trayEmoji");
  return {
    hidden: tray ? tray.hidden : null,
    tabs: head ? Array.from(head.querySelectorAll("[data-emoji-group]")).map((tab) => tab.dataset.emojiGroup) : [],
    active: head && head.querySelector(".is-on") ? head.querySelector(".is-on").dataset.emojiGroup : "",
    emojis: box ? Array.from(box.querySelectorAll("[data-emoji]")).map((btn) => btn.dataset.emoji) : [],
    input: document.querySelector("#messageInput").value,
  };
})()`);
const inputValue = () => evaluate(`document.querySelector("#messageInput").value`);
const clickTab = (group) => evaluate(`document.querySelector('[data-emoji-group="${group}"]')?.click()`);
const clickEmoji = (emoji) => evaluate(`(() => {
  const btn = Array.from(document.querySelectorAll("#trayEmoji [data-emoji]")).find((node) => node.dataset.emoji === ${JSON.stringify(emoji)});
  if (!btn) return false;
  btn.click();
  return true;
})()`);

await seedAndBoot();

/* ---------- 1. open: five groups, no recents yet ---------- */
await evaluate(`document.querySelector("#btnAttach").click()`);
await sleep(260);
let tray = await trayState();
check("tray opens", tray.hidden === false);
check("tray starts with the five colour groups", tray.tabs.join(",") === "face,soft,heart,hand,daily", tray.tabs.join(","));
check("first group is selected and filled", tray.active === "face" && tray.emojis.length === 8, `${tray.active} · ${tray.emojis.length}`);

/* ---------- 2. switching groups swaps the row ---------- */
await clickTab("hand");
await sleep(200);
tray = await trayState();
check("switching group replaces the emoji row", tray.active === "hand" && tray.emojis[0] === "👍" && tray.emojis.length === 6, `${tray.active} · ${tray.emojis.join("")}`);

/* ---------- 3. one tap inserts, the tray stays open ---------- */
await clickEmoji("👍");
await sleep(250);
tray = await trayState();
check("tapping an emoji inserts it", tray.input === "👍", tray.input);
check("the tray stays open after inserting", tray.hidden === false);
check("最近 appears as soon as there is history", tray.tabs[0] === "recent", tray.tabs.join(","));

/* ---------- 4. 最近 group reflects the tap ---------- */
await clickTab("recent");
await sleep(200);
tray = await trayState();
check("最近 group holds the tapped emoji", tray.emojis.length === 1 && tray.emojis[0] === "👍", tray.emojis.join(""));

/* ---------- 5. newest first, and repeats move to the front ---------- */
await clickTab("daily");
await sleep(150);
for (const emoji of ["☕", "🍰", "🌙"]) {
  await clickEmoji(emoji);
  await sleep(140);
}
await clickTab("recent");
await sleep(200);
tray = await trayState();
check("recents are newest first", tray.emojis.join(",") === "🌙,🍰,☕,👍", tray.emojis.join(","));
await clickTab("hand");
await sleep(150);
await clickEmoji("👍");
await sleep(200);
await clickTab("recent");
await sleep(200);
tray = await trayState();
check("a repeat jumps back to the front", tray.emojis.join(",") === "👍,🌙,🍰,☕", tray.emojis.join(","));
check("no duplicates in 最近", new Set(tray.emojis).size === tray.emojis.length);

const shot = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
fs.writeFileSync(path.join(ROOT, "docs", "test-1.9.12-tray.png"), Buffer.from(shot.data, "base64"));

/* ---------- 6. survives a reload ---------- */
await sleep(500); /* let the debounced save land */
await reload();
await evaluate(`document.querySelector("#btnAttach").click()`);
await sleep(300);
await clickTab("recent");
await sleep(250);
tray = await trayState();
check("最近 survives a reload", tray.emojis.join(",") === "👍,🌙,🍰,☕", tray.emojis.join(","));
check("the unsent emoji text is still kept as a draft", tray.input === "👍☕🍰🌙👍", tray.input);

/* ---------- 7. the tray closes with the chat ---------- */
await evaluate(`document.querySelector('[data-tab="list"]').click()`);
await sleep(400);
tray = await trayState();
check("leaving the chat closes the tray", tray.hidden === true);

/* ---------- 8. keyboard / submit paths still close it ---------- */
await evaluate(`document.querySelector("[data-chat-open]").click()`);
await sleep(450);
await evaluate(`document.querySelector("#btnAttach").click()`);
await sleep(220);
await evaluate(`(() => {
  const input = document.querySelector("#messageInput");
  input.value = "没网，看看输入框就行";
  input.dispatchEvent(new Event("input", { bubbles: true }));
  return true;
})()`);
await sleep(120);
await evaluate(`document.querySelector("#btnAttach").click()`);
await sleep(200);
tray = await trayState();
check("the + button closes the tray again", tray.hidden === true);
check("closing the tray keeps the typed text", tray.input === "没网，看看输入框就行", tray.input);

/* ---------- 9. opening settings closes the tray ---------- */
await evaluate(`document.querySelector("#btnAttach").click()`);
await sleep(220);
await evaluate(`document.querySelector("#btnPeer").click()`);
await sleep(600);
const behind = await evaluate(`(() => {
  const screen = document.body.dataset.screen;
  const tray = document.querySelector("#composerTray");
  return { screen, trayHidden: tray ? tray.hidden : null };
})()`);
check("settings opens", behind.screen === "settings", JSON.stringify(behind));
check("the tray does not wait behind the settings page", behind.trayHidden === true, JSON.stringify(behind));
await evaluate(`document.querySelector("#btnSettingsBack").click()`);
await sleep(500);
const back = await evaluate(`document.querySelector("#composerTray").hidden`);
check("coming back leaves the tray closed", back === true, String(back));

/* ---------- 10. group labels follow the UI language ---------- */
await seedAndBoot({ ...seed, settings: { ...seed.settings, uiLang: "en" } });
await evaluate(`document.querySelector("#btnAttach").click()`);
await sleep(280);
const englishTabs = await evaluate(`Array.from(document.querySelectorAll("#trayEmojiHead [data-emoji-group]")).map((tab) => tab.textContent.trim())`);
check("groups switch to English", englishTabs.join(",") === "Faces,Soft,Hearts,Hands,Daily", englishTabs.join(","));

check("no console errors", consoleErrors.length === 0, consoleErrors.slice(0, 2).join(" | "));

const failed = results.filter((item) => !item.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
ws.close();
child.kill("SIGKILL");
server.close();
await sleep(150);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
process.exit(failed.length ? 1 : 0);
