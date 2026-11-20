import test from "node:test";
import assert from "node:assert/strict";
import { THEMES } from "../js/config.js";
import { accentStrong, contrastRatio, mineBubble, mixHex, normaliseAccent, parseHex, readableInk } from "../js/palette.js";

test("normaliseAccent: what people actually type in a 色号 field", () => {
  assert.equal(normaliseAccent("#06c755"), "#06C755");
  assert.equal(normaliseAccent("06C755"), "#06C755");
  assert.equal(normaliseAccent("  #06C755  "), "#06C755");
  assert.equal(normaliseAccent("##06C755"), "#06C755");
  assert.equal(normaliseAccent("#0a0"), "#00AA00");
  assert.equal(normaliseAccent("f0a"), "#FF00AA");
  assert.equal(normaliseAccent("#"), "");
  assert.equal(normaliseAccent(""), "");
  assert.equal(normaliseAccent("nope"), "");
  assert.equal(normaliseAccent("#12345"), "");
  assert.equal(normaliseAccent(null), "");
});

test("contrast ratio matches the WCAG reference points", () => {
  assert.equal(contrastRatio("#000000", "#ffffff"), 21);
  assert.equal(contrastRatio("#ffffff", "#ffffff"), 1);
  assert.equal(contrastRatio("#777777", "#ffffff"), 4.48);
  assert.equal(contrastRatio("not-a-color", "#ffffff"), 0);
});

test("parseHex / mixHex behave on edge input", () => {
  assert.deepEqual(parseHex("#06C755"), { r: 6, g: 199, b: 85 });
  assert.deepEqual(parseHex("06c755"), { r: 6, g: 199, b: 85 });
  assert.equal(parseHex("#fff"), null);
  assert.equal(parseHex(""), null);
  assert.equal(mixHex("#000000", "#ffffff", 0.5), "#808080");
  assert.equal(mixHex("bogus", "#ffffff", 0.5), "bogus");
});

test("every built-in theme gets a readable user bubble", () => {
  for (const theme of THEMES) {
    const { bg, ink, ratio } = mineBubble(theme.accent);
    assert.ok(ratio >= 4.5, `${theme.id} ${theme.accent} -> ${bg} ${ratio}`);
    assert.equal(contrastRatio(bg, ink), ratio);
    assert.ok(parseHex(bg), `${theme.id} produced ${bg}`);
  }
});

test("a dark accent is left alone, a bright one is darkened", () => {
  const ink = mineBubble("#1B1B1B");
  assert.equal(ink.bg, "#1B1B1B");
  assert.equal(ink.changed, false);

  const line = mineBubble("#06C755");
  assert.equal(line.changed, true);
  assert.notEqual(line.bg, "#06C755");
  assert.ok(line.ratio >= 4.5);
  // Hue is preserved: the green channel stays dominant.
  const rgb = parseHex(line.bg);
  assert.ok(rgb.g > rgb.r && rgb.g > rgb.b, line.bg);
});

test("accentStrong only darkens as much as needed for text", () => {
  for (const theme of THEMES) {
    const strong = accentStrong(theme.accent);
    assert.ok(contrastRatio(strong, "#ffffff") >= 4.5, `${theme.id} ${strong}`);
  }
  assert.equal(accentStrong("#1B1B1B"), "#1B1B1B");
});

test("readableInk picks the side with more contrast", () => {
  assert.equal(readableInk("#fffefb"), "#141310");
  assert.equal(readableInk("#101010"), "#ffffff");
  assert.equal(readableInk("nope"), "#ffffff");
});
