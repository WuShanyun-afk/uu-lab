const PORT = process.env.CDP_PORT || "9333";
const TARGET = process.env.CDP_TARGET || "127.0.0.1:4173";
const EXPRESSION = process.env.CDP_EXPR || process.argv[2] || "document.title";
const ACTION = process.env.CDP_ACTION || process.argv[3] || "eval";

const targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
const page = targets.find((t) => t.type === "page" && t.url.includes(TARGET));
if (!page) {
  console.error("Target not found. Available:", targets.filter((t) => t.type === "page").map((t) => t.url));
  process.exit(1);
}

const ws = new WebSocket(page.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();

function send(method, params = {}) {
  return new Promise((resolve, reject) => {
    const messageId = ++id;
    pending.set(messageId, { resolve, reject });
    ws.send(JSON.stringify({ id: messageId, method, params }));
  });
}

ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message.result);
  }
};

await new Promise((resolve) => (ws.onopen = resolve));
await send("Runtime.enable");
await send("Page.enable");
if (process.env.CDP_MOBILE !== "0") {
  await send("Emulation.setDeviceMetricsOverride", {
    width: Number(process.env.CDP_WIDTH || 390),
    height: Number(process.env.CDP_HEIGHT || 844),
    deviceScaleFactor: Number(process.env.CDP_SCALE || 2),
    mobile: true,
    screenWidth: Number(process.env.CDP_WIDTH || 390),
    screenHeight: Number(process.env.CDP_HEIGHT || 844),
  });
  await send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
  await new Promise((r) => setTimeout(r, 400));
}

if (ACTION === "eval") {
  const result = await send("Runtime.evaluate", {
    expression: EXPRESSION,
    awaitPromise: true,
    returnByValue: true,
    userGesture: true,
  });
  if (result.exceptionDetails) {
    console.error(JSON.stringify(result.exceptionDetails, null, 2));
    process.exit(2);
  }
  console.log(JSON.stringify(result.result?.value ?? result.result, null, 2));
} else if (ACTION === "shot") {
  if (process.env.CDP_SCROLL) {
    const scrollExpression = process.env.CDP_SCROLL_INTO
      ? `(() => { const el = document.querySelector(${JSON.stringify(process.env.CDP_SCROLL)}); if (el) el.scrollIntoView({ block: "start" }); })()`
      : `(() => { const el = document.querySelector(${JSON.stringify(process.env.CDP_SCROLL)}); if (el) el.scrollTop = el.scrollHeight; })()`;
    await send("Runtime.evaluate", { expression: scrollExpression });
    await new Promise((r) => setTimeout(r, 250));
  }
  const result = await send("Page.captureScreenshot", { format: "png", fromSurface: true });
  const fs = await import("node:fs");
  fs.writeFileSync(EXPRESSION, Buffer.from(result.data, "base64"));
  console.log(EXPRESSION);
}
ws.close();
