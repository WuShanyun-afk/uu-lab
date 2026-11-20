import test from "node:test";
import assert from "node:assert/strict";
import { defaultState } from "../js/config.js";
import { buildStickerPackMessages, parseStickerPack, renderStickerSvg, svgToDataUrl } from "../js/studio.js";

const PACK = {
  name: "猫猫头的日常",
  theme: "深炭黑猫猫头，奶白颜文字，粉色小鼻子和腮红",
  style: "kaomoji",
  stickers: [
    { name: "在", caption: "平常", face: "normal" },
    { name: "贴贴", caption: "贴贴", face: "love" },
    { name: "困", caption: "睡着", face: "sleepy" },
    { name: "哼", caption: "生气", face: "angry" },
    { name: "吃", caption: "干饭", face: "eat" },
    { name: "晚安", caption: "晚安", face: "miss" },
  ],
};

test("kaomoji recipes render a self-contained cat-head SVG", () => {
  const svg = renderStickerSvg({ ...PACK.stickers[0], style: "kaomoji" });
  assert.ok(svg.startsWith("<svg"));
  assert.ok(svg.includes("ᗜ - ᗜ"));
  assert.ok(svg.includes("#332D2B"));
  assert.ok(!svg.includes("<script"));
  assert.ok(!svg.includes("href="));
  assert.ok(!svg.includes("<foreignObject"));
  assert.ok(!svg.includes("<body"));
});

test("kaomoji captions are escaped inside rendered SVG", () => {
  const svg = renderStickerSvg({ ...PACK.stickers[0], style: "kaomoji", caption: `"<&>` });
  assert.ok(svg.includes("&quot;&lt;&amp;&gt;"));
});

test("AI pack parser accepts a valid six-sticker kaomoji recipe", () => {
  const parsed = parseStickerPack(JSON.stringify(PACK));
  assert.equal(parsed.name, "猫猫头的日常");
  assert.equal(parsed.style, "kaomoji");
  assert.equal(parsed.stickers.length, 6);
  assert.equal(parsed.stickers[1].face, "love");
  assert.equal(parsed.stickers[1].kaomoji, "ᗜ ♡ ᗜ");
  assert.equal(parsed.stickers[1].animal, "blackcat");
  assert.equal(parsed.stickers[1].style, "kaomoji");
});

test("AI pack parser rejects too-small packs and repairs unknown faces", () => {
  assert.throws(() => parseStickerPack(JSON.stringify({ name: "x", stickers: [PACK.stickers[0]] })));
  const parsed = parseStickerPack(
    JSON.stringify({
      name: "x",
      stickers: [
        { ...PACK.stickers[0], face: "not-a-face" },
        PACK.stickers[1],
        PACK.stickers[2],
        PACK.stickers[3],
      ],
    }),
  );
  assert.equal(parsed.stickers[0].face, "normal");
  assert.equal(parsed.stickers[0].kaomoji, "ᗜ - ᗜ");

  const labelled = parseStickerPack(
    JSON.stringify({
      name: "x",
      stickers: [
        { ...PACK.stickers[0], face: "开心" },
        PACK.stickers[1],
        PACK.stickers[2],
        PACK.stickers[3],
      ],
    }),
  );
  assert.equal(labelled.stickers[0].face, "happy");
  assert.equal(labelled.stickers[0].kaomoji, "ᗜ ᴗ ᗜ");
});

test("old plush recipes still render for saved packs", () => {
  const svg = renderStickerSvg({
    style: "plush",
    face: "happy",
    animal: "blackcat",
    color: "#332D2B",
    accent: "#F4A7B1",
    caption: "旧表情",
  });
  assert.ok(svg.includes("旧表情"));
  assert.ok(svg.includes("<ellipse"));
  assert.ok(!svg.includes("ᗜ"));
});

test("SVG data URLs are safe image URLs", () => {
  const url = svgToDataUrl(renderStickerSvg({ ...PACK.stickers[0], style: "kaomoji" }));
  assert.ok(url.startsWith("data:image/svg+xml;base64,"));
  assert.ok(!url.includes("<svg"));
});

test("studio prompt is free-form by default and offers three visual types", () => {
  const state = defaultState();
  state.settings.aiName = "沈言";
  state.settings.persona = "冷静、嘴硬、会照顾人。";
  const messages = buildStickerPackMessages(state);
  const all = JSON.stringify(messages);
  assert.ok(all.includes("沈言"));
  assert.ok(all.includes("冷静、嘴硬"));
  assert.ok(all.includes("不要默认画黑猫颜文字"));
  assert.ok(all.includes("kaomoji"));
  assert.ok(all.includes("plush"));
  assert.ok(all.includes("emoji"));
  assert.ok(all.includes("rabbit"));
  assert.ok(all.includes("任意一个 emoji"));
  assert.ok(all.includes("必须正好 6 个"));
  assert.ok(!all.includes("必须正好 6 个；face 必须来自上面的枚举"));
});

test("studio prompt can be locked to one style and carries the user direction", () => {
  const state = defaultState();
  const messages = buildStickerPackMessages(state, { style: "emoji", direction: "奶油色柴犬，欠欠的吐槽风" });
  const all = JSON.stringify(messages);
  assert.ok(all.includes("本次固定为 emoji"));
  assert.ok(all.includes("奶油色柴犬"));
  assert.ok(all.includes("任意一个 emoji"));
  assert.ok(!all.includes("软萌动物捏捏"));
  assert.ok(!all.includes("一颗黑色猫猫头"));
});

test("emoji packs parse and render a free-form sticker", () => {
  const pack = {
    name: "柴犬的吐槽",
    theme: "奶油色小狗",
    style: "emoji",
    stickers: [
      { name: "无语", caption: "无语", emoji: "🙄", color: "#FFF2D8", accent: "#E9A9A0" },
      { name: "收到", caption: "收到", emoji: "🫡" },
      { name: "吃瓜", caption: "吃瓜", emoji: "🍉" },
      { name: "晚安", caption: "晚安", emoji: "🌙" },
      { name: "开心", caption: "开心", emoji: "😄" },
      { name: "问号", caption: "问号", emoji: "❓" },
    ],
  };
  const parsed = parseStickerPack(JSON.stringify(pack));
  assert.equal(parsed.style, "emoji");
  assert.equal(parsed.stickers[0].emoji, "🙄");
  assert.equal(parsed.stickers[0].color, "#FFF2D8");
  const svg = renderStickerSvg(parsed.stickers[0]);
  assert.ok(svg.includes("🙄"));
  assert.ok(svg.includes("无语"));
  assert.ok(!svg.includes("<script"));
});

test("plush packs can choose a non-cat animal and custom kaomoji is kept", () => {
  const plush = parseStickerPack(
    JSON.stringify({
      name: "小狗日常",
      style: "plush",
      animal: "dog",
      stickers: Array.from({ length: 6 }, (_, index) => ({
        name: `狗${index}`,
        caption: "汪汪",
        face: index === 0 ? "happy" : "normal",
      })),
    }),
    { style: "plush" },
  );
  assert.equal(plush.style, "plush");
  assert.equal(plush.stickers[0].animal, "dog");
  assert.ok(renderStickerSvg(plush.stickers[0]).includes("<ellipse"));

  const kao = parseStickerPack(
    JSON.stringify({
      ...PACK,
      stickers: [{ ...PACK.stickers[0], kaomoji: "( •̀ ω •́ )✧" }, ...PACK.stickers.slice(1)],
    }),
  );
  assert.equal(kao.stickers[0].kaomoji, "( •̀ ω •́ )✧");
  assert.ok(renderStickerSvg(kao.stickers[0]).includes("( •̀ ω •́ )✧"));
});
