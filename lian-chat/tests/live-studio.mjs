/* Live MiMo smoke test for the AI sticker studio. Key comes from env only. */
import { defaultState } from "../js/config.js";
import { chatCompletion } from "../js/api.js";
import { buildStickerPackMessages, parseStickerPack, renderStickerSvg } from "../js/studio.js";

const key = process.env.MIMO_API_KEY;
if (!key) {
  console.log("SKIP: set MIMO_API_KEY");
  process.exit(0);
}
const state = defaultState();
state.settings.apiKey = key;
state.settings.baseUrl = "https://api.xiaomimimo.com/v1";
state.settings.model = "mimo-v2.6-flash";
state.settings.aiName = "沈言";
state.settings.userName = "小满";
state.settings.relationship = "认识三年的恋人";
state.settings.persona = "表面冷静克制，实际很会照顾人。说话简短，偶尔嘴硬，习惯先问对方有没有吃饭。";
state.messages = [
  { id: "1", role: "user", kind: "text", text: "今天有点累。", ts: Date.now() - 1000 },
  { id: "2", role: "assistant", kind: "text", text: "那就早点休息。", ts: Date.now() },
];

const result = await chatCompletion({
  settings: state.settings,
  messages: buildStickerPackMessages(state),
  model: state.settings.model,
  maxTokens: 1300,
  temperature: 0.9,
  json: true,
});
const pack = parseStickerPack(result.content);
if (pack.stickers.length !== 6) throw new Error(`expected 6 stickers, got ${pack.stickers.length}`);
for (const sticker of pack.stickers) {
  const svg = renderStickerSvg(sticker);
  if (!svg.startsWith("<svg") || /<script|href=|foreignObject/i.test(svg)) {
    throw new Error("unsafe or invalid SVG");
  }
}
console.log(JSON.stringify({
  name: pack.name,
  theme: pack.theme,
  stickers: pack.stickers.map((s) => ({ name: s.name, animal: s.animal, face: s.face, prop: s.prop })),
  tokens: result.usage.total,
}, null, 2));
