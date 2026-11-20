import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { EMOJIS, EMOJI_GROUPS, defaultState, emojiGroupLabel } from "../js/config.js";
import { normaliseState } from "../js/store.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("emoji groups: unique ids, unique items, and EMOJIS is exactly their union", () => {
  const ids = EMOJI_GROUPS.map((group) => group.id);
  assert.equal(new Set(ids).size, ids.length, "duplicate group id");
  const items = EMOJI_GROUPS.flatMap((group) => group.items);
  assert.equal(new Set(items).size, items.length, "an emoji is listed in two groups");
  assert.deepEqual(EMOJIS, items, "EMOJIS must stay the union of EMOJI_GROUPS");
  for (const group of EMOJI_GROUPS) {
    assert.ok(group.items.length >= 6, `${group.id} is too thin to be a group`);
    assert.ok(group.label && group.labelEn, `${group.id} needs both labels`);
  }
});

test("emoji groups: labels follow the UI language", () => {
  const face = EMOJI_GROUPS[0];
  assert.equal(emojiGroupLabel(face, "zh"), face.label);
  assert.equal(emojiGroupLabel(face, "en"), face.labelEn);
  assert.equal(emojiGroupLabel(null), "");
});

test("emoji usage: empty by default, and a normal state round-trips", () => {
  assert.deepEqual(defaultState().emojiUsage, []);
  const now = Date.now();
  const state = normaliseState({
    emojiUsage: [
      { e: "😊", n: 4, at: now },
      { e: "❤️", n: 1, at: now - 1000 },
    ],
  });
  assert.deepEqual(state.emojiUsage.map((item) => item.e), ["😊", "❤️"]);
  assert.equal(state.emojiUsage[0].n, 4);
});

test("emoji usage: junk is dropped, duplicates collapse and the list caps at 12", () => {
  const now = Date.now();
  const raw = [
    { e: "😊", n: 2, at: now - 5 },
    { e: "😊", n: 9, at: now - 10 }, // same emoji twice -> keep the newer one
    { n: 3 }, // no emoji
    { e: "", n: 3 },
    "😭", // not an object
    null,
  ];
  for (let i = 0; i < 20; i += 1) raw.push({ e: `🎈${i}`, n: 1, at: now - i });
  const state = normaliseState({ emojiUsage: raw });
  assert.equal(state.emojiUsage.length, 12, "the recents list must stay short");
  assert.ok(new Set(state.emojiUsage.map((item) => item.e)).size === 12, "duplicates survived");
  assert.ok(!state.emojiUsage.some((item) => !item.e));
  const times = state.emojiUsage.map((item) => item.at);
  assert.deepEqual(times, [...times].sort((a, b) => b - a), "recents must be newest first");
  assert.ok(state.emojiUsage.every((item) => item.n >= 1 && item.n <= 999));
});

test("emoji usage: a broken list never takes the app down", () => {
  for (const value of [null, "😊", 42, {}, undefined]) {
    const state = normaliseState({ emojiUsage: value });
    assert.ok(Array.isArray(state.emojiUsage));
    assert.equal(state.emojiUsage.length, 0);
  }
});

test("composer tray: 最近 + 分组 are wired into the markup, the code and the styles", () => {
  const html = read("index.html");
  const app = read("js/app.js");
  const css = read("css/modules/18-composer.css");
  assert.ok(html.includes('id="trayEmojiHead"'), "group chips container missing");
  assert.ok(html.includes('id="trayEmoji"'), "emoji row missing");
  for (const hook of ["renderTrayEmojis", "recordEmojiUse", "trayEmojiGroups", "EMOJI_GROUPS"]) {
    assert.ok(app.includes(hook), `${hook} is not wired`);
  }
  /* every tap path (tray + sticker sheet) has to feed the recents */
  assert.ok(app.includes("recordEmojiUse(emoji)"), "insertEmoji must record usage");
  assert.ok(css.includes(".tray-emoji-tab") && css.includes(".tray-emoji-head"));
  assert.ok(css.includes(".tray-emoji-tab.is-on"), "the active group needs a style");
});

test("composer tray: the recents list is capped in code as well as in storage", () => {
  const app = read("js/app.js");
  assert.ok(/EMOJI_RECENT_MAX\s*=\s*12/.test(app), "the cap must match store.js's 12");
  assert.ok(app.includes("state.emojiUsage = list.slice(0, EMOJI_RECENT_MAX)"));
  /* persist() is the one save path that skips demo mode; a raw scheduleSave here
     would let a demo session overwrite the real chat with its seed data. */
  const record = app.slice(app.indexOf("function recordEmojiUse"), app.indexOf("function initComposerTray"));
  assert.ok(record.includes("persist()"), "recents must be saved through persist()");
  assert.ok(!record.includes("scheduleSave"), "recordEmojiUse must not bypass the demo guard");
});
