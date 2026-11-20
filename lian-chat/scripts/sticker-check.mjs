/* Sticker pack checks for 1.9.7: the 42 menhera-kun cut-outs, the legacy bi_*
 * aliases, and the sheet in both colour schemes.
 *
 *   node scripts/sticker-check.mjs
 *
 * Pure DOM driving, no network. Writes docs/test-1.9.8-stickers.png,
 * docs/test-1.9.8-stickers-full.png and docs/test-1.9.8-stickers-dark.png.
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

const profile = fs.mkdtempSync(path.join(os.tmpdir(), "lian-sticker-"));
const debugPort = 9990 + Math.floor(Math.random() * 40);
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
  { id: "m1", role: "assistant", kind: "text", text: "你来啦。今天过得怎么样？", ts: now - 3600000 },
  { id: "m2", role: "user", kind: "text", text: "今天降温了，我出门忘了带外套。", ts: now - 3480000 },
  // saved by 1.9.6 with the old prefix; must still render after the rename
  { id: "m3", role: "assistant", kind: "sticker", stickerId: "bi_shy", text: "", ts: now - 3420000 },
  { id: "m4", role: "assistant", kind: "text", text: "外套我拿着了。", ts: now - 3360000 },
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
// the first evaluate can land on about:blank where localStorage is denied
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
await sleep(450);

const results = [];
const capture = async (name) => {
  const result = await send("Page.captureScreenshot", { format: "png", fromSurface: true, captureBeyondViewport: false });
  fs.writeFileSync(path.join(ROOT, "docs", name), Buffer.from(result.data, "base64"));
};
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};

/* ---------- the old bi_* message still shows its sticker ---------- */
await waitFor(`!!document.querySelector("[data-chat-open]")`, 8000, "chat list");
await evaluate(`document.querySelector("[data-chat-open]").click()`);
await waitFor(`document.querySelectorAll(".msg").length >= 3`, 8000, "messages");
const legacy = await evaluate(`(() => {
  const cells = Array.from(document.querySelectorAll(".msg .msg-sticker img"));
  return { count: cells.length, src: cells.map((img) => img.getAttribute("src")), missing: document.querySelectorAll(".msg .is-missing").length };
})()`);
check(
  "a 1.9.6 bi_shy message renders as mk_shy",
  legacy.count >= 1 && legacy.src.some((s) => s.includes("mk_shy.webp")) && legacy.missing === 0,
  JSON.stringify(legacy),
);

/* ---------- alias resolution in the module itself ---------- */
const alias = await evaluate(`(async () => {
  const cfg = await import("./js/config.js");
  return {
    legacy: cfg.getSticker("bi_sleepy")?.id || null,
    current: cfg.getSticker("mk_sleepy")?.id || null,
    unknown: cfg.getSticker("bi_gone")?.id || null,
    packs: cfg.BUILTIN_PACKS.map((p) => [p.id, p.name, p.stickers.length]),
    total: cfg.BUILTIN_STICKERS.length,
  };
})()`);
check(
  "config exposes menhera_kun (44) and menhera_jiang (25)",
  alias.total === 69 &&
    alias.packs.length === 2 &&
    alias.packs[0][0] === "menhera_kun" && alias.packs[0][2] === 44 &&
    alias.packs[1][0] === "menhera_jiang" && alias.packs[1][2] === 25,
  JSON.stringify(alias.packs),
);
check("bi_sleepy resolves to mk_sleepy, unknown bi_ id resolves to nothing", alias.legacy === "mk_sleepy" && alias.current === "mk_sleepy" && alias.unknown === null, JSON.stringify(alias));

/* ---------- the sheet ---------- */
const openTiming = await evaluate(`(async () => {
  const t0 = performance.now();
  document.querySelector("#btnSticker").click();
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  const painted = performance.now() - t0;
  const imgs = Array.from(document.querySelectorAll(".sticker-cell.builtin img"));
  const t1 = performance.now();
  await Promise.all(imgs.map((img) => (img.decode ? img.decode().catch(() => {}) : Promise.resolve())));
  return { painted: Math.round(painted), decoded: Math.round(performance.now() - t1), count: imgs.length };
})()`);
await waitFor(`!!document.querySelector("#stickerGrid")`, 5000, "sticker sheet");
await sleep(400);
check(
  "69-cell sheet paints fast",
  openTiming.count === 69 && openTiming.painted < 250,
  `paint ${openTiming.painted}ms, images decoded ${openTiming.decoded}ms`,
);
const sheet = await evaluate(`(() => {
  const cells = Array.from(document.querySelectorAll(".sticker-cell.builtin"));
  const imgs = cells.map((cell) => cell.querySelector("img"));
  return {
    cells: cells.length,
    labels: Array.from(document.querySelectorAll(".sticker-group-label")).map((el) => el.textContent),
    chips: Array.from(document.querySelectorAll(".sticker-pack-chip")).map((el) => el.textContent),
    onChip: (document.querySelector(".sticker-pack-chip.is-on") || {}).textContent || "",
    loaded: imgs.filter((img) => img.complete && img.naturalWidth > 0).length,
    ids: cells.map((cell) => cell.dataset.sticker),
    names: cells.map((cell) => cell.querySelector(".cell-name")?.textContent || ""),
  };
})()`);
check("builtin tab lists all 69 stickers", sheet.cells === 69, `${sheet.cells} cells`);
check("every cut-out actually loaded", sheet.loaded === 69, `${sheet.loaded}/69`);
check(
  "both packs get a labelled group",
  sheet.labels.some((text) => text.includes("menhera君") && text.includes("44")) &&
    sheet.labels.some((text) => text.includes("menhera酱") && text.includes("25")),
  JSON.stringify(sheet.labels),
);
check(
  "pack chips appear once there are two packs",
  sheet.chips.length === 3 && sheet.chips[0].includes("69") && sheet.chips[1].includes("44") && sheet.chips[2].includes("25"),
  JSON.stringify(sheet.chips),
);
check("the default chip is 全部", sheet.onChip.includes("全部"), sheet.onChip);
check(
  "ids and names look right at the seam",
  sheet.ids.includes("mk_hello") && sheet.ids.includes("mk_nope") && sheet.ids.includes("mj_hello") && sheet.ids.includes("mj_huh") &&
    sheet.names.includes("求收养") && sheet.names.includes("陪我嘛"),
  `${sheet.ids[0]} … ${sheet.ids[sheet.ids.length - 1]}`,
);
await capture("test-1.9.8-stickers.png");

/* full pack on one canvas: lift the sheet's height cap and grow the viewport */
await evaluate(`(() => {
  const style = document.createElement("style");
  style.id = "shot-full";
  style.textContent = ".sheet{max-height:none!important}";
  document.head.appendChild(style);
  return true;
})()`);
await send("Emulation.setDeviceMetricsOverride", {
  width: 390, height: 1700, deviceScaleFactor: 2, mobile: true, screenWidth: 390, screenHeight: 1700,
});
await sleep(500);
await evaluate(`(() => { document.querySelector(".sheet").scrollTop = 0; return true; })()`);
await sleep(300);
await capture("test-1.9.8-stickers-full.png");
await evaluate(`document.querySelector("#shot-full").remove()`);
await send("Emulation.setDeviceMetricsOverride", {
  width: 390, height: 844, deviceScaleFactor: 2, mobile: true, screenWidth: 390, screenHeight: 844,
});
await sleep(300);

/* ---------- filtering by pack ---------- */
await evaluate(`document.querySelector('[data-sticker-pack="menhera_jiang"]').click()`);
await sleep(220); // openSheet binds its listeners on the next frame
await waitFor(`document.querySelectorAll(".sticker-cell.builtin").length === 25`, 4000, "jiang filter");
const jiangOnly = await evaluate(`(() => ({
  cells: document.querySelectorAll(".sticker-cell.builtin").length,
  ids: Array.from(document.querySelectorAll(".sticker-cell.builtin")).map((cell) => cell.dataset.sticker),
  labels: Array.from(document.querySelectorAll(".sticker-group-label")).map((el) => el.textContent),
  on: (document.querySelector(".sticker-pack-chip.is-on") || {}).textContent || "",
}))()`);
check(
  "menhera酱 chip shows only its 25 stickers",
  jiangOnly.cells === 25 && jiangOnly.ids.every((id) => id.startsWith("mj_")) && jiangOnly.on.includes("menhera酱"),
  `${jiangOnly.cells} cells · ${jiangOnly.on}`,
);
check("a filtered view keeps a single pack label", jiangOnly.labels.length === 1 && jiangOnly.labels[0].includes("25"), JSON.stringify(jiangOnly.labels));
await capture("test-1.9.8-stickers-jiang.png");
await evaluate(`document.querySelector('[data-sticker-pack="menhera_kun"]').click()`);
await sleep(220);
await waitFor(`document.querySelectorAll(".sticker-cell.builtin").length === 44`, 4000, "kun filter");
check("menhera君 chip shows only its 44 stickers", (await evaluate(`Array.from(document.querySelectorAll(".sticker-cell.builtin")).every((cell) => cell.dataset.sticker.startsWith("mk_"))`)));
await evaluate(`document.querySelector('[data-sticker-pack="all"]').click()`);
await sleep(220);
await waitFor(`document.querySelectorAll(".sticker-cell.builtin").length === 69`, 4000, "all filter");
check("全部 brings the full set back", (await evaluate(`document.querySelectorAll(".sticker-group-label").length`)) === 2);

/* ---------- the other two tabs still work ---------- */
await evaluate(`document.querySelector('[data-sticker-tab="custom"]').click()`);
await sleep(220);
await waitFor(`!!document.querySelector("#addSticker")`, 4000, "custom tab");
const customTab = await evaluate(`(() => ({
  importCell: !!document.querySelector("#addSticker"),
  makeCell: !!document.querySelector("#aiMakeSticker"),
  builtin: document.querySelectorAll(".sticker-cell.builtin").length,
}))()`);
check("custom tab keeps the import and AI cells", customTab.importCell && customTab.makeCell && customTab.builtin === 0, JSON.stringify(customTab));
await evaluate(`document.querySelector('[data-sticker-tab="emoji"]').click()`);
await waitFor(`document.querySelectorAll(".emoji-cell").length > 0`, 4000, "emoji tab");
/* 1.9.12 grew the emoji set (grouped tray), so pin a floor rather than an exact count */
const emojiCells = await evaluate(`(() => {
  const cells = Array.from(document.querySelectorAll(".emoji-cell"));
  return { n: cells.length, keyed: cells.every((cell) => !!cell.dataset.emoji) };
})()`);
check("emoji tab still renders its picker", emojiCells.n >= 24 && emojiCells.keyed, JSON.stringify(emojiCells));
await evaluate(`document.querySelector('[data-sticker-tab="builtin"]').click()`);
await sleep(300);
const backToBuiltin = await evaluate(`(() => ({
  cells: document.querySelectorAll(".sticker-cell.builtin").length,
  tabs: Array.from(document.querySelectorAll(".sticker-tab")).map((el) => [el.dataset.stickerTab, el.classList.contains("is-on")]),
  chips: document.querySelectorAll(".sticker-pack-chip").length,
}))()`);
check("builtin tab comes back with all 69", backToBuiltin.cells === 69, JSON.stringify(backToBuiltin));
await sleep(200);

/* ---------- send one sticker ---------- */
await evaluate(`document.querySelector('[data-sticker="mj_hello"]').click()`);
await sleep(500);
const sent = await evaluate(`(() => {
  const imgs = Array.from(document.querySelectorAll(".msg.user .msg-sticker img"));
  return { count: imgs.length, src: imgs.map((img) => img.getAttribute("src")), missing: document.querySelectorAll(".msg .is-missing").length };
})()`);
check("tapping a sticker sends it", sent.count === 1 && sent.src[0].includes("mj_hello.webp") && sent.missing === 0, JSON.stringify(sent));
await sleep(400);
// the mock endpoint refuses the follow-up reply request; the banner is harness
// noise, not part of the sticker story, so keep it out of the screenshot.
await evaluate(`(() => { const bar = document.querySelector("#errorBar"); if (bar) bar.hidden = true; return true; })()`);
await capture("test-1.9.8-sticker-chat.png");

/* ---------- dark mode: check the matte against a dark bubble ---------- */
await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] });
await sleep(400);
await evaluate(`document.querySelector("#btnSticker").click()`);
await waitFor(`!!document.querySelector("#stickerGrid")`, 5000, "sticker sheet dark");
await sleep(450);
const dark = await evaluate(`(() => {
  const cells = Array.from(document.querySelectorAll(".sticker-cell.builtin"));
  const imgs = cells.map((cell) => cell.querySelector("img"));
  return {
    cells: cells.length,
    loaded: imgs.filter((img) => img.complete && img.naturalWidth > 0).length,
    sheetBg: getComputedStyle(document.querySelector(".sheet")).backgroundColor,
    bodyBg: getComputedStyle(document.body).backgroundColor,
  };
})()`);
check("dark mode keeps every sticker loaded", dark.cells === 69 && dark.loaded === 69, JSON.stringify({ ...dark, cells: dark.cells, loaded: dark.loaded }));
// keep the dark shot short: the top of the sheet shows the tab bar, the pack
// label and the first rows, which is where the matte is judged.
await evaluate(`(() => {
  const style = document.createElement("style");
  style.id = "shot-full";
  style.textContent = ".sheet{max-height:none!important}";
  document.head.appendChild(style);
  return true;
})()`);
await send("Emulation.setDeviceMetricsOverride", {
  width: 390, height: 1500, deviceScaleFactor: 2, mobile: true, screenWidth: 390, screenHeight: 1500,
});
await sleep(500);
await evaluate(`(() => { document.querySelector(".sheet").scrollTop = 0; return true; })()`);
await sleep(300);
await capture("test-1.9.8-stickers-dark.png");
await evaluate(`document.querySelector("#shot-full").remove()`);

check("no console errors", consoleErrors.length === 0, consoleErrors.slice(0, 2).join(" | "));

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
ws.close();
server.close();
child.kill();
process.exit(failed.length ? 1 : 0);
