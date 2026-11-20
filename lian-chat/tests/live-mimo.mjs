/* Live smoke test against MiMo. Run with MIMO_API_KEY in the environment.
   The key is never written to disk by this script. */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { defaultState } from "../js/config.js";
import { chatCompletion } from "../js/api.js";
import { buildChatMessages, buildReportMessages, parseJsonReply, parseReply } from "../js/prompt.js";
import { buildReportFromRaw } from "../js/report.js";
import { sceneSvg } from "../js/scenes.js";

const key = process.env.MIMO_API_KEY;
if (!key) {
  console.log("SKIP: set MIMO_API_KEY to run the live test");
  process.exit(0);
}

const state = defaultState();
state.settings.apiKey = key;
state.settings.baseUrl = "https://api.xiaomimimo.com/v1";
state.settings.model = "mimo-v2.6-flash";
state.settings.aiName = "沈言";
state.settings.userName = "小满";
state.settings.persona = "话少，克制，习惯先问对方有没有吃饭。";
state.settings.optimize.autoSticker = false;
state.memories = [{ id: "1", text: "小满喝咖啡不加糖。", createdAt: Date.now() }];

const results = [];
let failures = 0;

async function run(name, fn) {
  try {
    const value = await fn();
    results.push({ name, ok: true, ...value });
    console.log(`PASS ${name}`, JSON.stringify(value));
  } catch (error) {
    failures += 1;
    results.push({ name, ok: false, error: error.message, code: error.code });
    console.error(`FAIL ${name}:`, error.code || "", error.message);
  }
}

const only = process.env.LIVE_ONLY;
if (!only || only === "chat") await run("chat + sticker directive", async () => {
  const user = { id: "u1", role: "user", kind: "text", text: "我有点困了。用一句短句回我，再配一张最合适的猫咪表情包。", ts: Date.now() };
  state.messages.push(user);
  const result = await chatCompletion({
    settings: state.settings,
    messages: buildChatMessages(state, user),
    model: state.settings.model,
    maxTokens: 260,
  });
  const parsed = parseReply(result.content, state, { autoSticker: false });
  if (!parsed.stickerIds.length) throw new Error(`no sticker directive in: ${result.content.slice(0, 160)}`);
  if (!parsed.text) throw new Error("no visible text");
  return { text: parsed.text.slice(0, 80), stickers: parsed.stickerIds, tokens: result.usage.total };
});

if (!only || only === "report") await run("daily report JSON", async () => {
  state.messages.push({
    id: "a1", role: "assistant", kind: "text",
    text: "中午随便吃了点，两个煎蛋，一杯咖啡。窗外在下雨。", ts: Date.now(),
  });
  const result = await chatCompletion({
    settings: state.settings,
    messages: buildReportMessages(state),
    model: state.settings.model,
    maxTokens: 1200,
    json: true,
  });
  const parsed = parseJsonReply(result.content);
  const report = buildReportFromRaw(parsed);
  if (!report.title) throw new Error("missing title");
  if (report.blocks.length < 2) throw new Error(`expected 2+ blocks, got: ${JSON.stringify(parsed).slice(0, 240)}`);
  const scenes = report.blocks.map((block) => block.scene).filter(Boolean);
  if (!scenes.length) throw new Error(`no scene picked: ${JSON.stringify(report.blocks).slice(0, 240)}`);
  if (scenes.some((scene) => !sceneSvg(scene))) throw new Error(`unknown scene id: ${scenes.join(",")}`);
  return {
    title: String(report.title).slice(0, 40),
    blocks: report.blocks.length,
    scenes,
    firstText: report.blocks[0].text.slice(0, 40),
    tokens: result.usage.total,
  };
});

if (!only || only === "vision") await run("vision input", async () => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const data = fs.readFileSync(path.join(here, "vision-test.png")).toString("base64");
  const image = {
    id: "img1",
    role: "user",
    kind: "image",
    text: "只回答图片里的字母和主要颜色，格式：A-红色",
    ts: Date.now(),
    image: { dataUrl: `data:image/png;base64,${data}`, width: 320, height: 320, name: "vision-test.png" },
  };
  state.messages.push(image);
  const result = await chatCompletion({
    settings: state.settings,
    messages: buildChatMessages(state, image),
    model: state.settings.model,
    maxTokens: 180,
  });
  if (!/A/i.test(result.content) || !/红|red/i.test(result.content)) {
    throw new Error(`unexpected vision answer: ${result.content.slice(0, 160)}`);
  }
  return { answer: result.content.replace(/\s+/g, " ").slice(0, 60), tokens: result.usage.total };
});

const total = results.reduce((sum, item) => sum + (item.tokens || 0), 0);
console.log(`TOTAL live tokens: ${total}`);
if (failures) process.exit(1);
