/* 「重来这一条」/「重画一张」checks for 1.9.10.
 *
 *   node scripts/regen-check.mjs
 *
 * A same-origin mock OpenAI endpoint answers the two requests, so the real
 * request/parse/replace path is exercised end to end.
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

const OLD_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 320"><rect width="320" height="320" fill="#2b3a55"/><circle cx="160" cy="160" r="60" fill="#f6c177"/></svg>`;
const NEW_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 320"><rect width="320" height="320" fill="#f2f7f3"/><path d="M60 220h200" stroke="#5b8c6a" stroke-width="10" stroke-linecap="round"/><circle cx="160" cy="120" r="46" fill="#7fb98a"/></svg>`;

const MOCK = { calls: 0, notes: [] };
const server = createServer((req, res) => {
  const url = new URL(req.url || "/", "http://127.0.0.1");
  if (url.pathname === "/mock/v1/chat/completions") {
    MOCK.calls += 1;
    let body = "";
    req.on("data", (chunk) => { body += chunk; });
    req.on("end", () => {
      let payload = {};
      try { payload = JSON.parse(body || "{}"); } catch { /* ignore */ }
      const last = String(payload.messages?.at(-1)?.content || "");
      MOCK.notes.push(last.slice(0, 24));
      const wantsDrawing = last.includes("重新画一张");
      const content = wantsDrawing ? `画好了。\n\`\`\`svg\n${NEW_SVG}\n\`\`\`` : "我重新说一遍。";
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({
        choices: [{ message: { role: "assistant", content }, finish_reason: "stop" }],
        usage: { prompt_tokens: 30, completion_tokens: 40, total_tokens: 70 },
      }));
    });
    return;
  }
  const raw = decodeURIComponent(url.pathname);
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
const port = server.address().port;
const base = `http://127.0.0.1:${port}/`;

const edge = [
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
].find((p) => fs.existsSync(p));
if (!edge) {
  console.error("SKIP: Microsoft Edge not found");
  server.close();
  process.exit(2);
}

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-regen-"));
const debugPort = 9880 + Math.floor(Math.random() * 40);
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
  if (message.method === "Runtime.consoleAPICalled" && message.params.type === "error") {
    consoleErrors.push(message.params.args.map((a) => a.value ?? a.description ?? "").join(" "));
  }
  if (message.method === "Runtime.exceptionThrown") {
    consoleErrors.push(message.params.exceptionDetails.exception?.description || "exception");
  }
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
  { id: "u1", role: "user", kind: "text", text: "在吗", ts: now - 600000 },
  { id: "a1", role: "assistant", kind: "text", text: "在。", ts: now - 590000 },
  { id: "u2", role: "user", kind: "text", text: "画个太阳给我", ts: now - 400000 },
  { id: "a2", role: "assistant", kind: "drawing", drawing: { type: "svg", markup: OLD_SVG, createdAt: now - 390000 }, text: "", ts: now - 390000 },
  { id: "u3", role: "user", kind: "text", text: "好看", ts: now - 200000 },
  { id: "a3", role: "assistant", kind: "text", text: "嗯。", ts: now - 190000 },
];
const seed = {
  onboarded: true,
  settings: {
    provider: "custom", apiKey: "sk-mock", baseUrl: `http://127.0.0.1:${port}/mock/v1`, model: "mock-model",
    aiName: "沈言", userName: "小满", relationship: "认识三年的恋人", persona: "话少。",
    greeting: "你来啦。", theme: "paper",
    optimize: { noActions: true, segments: false, autoSticker: true, emoji: true, shortReplies: true, quotes: true, streaming: false, drawings: true },
  },
  chats: [{
    id: "c1", name: "沈言", relationship: "认识三年的恋人", keyId: "k1",
    createdAt: now - 86400000, updatedAt: now, messages: [], unread: 0,
  }],
  keys: [{ id: "k1", name: "Mock", provider: "custom", apiKey: "sk-mock", baseUrl: `http://127.0.0.1:${port}/mock/v1`, model: "mock-model", createdAt: now }],
  activeChatId: "c1", activeKeyId: "k1",
  messages,
  memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
};

await send("Page.navigate", { url: base });
await waitFor(`document.readyState === "complete" && location.protocol === "http:"`, 10000, "page ready");
await sleep(250);
await evaluate(`(async () => {
  localStorage.clear();
  await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
  localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(seed))});
  return true;
})()`);
await send("Page.reload");
await waitFor(`!!document.querySelector("#boot.is-done")`, 15000, "boot");
await sleep(300);
await waitFor(`!!document.querySelector("[data-chat-open]")`, 8000, "chat list");
await evaluate(`document.querySelector("[data-chat-open]").click()`);
await waitFor(`document.querySelectorAll(".msg").length >= 6`, 8000, "messages");
await sleep(400);

const results = [];
const capture = async (name) => {
  const result = await send("Page.captureScreenshot", { format: "png", fromSurface: true, captureBeyondViewport: false });
  fs.writeFileSync(path.join(ROOT, "docs", name), Buffer.from(result.data, "base64"));
};
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};

/* press-and-hold a message, then pick a menu item */
const longPress = async (messageId) => {
  await evaluate(`(() => {
    const node = document.querySelector('.msg[data-message="${messageId}"]');
    const rect = node.getBoundingClientRect();
    node.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, clientX: rect.left + 12, clientY: rect.top + 12, pointerType: "touch", isPrimary: true }));
    return true;
  })()`);
  await sleep(650);
};
const pickMenu = async (action) => {
  await evaluate(`document.querySelector('[data-menu="${action}"]').click()`);
};

/* ---------- re-roll one text reply, keep the rest ---------- */
await longPress("a1");
const textMenu = await evaluate(`(() => {
  const items = Array.from(document.querySelectorAll(".msg-menu [data-menu]"));
  return { open: items.length > 0, items: items.map((el) => el.dataset.menu), label: (items.find((el) => el.dataset.menu === "regen") || {}).textContent || "" };
})()`);
check("a text reply offers 重新生成", textMenu.open && textMenu.items.includes("regen"), textMenu.label.trim());
await capture("test-1.9.10-regen-menu.png");
await pickMenu("regen");
await waitFor(`(document.querySelector('.msg[data-message="a1"] .bubble') || {}).textContent === "我重新说一遍。"`, 10000, "text rerolled");
const afterText = await evaluate(`(() => {
  const ids = Array.from(document.querySelectorAll(".msg[data-message]")).map((el) => el.dataset.message);
  const texts = Object.fromEntries(Array.from(document.querySelectorAll(".msg[data-message]")).map((el) => [el.dataset.message, el.textContent.replace(/\\s+/g, " ").trim()]));
  return { ids, a1: texts.a1, a3: texts.a3, calls: null };
})()`);
check("only that bubble changed", afterText.a1.includes("我重新说一遍"), afterText.a1);
check("later messages are still there", afterText.ids.join(",") === "u1,a1,u2,a2,u3,a3" && afterText.a3.includes("嗯"), JSON.stringify(afterText.ids));
const callCount = MOCK.calls;
check("the request carried a rephrase note", MOCK.notes.some((note) => note.includes("重新说一遍")), MOCK.notes.join(" | ").slice(0, 60));

/* ---------- redraw a picture, keep the rest ---------- */
await longPress("a2");
const drawMenu = await evaluate(`(() => {
  const item = Array.from(document.querySelectorAll(".msg-menu [data-menu]")).find((el) => el.dataset.menu === "regen");
  return { label: item ? item.textContent.trim() : "" };
})()`);
check("a picture offers 重画一张", drawMenu.label.includes("重画"), drawMenu.label);
await capture("test-1.9.10-redraw-menu.png");
/* Remember the old data URI: the new <img> is inserted before the browser has
   decoded it, so waiting on naturalWidth alone can match the previous picture. */
const beforeDraw = await evaluate(
  `(() => { const img = document.querySelector('.msg[data-message="a2"] .msg-art img'); return img ? img.getAttribute('src') || '' : ''; })()`,
);
await pickMenu("regen");
await waitFor(`(() => {
  const img = document.querySelector('.msg[data-message="a2"] .msg-art img');
  if (!img || !img.complete || !(img.naturalWidth > 0)) return false;
  return img.getAttribute('src') !== ${JSON.stringify(beforeDraw)};
})()`, 15000, "picture redrawn");
const afterDraw = await evaluate(`(() => {
  const img = document.querySelector('.msg[data-message="a2"] .msg-art img');
  const ids = Array.from(document.querySelectorAll(".msg[data-message]")).map((el) => el.dataset.message);
  const a3 = (document.querySelector('.msg[data-message="a3"]') || {}).textContent || "";
  const rect = img ? img.getBoundingClientRect() : null;
  return {
    src: img ? img.getAttribute("src").slice(0, 60) : "",
    sameSize: img ? img.naturalWidth : 0,
    complete: img ? img.complete : null,
    rect: rect ? [Math.round(rect.top), Math.round(rect.height)] : null,
    ids, a3: a3.replace(/\\s+/g, " ").trim(), calls: ${MOCK.calls},
  };
})()`);
check("the picture was replaced in place", afterDraw.src.startsWith("data:image/svg+xml") && afterDraw.sameSize === 320, `${afterDraw.sameSize}px src=${afterDraw.src.length} complete=${afterDraw.complete} rect=${JSON.stringify(afterDraw.rect)}`);
check("messages after the picture survived", afterDraw.ids.join(",") === "u1,a1,u2,a2,u3,a3" && afterDraw.a3.includes("嗯"), JSON.stringify(afterDraw.ids));
check("the redraw request asked for a new picture", MOCK.notes.some((note) => note.includes("重新画一张")), MOCK.notes.at(-1));
check("two requests in total, nothing else", MOCK.calls === callCount + 1, `calls=${MOCK.calls}`);
await capture("test-1.9.10-redraw.png");

check("no console errors", consoleErrors.length === 0, consoleErrors.slice(0, 2).join(" | "));

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
ws.close();
server.close();
child.kill();
process.exit(failed.length ? 1 : 0);
