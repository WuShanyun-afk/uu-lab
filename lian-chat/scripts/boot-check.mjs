/* Headless browser regression for Lian.
 *
 * Reproduces what the unit tests cannot see: the app booting in a real DOM.
 * It covers the 1.9.0 crash "PROVIDERS is not defined", which only happened
 * when an older install (settings.apiKey set, keys[] empty) was upgraded.
 *
 * Usage:
 *   node scripts/boot-check.mjs                 # fresh boot + upgrade boot
 *   LIAN_API_KEY=sk-... node scripts/boot-check.mjs --live   # + real chat turn
 *
 * Exit codes: 0 pass, 1 failure, 2 environment missing (no Edge).
 */
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const LIVE = process.argv.includes("--live");
const REPORT = process.argv.includes("--report");
const API_KEY = process.env.LIAN_API_KEY || process.env.MIMO_API_KEY || "";
const EDGE_CANDIDATES = [
  "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
  "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  "msedge",
];

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".woff2": "font/woff2",
  ".mp3": "audio/mpeg",
  ".txt": "text/plain; charset=utf-8",
};

const failures = [];
function fail(message) {
  failures.push(message);
  console.error(`FAIL ${message}`);
}
function pass(message) {
  console.log(`PASS ${message}`);
}

/* ------------------------------------------------------------------ server */

function startServer() {
  const server = createServer((req, res) => {
    const raw = decodeURIComponent((req.url || "/").split("?")[0]);
    let file = path.join(ROOT, raw === "/" ? "index.html" : raw);
    if (!file.startsWith(ROOT)) {
      res.writeHead(403).end("forbidden");
      return;
    }
    if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, "index.html");
    if (!fs.existsSync(file)) {
      res.writeHead(404, { "content-type": "text/plain" }).end("not found");
      return;
    }
    res.writeHead(200, {
      "content-type": MIME[path.extname(file).toLowerCase()] || "application/octet-stream",
      "cache-control": "no-store",
    });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve({ server, port: server.address().port }));
  });
}

/* --------------------------------------------------------------- cdp client */

function cdp(ws) {
  let id = 0;
  const pending = new Map();
  const listeners = new Map();
  return {
    send(method, params = {}) {
      return new Promise((resolve, reject) => {
        const messageId = ++id;
        pending.set(messageId, { resolve, reject });
        ws.send(JSON.stringify({ id: messageId, method, params }));
      });
    },
    on(method, fn) {
      if (!listeners.has(method)) listeners.set(method, new Set());
      listeners.get(method).add(fn);
    },
    dispatch(message) {
      if (message.id && pending.has(message.id)) {
        const { resolve, reject } = pending.get(message.id);
        pending.delete(message.id);
        if (message.error) reject(new Error(JSON.stringify(message.error)));
        else resolve(message.result);
        return;
      }
      for (const fn of listeners.get(message.method) || []) fn(message.params);
    },
  };
}

async function waitForHttp(url, timeoutMs = 15000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const response = await fetch(url);
      if (response.ok) return await response.json();
    } catch {
      // not up yet
    }
    await sleep(150);
  }
  throw new Error(`timeout waiting for ${url}`);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/* --------------------------------------------------------------------- main */

function findEdge() {
  for (const candidate of EDGE_CANDIDATES) {
    if (candidate === "msedge") return candidate;
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

const edge = findEdge();
if (!edge) {
  console.error("SKIP: Microsoft Edge not found, browser regression not run");
  process.exit(2);
}

const { server, port } = await startServer();
const base = `http://127.0.0.1:${port}/`;
const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-boot-"));
const debugPort = 9500 + Math.floor(Math.random() * 400);
const child = spawn(edge, [
  "--headless=new",
  "--disable-gpu",
  "--no-first-run",
  "--no-default-browser-check",
  "--disable-extensions",
  "--mute-audio",
  `--user-data-dir=${profile}`,
  `--remote-debugging-port=${debugPort}`,
  "about:blank",
], { stdio: "ignore" });

let ws;
let client;
const consoleErrors = [];
const pageExceptions = [];

try {
  await waitForHttp(`http://127.0.0.1:${debugPort}/json/version`);
  const targets = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
  const page = targets.find((t) => t.type === "page");
  if (!page) throw new Error("no debuggable page");
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    ws.onopen = resolve;
    ws.onerror = reject;
  });
  client = cdp(ws);
  ws.onmessage = (event) => client.dispatch(JSON.parse(event.data));

  await client.send("Runtime.enable");
  await client.send("Page.enable");
  await client.send("Log.enable");
  await client.send("Emulation.setDeviceMetricsOverride", {
    width: 390, height: 844, deviceScaleFactor: 2, mobile: true,
    screenWidth: 390, screenHeight: 844,
  });

  client.on("Runtime.exceptionThrown", (params) => {
    pageExceptions.push(params.exceptionDetails?.exception?.description || JSON.stringify(params));
  });
  client.on("Runtime.consoleAPICalled", (params) => {
    if (params.type !== "error") return;
    const text = (params.args || []).map((arg) => arg.value ?? arg.description ?? "").join(" ");
    if (/favicon|Failed to load resource/i.test(text)) return;
    consoleErrors.push(text);
  });

  async function evaluate(expression, { awaitPromise = true } = {}) {
    const result = await client.send("Runtime.evaluate", {
      expression, awaitPromise, returnByValue: true, userGesture: true,
    });
    if (result.exceptionDetails) {
      throw new Error(result.exceptionDetails.exception?.description || JSON.stringify(result.exceptionDetails));
    }
    return result.result?.value;
  }

  async function waitFor(expression, timeoutMs, label) {
    const started = Date.now();
    while (Date.now() - started < timeoutMs) {
      if (await evaluate(expression)) return true;
      await sleep(120);
    }
    fail(`timeout waiting for ${label}`);
    return false;
  }

  async function boot() {
    consoleErrors.length = 0;
    pageExceptions.length = 0;
    await client.send("Page.navigate", { url: base });
    const started = Date.now();
    while (Date.now() - started < 15000) {
      const state = await evaluate(
        `document.querySelector("#boot.is-done") ? "done" : (document.body.innerText.includes("启动失败") ? "failed" : "pending")`,
      ).catch(() => "pending");
      if (state !== "pending") return state;
      await sleep(150);
    }
    return "timeout";
  }

  /* --------------------------------------------- phase 1: fresh install boot */

  let state = await boot();
  if (state === "done") pass("fresh install boots to the app shell");
  else fail(`fresh install did not boot (state=${state})`);
  const shell = await evaluate(`({
    screen: document.body.dataset.screen,
    tabs: document.querySelectorAll("#tabBar [data-tab]").length,
    boot: document.querySelector("#boot").className,
    text: document.body.innerText.slice(0, 200),
  })`);
  if (shell.screen && shell.tabs === 3) pass(`bottom tab bar has 3 entries (screen=${shell.screen})`);
  else fail(`tab bar unexpected: ${JSON.stringify(shell)}`);
  if (/启动失败|is not defined/.test(shell.text)) fail(`boot error text: ${shell.text}`);

  /* ------------------------------ phase 2: upgrade from 1.8 (the real crash) */

  const legacy = {
    onboarded: true,
    setupStep: 0,
    settings: {
      apiKey: "legacy",
      provider: "mimo",
      baseUrl: "https://api.xiaomimimo.com/v1",
      model: "mimo-v2.6-flash",
      aiName: "沈言",
      userName: "小满",
      persona: "话少，克制。",
      greeting: "你来啦。",
    },
    messages: [{ id: "m1", role: "assistant", kind: "text", text: "你来啦。", ts: Date.now() - 60000 }],
    activeChatId: "",
    activeKeyId: "",
    keys: [],
  };
  await evaluate(`(async () => {
    localStorage.clear();
    await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
    localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(legacy))});
    return true;
  })()`);
  state = await boot();
  if (state === "done") pass("upgrade from a 1.8-style state (apiKey, no keys[]) boots");
  else fail(`upgrade boot crashed (state=${state})`);

  const upgraded = await evaluate(`({
    screen: document.body.dataset.screen,
    chatRows: document.querySelectorAll("[data-chat-open]").length,
    aiName: (document.querySelector(".chat-row-name, [data-chat-open]") || {}).textContent || "",
    text: document.body.innerText.slice(0, 200),
  })`);
  if (upgraded.chatRows >= 1) pass(`legacy chat migrated into the list (${upgraded.chatRows} row)`);
  else fail(`legacy chat missing after migration: ${JSON.stringify(upgraded)}`);

  const keyMigration = await evaluate(`(async () => {
    await new Promise((resolve) => setTimeout(resolve, 800));
    const value = await new Promise((resolve) => {
      const req = indexedDB.open("lian-chat", 2);
      req.onsuccess = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains("state")) return resolve(null);
        const get = db.transaction("state", "readonly").objectStore("state").get("main");
        get.onsuccess = () => resolve(get.result || null);
        get.onerror = () => resolve(null);
      };
      req.onerror = () => resolve(null);
    });
    if (!value) return { persisted: false };
    return { persisted: true, keys: (value.keys || []).length, chats: (value.chats || []).length, activeKeyId: value.activeKeyId };
  })()`);
  if (keyMigration.persisted && keyMigration.keys >= 1) {
    pass(`legacy settings.apiKey became a saved key entry (keys=${keyMigration.keys}, chats=${keyMigration.chats})`);
  } else {
    fail(`legacy settings.apiKey was not persisted as a key: ${JSON.stringify(keyMigration)}`);
  }

  /* ------------------------------- phase 3: report renders inline, no iframe */

  const reportState = JSON.parse(JSON.stringify(legacy));
  reportState.messages = [
    {
      id: "r1",
      role: "assistant",
      kind: "report",
      ts: Date.now() - 30000,
      report: {
        title: "窗边的下午",
        summary: "吃了鸡蛋，窗外下雨了。",
        html: "",
        blocks: [
          { text: "下午煎了两个蛋，蛋黄还是流心的。<script>window.__pwned = 1;</script>", scene: "egg" },
          { text: "吃完把窗推开，外面在下雨。", scene: "rain" },
          { text: "坐着听了会儿歌，想了你一下。", scene: "music" },
          { text: "这一句没有画面。", scene: "" },
        ],
        createdAt: Date.now() - 30000,
      },
    },
    {
      id: "r2",
      role: "assistant",
      kind: "report",
      ts: Date.now() - 20000,
      report: {
        title: "旧版报备",
        summary: "1.9.0 之前存下来的 HTML 报备。",
        html: '<h2>旧版报备</h2><p>第一段。</p><p onclick="alert(1)">第二段。</p><p>第三段。</p>',
        createdAt: Date.now() - 20000,
      },
    },
  ];
  await evaluate(`(async () => {
    localStorage.clear();
    await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
    localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(reportState))});
    return true;
  })()`);
  state = await boot();
  if (state !== "done") fail("report phase failed to boot");
  await evaluate(`(document.querySelector("[data-chat-open]") || {click(){}}).click()`);
  await waitFor(`document.querySelectorAll("[data-report]").length >= 2`, 8000, "report cards");
  await evaluate(`document.querySelector("[data-report]").click()`);
  await waitFor(`!!document.querySelector("#reportDirect")`, 8000, "report viewer");
  const report = await evaluate(`({
    blocks: document.querySelectorAll("#reportDirect .report-block").length,
    scenes: document.querySelectorAll("#reportDirect .report-scene svg").length,
    textScenes: document.querySelectorAll("#reportDirect .report-block.is-text").length,
    iframes: document.querySelectorAll("iframe").length,
    scripts: document.querySelectorAll("#reportDirect script, #reportDirect img, #reportDirect a").length,
    pwned: Boolean(window.__pwned),
    inlineHandlers: [...document.querySelectorAll("#reportDirect *")].filter((el) => el.hasAttribute("onclick")).length,
    playing: document.querySelector("#reportDirect")?.classList.contains("is-playing") || false,
    hasReplay: !!document.querySelector("#reportReplay"),
    firstText: (document.querySelector("#reportDirect .report-block p") || {}).textContent || "",
  })`);
  if (report.blocks === 4) pass(`report renders ${report.blocks} text blocks`);
  else fail(`report blocks unexpected: ${JSON.stringify(report)}`);
  if (report.scenes === 3) pass(`report renders ${report.scenes} local scene illustrations`);
  else fail(`scene illustrations missing: ${JSON.stringify(report)}`);
  if (report.textScenes === 1) pass("block without a scene renders as text only");
  else fail(`text-only block missing: ${JSON.stringify(report)}`);
  if (report.iframes === 0) pass("report renders without an iframe");
  else fail(`report still creates ${report.iframes} iframe(s)`);
  if (report.scripts === 0 && report.inlineHandlers === 0 && !report.pwned) pass("report content is escaped and sanitised before rendering");
  else fail(`report sanitising failed: ${JSON.stringify(report)}`);
  if (report.hasReplay) {
    await evaluate(`document.querySelector("#reportReplay").click()`);
    let replaying = false;
    for (let attempt = 0; attempt < 10 && !replaying; attempt += 1) {
      replaying = await evaluate(`document.querySelector("#reportDirect")?.classList.contains("is-playing") || false`);
      if (!replaying) await sleep(100);
    }
    if (replaying) pass("report replay re-triggers the reveal animation");
    else fail("report replay did not re-trigger the reveal animation");
  } else {
    fail("report replay button missing");
  }
  await evaluate(`document.querySelector("#reportDone")?.click()`);

  // Legacy HTML reports saved before 1.9.3 must still open.
  await waitFor(`document.querySelectorAll("[data-report]").length >= 2`, 5000, "legacy report card");
  await evaluate(`document.querySelectorAll("[data-report]")[1].click()`);
  await waitFor(`!!document.querySelector("#reportDirect")`, 8000, "legacy report viewer");
  const legacyReport = await evaluate(`({
    headings: document.querySelectorAll("#reportDirect h2").length,
    scripts: document.querySelectorAll("#reportDirect script").length,
    inlineHandlers: [...document.querySelectorAll("#reportDirect *")].filter((el) => el.hasAttribute("onclick")).length,
  })`);
  if (legacyReport.headings >= 1 && legacyReport.scripts === 0 && legacyReport.inlineHandlers === 0) {
    pass("legacy HTML report still renders through the sanitiser");
  } else {
    fail(`legacy report failed: ${JSON.stringify(legacyReport)}`);
  }
  await evaluate(`document.querySelector("#reportDone")?.click()`);

  /* ------------------------------------------ phase 4: optional live chat run */

  if (LIVE) {
    if (!API_KEY) {
      fail("--live requested but LIAN_API_KEY is not set");
    } else {
      const liveState = JSON.parse(JSON.stringify(legacy));
      liveState.settings.apiKey = API_KEY;
      liveState.messages = [];
      await evaluate(`(async () => {
        localStorage.clear();
        await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
        localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(liveState))});
        return true;
      })()`);
      state = await boot();
      if (state !== "done") fail("live phase failed to boot");

      await evaluate(`(document.querySelector("[data-chat-open]") || {click(){}}).click()`);
      await waitFor(`!!document.querySelector("#messageInput")`, 8000, "composer");
      const baseline = await evaluate(`document.querySelectorAll(".msg.ai").length`);
      await evaluate(`(() => {
        const input = document.querySelector("#messageInput");
        input.value = "在吗？用一句话回我。";
        input.dispatchEvent(new Event("input", { bubbles: true }));
        const form = document.querySelector("#composer");
        form.requestSubmit ? form.requestSubmit() : form.submit();
        return true;
      })()`);

      await waitFor(`document.querySelectorAll(".msg.user").length >= 1`, 15000, "user bubble");
      const replied = await waitFor(
        `document.querySelectorAll(".msg.ai").length > ${baseline} || !!document.querySelector("#errorBar:not([hidden])")`,
        120000,
        "assistant reply",
      );
      const reply = await evaluate(`(() => {
        const bubbles = [...document.querySelectorAll(".msg.ai")];
        const last = bubbles.at(-1);
        const err = document.querySelector("#errorBar:not([hidden])");
        return {
          text: last ? last.innerText.trim().replace(/\\s+/g, " ").slice(0, 120) : "",
          error: err ? err.innerText.trim().replace(/\\s+/g, " ").slice(0, 160) : "",
          aiMessages: bubbles.length,
          userMessages: document.querySelectorAll(".msg.user").length,
          greetingOnly: bubbles.length === 1,
        };
      })()`);
      if (replied && reply.text && !reply.greetingOnly) pass(`live chat replied: "${reply.text}"`);
      else fail(`live chat produced no new assistant message (baseline=${baseline}, ai=${reply.aiMessages}, error=${reply.error || "none"})`);
      if (reply.error) fail(`live chat surfaced an error: ${reply.error}`);
      const integrity = await evaluate(`(() => {
        const ids = [...document.querySelectorAll("#messageList .msg")].map((el) => el.dataset.message);
        return { count: ids.length, unique: new Set(ids).size };
      })()`);
      if (integrity.count === integrity.unique && integrity.count >= 2) {
        pass(`incremental chat render has no duplicated bubbles (${integrity.count} messages)`);
      } else {
        fail(`chat DOM looks wrong after append: ${JSON.stringify(integrity)}`);
      }
    }
  }

  /* ------------------------------ phase 5: live report generation (optional) */

  if (REPORT) {
    if (!API_KEY) {
      fail("--report requested but LIAN_API_KEY is not set");
    } else {
      const reportSeed = JSON.parse(JSON.stringify(legacy));
      reportSeed.settings.apiKey = API_KEY;
      reportSeed.messages = [
        { id: "p1", role: "user", kind: "text", text: "中午吃了什么？", ts: Date.now() - 7200000 },
        { id: "p2", role: "assistant", kind: "text", text: "随便煎了两个蛋，喝了杯咖啡。窗外在下雨。", ts: Date.now() - 7000000 },
        { id: "p3", role: "user", kind: "text", text: "那下午呢？", ts: Date.now() - 3600000 },
        { id: "p4", role: "assistant", kind: "text", text: "把旧歌翻出来听，想着晚上要不要煮面。", ts: Date.now() - 3500000 },
      ];
      await evaluate(`(async () => {
        localStorage.clear();
        await new Promise((resolve) => { const req = indexedDB.deleteDatabase("lian-chat"); req.onsuccess = req.onerror = req.onblocked = () => resolve(); });
        localStorage.setItem("lian.state.fallback.v1", ${JSON.stringify(JSON.stringify(reportSeed))});
        return true;
      })()`);
      state = await boot();
      if (state !== "done") fail("report generation phase failed to boot");

      await evaluate(`document.querySelector('[data-tab="home"]')?.click()`);
      await waitFor(`!!document.querySelector('[data-home-action="report"]')`, 6000, "report quick entry");
      await evaluate(`document.querySelector('[data-home-action="report"]').click()`);
      await waitFor(`!!document.querySelector("#reportGenerate")`, 6000, "report sheet");
      // openSheet binds its buttons inside requestAnimationFrame, so give the
      // first frame a moment before tapping the primary action.
      await sleep(400);
      await evaluate(`document.querySelector("#reportGenerate").click()`);

      const ok = await waitFor(
        `document.querySelectorAll("#reportDirect .report-block").length >= 2 || !!document.querySelector("#reportError:not([hidden])")`,
        60000,
        "model-generated report",
      );
      if (!ok) {
        const diag = await evaluate(`(() => {
          const button = document.querySelector("#reportGenerate");
          const error = document.querySelector("#reportError");
          const toastEl = document.querySelector(".toast");
          return {
            buttonText: button ? button.textContent.trim().slice(0, 40) : "(sheet closed)",
            buttonDisabled: button ? button.disabled : null,
            errorText: error ? error.textContent.trim().slice(0, 160) : "",
            toastText: toastEl ? toastEl.textContent.trim().slice(0, 120) : "",
            sheetOpen: !!document.querySelector("#sheetLayer:not([hidden])"),
            directExists: !!document.querySelector("#reportDirect"),
            directHtml: (document.querySelector("#reportDirect") || {}).innerHTML?.slice(0, 200) || "",
            apiRequests: performance.getEntriesByType("resource").filter((r) => r.name.includes("xiaomimimo")).map((r) => ({ name: r.name.slice(-40), ms: Math.round(r.duration), size: r.transferSize })),
          };
        })()`);
        console.log("diag:", JSON.stringify(diag, null, 2));
      }
      const generated = await evaluate(`(() => {
        const blocks = [...document.querySelectorAll("#reportDirect .report-block")];
        const error = document.querySelector("#reportError:not([hidden])");
        const card = document.querySelector(".report-card");
        return {
          blocks: blocks.length,
          scenes: document.querySelectorAll("#reportDirect .report-scene svg").length,
          example: (blocks[0]?.querySelector("p") || {}).textContent || "",
          scenesUsed: [...document.querySelectorAll("#reportDirect .report-scene")].length,
          cardTitle: card ? (card.querySelector("h3") || {}).textContent : "",
          error: error ? error.textContent.trim().slice(0, 120) : "",
        };
      })()`);
      if (generated.blocks >= 2) pass(`model report rendered ${generated.blocks} blocks with ${generated.scenes} illustrations`);
      else fail(`model report did not render blocks: ${JSON.stringify(generated)}`);
      if (generated.scenes >= 1) pass(`model picked at least one scene (${generated.scenesUsed} illustrations)`);
      else fail(`model report had no scene illustrations: ${JSON.stringify(generated)}`);
      if (generated.error) fail(`report generation surfaced an error: ${generated.error}`);

      const reportShot = path.join(ROOT, "docs", "test-1.9.10-report-live.png");
      await sleep(2600); // let the staggered reveal animation finish
      const shotData = await client.send("Page.captureScreenshot", { format: "png", fromSurface: true });
      fs.mkdirSync(path.dirname(reportShot), { recursive: true });
      fs.writeFileSync(reportShot, Buffer.from(shotData.data, "base64"));
      console.log(`live report screenshot: ${reportShot}`);
    }
  }

  if (consoleErrors.length) {
    fail(`console errors: ${JSON.stringify(consoleErrors.slice(0, 4))}`);
  } else {
    pass("no console errors during boot phases");
  }
  if (pageExceptions.length) {
    fail(`uncaught page exceptions: ${JSON.stringify(pageExceptions.slice(0, 4))}`);
  } else {
    pass("no uncaught page exceptions");
  }

  const shot = await client.send("Page.captureScreenshot", { format: "png", fromSurface: true });
  const outShot = path.join(ROOT, "docs", "test-1.9.12-boot.png");
  fs.mkdirSync(path.dirname(outShot), { recursive: true });
  fs.writeFileSync(outShot, Buffer.from(shot.data, "base64"));
  console.log(`screenshot: ${outShot}`);
} catch (error) {
  fail(`harness error: ${error.message}`);
} finally {
  try { ws?.close(); } catch { /* ignore */ }
  child.kill("SIGKILL");
  server.close();
  await sleep(300);
  try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* ignore */ }
}

if (failures.length) {
  console.error(`\n${failures.length} failure(s)`);
  process.exit(1);
}
console.log("\nall boot checks passed");
