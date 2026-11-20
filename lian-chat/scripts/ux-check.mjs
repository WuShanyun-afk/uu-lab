/* Interaction checks for 1.9.6: long-press menu, search, drafts, unread.
 *
 *   node scripts/ux-check.mjs
 *
 * Pure DOM driving, no network. Writes docs/test-1.9.6-ux.png at the end.
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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-ux-"));
const debugPort = 9950 + Math.floor(Math.random() * 40);
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
const waitFor = async (expression, timeout, label) => {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if (await evaluate(expression)) return true;
    await sleep(70);
  }
  throw new Error(`timeout: ${label}`);
};

const now = Date.now();
const messages = [
  { id: "m1", role: "assistant", kind: "text", text: "你来啦。今天过得怎么样？", ts: now - 3600000 },
  { id: "m2", role: "user", kind: "text", text: "今天降温了，我出门忘了带外套。", ts: now - 3480000 },
  { id: "m3", role: "assistant", kind: "text", text: "外套我拿着了，路上小心点。", ts: now - 3420000 },
  { id: "m4", role: "user", kind: "text", text: "晚上吃了碗热汤面，还加了个蛋。", ts: now - 600000 },
  { id: "m5", role: "assistant", kind: "text", text: "吃了热的就行。", ts: now - 540000 },
];
const seed = {
  onboarded: true,
  settings: {
    provider: "custom", apiKey: "sk-seed", baseUrl: "http://127.0.0.1:1/v1", model: "m",
    aiName: "沈言", userName: "小满", relationship: "认识三年的恋人", persona: "话少。",
    greeting: "你来啦。", theme: "paper",
  },
  chats: [{
    id: "c1", name: "沈言", relationship: "认识三年的恋人", keyId: "k1",
    createdAt: now - 86400000, updatedAt: now, messages, unread: 2,
  }],
  keys: [{ id: "k1", name: "Mock", provider: "custom", apiKey: "sk-seed", baseUrl: "http://127.0.0.1:1/v1", model: "m", createdAt: now }],
  activeChatId: "c1", activeKeyId: "k1",
  messages,
  memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
};

await send("Page.navigate", { url: base });
await sleep(400);
await evaluate(`(async () => {
  localStorage.clear();
  await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
  localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(seed))});
  return true;
})()`);
await send("Page.reload");
await waitFor(`!!document.querySelector("#boot.is-done")`, 15000, "boot");
await sleep(250);

const results = [];
const capture = async (name) => {
  const result = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
  fs.writeFileSync(path.join(ROOT, "docs", name), Buffer.from(result.data, "base64"));
};
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};

/* ---------- unread badge on the chat list ---------- */
const listBadge = await evaluate(`(() => {
  const row = document.querySelector(".chat-row");
  const tab = document.querySelector('.tab-item[data-tab="list"]');
  return {
    rowUnread: row ? row.classList.contains("has-unread") : false,
    badge: (document.querySelector(".chat-unread") || {}).textContent || "",
    tabDot: tab ? tab.classList.contains("has-unread") : false,
  };
})()`);
check("list shows unread badge", listBadge.rowUnread && listBadge.badge === "2", JSON.stringify(listBadge));
check("tab bar shows the unread dot", listBadge.tabDot);

/* ---------- list search ---------- */
await evaluate(`(() => {
  const input = document.querySelector("#listSearchInput");
  input.value = "汤面";
  input.dispatchEvent(new Event("input", { bubbles: true }));
  return true;
})()`);
await sleep(200);
const filtered = await evaluate(`(() => ({
  rows: document.querySelectorAll(".chat-row").length,
  marks: document.querySelectorAll(".chat-row .search-hit").length,
}))()`);
check("list search keeps the matching chat", filtered.rows === 1 && filtered.marks >= 1, JSON.stringify(filtered));
await capture("test-1.9.6-list-search.png");
await evaluate(`(() => {
  const input = document.querySelector("#listSearchInput");
  input.value = "不存在的词";
  input.dispatchEvent(new Event("input", { bubbles: true }));
  return true;
})()`);
await sleep(200);
const emptySearch = await evaluate(`document.body.querySelector(".chat-list-empty")?.innerText || ""`);
check("list search shows the empty state", emptySearch.length > 0, emptySearch.slice(0, 20));
await evaluate(`(() => {
  document.querySelector("#listSearchClear").click();
  return true;
})()`);
await sleep(200);
check("clearing the search restores all chats", (await evaluate(`document.querySelectorAll(".chat-row").length`)) === 1);

/* ---------- open chat: unread cleared, long-press menu ---------- */
await evaluate(`document.querySelector("[data-chat-open]").click()`);
await sleep(450);
await evaluate(`document.querySelector("#btnChatBack").click()`);
await sleep(350);
const unreadAfterOpen = await evaluate(`(() => ({
  badge: !!document.querySelector(".chat-row .chat-unread"),
  rowUnread: !!document.querySelector(".chat-row.has-unread"),
  tab: document.querySelector('.tab-item[data-tab="list"]').classList.contains("has-unread"),
}))()`);
check("opening the chat clears the badge", !unreadAfterOpen.badge && !unreadAfterOpen.rowUnread && !unreadAfterOpen.tab, JSON.stringify(unreadAfterOpen));
await evaluate(`document.querySelector("[data-chat-open]").click()`);
await sleep(400);

// Long press via synthetic pointer events on the first assistant bubble.
await evaluate(`(() => {
  const bubble = document.querySelector(".msg.ai .bubble");
  const rect = bubble.getBoundingClientRect();
  const opts = { bubbles: true, clientX: rect.left + 10, clientY: rect.top + 10, pointerType: "touch", isPrimary: true };
  bubble.dispatchEvent(new PointerEvent("pointerdown", opts));
  return true;
})()`);
await sleep(650);
const menu = await evaluate(`(() => {
  const node = document.querySelector(".msg-menu");
  return {
    open: !!node,
    items: node ? Array.from(node.querySelectorAll("[data-menu]")).map((el) => el.dataset.menu) : [],
  };
})()`);
check("long press opens the menu", menu.open, JSON.stringify(menu.items));
await capture("test-1.9.6-menu.png");
check("menu offers copy/quote/regenerate/delete", ["copy", "quote", "regen", "delete"].every((id) => menu.items.includes(id)));

/* ---------- copy ---------- */
await evaluate(`document.querySelector('[data-menu="copy"]').click()`);
await sleep(250);
const copied = await evaluate(`(() => {
  const toast = document.querySelector("#toast");
  return { menu: !!document.querySelector(".msg-menu"), toast: toast && !toast.hidden ? toast.innerText.trim() : "" };
})()`);
check("copy closes the menu", !copied.menu);
check("copy shows a toast", copied.toast.length > 0, copied.toast);

/* ---------- delete ---------- */
const beforeDelete = await evaluate(`document.querySelectorAll(".msg").length`);
await evaluate(`(() => {
  const bubble = document.querySelectorAll(".msg.ai .bubble")[0];
  const rect = bubble.getBoundingClientRect();
  bubble.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, clientX: rect.left + 8, clientY: rect.top + 8, pointerType: "touch", isPrimary: true }));
  return true;
})()`);
await sleep(600);
await evaluate(`document.querySelector('[data-menu="delete"]')?.click()`);
await sleep(400);
const afterDelete = await evaluate(`document.querySelectorAll(".msg").length`);
check("delete removes one message", afterDelete === beforeDelete - 1, `${beforeDelete} → ${afterDelete}`);

/* ---------- in-chat search ---------- */
await evaluate(`document.querySelector("#btnChatSearch").click()`);
await sleep(200);
await evaluate(`(() => {
  const input = document.querySelector("#chatSearchInput");
  input.value = "汤面";
  input.dispatchEvent(new Event("input", { bubbles: true }));
  return true;
})()`);
await sleep(350);
const chatSearch = await evaluate(`(() => ({
  bar: !document.querySelector("#chatSearchBar").hidden,
  count: (document.querySelector("#chatSearchCount") || {}).textContent || "",
  hit: document.querySelectorAll(".msg.is-hit").length,
}))()`);
check("chat search opens and counts", chatSearch.bar && /1\/1/.test(chatSearch.count), JSON.stringify(chatSearch));
check("chat search highlights the message", chatSearch.hit >= 1);
await capture("test-1.9.6-chat-search.png");

/* ---------- drafts ---------- */
await evaluate(`document.querySelector("#chatSearchClose").click()`);
await evaluate(`(() => {
  const input = document.querySelector("#messageInput");
  input.value = "先写着，等会儿再发";
  input.dispatchEvent(new Event("input", { bubbles: true }));
  return true;
})()`);
await sleep(300);
await evaluate(`document.querySelector("#btnChatBack").click()`);
await sleep(350);
await evaluate(`document.querySelector("[data-chat-open]").click()`);
await sleep(400);
const draft = await evaluate(`document.querySelector("#messageInput").value`);
check("draft survives switching chats", draft === "先写着，等会儿再发", draft);

/* ---------- screenshot ---------- */
const shot = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
fs.writeFileSync(path.join(ROOT, "docs", "test-1.9.6-ux.png"), Buffer.from(shot.data, "base64"));

const failed = results.filter((item) => !item.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
ws.close();
child.kill("SIGKILL");
server.close();
await sleep(150);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
process.exit(failed.length ? 1 : 0);
