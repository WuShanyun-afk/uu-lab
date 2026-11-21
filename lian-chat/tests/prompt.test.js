import test from "node:test";
import assert from "node:assert/strict";
import { BUILTIN_STICKERS, defaultState } from "../js/config.js";
import { availableStickers, buildChatMessages, buildQuoteCatalog, buildSystemPrompt, chooseAutoSticker, moodFromText, parseJsonReply, parseReply, splitSegments, stripActionDescriptions } from "../js/prompt.js";
import { escapeHtml, isEmojiOnly, renderRichText } from "../js/utils.js";

function state(overrides = {}) {
  const value = defaultState();
  value.settings.apiKey = "test";
  value.settings.optimize.autoSticker = false;
  Object.assign(value.settings, overrides);
  return value;
}

test("sticker directives are extracted and removed from visible text", () => {
  const s = state();
  s.customStickers = [{ id: "custom_night", name: "晚安", dataUrl: "data:image/png;base64,x", mood: "night" }];
  const result = parseReply("那就早点睡。\n[[sticker:custom_night]]", s);
  assert.deepEqual(result.stickerIds, ["custom_night"]);
  assert.equal(result.text, "那就早点睡。");
});

test("sticker parser tolerates common model formatting", () => {
  const s = state();
  s.customStickers = [{ id: "custom_ok", name: "收到", aliases: ["ok"], dataUrl: "data:image/png;base64,x" }];
  for (const raw of ["好的 [sticker:custom_ok]", "【表情：收到】", "[[custom_ok]]", "[[表情:收到]]", "我发了一个「收到」表情"]) {
    const result = parseReply(raw, s);
    assert.equal(result.stickerIds.length, 1, raw);
  }
});

test("stage directions are removed but ordinary parentheses stay inline", () => {
  const s = state();
  const result = parseReply("（轻轻抱住你）我在呢。\n*smile*\n明天见。", s);
  assert.ok(!result.text.includes("抱住"));
  assert.ok(!result.text.toLowerCase().includes("smile"));
  assert.ok(result.text.includes("我在呢。"));
  assert.equal(stripActionDescriptions("今天下雨（记得带伞）。"), "今天下雨（记得带伞）。");
  assert.equal(stripActionDescriptions("（明天见）"), "（明天见）");
  assert.equal(stripActionDescriptions("（轻轻抱住你）"), "");
});

test("segmented output respects blank lines and caps at four bubbles", () => {
  assert.deepEqual(splitSegments("A\n\nB\n\nC", true), ["A", "B", "C"]);
  assert.equal(splitSegments("A\n\nB\n\nC\n\nD\n\nE", true).length, 4);
  assert.deepEqual(splitSegments("A\n\nB", false), ["A\n\nB"]);
});

test("emoji-only rendering is recognised", () => {
  assert.equal(isEmojiOnly("🥺"), true);
  assert.equal(isEmojiOnly("你好 🥺"), false);
});

test("HTML is escaped and links are still linkified", () => {
  assert.equal(escapeHtml("<script>alert(1)</script>"), "&lt;script&gt;alert(1)&lt;/script&gt;");
  assert.ok(renderRichText("看 https://example.com/x").includes("<a href=\"https://example.com/x\""));
  assert.ok(!renderRichText("<img src=x onerror=alert(1)>").includes("<img"));
});

test("system prompt includes persona, memory, sticker schema and no-action rule", () => {
  const s = state({ aiName: "沈言", persona: "话少，嘴硬。" });
  s.memories = [{ id: "1", text: "我不喝加糖咖啡。", createdAt: 0 }];
  s.customStickers = [{ id: "custom_ok", name: "收到", dataUrl: "data:image/png;base64,x" }];
  const prompt = buildSystemPrompt(s);
  assert.ok(prompt.includes("沈言"));
  assert.ok(prompt.includes("我不喝加糖咖啡"));
  assert.ok(prompt.includes("custom_ok(收到)"));
  assert.ok(!prompt.includes("cat_love"));
  assert.ok(prompt.includes("[[sticker:ID]]"));
  assert.ok(prompt.includes("不要用括号"));
});

test("built-in stickers are offered even when the custom library is empty", () => {
  const s = state({ aiName: "沈言" });
  const prompt = buildSystemPrompt(s);
  assert.ok(prompt.includes("mk_hello(打招呼)"));
  assert.ok(prompt.includes("mk_sleep(睡觉)"));
  assert.ok(!prompt.includes("现在还没有可用的表情 ID"));
  assert.ok(prompt.includes("[[sticker:ID]]"));
});

test("built-in sticker ids are parsed from model output", () => {
  const s = state();
  const parsed = parseReply("困了。\n[[sticker:mk_sleepy]]", s);
  assert.deepEqual(parsed.stickerIds, ["mk_sleepy"]);
  assert.equal(parsed.text, "困了。");
});

test("built-in moods participate in the deterministic auto-sticker fallback", () => {
  const s = state();
  s.settings.optimize.autoSticker = true;
  const picked = ["晚安，好梦", "困了", "在吗", "哈哈"].map((text) => chooseAutoSticker(text, s));
  assert.ok(picked.some((id) => id && id.startsWith("mk_")));
});

test("custom sticker moods are inferred from their names for auto-fallback", () => {
  const s = state();
  s.settings.optimize.autoSticker = true;
  s.customStickers = [{ id: "custom_happy", name: "好耶", dataUrl: "data:image/png;base64,x", mood: "happy" }];
  assert.equal(moodFromText("好耶"), "happy");
  assert.equal(moodFromText("完全无关的一句话"), null);
  const picked = ["今天好开心", "好耶", "开心", "太棒了"].map((text) => chooseAutoSticker(text, s));
  assert.ok(picked.includes("custom_happy"));
});

test("buildChatMessages does not leak a model name and keeps visible history", () => {
  const s = state({ aiName: "沈言", model: "very-secret-model" });
  s.messages = [
    { id: "a", role: "user", kind: "text", text: "在吗", ts: 1 },
    { id: "b", role: "assistant", kind: "text", text: "在。", ts: 2 },
  ];
  const current = { id: "c", role: "user", kind: "text", text: "今天好累", ts: 3 };
  s.messages.push(current);
  const messages = buildChatMessages(s, current);
  assert.equal(messages[0].role, "system");
  assert.ok(!JSON.stringify(messages).includes("very-secret-model"));
  assert.ok(JSON.stringify(messages).includes("今天好累"));
});

test("AI-made sticker ids are parsed", () => {
  const s = state();
  s.customStickers = [{ id: "ai_pack_1_0", name: "吃饭了没", dataUrl: "data:image/svg+xml;base64,PHN2Zz4=", ai: true }];
  const parsed = parseReply("[[sticker:ai_pack_1_0]]", s);
  assert.deepEqual(parsed.stickerIds, ["ai_pack_1_0"]);
});

test("assistant sticker bookkeeping is not replayed as literal text", () => {
  const s = state();
  s.customStickers = [{ id: "custom_ok", name: "收到", dataUrl: "data:image/png;base64,x" }];
  s.messages = [
    { id: "a", role: "user", kind: "text", text: "在吗", ts: 1 },
    { id: "b", role: "assistant", kind: "sticker", stickerId: "custom_ok", ts: 2 },
  ];
  const current = { id: "c", role: "user", kind: "text", text: "嗯", ts: 3 };
  const all = JSON.stringify(buildChatMessages(s, current));
  assert.ok(!all.includes("我发了一个"));
});

test("text file contents are included for the model", () => {
  const s = state();
  const file = {
    id: "f",
    role: "user",
    kind: "file",
    text: "看看这个",
    ts: 1,
    file: { name: "note.txt", sizeLabel: "10 B", textPreview: "记得吃饭，别熬夜。" },
  };
  const all = JSON.stringify(buildChatMessages(s, file));
  assert.ok(all.includes("记得吃饭，别熬夜"));
});

test("JSON report parsing tolerates code fences and prose", () => {
  const raw = "```json\n{\"title\":\"窗边\",\"summary\":\"...\",\"html\":\"<p>ok</p>\"}\n```";
  const parsed = parseJsonReply(raw);
  assert.equal(parsed.title, "窗边");
});

test("a JSON reply cut off by max_tokens is repaired", () => {
  const cut = '{"title":"凌晨一点的日常","summary":"改代码改到现在","blocks":[{"text":"第一段","scene":"moon"},{"text":"第二段';
  const parsed = parseJsonReply(cut);
  assert.equal(parsed.title, "凌晨一点的日常");
  assert.equal(parsed.blocks.length, 2);
  assert.equal(parsed.blocks[1].text, "第二段");
});

test("a JSON reply cut in the middle of a key still yields what it had", () => {
  const parsed = parseJsonReply('{"title":"窗边","summ');
  assert.equal(parsed.title, "窗边");
  assert.equal(parsed.summ, undefined);
});

test("nonsense that is not JSON still throws", () => {
  assert.throws(() => parseJsonReply("今天下了雨。"));
  assert.throws(() => parseJsonReply(""));
});

test("AI-made stickers resolve by id, caption and mixed directives", () => {
  const s = state();
  s.customStickers = [
    { id: "ai_pack_late_0", name: "冷脸", caption: "平常", dataUrl: "data:image/svg+xml;base64,PHN2Zz4=", ai: true, packId: "pack_late" },
  ];
  s.stickerStudio.packs = [{ id: "pack_late", name: "猫猫头", stickerIds: ["ai_pack_late_0"], equipped: true }];
  for (const raw of [
    "嗯。\n[[sticker:ai_pack_late_0]]",
    "嗯。\n[[sticker:ai_pack_late_0 (冷脸)]]",
    "嗯。\n[[sticker:冷脸]]",
  ]) {
    const parsed = parseReply(raw, s, { autoSticker: false });
    assert.deepEqual(parsed.stickerIds, ["ai_pack_late_0"], raw);
    assert.equal(parsed.text, "嗯。");
  }
});

test("AI pack ids longer than 24 characters resolve without a stray bracket", () => {
  const s = state();
  s.customStickers = [
    { id: "ai_pack_mwnl8uy8_ab12cd_0", name: "在", dataUrl: "data:image/svg+xml;base64,PHN2Zz4=", ai: true, packId: "pack_mwnl8uy8_ab12cd" },
  ];
  s.stickerStudio.packs = [{ id: "pack_mwnl8uy8_ab12cd", name: "长 ID", stickerIds: ["ai_pack_mwnl8uy8_ab12cd_0"], equipped: true }];
  for (const raw of ["嗯。\n[[ai_pack_mwnl8uy8_ab12cd_0]]", "嗯。\n[[sticker:ai_pack_mwnl8uy8_ab12cd_0]]", "嗯。\n[ai_pack_mwnl8uy8_ab12cd_0]"]) {
    const parsed = parseReply(raw, s, { autoSticker: false });
    assert.deepEqual(parsed.stickerIds, ["ai_pack_mwnl8uy8_ab12cd_0"], raw);
    assert.equal(parsed.text, "嗯。");
  }
});

test("unknown sticker directives are removed instead of leaking into the bubble", () => {
  const s = state();
  const parsed = parseReply("好吧。\n[[sticker:missing_sticker]]", s, { autoSticker: false });
  assert.deepEqual(parsed.stickerIds, []);
  assert.equal(parsed.text, "好吧。");
});

test("a big custom library never crowds the built-in packs out of the prompt", () => {
  const s = state();
  s.customStickers = Array.from({ length: 70 }, (_, i) => ({
    id: `custom_${i}`,
    name: `自${i}`,
    dataUrl: "data:image/png;base64,x",
  }));
  const available = availableStickers(s);
  const builtinCount = BUILTIN_STICKERS.length;
  assert.ok(available.filter((sticker) => sticker.packId).length === builtinCount, "every builtin stays available");
  // the tail of the last pack used to be cut off by a 60-entry slice
  assert.ok(available.some((sticker) => sticker.id === "mj_huh"), "last menhera酱 sticker is reachable");
  const prompt = buildSystemPrompt(s);
  assert.ok(prompt.includes("mj_huh(诶？)"));
  // and a model that picks it is not silently rejected
  const parsed = parseReply("嗯？\n[[sticker:mj_huh]]", s);
  assert.deepEqual(parsed.stickerIds, ["mj_huh"]);
  assert.ok(available.length <= 40 + builtinCount);
});

test("a regeneration note rides along for one request only", () => {
  const s = state();
  const user = { id: "u1", role: "user", kind: "text", text: "在吗", ts: 1 };
  s.messages = [user];
  const plain = buildChatMessages(s, user);
  const nudged = buildChatMessages(s, user, { note: "[系统旁白：换一种说法]" });
  assert.deepEqual(nudged.at(-1), { role: "user", content: "[系统旁白：换一种说法]" });
  assert.equal(nudged.length, plain.length + 1);
  assert.equal(s.messages.length, 1, "the note must never enter stored history");
});

test("re-rolling one reply only sends the history before it", () => {
  const s = state();
  s.messages = [
    { id: "u1", role: "user", kind: "text", text: "第一句", ts: 1 },
    { id: "a1", role: "assistant", kind: "text", text: "旧回复", ts: 2 },
    { id: "u2", role: "user", kind: "text", text: "第二句", ts: 3 },
    { id: "a2", role: "assistant", kind: "text", text: "后面的回复", ts: 4 },
  ];
  const truncated = { ...s, messages: s.messages.slice(0, 1) };
  const built = buildChatMessages(truncated, s.messages[0]);
  const dump = JSON.stringify(built);
  assert.ok(dump.includes("第一句"));
  assert.ok(!dump.includes("旧回复"));
  assert.ok(!dump.includes("第二句"));
  assert.ok(!dump.includes("后面的回复"));
});

test("old AI packs without an equipped flag are still available", () => {
  const s = state();
  s.customStickers = [
    { id: "ai_old_0", name: "在", dataUrl: "data:image/svg+xml;base64,PHN2Zz4=", ai: true, packId: "old_pack" },
  ];
  s.stickerStudio.packs = [{ id: "old_pack", name: "旧表情", stickerIds: ["ai_old_0"] }];
  const prompt = buildSystemPrompt(s);
  assert.ok(prompt.includes("ai_old_0(在)"));
});

test("unequipped AI packs are not offered to the model", () => {
  const s = state();
  s.customStickers = [
    { id: "ai_off_0", name: "收起", dataUrl: "data:image/svg+xml;base64,PHN2Zz4=", ai: true, packId: "off_pack" },
  ];
  s.stickerStudio.packs = [{ id: "off_pack", name: "收起", stickerIds: ["ai_off_0"], equipped: false }];
  assert.ok(!buildSystemPrompt(s).includes("ai_off_0(收起)"));
});

test("quote reply catalogs only expose recent user messages and parse the marker", () => {
  const s = state({ userName: "小满" });
  s.messages = [
    { id: "u1", role: "user", kind: "text", text: "今天下雨了", ts: 1 },
    { id: "a1", role: "assistant", kind: "text", text: "记得带伞。", ts: 2 },
  ];
  const current = { id: "u2", role: "user", kind: "text", text: "嗯", ts: 3 };
  s.messages.push(current);
  const catalog = buildQuoteCatalog(s, current.id);
  assert.equal(catalog.length, 1);
  assert.equal(catalog[0].ref, "U1");
  assert.equal(catalog[0].messageId, "u1");
  assert.ok(JSON.stringify(buildChatMessages(s, current)).includes("[[quote:U1]]"));
  const parsed = parseReply("[[quote:U1]]\n我带了。", s, { quoteCatalog: catalog, autoSticker: false });
  assert.equal(parsed.quote.messageId, "u1");
  assert.equal(parsed.text, "我带了。");
});

test("a user quote is included in the current prompt as context", () => {
  const s = state({ userName: "小满" });
  const current = {
    id: "u2",
    role: "user",
    kind: "text",
    text: "我带了。",
    ts: 3,
    quote: { id: "a1", role: "assistant", name: "沈言", text: "记得带伞。" },
  };
  const all = JSON.stringify(buildChatMessages(s, current));
  assert.ok(all.includes("对方引用了我的消息"));
  assert.ok(all.includes("记得带伞"));
});

test("after-block prompt asks for a natural follow-up without mentioning the block", () => {
  const s = state();
  const all = JSON.stringify(buildChatMessages(s, null, { proactive: true, afterBlock: true }));
  assert.ok(all.includes("结束了和对方的冷战"));
  assert.ok(all.includes("不要提「冷战」「屏蔽」"));
});

test("refused messages are not replayed to the model", () => {
  const s = state();
  s.messages = [
    { id: "u1", role: "user", kind: "text", text: "这句被拒收了", ts: 1, delivery: "refused" },
    { id: "u2", role: "user", kind: "text", text: "这句只读不回", ts: 2, delivery: "silent" },
  ];
  const current = { id: "u3", role: "user", kind: "text", text: "现在呢", ts: 3 };
  s.messages.push(current);
  const all = JSON.stringify(buildChatMessages(s, current));
  assert.ok(!all.includes("这句被拒收了"));
  assert.ok(all.includes("这句只读不回"));
});

test("block markers are parsed only as a request and removed from visible text", () => {
  const s = state();
  s.settings.blocking.enabled = true;
  assert.ok(buildSystemPrompt(s).includes("[[block]]"));
  const parsed = parseReply("我先不说了。\n[[block]]", s, { autoSticker: false });
  assert.equal(parsed.blockRequested, true);
  assert.equal(parsed.text, "我先不说了。");
});
