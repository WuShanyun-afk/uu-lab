/* Regression checks for the two leaks seen on the phone (1.9.13):
 *
 *   node scripts/leak-check.mjs
 *
 * 1. a drawing reply that got cut off mid-<svg> used to show its raw source in
 *    a bubble;
 * 2. a daily report whose JSON never finished used to render `{"title":"…`.
 *
 * Serves the app plus a mock OpenAI-compatible endpoint on the same origin, so
 * the real fetch / parse / render path is exercised. No real provider.
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

const SVG = `<svg viewBox="0 0 320 320" xmlns="http://www.w3.org/2000/svg">
<rect width="320" height="320" fill="#1c1c22"/>
<circle cx="160" cy="150" r="70" fill="#3a3a44"/>
<path d="M100 240 L160 190 L220 240 Z" fill="#0d0d11"/>
</svg>`;

/* Replies keyed by a word in the user's message, so one mock can answer every case. */
const REPLIES = {
  断: "在睡觉。拍糊了。\n\n```svg\n<svg viewBox=\"0 0 320 320\"><rect width=\"320\" height=\"320\" fill=\"#1c1c22\"/><circle cx=\"160\" cy=\"140\" r=\"60",
  空: "```svg\n<svg viewBox=\"0 0 320 320\"><path d=\"M100 130 L82",
  满: `在睡觉。这张给你。\n\n\`\`\`svg\n${SVG}\n\`\`\``,
  /* the phone case: the model answered with bare <svg> and no fence at all */
  裸: `画好了。\n\n${SVG}\n\n希望你会喜欢。`,
  码: `给你代码：\n\`\`\`svg\n${SVG}\n\`\`\``,
};
/* The report request asks for blocks + a scene id; this one is cut off. */
const REPORT_CUT = '{"title":"凌晨一点的日常","summary":"改代码改到现在，窗外的路灯还亮着","blocks":[{"text":"改到一点，头发乱了","scene":"moon"},{"text":"本来还想';

const MOCK = { requests: 0, report: 0, drawing: 0 };

const server = createServer((req, res) => {
  const url = new URL(req.url || "/", "http://127.0.0.1");
  if (url.pathname === "/mock/v1/chat/completions") {
    MOCK.requests += 1;
    let body = "";
    req.on("data", (chunk) => { body += chunk; });
    req.on("end", async () => {
      let payload = {};
      try { payload = JSON.parse(body || "{}"); } catch { /* ignore */ }
      const messages = Array.isArray(payload.messages) ? payload.messages : [];
      const lastUser = [...messages].reverse().find((message) => message.role === "user")?.content ?? "";
      const system = messages.find((message) => message.role === "system")?.content ?? "";
      const wantsReport = payload.response_format?.type === "json_object" || /"blocks"/.test(system);
      let reply = "嗯，我在。";
      if (wantsReport) {
        MOCK.report += 1;
        reply = REPORT_CUT;
      } else {
        MOCK.drawing += 1;
        for (const [key, value] of Object.entries(REPLIES)) {
          if (String(lastUser).includes(key)) { reply = value; break; }
        }
      }
      const stream = Boolean(payload.stream);
      if (!stream) {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({
          choices: [{ message: { role: "assistant", content: reply }, finish_reason: "length" }],
          usage: { prompt_tokens: 20, completion_tokens: 40, total_tokens: 60 },
        }));
        return;
      }
      res.writeHead(200, { "content-type": "text/event-stream; charset=utf-8", "cache-control": "no-store", connection: "keep-alive" });
      const write = (obj) => res.write(`data: ${JSON.stringify(obj)}\n\n`);
      write({ choices: [{ index: 0, delta: { role: "assistant" } }] });
      for (const char of reply) {
        await sleep(4);
        write({ choices: [{ index: 0, delta: { content: char } }] });
      }
      write({ choices: [{ index: 0, delta: {}, finish_reason: "length" }], usage: { prompt_tokens: 20, completion_tokens: 40, total_tokens: 60 } });
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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-leak-"));
const debugPort = 9760 + Math.floor(Math.random() * 60);
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

const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};
const capture = async (name) => {
  const shot = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
  fs.writeFileSync(path.join(ROOT, "docs", name), Buffer.from(shot.data, "base64"));
};

const now = Date.now();
const seed = (drawings, extra = []) => ({
  onboarded: true,
  settings: {
    provider: "custom", apiKey: "seed", baseUrl: `http://127.0.0.1:${port}/mock/v1`, model: "m",
    aiName: "Cat", userName: "小满", relationship: "认识三年的恋人", persona: "话少。",
    greeting: "你来啦。", theme: "paper", layout: "line",
    optimize: { noActions: true, segments: false, autoSticker: false, emoji: true, shortReplies: true, quotes: true, streaming: true, drawings },
  },
  chats: [{
    id: "c1", name: "Cat", relationship: "认识三年的恋人", keyId: "k1",
    createdAt: now - 86400000, updatedAt: now, messages: extra,
  }],
  keys: [{ id: "k1", name: "Mock", provider: "custom", apiKey: "seed", baseUrl: `http://127.0.0.1:${port}/mock/v1`, model: "m", createdAt: now }],
  activeChatId: "c1", activeKeyId: "k1",
  messages: extra, memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
});

async function boot(drawings, extra = []) {
  await send("Page.navigate", { url: base });
  await sleep(400);
  await evaluate(`(async () => {
    localStorage.clear();
    await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
    localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(seed(drawings, extra)))});
    return true;
  })()`);
  await send("Page.reload");
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const done = await evaluate(`!document.querySelector("#boot") || !!document.querySelector("#boot.is-done")`);
    if (done) break;
    await sleep(110);
  }
  await sleep(320);
  await evaluate(`document.querySelector("[data-chat-open]")?.click()`);
  await sleep(450);
}

async function say(text) {
  const before = await evaluate(`document.querySelectorAll(".msg").length`);
  await evaluate(`(() => {
    const input = document.querySelector("#messageInput");
    input.value = ${JSON.stringify(text)};
    input.dispatchEvent(new Event("input", { bubbles: true }));
    document.querySelector("#composer").requestSubmit();
    return true;
  })()`);
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const count = await evaluate(`document.querySelectorAll(".msg").length`);
    const live = await evaluate(`!!document.querySelector(".msg.is-live")`);
    if (count > before + 1 && !live) break;
    await sleep(120);
  }
  await sleep(260);
}

const lastBubbles = () => evaluate(`(() => {
  const nodes = Array.from(document.querySelectorAll(".msg")).slice(-3);
  return {
    texts: nodes.map((node) => (node.querySelector(".bubble")?.innerText || "").trim()),
    arts: document.querySelectorAll(".msg-art").length,
    error: (() => { const bar = document.querySelector("#errorBar"); return bar && !bar.hidden ? (bar.innerText || "").trim() : ""; })(),
  };
})()`);

/* ---------- 1. a drawing cut off mid-<svg> (drawings on) ---------- */
await boot(true);
await say("画一张：断");
let state = await lastBubbles();
check("a cut-off drawing keeps only its words", state.texts.includes("在睡觉。拍糊了。"), JSON.stringify(state.texts));
check("no svg source is shown in a bubble", !state.texts.join(" ").includes("<svg") && !state.texts.join(" ").includes("```"), state.texts.join(" | ").slice(0, 90));
check("no half drawing is rendered", state.arts === 0, String(state.arts));
check("no error bar for a cut-off drawing", state.error === "", state.error);
await capture("test-1.9.13-cut.png");

/* ---------- 2. nothing but a cut-off drawing ---------- */
await say("画一张：空");
state = await lastBubbles();
const broken = state.texts.find((text) => text.includes("没画完")) || "";
check("an empty cut-off drawing says one line", Boolean(broken), state.texts.join(" | ").slice(0, 90));

/* ---------- 3. a complete drawing still renders ---------- */
await say("画一张：满");
state = await lastBubbles();
const art = await evaluate(`(() => {
  const node = document.querySelector(".msg-art.is-svg img");
  return node ? { src: node.getAttribute("src") || "", loaded: node.naturalWidth > 0 } : null;
})()`);
check("a complete drawing still renders", Boolean(art) && art.loaded && art.src.startsWith("data:image/svg+xml"), JSON.stringify(art).slice(0, 80));
await capture("test-1.9.13-drawing.png");

/* ---------- 4. the phone case: a bare <svg>, drawings switch OFF ---------- */
await boot(false);
await say("画一张：裸");
state = await lastBubbles();
const bareArt = await evaluate(`(() => {
  const node = document.querySelector(".msg-art.is-svg img");
  return node ? { src: node.getAttribute("src") || "", loaded: node.naturalWidth > 0 } : null;
})()`);
check("a bare svg still becomes a picture with drawings off", Boolean(bareArt) && bareArt.loaded, JSON.stringify(bareArt).slice(0, 80));
check("a bare svg leaves no source in the bubbles", !state.texts.join(" ").includes("<svg") && !state.texts.join(" ").includes("</svg>"), state.texts.join(" | ").slice(0, 90));
check("the words around a bare svg are kept", state.texts.join(" ").includes("画好了") && state.texts.join(" ").includes("喜欢"), state.texts.join(" | ").slice(0, 90));
await capture("test-1.9.14-bare.png");

/* ---------- 5. a fenced svg with the switch off is a picture too ---------- */
await say("给我代码：码");
state = await lastBubbles();
const fencedArt = await evaluate(`document.querySelectorAll(".msg-art.is-svg").length`);
check("a fenced svg also renders with drawings off", fencedArt >= 2, String(fencedArt));
check("no fence markers reach a bubble", !state.texts.join(" ").includes("```") && !state.texts.join(" ").includes("<svg"), state.texts.join(" | ").slice(0, 90));

/* ---------- 6. history saved before the fix is repaired on load ---------- */
await boot(false, [{ id: "legacy1", role: "assistant", kind: "text", text: `给你画好啦🐱\n\n${SVG}`, ts: now - 120000 }]);
const legacy = await evaluate(`(() => ({
  arts: document.querySelectorAll(".msg-art.is-svg").length,
  texts: Array.from(document.querySelectorAll(".msg .bubble")).map((node) => node.innerText.trim()),
}))()`);
check("an old raw-svg reply is repaired into a picture", legacy.arts >= 1, JSON.stringify(legacy).slice(0, 90));
check("the repaired reply keeps its words", legacy.texts.some((text) => text.includes("给你画好啦")), legacy.texts.join(" | ").slice(0, 70));
check("no svg source survives in history", !legacy.texts.join(" ").includes("<svg"), legacy.texts.join(" | ").slice(0, 70));

/* ---------- 7. a report whose JSON never finished ---------- */
await evaluate(`document.querySelector("#btnAttach").click()`);
await sleep(200);
await evaluate(`document.querySelector('[data-tray="report"]').click()`);
await sleep(500);
await evaluate(`document.querySelector("#reportGenerate").click()`);
for (let attempt = 0; attempt < 100; attempt += 1) {
  if (await evaluate(`!!document.querySelector("#reportDirect")`)) break;
  await sleep(120);
}
await sleep(400);
const report = await evaluate(`(() => {
  const body = document.querySelector("#reportDirect");
  const text = body ? body.innerText.replace(/\\s+/g, " ").trim() : "";
  return { text, raw: text.includes('{"') || text.includes('"title"'), open: Boolean(document.querySelector("#reportScroll")) };
})()`);
check("the report viewer opens", report.open);
check("the report shows a readable title", report.text.includes("凌晨一点的日常"), report.text.slice(0, 60));
check("the report never shows raw JSON", !report.raw, report.text.slice(0, 60));
check("the report is not empty", report.text.length > 12, String(report.text.length));

check("no console errors", consoleErrors.length === 0, consoleErrors.slice(0, 2).join(" | "));
console.log(`\nmock requests: ${MOCK.requests} (drawing ${MOCK.drawing}, report ${MOCK.report})`);

const shot = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
fs.writeFileSync(path.join(ROOT, "docs", "test-1.9.13-report.png"), Buffer.from(shot.data, "base64"));

const failed = results.filter((item) => !item.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
ws.close();
child.kill("SIGKILL");
server.close();
await sleep(150);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
process.exit(failed.length ? 1 : 0);
