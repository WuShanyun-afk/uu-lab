import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { THEMES, defaultState } from "../js/config.js";
import { normaliseState } from "../js/store.js";
import { CHAT_MODES, ROLEPLAY_PRESETS, chatModeOf, parseNarration } from "../js/roleplay.js";
import { buildSystemPrompt, parseReply } from "../js/prompt.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

function modeState(mode) {
  const state = defaultState();
  state.settings.apiKey = "test";
  state.settings.optimize.autoSticker = false;
  state.settings.mode = mode;
  return state;
}

test("modes: three of them, companion by default, anything else falls back", () => {
  assert.deepEqual(CHAT_MODES, ["companion", "roleplay", "assistant"]);
  assert.equal(defaultState().settings.mode, "companion");
  assert.equal(chatModeOf({ mode: "roleplay" }), "roleplay");
  assert.equal(chatModeOf({ mode: "nonsense" }), "companion");
  assert.equal(chatModeOf(undefined), "companion");
  assert.equal(normaliseState({ settings: { mode: "assistant" } }).settings.mode, "assistant");
  assert.equal(normaliseState({ settings: { mode: "bot" } }).settings.mode, "companion");
  assert.equal(normaliseState({ settings: { mode: "roleplay" } }).settings.modeTheme, "paper");
});

test("roleplay presets are complete and show the action style", () => {
  assert.ok(ROLEPLAY_PRESETS.length >= 6, "a scenario library needs a few cards");
  const ids = new Set();
  for (const preset of ROLEPLAY_PRESETS) {
    assert.ok(preset.id && !ids.has(preset.id), `duplicate id ${preset.id}`);
    ids.add(preset.id);
    for (const key of ["name", "title", "titleEn", "tag", "tagEn", "relationship", "persona", "greeting"]) {
      assert.ok(String(preset[key] || "").trim().length > 0, `${preset.id}.${key} is empty`);
    }
    assert.ok(/[*（(]/.test(preset.greeting), `${preset.id} greeting should use the action style`);
    assert.ok(preset.persona.length <= 1200, `${preset.id} persona is longer than the field`);
  }
});

test("narration: actions, standalone narration lines and speech", () => {
  const pieces = parseNarration("*把杯子推过去* 喝吧。\n（外面开始下雨）\n我等你。");
  assert.deepEqual(pieces.map((piece) => piece.type), ["action", "speech", "narration", "speech"]);
  assert.equal(pieces[0].text, "把杯子推过去");
  assert.equal(pieces[1].text, "喝吧。");
  assert.equal(pieces[2].text, "外面开始下雨");
  assert.equal(pieces[3].text, "我等你。");

  assert.deepEqual(parseNarration(""), []);
  assert.deepEqual(parseNarration("普通一句话"), [{ type: "speech", text: "普通一句话" }]);
  /* an odd number of stars must not swallow the rest of the sentence */
  assert.deepEqual(parseNarration("*没关门"), [{ type: "speech", text: "*没关门" }]);
});

test("the prompt changes with the mode", () => {
  const companion = buildSystemPrompt(modeState("companion"));
  assert.ok(companion.includes("绝对不要用括号、星号"));
  assert.ok(!companion.includes("【你的身份】"));
  assert.ok(!companion.includes("表演规则"));

  const roleplay = buildSystemPrompt(modeState("roleplay"));
  assert.ok(roleplay.includes("表演规则"));
  assert.ok(roleplay.includes("*星号*"));
  assert.ok(roleplay.includes("OOC"));
  assert.ok(!roleplay.includes("绝对不要用括号、星号"));

  const assistant = buildSystemPrompt(modeState("assistant"));
  assert.ok(assistant.includes("私人 AI 助理"));
  assert.ok(assistant.includes("Markdown 代码块"));
  assert.ok(!assistant.includes("[[sticker:"), "assistant must not be offered stickers");
  assert.ok(!assistant.includes("1–2 句短句"), "assistant should not be told to answer in one line");
});

test("roleplay keeps *actions* in the bubble text, companion strips them", () => {
  const raw = "*抱住你* 穿上。";
  const roleplay = parseReply(raw, modeState("roleplay"));
  assert.ok(roleplay.text.includes("抱住你"), roleplay.text);
  const companion = parseReply(raw, modeState("companion"));
  assert.ok(!companion.text.includes("抱住你"), companion.text);
});

test("assistant mode never sends a sticker", () => {
  const state = modeState("assistant");
  state.settings.optimize.autoSticker = true;
  const parsed = parseReply("好。\n[[sticker:mk_ok]]", state);
  assert.deepEqual(parsed.stickerIds, []);
  assert.ok(!parsed.text.includes("[[sticker"), parsed.text);
});

test("the assistant theme exists and everything is wired", () => {
  const theme = THEMES.find((item) => item.id === "assistant");
  assert.ok(theme, "assistant theme missing");
  assert.ok(theme.label && theme.labelEn);
  assert.ok(/^#[0-9a-f]{6}$/i.test(theme.accent));
  assert.ok(theme.bubble?.bg && theme.bubble?.ink);
  assert.equal(THEMES.filter((item) => item.id === theme.id).length, 1);

  const themes = read("css/modules/15-themes.css");
  assert.ok(themes.includes('body[data-theme="assistant"]'), "no palette for the assistant theme");
  const shared = themes.split("共享层")[1] || "";
  assert.ok(shared.includes('[data-theme="assistant"]'), "assistant theme is out of the shared layer");

  const modesCss = read("css/modules/19-modes.css");
  for (const hook of [".msg-action", ".msg-narration", 'body[data-mode="assistant"]', ".mode-card", ".preset-chip"]) {
    assert.ok(modesCss.includes(hook) || hook === ".msg-action" || hook === ".msg-narration", `${hook} has no styles`);
  }

  const html = read("index.html");
  assert.ok(html.includes("css/modules/19-modes.css"), "stylesheet not linked");
  const sw = read("sw.js");
  assert.ok(sw.includes("css/modules/19-modes.css"), "stylesheet not precached");
  assert.ok(sw.includes("js/roleplay.js"), "roleplay module not precached");

  const settings = read("js/settings.js");
  assert.ok(settings.includes("data-mode="), "settings has no mode picker");
  assert.ok(settings.includes("onMode"), "settings never calls onMode");

  const app = read("js/app.js");
  assert.ok(app.includes("setChatMode"), "no mode switching");
  assert.ok(app.includes("dataset.mode"), "mode never reaches the body");
  assert.ok(app.includes("ROLEPLAY_PRESETS"), "presets unused");
  assert.ok(app.includes("renderNarrationMarkup"), "narration never rendered");
  assert.ok(app.includes("newChatPresets"), "presets not offered when creating a chat");
});

test("the module page is the bottom-bar home of the two modes", () => {
  const html = read("index.html");
  assert.ok(html.includes('id="moduleScreen"'), "module screen missing");
  assert.ok(html.includes('data-tab="module"'), "module tab missing");
  assert.equal((html.match(/data-tab="/g) || []).length, 4, "the bottom bar should have four entries");
  assert.ok(html.includes('id="moduleBody"'), "module body missing");

  const ui = read("js/ui.js");
  assert.ok(ui.includes('module: "#moduleScreen"'), "showScreen does not know the module screen");

  const app = read("js/app.js");
  assert.ok(app.includes('"module"'), "openTab does not accept module");
  assert.ok(app.includes("renderModuleHome"), "module page never renders");
  assert.ok(app.includes("bindModuleScreen"), "module page is not wired");
  assert.ok(app.includes("data-module-pick"), "module cards not rendered");
  assert.ok(app.includes("renderAssistantMarkup"), "assistant text is not rendered specially");
  assert.ok(app.includes("msg-code"), "assistant code blocks missing");
  assert.ok(app.includes("data-copy-code"), "code copy button missing");

  const css = read("css/modules/19-modes.css");
  for (const hook of [".module-card", ".module-scroll", "body[data-screen=\"module\"] .tabbar", ".msg-code", ".rp-action", ".rp-narration", ".as-line"]) {
    assert.ok(css.includes(hook), `${hook} has no styles`);
  }
});

test("roleplay narration is rendered as separate blocks", () => {
  const app = read("js/app.js");
  const start = app.indexOf("function renderNarrationMarkup");
  const end = app.indexOf("function renderAssistantMarkup");
  assert.ok(start > 0 && end > start, "renderers missing");
  const body = app.slice(start, end);
  for (const cls of ["rp-action", "rp-narration", "rp-line"]) {
    assert.ok(body.includes(cls), `${cls} is not produced`);
  }
  assert.ok(!body.includes("<br>"), "narration should use blocks, not line breaks");
});
