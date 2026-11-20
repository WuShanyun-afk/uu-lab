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
