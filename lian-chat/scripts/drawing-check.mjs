/* Checks for 1.9.9 drawings: AI-sent SVG / HTML pictures.
 *
 *   node scripts/drawing-check.mjs
 *
 * Seeds two drawing messages (one SVG, one animated HTML), verifies rendering
 * and sandboxing, exercises the settings switch + token warning, and writes
 * docs/test-1.9.9-drawings*.png.
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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-draw-"));
const debugPort = 9930 + Math.floor(Math.random() * 40);
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

const SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 320">
  <defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#f7c9a3"/><stop offset="1" stop-color="#f9e7d2"/>
  </linearGradient></defs>
  <rect width="320" height="320" fill="url(#sky)"/>
  <circle cx="228" cy="104" r="34" fill="#f6a96b"/>
  <path d="M0 246c46-26 88-24 132-6s54 6 96-10 66-8 92 4v86H0z" fill="#6b7f6a"/>
  <path d="M0 268c60-14 96-8 140 4s74 4 180-12v60H0z" fill="#4d5f50"/>
  <text x="26" y="60" font-size="17" fill="#5b4636" font-family="sans-serif">今天也过去啦</text>
</svg>`;

const HTML = `<div class="cloud"><span></span><span></span><span></span></div>
<div class="rain"></div>
<style>
  body { background: #eef3f7; }
  .cloud { position: relative; width: 180px; height: 90px; }
  .cloud span { position: absolute; border-radius: 50%; background: #fff; box-shadow: 0 6px 18px rgba(70,90,110,.18); animation: drift 4s ease-in-out infinite; }
  .cloud span:nth-child(1) { width: 74px; height: 74px; left: 0; top: 12px; }
  .cloud span:nth-child(2) { width: 96px; height: 96px; left: 40px; top: 0; animation-delay: .3s; }
  .cloud span:nth-child(3) { width: 66px; height: 66px; right: 0; top: 20px; animation-delay: .6s; }
  .rain { position: absolute; left: 50%; top: 128px; width: 2px; height: 46px; background: #9fc4dc; border-radius: 2px; animation: fall 1.4s linear infinite; }
  @keyframes drift { 50% { transform: translateY(-10px); } }
  @keyframes fall { 0% { transform: translateY(0); opacity: 0; } 30% { opacity: 1; } 100% { transform: translateY(48px); opacity: 0; } }
</style>`;

const now = Date.now();
const messages = [
  { id: "m1", role: "user", kind: "text", text: "外面下雨了吗？", ts: now - 300000 },
  { id: "m2", role: "assistant", kind: "text", text: "我这边飘着一点。", ts: now - 290000 },
  { id: "m3", role: "assistant", kind: "drawing", drawing: { type: "html", markup: HTML, createdAt: now - 280000 }, text: "", ts: now - 280000 },
  { id: "m4", role: "user", kind: "text", text: "你那边天好看吗", ts: now - 200000 },
  { id: "m5", role: "assistant", kind: "drawing", drawing: { type: "svg", markup: SVG, createdAt: now - 190000 }, text: "", ts: now - 190000 },
  { id: "m6", role: "assistant", kind: "text", text: "太阳在往下掉了。", ts: now - 180000 },
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
    createdAt: now - 86400000, updatedAt: now, messages: [], unread: 0,
  }],
  keys: [{ id: "k1", name: "Mock", provider: "custom", apiKey: "sk-seed", baseUrl: "http://127.0.0.1:1/v1", model: "m", createdAt: now }],
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
await waitFor(`document.querySelectorAll(".msg").length >= 5`, 8000, "messages");
await sleep(600);

const results = [];
const capture = async (name) => {
  const result = await send("Page.captureScreenshot", { format: "png", fromSurface: true, captureBeyondViewport: false });
  fs.writeFileSync(path.join(ROOT, "docs", name), Buffer.from(result.data, "base64"));
};
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};

/* ---------- SVG drawing ---------- */
const svg = await evaluate(`(() => {
  const arts = Array.from(document.querySelectorAll(".msg-art.is-svg"));
  const img = arts[0]?.querySelector("img");
  return {
    count: arts.length,
    src: img ? img.getAttribute("src").slice(0, 34) : "",
    loaded: img ? img.complete && img.naturalWidth > 0 : false,
    width: img ? img.naturalWidth : 0,
    clickable: Boolean(arts[0]?.querySelector("[data-drawing-view]")) || (arts[0]?.tagName === "BUTTON"),
  };
})()`);
check("an svg drawing renders as an image", svg.count === 1 && svg.loaded && svg.width >= 300, JSON.stringify(svg));
check("the svg image is a data: URI, never a file or network URL", svg.src.startsWith("data:image/svg+xml"), svg.src);

/* ---------- HTML drawing ---------- */
const htmlArt = await evaluate(`(() => {
  const frame = document.querySelector(".msg-art.is-html iframe");
  const srcdoc = frame ? frame.getAttribute("srcdoc") || "" : "";
  return {
    frame: Boolean(frame),
    sandbox: frame ? frame.getAttribute("sandbox") : null,
    hasCsp: srcdoc.includes("Content-Security-Policy"),
    forbidsScripts: srcdoc.includes("script-src 'none'"),
    keepsAnimation: srcdoc.includes("@keyframes"),
    strippedScript: !/<script/i.test(srcdoc),
  };
})()`);
check("an html drawing renders inside an iframe", htmlArt.frame, JSON.stringify({ frame: htmlArt.frame }));
check("the iframe has an empty sandbox (no scripts, no same-origin)", htmlArt.sandbox === "", `sandbox="${htmlArt.sandbox}"`);
check("the iframe document carries a strict CSP", htmlArt.hasCsp && htmlArt.forbidsScripts, JSON.stringify(htmlArt));
check("css animation survives into the frame", htmlArt.keepsAnimation, "keyframes kept");

/* ---------- viewer ---------- */
await evaluate(`document.querySelectorAll(".msg-art.is-svg [data-drawing-view], .msg-art.is-svg")[0].click()`);
await sleep(400);
const viewer = await evaluate(`(() => {
  const modal = document.querySelector("#modalLayer:not([hidden]) .drawing-viewer");
  const img = modal?.querySelector("img.drawing-full");
  return { open: Boolean(modal), img: Boolean(img), huge: img ? img.naturalWidth > 300 : false };
})()`);
check("tapping a drawing opens the larger view", viewer.open && viewer.img && viewer.huge, JSON.stringify(viewer));
await evaluate(`document.querySelector("[data-close-drawing]")?.click()`);
await sleep(250);
await capture("test-1.9.9-drawings.png");

/* ---------- dark theme keeps the picture readable ---------- */
await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] });
await sleep(400);
const dark = await evaluate(`(() => {
  const art = document.querySelector(".msg-art.is-svg");
  const img = art?.querySelector("img");
  return {
    bodyBg: getComputedStyle(document.body).backgroundColor,
    stage: art ? getComputedStyle(art).backgroundColor : "",
    loaded: img ? img.naturalWidth > 0 : false,
  };
})()`);
check("dark mode still paints a light stage under the picture", /rgb\(2[0-9]{2}, 2[0-9]{2}, 2[0-9]{2}\)/.test(dark.stage) && dark.loaded, JSON.stringify(dark));
await capture("test-1.9.9-drawings-dark.png");
await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "light" }] });
await sleep(300);

/* ---------- the switch + its token warning ---------- */
await evaluate(`document.querySelector("#btnChatBack")?.click()`);
await sleep(350);
await evaluate(`(() => { document.querySelector('[data-tab="home"]').click(); return true; })()`);
await sleep(300);
await evaluate(`document.querySelector('[data-home-action="experience"]').click()`);
await waitFor(`!!document.querySelector("#settingsBody")`, 6000, "settings");
await evaluate(`(() => {
  const group = document.querySelector('[data-group="experience"]');
  if (group) group.open = true;
  return true;
})()`);
await sleep(350);
const row = await evaluate(`(() => {
  const el = document.querySelector('[data-toggle="drawings"]');
  return {
    exists: Boolean(el),
    checked: el ? el.querySelector('input').checked : null,
    hint: el ? el.textContent.replace(/\\s+/g, " ").trim() : "",
  };
})()`);
check("settings has the drawing switch, off by default", row.exists && row.checked === false, row.hint.slice(0, 46));
await capture("test-1.9.9-drawings-settings.png");
await evaluate(`(() => {
  const input = document.querySelector('[data-toggle="drawings"] input');
  input.checked = true;
  input.dispatchEvent(new Event("change", { bubbles: true }));
  return true;
})()`);
await sleep(400);
const warn = await evaluate(`(() => {
  const modal = document.querySelector("#modalLayer:not([hidden]) .confirm-modal");
  return { open: Boolean(modal), text: modal ? modal.textContent.replace(/\\s+/g, " ").trim() : "" };
})()`);
check(
  "turning it on asks about token cost first",
  warn.open && warn.text.includes("token"),
  warn.text.slice(0, 60),
);
await capture("test-1.9.9-drawings-warning.png");
await evaluate(`document.querySelector(".confirm-modal [data-confirm]")?.click()`);
await sleep(400);
// the switch must survive a reload (state is saved through IndexedDB)
await send("Page.reload");
await waitFor(`!!document.querySelector("#boot.is-done")`, 15000, "reload boot");
await sleep(400);
await evaluate(`document.querySelector('[data-tab="home"]').click()`);
await sleep(300);
await evaluate(`document.querySelector('[data-home-action="experience"]').click()`);
await waitFor(`!!document.querySelector('[data-toggle="drawings"] input')`, 6000, "drawings row after reload");
const saved = await evaluate(`(() => {
  const input = document.querySelector('[data-toggle="drawings"] input');
  return { checked: input ? input.checked : null };
})()`);
check("confirming stores the switch (still on after reload)", saved.checked === true, JSON.stringify(saved));

/* ---------- parse + prompt wiring, straight from the modules ---------- */
const wiring = await evaluate(`(async () => {
  const cfg = await import("./js/config.js");
  const prompt = await import("./js/prompt.js");
  const s = cfg.defaultState();
  s.settings.apiKey = "t";
  s.settings.optimize.drawings = true;
  const raw = "看这个。\\n\`\`\`svg\\n${SVG.replace(/\n/g, "\\n").replace(/"/g, '\\"')}\\n\`\`\`";
  const parsed = prompt.parseReply(raw, s);
  const text = prompt.buildSystemPrompt(s);
  return {
    drawings: parsed.drawings.length,
    cleanText: parsed.text,
    promptBlock: text.includes("【现场画画面】"),
    svgRule: text.includes("\`\`\`svg"),
  };
})()`);
check("parseReply turns a fenced svg into a drawing", wiring.drawings === 1 && wiring.cleanText === "看这个。", JSON.stringify(wiring).slice(0, 80));
check("the system prompt teaches the syntax only when enabled", wiring.promptBlock && wiring.svgRule);

check("no console errors", consoleErrors.length === 0, consoleErrors.slice(0, 2).join(" | "));

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
ws.close();
server.close();
child.kill();
process.exit(failed.length ? 1 : 0);
