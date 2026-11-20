/* Verify streaming replies end-to-end without touching a real provider.
 *
 *   node scripts/stream-check.mjs [--no-stream]
 *
 * Serves the app plus a mock OpenAI-compatible endpoint on the same origin, so
 * the browser-side fetch (and CORS) path is the real one. Checks that:
 *   - the first streamed characters show up well before the whole reply,
 *   - the live bubble disappears and the final bubbles are the parsed text,
 *   - a provider without SSE falls back to a normal JSON response.
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

const REPLY = "外套我拿着了，路上小心点。";
const CHUNKS = [...REPLY].map((char) => char);
const MOCK = { requests: 0, streamed: 0, plain: 0, forcePlain: false };

const server = createServer((req, res) => {
  const url = new URL(req.url || "/", "http://127.0.0.1");
  if (url.pathname === "/mock/v1/chat/completions") {
    MOCK.requests += 1;
    let body = "";
    req.on("data", (chunk) => { body += chunk; });
    req.on("end", async () => {
      let payload = {};
      try { payload = JSON.parse(body || "{}"); } catch { /* ignore */ }
      if (!payload.stream || MOCK.forcePlain) {
        MOCK.plain += 1;
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({
          choices: [{ message: { role: "assistant", content: REPLY }, finish_reason: "stop" }],
          usage: { prompt_tokens: 11, completion_tokens: 12, total_tokens: 23 },
        }));
        return;
      }
      MOCK.streamed += 1;
      res.writeHead(200, {
        "content-type": "text/event-stream; charset=utf-8",
        "cache-control": "no-store",
        connection: "keep-alive",
      });
      const write = (obj) => res.write(`data: ${JSON.stringify(obj)}\n\n`);
      write({ choices: [{ index: 0, delta: { role: "assistant" } }] });
      for (const part of CHUNKS) {
        await sleep(35);
        write({ choices: [{ index: 0, delta: { content: part } }] });
      }
      write({ choices: [{ index: 0, delta: {}, finish_reason: "stop" }], usage: { prompt_tokens: 11, completion_tokens: 12, total_tokens: 23 } });
      res.write("data: [DONE]\n\n");
      res.end();
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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-stream-"));
const debugPort = 9900 + Math.floor(Math.random() * 90);
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
    if (await evaluate(expression)) return Date.now() - t0;
    await sleep(60);
  }
  throw new Error(`timeout waiting for ${label}`);
};

const now = Date.now();
const seed = {
  onboarded: true,
  settings: {
    provider: "custom",
    apiKey: "sk-mock",
    baseUrl: `${base}mock/v1`,
    model: "mock-model",
    aiName: "沈言",
    userName: "小满",
    relationship: "认识三年的恋人",
    persona: "话少，克制。",
    greeting: "你来啦。",
    theme: "line",
    optimize: { noActions: true, segments: false, autoSticker: false, emoji: true, shortReplies: true, quotes: false, streaming: true },
    realism: { enabled: false, typing: true, minDelay: 0, maxDelay: 0, autoDelay: false, segmentDelay: 0 },
  },
  chats: [{
    id: "c1", name: "沈言", relationship: "认识三年的恋人", keyId: "k1",
    createdAt: now - 86400000, updatedAt: now,
    messages: [{ id: "g1", role: "assistant", kind: "text", text: "你来啦。", ts: now - 3600000 }],
  }],
  keys: [{ id: "k1", name: "Mock", provider: "custom", apiKey: "sk-mock", baseUrl: `${base}mock/v1`, model: "mock-model", createdAt: now }],
  activeChatId: "c1", activeKeyId: "k1",
  messages: [{ id: "g1", role: "assistant", kind: "text", text: "你来啦。", ts: now - 3600000 }],
  memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
};

await send("Page.navigate", { url: base });
await sleep(500);
await evaluate(`(async () => {
  localStorage.clear();
  await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
  localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(seed))});
  return true;
})()`);
await send("Page.reload");
await waitFor(`!!document.querySelector("#boot.is-done")`, 15000, "boot");
await sleep(200);
await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
await waitFor(`!!document.querySelector("#messageInput")`, 8000, "composer");

const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};

const before = await evaluate(`document.querySelectorAll(".msg.ai").length`);
const t0 = Date.now();
await evaluate(`(() => {
  const input = document.querySelector("#messageInput");
  input.value = "外面下雨了，你带伞了吗";
  input.dispatchEvent(new Event("input", { bubbles: true }));
  document.querySelector("#composer").requestSubmit();
  return true;
})()`);

const firstText = await waitFor(`(() => {
  const live = document.querySelector(".msg.is-live .bubble");
  return !!live && (live.textContent || "").trim().length > 0;
})()`, 8000, "first streamed characters");
check("live bubble shows text early", firstText < 2000, `${Date.now() - t0}ms after send`);
const liveShot = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
fs.writeFileSync(path.join(ROOT, "docs", "test-1.9.6-stream.png"), Buffer.from(liveShot.data, "base64"));

await waitFor(`!document.querySelector(".msg.is-live")`, 20000, "stream to finish");
const done = Date.now() - t0;
const after = await evaluate(`(() => {
  const nodes = Array.from(document.querySelectorAll(".msg.ai"));
  const last = nodes.at(-1);
  return {
    count: nodes.length,
    live: !!document.querySelector(".msg.is-live"),
    text: last ? last.innerText.replace(/\\s+/g, " ").trim() : "",
    error: (document.querySelector("#errorBar:not([hidden])") || {}).innerText || "",
    userMessages: document.querySelectorAll(".msg.user").length,
  };
})()`);
check("live bubble removed", !after.live);
check("reply text matches the streamed text", after.text.includes(REPLY), after.text.slice(0, 30));
check("no error bar", !after.error, after.error);
check("one new assistant bubble", after.count === before + 1, `before=${before} after=${after.count}`);
check("streaming used", MOCK.streamed === 1, `streamed=${MOCK.streamed} plain=${MOCK.plain}`);
check("stream finished in a sane time", done < 15000, `${done}ms`);

// ---- fallback: a provider that ignores `stream` and answers with plain JSON ----
MOCK.forcePlain = true;
await send("Page.reload");
await waitFor(`!!document.querySelector("#boot.is-done")`, 15000, "boot 2");
await sleep(200);
await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
await waitFor(`!!document.querySelector("#messageInput")`, 8000, "composer 2");
const plainBefore = await evaluate(`document.querySelectorAll(".msg.ai").length`);
await evaluate(`(() => {
  const input = document.querySelector("#messageInput");
  input.value = "再说一遍";
  input.dispatchEvent(new Event("input", { bubbles: true }));
  document.querySelector("#composer").requestSubmit();
  return true;
})()`);
await waitFor(`document.querySelectorAll(".msg.ai").length > ${plainBefore} || !!document.querySelector("#errorBar:not([hidden])")`, 20000, "plain reply");
const plainState = await evaluate(`(() => {
  const last = Array.from(document.querySelectorAll(".msg.ai")).at(-1);
  return {
    text: last ? last.innerText.replace(/\\s+/g, " ").trim() : "",
    error: (document.querySelector("#errorBar:not([hidden])") || {}).innerText || "",
  };
})()`);
check("fallback still delivers a reply", plainState.text.includes(REPLY) && !plainState.error, plainState.text.slice(0, 30));

const failed = results.filter((item) => !item.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);

ws.close();
child.kill("SIGKILL");
server.close();
await sleep(150);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
process.exit(failed.length ? 1 : 0);
