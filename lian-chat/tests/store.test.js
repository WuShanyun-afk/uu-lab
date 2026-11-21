import test from "node:test";
import assert from "node:assert/strict";
import { normaliseState } from "../js/store.js";

test("normaliseState survives null settings and missing blocks", () => {
  const state = normaliseState({ settings: null, memories: null, messages: null, block: { until: 1 } });
  assert.equal(typeof state.settings.optimize, "object");
  assert.equal(state.settings.optimize.quotes, true);
  assert.equal(state.settings.realism.enabled, true);
  assert.equal(state.settings.blocking.mode, "silent");
  assert.equal(state.block, null);
});

test("normaliseState defaults old AI packs to equipped", () => {
  const state = normaliseState({
    stickerStudio: { packs: [{ id: "p", stickerIds: ["a"] }] },
  });
  assert.equal(state.stickerStudio.packs[0].equipped, true);
});

test("normaliseState keeps multiple chats and API keys", () => {
  const state = normaliseState({
    activeChatId: "c1",
    activeKeyId: "k1",
    keys: [{ id: "k1", name: "Main", provider: "mimo", apiKey: "test", baseUrl: "https://example.com/v1", model: "m" }],
    chats: [{ id: "c1", name: "A", messages: [{ id: "m1", role: "user", text: "hi" }] }],
  });
  assert.equal(state.keys.length, 1);
  assert.equal(state.keys[0].name, "Main");
  assert.equal(state.chats.length, 1);
  assert.equal(state.chats[0].messages.length, 1);
  assert.equal(state.activeChatId, "c1");
});

test("normaliseState keeps studio type and direction, and repairs unknown types", () => {
  const state = normaliseState({
    stickerStudio: { packs: [], style: "plush", direction: "奶油色柴犬" },
  });
  assert.equal(state.stickerStudio.style, "plush");
  assert.equal(state.stickerStudio.direction, "奶油色柴犬");

  const repaired = normaliseState({ stickerStudio: { packs: [], style: "not-a-style" } });
  assert.equal(repaired.stickerStudio.style, "auto");
  assert.equal(repaired.stickerStudio.direction, "");
});

test("normaliseState keeps the pre-assistant theme and accent", () => {
  /* 1.9.19: theme=custom is not in THEMES, so the accent has to survive on its own */
  const state = normaliseState({ settings: { modeTheme: "custom", modeAccent: "#FF00AA" } });
  assert.equal(state.settings.modeTheme, "custom");
  assert.equal(state.settings.modeAccent, "#FF00AA");

  const empty = normaliseState({ settings: { modeTheme: "paper" } });
  assert.equal(empty.settings.modeAccent, "");
  const bad = normaliseState({ settings: { modeAccent: 42 } });
  assert.equal(bad.settings.modeAccent, "");
});

test("normaliseState keeps the assistant capability switches", () => {
  const state = normaliseState({ settings: { assistant: { web: true, thinking: 1 } } });
  assert.equal(state.settings.assistant.web, true);
  assert.equal(state.settings.assistant.thinking, true);
  assert.deepEqual(normaliseState({}).settings.assistant, { web: false, thinking: false });
});
