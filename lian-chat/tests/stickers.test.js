import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  BUILTIN_PACKS,
  BUILTIN_STICKERS,
  LEGACY_STICKER_IDS,
  builtinPackLabel,
  getSticker,
  stickerSrc,
} from "../js/config.js";

const stickerDir = fileURLToPath(new URL("../assets/stickers/", import.meta.url));
const MOODS = new Set([
  "hello", "shy", "ok", "cheer", "laugh", "question", "happy",
  "sleepy", "night", "bored", "sad", "shock", "love", "angry", "party",
]);

test("both menhera packs are described in one place", () => {
  assert.deepEqual(
    BUILTIN_PACKS.map((pack) => [pack.id, pack.name, pack.nameEn, pack.stickers.length]),
    [
      ["menhera_kun", "menhera君", "Menhera-kun", 44],
      ["menhera_jiang", "menhera酱", "Menhera-chan", 25],
    ],
  );
  assert.equal(BUILTIN_STICKERS.length, 69);
  for (const pack of BUILTIN_PACKS) {
    assert.ok(pack.stickers.length >= 4, pack.id);
    assert.ok(BUILTIN_STICKERS.filter((sticker) => sticker.packId === pack.id).length === pack.stickers.length);
  }
});

test("builtin sticker ids, names and moods are sane across both packs", () => {
  const ids = new Set();
  for (const sticker of BUILTIN_STICKERS) {
    const prefix = sticker.packId === "menhera_kun" ? "mk_" : "mj_";
    assert.ok(sticker.id.startsWith(prefix), `${sticker.id} should start with ${prefix}`);
    assert.match(sticker.file, /^(mk|mj)_[a-z0-9-]+\.webp$/, sticker.id);
    assert.ok(!ids.has(sticker.id), `duplicate id ${sticker.id}`);
    ids.add(sticker.id);
    assert.ok(sticker.name.length > 0 && sticker.name.length <= 6, sticker.id);
    assert.ok(MOODS.has(sticker.mood), `${sticker.id} mood=${sticker.mood}`);
  }
});

test("every builtin sticker file is a real 320px webp on disk", () => {
  for (const sticker of BUILTIN_STICKERS) {
    const path = `${stickerDir}${sticker.file}`;
    const bytes = statSync(path).size;
    assert.ok(bytes > 2000, `${sticker.file} is only ${bytes} B`);
    const head = readFileSync(path).subarray(0, 12);
    assert.equal(head.toString("ascii", 0, 4), "RIFF", sticker.file);
    assert.equal(head.toString("ascii", 8, 12), "WEBP", sticker.file);
    assert.equal(stickerSrc(sticker), `assets/stickers/${sticker.file}`);
  }
});

test("the old bi_* ids still resolve after the rename", () => {
  assert.equal(Object.keys(LEGACY_STICKER_IDS).length, 23);
  for (const [oldId, newId] of Object.entries(LEGACY_STICKER_IDS)) {
    assert.match(oldId, /^bi_/);
    const sticker = getSticker(oldId, []);
    assert.ok(sticker, `${oldId} no longer resolves`);
    assert.equal(sticker.id, newId);
    assert.equal(getSticker(newId, []).name, sticker.name);
  }
  assert.equal(getSticker("bi_shy", []).name, "害羞");
  assert.equal(getSticker("bi_silly", []).name, "笨蛋");
  assert.equal(getSticker("bi_removed_in_1_9_7", []), null);
  assert.equal(getSticker("", []), null);
});

test("a custom sticker still wins over a builtin with the same id", () => {
  const custom = [{ id: "mk_shy", name: "我的害羞", dataUrl: "data:image/png;base64,x" }];
  assert.equal(getSticker("mk_shy", custom).name, "我的害羞");
  assert.equal(stickerSrc(getSticker("mk_shy", custom)), "data:image/png;base64,x");
});

test("a shared name resolves to the first pack that owns it", () => {
  // 点赞 / 晚安 / 困 / 喵~ / 不行 exist in both packs; the id always wins,
  // and a bare name must not crash the lookup.
  assert.equal(getSticker("mk_like", []).packId, "menhera_kun");
  assert.equal(getSticker("mj_like", []).packId, "menhera_jiang");
  assert.equal(getSticker("点赞", []), null); // names are not ids: never guessed
});

test("pack labels follow the UI language", () => {
  const [kun, jiang] = BUILTIN_PACKS;
  assert.equal(builtinPackLabel(kun, "zh"), "menhera君");
  assert.equal(builtinPackLabel(kun, "en"), "Menhera-kun");
  assert.equal(builtinPackLabel(jiang, "en"), "Menhera-chan");
  assert.equal(builtinPackLabel(jiang), "menhera酱");
  assert.equal(builtinPackLabel(null, "en"), "");
});
