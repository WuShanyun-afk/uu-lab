import test from "node:test";
import assert from "node:assert/strict";
import { THEMES, defaultState, themeLabel } from "../js/config.js";

test("every theme has a Chinese and an English label", () => {
  for (const theme of THEMES) {
    assert.equal(typeof theme.label, "string");
    assert.ok(theme.label.length > 0, theme.id);
    assert.equal(typeof theme.labelEn, "string", theme.id);
    assert.ok(theme.labelEn.length > 0, theme.id);
    assert.match(theme.accent, /^#[0-9a-f]{6}$/i, theme.id);
  }
});

test("themeLabel follows the UI language", () => {
  const paper = THEMES.find((theme) => theme.id === "paper");
  assert.equal(themeLabel(paper, "zh"), "纸间");
  assert.equal(themeLabel(paper, "en"), "Paper");
  assert.equal(themeLabel(paper), "纸间");
  assert.equal(themeLabel(null, "en"), "");
});

test("paper is selectable and is not the default theme", () => {
  const state = defaultState();
  assert.equal(state.settings.theme, "line");
  assert.ok(THEMES.some((theme) => theme.id === "paper"));
  assert.equal(THEMES.filter((theme) => theme.immersive).length, 1);
});

test("the paper theme keeps its own accent and background", () => {
  const paper = THEMES.find((theme) => theme.id === "paper");
  assert.equal(paper.bg, "#EEF0E8");
  assert.ok(paper.swatch.includes("linear-gradient"));
});
