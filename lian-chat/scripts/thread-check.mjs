/* Regression checks for 1.9.19: async results must land in the chat that
 * started them, empty module threads must stay empty, assistant code must stay
 * code, and the custom accent must survive a visit to the assistant module.
 *
 *   node scripts/thread-check.mjs
 *
 * Drives the real page over CDP. No network: the OpenAI-compatible endpoint is
 * mocked inside the page with a delayed JSON response.
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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-thread-"));
const debugPort = 10020 + Math.floor(Math.random() * 60);
const child = spawn(edge, [
  "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
  "--mute-audio", `--user-data-dir=${profile}`, `--remote-debugging-port=${debugPort}`, "about:blank",
], { stdio: "ignore" });

let targets;
const started = Date.now();
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

const now = Date.now();
const msg = (id, role, text, ts) => ({ id, role, kind: "text", text, ts });
const baseSettings = (mode) => ({
  provider: "custom", apiKey: "seed", baseUrl: "http://127.0.0.1:1/v1", model: "m",
  aiName: "沈砚", userName: "小满", relationship: "客栈老板与常来的刀客", persona: "话少。",
  theme: "paper", layout: "line", mode,
  realism: { enabled: false },
  optimize: { streaming: false, quotes: false, segments: false },
});
const chat = (id, mode, name, messages, extra = {}) => ({
  id, mode, kind: mode === "companion" ? "" : "module", name, keyId: "k1", avatar: "",
  relationship: "", persona: "", greeting: "", messages, memories: [],
  memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
  block: null, blockFollowUp: null, createdAt: now - 86400000, updatedAt: now,
  ...extra,
});
const key = { id: "k1", name: "Mock", provider: "custom", apiKey: "seed", baseUrl: "http://127.0.0.1:1/v1", model: "m", createdAt: now };
const wrap = (settings, chats, activeChatId, messages, activeByMode) => ({
  onboarded: true, settings, chats, keys: [key], activeChatId, activeKeyId: "k1",
  activeByMode: activeByMode || { companion: activeChatId, roleplay: "", assistant: "" },
  messages, memories: [], memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
});

async function waitBoot() {
  for (let attempt = 0; attempt < 150; attempt += 1) {
    if (await evaluate(`!document.querySelector("#boot") || !!document.querySelector("#boot.is-done")`)) break;
    await sleep(110);
  }
  await sleep(360);
}

async function boot(seed) {
  await send("Page.navigate", { url: base });
  await sleep(420);
  await evaluate(`(async () => {
    localStorage.clear();
    await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
    localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(seed))});
    return true;
  })()`);
  await send("Page.reload");
  await waitBoot();
}

const readChats = () => evaluate(`(async () => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open("lian-chat"); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  const st = await new Promise((res, rej) => { const tx = db.transaction("state", "readonly"); const rq = tx.objectStore("state").get("main"); rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });
  if (!st) return null;
  return {
    activeChatId: st.activeChatId,
    settings: { theme: st.settings.theme, accent: st.settings.accent, modeTheme: st.settings.modeTheme, modeAccent: st.settings.modeAccent },
    chats: (st.chats || []).map((c) => ({ id: c.id, mode: c.mode, name: c.name, greeting: c.greeting, texts: (c.messages || []).map((m) => m.text), memories: (c.memories || []).map((m) => m.text) })),
  };
})()`);

const openRow = async (name) => {
  await evaluate(`(() => { const row = [...document.querySelectorAll("[data-chat-open]")].find((n) => n.textContent.includes(${JSON.stringify(name)})); row?.click(); })()`);
  await sleep(520);
};
const openChatById = async (id) => {
  await evaluate(`document.querySelector('[data-chat-open="${id}"]')?.click()`);
  await sleep(520);
};
const openModuleTab = async () => {
  await evaluate(`document.querySelector('[data-tab="module"]').click()`);
  await sleep(360);
};
const pickModule = async (mode) => {
  await evaluate(`document.querySelector('[data-module-pick="${mode}"]')?.click()`);
  await sleep(650);
};
const mockReply = async (content, delay = 1500, extra = {}) => {
  await evaluate(`(() => {
    window.__mockCalls = 0;
    window.__lastBody = null;
    const real = window.fetch;
    window.fetch = (url, opts) => {
      if (String(url).includes("/chat/completions")) {
        window.__mockCalls += 1;
        try { window.__lastBody = JSON.parse(opts?.body || "null"); } catch { window.__lastBody = null; }
        return new Promise((resolve) => setTimeout(() => resolve(new Response(JSON.stringify({
          id: "x", choices: [{ index: 0, message: { role: "assistant", content: ${JSON.stringify(content)}, ...${JSON.stringify(extra)} }, finish_reason: "stop" }],
          usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 },
        }), { status: 200, headers: { "content-type": "application/json" } })), ${delay}));
      }
      return real(url, opts);
    };
  })()`);
};
const sendText = async (text) => {
  await evaluate(`(() => {
    const input = document.querySelector("#messageInput");
    input.value = ${JSON.stringify(text)};
    input.dispatchEvent(new Event("input", { bubbles: true }));
    document.querySelector("#btnSend").click();
  })()`);
};

/* ================= 1. a reply must stay in the chat that asked ================= */
{
  const companion = [msg("m1", "assistant", "老位置。", now - 5000), msg("m2", "user", "今天有热的吗？", now - 4000)];
  const assistant = [msg("a1", "assistant", "在。要处理什么？", now - 9000)];
  await boot(wrap(baseSettings("companion"), [
    chat("c1", "companion", "沈砚", companion),
    chat("c3", "assistant", "Lian", assistant, { updatedAt: now - 600000 }),
  ], "c1", companion, { companion: "c1", roleplay: "", assistant: "c3" }));
  await openRow("沈砚");
  await mockReply("这条回答属于陪伴会话", 1500);
  await sendText("在吗");
  await sleep(280);
  await openModuleTab();
  await pickModule("assistant");
  await sleep(3200);
  const state = await readChats();
  const c1 = state?.chats.find((c) => c.id === "c1");
  const c3 = state?.chats.find((c) => c.id === "c3");
  check("reply stays in the companion thread after switching modules", Boolean(c1?.texts.includes("这条回答属于陪伴会话")), JSON.stringify(c1?.texts));
  check("the assistant thread did not receive the companion reply", !c3?.texts.some((t) => String(t).includes("属于陪伴会话")), JSON.stringify(c3?.texts));
  const visible = await evaluate(`document.querySelector("#messageList").innerText`);
  check("the assistant page shows no companion reply", !visible.includes("属于陪伴会话"), visible.slice(0, 60));
  check("the companion thread got no duplicate", (c1?.texts.filter((t) => t === "这条回答属于陪伴会话").length || 0) === 1, String(c1?.texts.length));
}

/* ================= 2. regenerating then switching must not damage history ================= */
{
  const a = [
    msg("a1", "assistant", "A 的第一句", now - 4000),
    msg("a2", "user", "A 的提问", now - 3900),
    msg("a3", "assistant", "A 的旧回答", now - 3800),
    msg("a4", "user", "A 的最后一句", now - 3700),
  ];
  const b = [msg("b1", "assistant", "B 的第一句", now - 2000), msg("b2", "user", "B 的提问", now - 1900)];
  await boot(wrap(baseSettings("companion"), [
    chat("cA", "companion", "甲", a),
    chat("cB", "companion", "乙", b, { updatedAt: now - 600000 }),
  ], "cA", a));
  await openRow("甲");
  await mockReply("A 的新回答", 1800);
  await evaluate(`(() => {
    const node = document.querySelector('.msg[data-message="a3"] .bubble');
    const r = node.getBoundingClientRect();
    node.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, cancelable: true, clientX: r.left + 20, clientY: r.top + 10, pointerType: "mouse", button: 0, isPrimary: true }));
  })()`);
  await sleep(700);
  const menu = await evaluate(`!!document.querySelector(".msg-menu [data-menu='regen']")`);
  check("the regenerate menu opens", menu, String(menu));
  await evaluate(`document.querySelector(".msg-menu [data-menu='regen']")?.click()`);
  await sleep(300);
  await evaluate(`document.querySelector('[data-tab="list"]').click()`);
  await sleep(300);
  await openRow("乙");
  await sleep(3300);
  const state = await readChats();
  const chatA = state?.chats.find((c) => c.id === "cA");
  const chatB = state?.chats.find((c) => c.id === "cB");
  check("regenerating then switching keeps the tail of the original chat", chatA?.texts.join("|") === "A 的第一句|A 的提问|A 的新回答|A 的最后一句", JSON.stringify(chatA?.texts));
  check("the chat switched to keeps its own history", chatB?.texts.join("|") === "B 的第一句|B 的提问", JSON.stringify(chatB?.texts));
  check("the regenerated text did not leak into the other chat", !chatB?.texts.some((t) => String(t).includes("A 的新回答")), JSON.stringify(chatB?.texts));
  check("the header still says 乙", (await evaluate(`document.querySelector("#peerName")?.textContent`)) === "乙", await evaluate(`document.querySelector("#peerName")?.textContent`));
}

/* ================= 3. an empty roleplay thread stays empty after a reload ================= */
{
  const companion = [msg("m1", "assistant", "老位置。", now - 5000)];
  const seed = wrap(baseSettings("roleplay"), [
    chat("c1", "companion", "沈砚", companion),
    chat("cR", "roleplay", "剧本", [], { greeting: "" }),
  ], "cR", [], { companion: "c1", roleplay: "cR", assistant: "" });
  await boot(seed);
  await sleep(400);
  await send("Page.reload");
  await waitBoot();
  await openRow("剧本");
  const state = await readChats();
  const roleplay = state?.chats.find((c) => c.id === "cR");
  const view = await evaluate(`({
    bubbles: [...document.querySelectorAll(".msg .bubble")].map((n) => n.innerText),
    empty: Boolean(document.querySelector(".empty-chat")),
  })`);
  check("an empty roleplay thread is still empty after a reload", (roleplay?.texts.length || 0) === 0, JSON.stringify(roleplay?.texts));
  check("it shows the pick-a-scene empty state", view.empty && view.bubbles.length === 0, JSON.stringify(view));
  check("its greeting stays empty instead of the companion default", (roleplay?.greeting || "") === "", roleplay?.greeting);
}

/* ================= 4. picking a scene reuses the placeholder ================= */
{
  const companion = [msg("m1", "assistant", "老位置。", now - 5000)];
  await boot(wrap(baseSettings("companion"), [chat("c1", "companion", "沈砚", companion)], "c1", companion));
  await openModuleTab();
  await pickModule("roleplay");
  await evaluate(`document.querySelector("[data-open-scenes]")?.click()`);
  await sleep(500);
  const presets = await evaluate(`document.querySelectorAll("[data-preset]").length`);
  check("the empty roleplay page offers the scene cards", presets > 0, String(presets));
  await evaluate(`document.querySelector("[data-preset]")?.click()`);
  await sleep(250);
  await evaluate(`document.querySelector("#newChatForm button[type='submit']")?.click()`);
  await sleep(1100);
  const state = await readChats();
  const roleplayChats = (state?.chats || []).filter((c) => c.mode === "roleplay");
  check("picking a scene leaves exactly one roleplay thread", roleplayChats.length === 1, String(roleplayChats.length));
  check("that thread now holds the scene", roleplayChats[0]?.name === "沈砚" && roleplayChats[0]?.texts.length === 1, JSON.stringify(roleplayChats[0]));
  const header = await evaluate(`document.querySelector("#peerName")?.textContent`);
  check("the chat header shows the scene character", header === "沈砚", header);
}

/* ================= 5. assistant answers keep html/svg code as code ================= */
{
  const assistant = [msg("a1", "assistant", "在。要处理什么？", now - 9000)];
  await boot(wrap(baseSettings("assistant"), [
    chat("c1", "companion", "沈砚", [msg("m1", "assistant", "老位置。", now - 5000)]),
    chat("c3", "assistant", "Lian", assistant, { updatedAt: now }),
  ], "c3", assistant, { companion: "c1", roleplay: "", assistant: "c3" }));
  await openChatById("c3");
  await mockReply("给你一个卡片：\n\n```html\n<div class=\"card\">你好</div>\n```", 900);
  await sendText("给我一个 html 卡片");
  await sleep(2200);
  const view = await evaluate(`(() => ({
    code: document.querySelectorAll(".msg-code").length,
    art: document.querySelectorAll(".msg-art").length,
    copy: document.querySelectorAll("[data-copy-code]").length,
    codeText: [...document.querySelectorAll(".msg-code code")].map((n) => n.textContent).join("|"),
  }))()`);
  check("an html answer renders as a code block", view.code >= 1 && view.codeText.includes('<div class="card">'), JSON.stringify({ code: view.code, text: view.codeText }));
  check("it does not become a drawing", view.art === 0, String(view.art));
  check("the code block offers a copy button", view.copy >= 1, String(view.copy));
}

/* ================= 6. svg source survives in the assistant thread ================= */
{
  const svg = '<svg viewBox="0 0 10 10"><rect x="1" y="1" width="4" height="4"/></svg>';
  const history = [
    msg("u1", "user", `这段 svg 有什么问题？\n${svg}`, now - 100000),
    msg("a1", "assistant", `宽度没写，会默认 300×150。\n\n\`\`\`svg\n${svg}\n\`\`\``, now - 90000),
  ];
  await boot(wrap(baseSettings("assistant"), [
    chat("c1", "companion", "沈砚", [msg("m1", "assistant", "老位置。", now - 5000)]),
    chat("c3", "assistant", "Lian", history, { updatedAt: now }),
  ], "c3", history, { companion: "c1", roleplay: "", assistant: "c3" }));
  await openChatById("c3");
  const view = await evaluate(`(() => ({
    msgs: document.querySelectorAll(".msg").length,
    art: document.querySelectorAll(".msg-art").length,
    text: document.querySelector("#messageList").innerText,
    code: document.querySelectorAll(".msg-code").length,
  }))()`);
  check("a pasted svg is not turned into a picture", view.art === 0, String(view.art));
  check("the pasted svg source is still visible", view.text.includes("<svg"), view.text.slice(0, 80));
  check("the assistant svg reply renders as code", view.code === 1, String(view.code));
  check("the history was not split into extra messages", view.msgs === 2, String(view.msgs));
}

/* ================= 7. a custom accent survives the assistant module ================= */
{
  const seed = wrap({ ...baseSettings("companion"), theme: "custom", accent: "#FF00AA" }, [
    chat("c1", "companion", "沈砚", [msg("m1", "assistant", "老位置。", now - 5000)]),
  ], "c1", [msg("m1", "assistant", "老位置。", now - 5000)]);
  await boot(seed);
  await openModuleTab();
  await pickModule("assistant");
  await sleep(400);
  await openModuleTab();
  await pickModule("companion");
  await sleep(600);
  const state = await readChats();
  const accent = await evaluate(`getComputedStyle(document.body).getPropertyValue("--accent").trim().toUpperCase()`);
  check("the custom theme id comes back", state?.settings.theme === "custom", `${state?.settings.theme}/${state?.settings.modeTheme}`);
  check("the custom accent comes back", String(state?.settings.accent).toUpperCase() === "#FF00AA" && accent === "#FF00AA", `${state?.settings.accent}/${accent}`);
}

/* ================= 8. memory organisation lands in the chat that started it ================= */
{
  const a = [msg("u1", "user", "我喝咖啡不加糖", now - 20000), msg("a1", "assistant", "记住了。", now - 19000)];
  const b = [msg("u2", "user", "今天加班", now - 18000), msg("a2", "assistant", "辛苦。", now - 17000)];
  await boot(wrap(baseSettings("companion"), [
    chat("c1", "companion", "甲", a),
    chat("cB", "companion", "乙", b, { updatedAt: now - 600000 }),
  ], "c1", a));
  await openRow("甲");
  await evaluate(`document.querySelector("#btnPeer")?.click()`);
  await sleep(600);
  await mockReply('{"memories":["小满喝咖啡不加糖"]}', 1400);
  const button = await evaluate(`!!document.querySelector("[data-organize-memory]")`);
  check("the settings page offers memory organisation", button, String(button));
  await evaluate(`document.querySelector("[data-organize-memory]")?.click()`);
  await sleep(300);
  await evaluate(`document.querySelector('[data-tab="list"]').click()`);
  await sleep(300);
  await openRow("乙");
  await sleep(2600);
  const state = await readChats();
  const chatA = state?.chats.find((c) => c.id === "c1");
  const chatB = state?.chats.find((c) => c.id === "cB");
  check("organised memories are written to the chat that asked for them", chatA?.memories.includes("小满喝咖啡不加糖"), JSON.stringify(chatA?.memories));
  check("the chat switched to gets no borrowed memories", (chatB?.memories || []).length === 0, JSON.stringify(chatB?.memories));
}

/* ================= 9. assistant welcome + quick prompts ================= */
{
  const greeting = { ...msg("g1", "assistant", "在。要处理什么？", now - 60000), greeting: true };
  await boot(wrap(baseSettings("assistant"), [
    chat("c1", "companion", "沈砚", [msg("m1", "assistant", "老位置。", now - 5000)]),
    chat("c3", "assistant", "Lian", [greeting], { updatedAt: now }),
  ], "c3", [greeting], { companion: "c1", roleplay: "", assistant: "c3" }));
  await openChatById("c3");
  const welcome = await evaluate(`({
    present: !!document.querySelector("#asWelcome"),
    prompts: document.querySelectorAll(".as-prompt").length,
    greetingActions: document.querySelectorAll('[data-message="g1"] .as-actions').length,
    header: document.querySelector("#peerName")?.textContent,
    toolsHidden: document.querySelector("#assistantTools")?.hidden,
    webDisabled: document.querySelector('[data-assistant-tool="web"]')?.disabled,
    thinkingDisabled: document.querySelector('[data-assistant-tool="thinking"]')?.disabled,
  })`);
  check("the idle assistant page shows the welcome card", welcome.present && welcome.prompts === 4, JSON.stringify(welcome));
  check("the greeting has no copy/regenerate actions", welcome.greetingActions === 0, String(welcome.greetingActions));
  check("the assistant header shows the provider name", welcome.header === "自定义", String(welcome.header));
  check("the capability bar is visible, but disabled off MiMo", welcome.toolsHidden === false && welcome.webDisabled === true && welcome.thinkingDisabled === true, JSON.stringify(welcome));
  await evaluate(`document.querySelector(".as-prompt")?.click()`);
  await sleep(160);
  const filled = await evaluate(`document.querySelector("#messageInput").value`);
  check("a quick prompt fills the composer", String(filled).startsWith("帮我解释这段代码"), filled.slice(0, 20));
  await send("Emulation.setDeviceMetricsOverride", {
    width: 320, height: 568, deviceScaleFactor: 2, mobile: true, screenWidth: 320, screenHeight: 568,
  });
  await sleep(360);
  const narrow = await evaluate(`(() => {
    const header = document.querySelector(".chat-header");
    const heights = (selector) => [...document.querySelectorAll(selector)].map((node) => node.getBoundingClientRect().height);
    return {
      overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      headerOverflow: header ? header.scrollWidth - header.clientWidth : 0,
      actionMin: Math.min(99, ...heights(".as-action")),
      promptMin: Math.min(99, ...heights(".as-prompt")),
    };
  })()`);
  check("the assistant header fits a 320px screen", narrow.overflow <= 0 && narrow.headerOverflow <= 0, JSON.stringify(narrow));
  check("assistant quick prompts stay tappable", narrow.promptMin >= 24, JSON.stringify(narrow));
  await send("Emulation.setDeviceMetricsOverride", {
    width: 390, height: 844, deviceScaleFactor: 2, mobile: true, screenWidth: 390, screenHeight: 844,
  });
  await sleep(260);
  await mockReply("先看边界条件。", 900);
  await evaluate(`(() => {
    const input = document.querySelector("#messageInput");
    input.value = "解释一下";
    input.dispatchEvent(new Event("input", { bubbles: true }));
    document.querySelector("#btnSend").click();
  })()`);
  await sleep(2100);
  const after = await evaluate(`({
    welcome: !!document.querySelector("#asWelcome"),
    actions: document.querySelectorAll(".as-actions").length,
    meta: document.querySelectorAll(".as-meta").length,
    thinking: !!document.querySelector("#asThinking"),
  })`);
  check("the welcome card disappears after the first question", after.welcome === false, String(after.welcome));
  check("the answer offers copy / regenerate", after.actions >= 1, String(after.actions));
  check("every assistant-page message has a meta line", after.meta >= 3, String(after.meta));
  check("the thinking indicator is gone after the reply", after.thinking === false, String(after.thinking));
}

/* ================= 10. MiMo: provider name, web search + deep thinking ================= */
{
  const greeting = { ...msg("g1", "assistant", "在。要处理什么？", now - 60000), greeting: true };
  const mimoSettings = {
    ...baseSettings("assistant"),
    provider: "mimo",
    baseUrl: "https://api.xiaomimimo.com/v1",
    model: "mimo-v2.6-flash",
  };
  const seed = wrap(mimoSettings, [
    chat("c3", "assistant", "Lian", [greeting], { updatedAt: now, keyId: "k2" }),
  ], "c3", [greeting], { companion: "", roleplay: "", assistant: "c3" });
  seed.keys = [{ ...key, id: "k2", name: "MiMo", provider: "mimo", baseUrl: "https://api.xiaomimimo.com/v1", model: "mimo-v2.6-flash" }];
  seed.activeKeyId = "k2";
  await boot(seed);
  await openChatById("c3");
  const header = await evaluate(`document.querySelector("#peerName")?.textContent`);
  check("a MiMo assistant is titled MiMo", header === "MiMo", String(header));
  const caps = await evaluate(`({
    web: document.querySelector('[data-assistant-tool="web"]')?.disabled,
    thinking: document.querySelector('[data-assistant-tool="thinking"]')?.disabled,
  })`);
  check("MiMo enables both capability toggles", caps.web === false && caps.thinking === false, JSON.stringify(caps));
  await evaluate(`document.querySelector('[data-assistant-tool="web"]')?.click()`);
  await evaluate(`document.querySelector('[data-assistant-tool="thinking"]')?.click()`);
  await sleep(200);
  const pressed = await evaluate(`({
    web: document.querySelector('[data-assistant-tool="web"]')?.getAttribute("aria-pressed"),
    thinking: document.querySelector('[data-assistant-tool="thinking"]')?.getAttribute("aria-pressed"),
    thinkingText: document.querySelector("#asThinking")?.innerText || "",
  })`);
  check("the toggles show their pressed state", pressed.web === "true" && pressed.thinking === "true", JSON.stringify(pressed));
  await mockReply("武汉明天多云，22~25℃，记得带伞。", 700, {
    reasoning_content: "先确认日期，再查武汉的天气。",
    annotations: [
      { type: "url_citation", url: "https://example.com/weather/wuhan", title: "武汉天气预报", site_name: "示例天气" },
    ],
  });
  await evaluate(`(() => {
    const input = document.querySelector("#messageInput");
    input.value = "武汉明天天气怎么样？";
    input.dispatchEvent(new Event("input", { bubbles: true }));
    document.querySelector("#btnSend").click();
  })()`);
  await sleep(1900);
  const body = await evaluate(`window.__lastBody || null`);
  check("the request turns on MiMo deep thinking", body?.thinking?.type === "enabled", JSON.stringify(body?.thinking));
  check("the request sends the native web_search tool", body?.tools?.[0]?.type === "web_search" && body?.tool_choice === "auto", JSON.stringify(body?.tools));
  check("thinking is given a larger token budget", Number(body?.max_tokens) >= 4096, String(body?.max_tokens));
  const rendered = await evaluate(`({
    think: !!document.querySelector(".as-think"),
    thinkText: document.querySelector(".as-think-body")?.textContent || "",
    sources: document.querySelectorAll(".as-sources a").length,
    sourceHref: document.querySelector(".as-sources a")?.getAttribute("href") || "",
  })`);
  check("the reasoning panel is rendered", rendered.think && rendered.thinkText.includes("先确认日期"), JSON.stringify(rendered.thinkText?.slice(0, 30)));
  check("web sources are rendered as links", rendered.sources === 1 && rendered.sourceHref.includes("example.com"), JSON.stringify({ n: rendered.sources, href: rendered.sourceHref }));
}

check("no console errors", consoleErrors.length === 0, consoleErrors.slice(0, 2).join(" | "));

const failed = results.filter((item) => !item.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
ws.close();
child.kill("SIGKILL");
server.close();
await sleep(150);
try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
process.exit(failed.length ? 1 : 0);
