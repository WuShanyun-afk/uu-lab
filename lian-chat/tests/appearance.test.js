import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { CHAT_LAYOUTS, THEMES, defaultState } from "../js/config.js";
import { normaliseState } from "../js/store.js";
import { contrastRatio } from "../js/palette.js";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (file) => fs.readFileSync(path.join(ROOT, file), "utf8");
const hex = /^#[0-9a-f]{6}$/i;

test("themes: 16 skins, unique ids, valid accent/bg", () => {
  assert.equal(THEMES.length, 16);
  assert.ok(THEMES.some((theme) => theme.id === "assistant"), "the assistant skin is required by assistant mode");
  const ids = new Set(THEMES.map((theme) => theme.id));
  assert.equal(ids.size, THEMES.length);
  for (const theme of THEMES) {
    assert.match(theme.accent, hex, theme.id);
    assert.match(theme.bg, hex, theme.id);
    assert.ok(theme.swatch || theme.accent, `${theme.id} needs a swatch`);
    if (theme.statusBar) assert.match(theme.statusBar, hex, `${theme.id} statusBar`);
  }
});

test("themes: every bubble colour keeps 4.5:1 against its ink", () => {
  for (const theme of THEMES.filter((item) => item.bubble)) {
    const { bg, ink } = theme.bubble;
    assert.match(bg, hex, theme.id);
    assert.match(ink, hex, theme.id);
    assert.ok(contrastRatio(bg, ink) >= 4.5, `${theme.id}: ${contrastRatio(bg, ink)}`);
  }
});

test("themes: the new skins have their own stylesheet block", () => {
  const extra = read("css/modules/15-themes.css");
  const ids = ["mint", "berry", "butter", "lilac", "sky", "dawn", "mono", "neo"];
  for (const id of ids) {
    assert.ok(extra.includes(`body[data-theme="${id}"]`), `missing css for ${id}`);
  }
  assert.ok(read("css/modules/07-theme-paper.css").includes('data-theme="paper"'));
});

test("layouts: eight presets, unique ids, line stays the default", () => {
  assert.deepEqual(CHAT_LAYOUTS.map((item) => item.id), [
    "line", "imessage", "letter", "bubble", "plain", "journal", "timeline", "comic",
  ]);
  for (const layout of CHAT_LAYOUTS) {
    assert.equal(typeof layout.label, "string");
    assert.ok(layout.label.includes("/"), `${layout.id} label should be bilingual`);
  }
  assert.equal(defaultState().settings.layout, "line");
});

test("layouts: unknown values fall back to line, valid ones survive", () => {
  assert.equal(normaliseState({ settings: { layout: "sparkles" } }).settings.layout, "line");
  assert.equal(normaliseState({ settings: { layout: "" } }).settings.layout, "line");
  for (const id of ["imessage", "letter", "bubble", "plain", "journal", "timeline", "comic"]) {
    assert.equal(normaliseState({ settings: { layout: id } }).settings.layout, id);
  }
});

test("layouts: each preset has structure rules, and the shared hooks exist", () => {
  const css = read("css/modules/16-layouts.css");
  assert.ok(css.includes(".msg-name"), "sender label hook");
  assert.ok(css.includes(".chat-crest"), "letter crest hook");
  for (const id of ["imessage", "letter", "bubble", "plain", "journal", "timeline", "comic"]) {
    assert.ok(css.includes(`[data-layout="${id}"]`), `${id} has no rules`);
  }
  /* the default layout must not restyle anything */
  assert.ok(!css.includes('[data-layout="line"]'), "line should stay rule-free");
});

test("layouts: stylesheet is wired into index.html and the precache", () => {
  const html = read("index.html");
  const sw = read("sw.js");
  assert.ok(html.includes("css/modules/16-layouts.css"));
  assert.ok(sw.includes("css/modules/16-layouts.css"));
  assert.ok(!html.includes("16-chat-styles.css"), "old module should be gone");
});

test("screens: list, home and contacts design layer is wired in", () => {
  const html = read("index.html");
  const sw = read("sw.js");
  const css = read("css/modules/17-screens.css");
  assert.ok(html.includes("css/modules/17-screens.css"));
  assert.ok(sw.includes("css/modules/17-screens.css"));
  assert.ok(sw.includes("js/insights.js"), "insights.js must be precached");
  for (const hook of [".list-hero", ".list-filters", ".chat-row", ".home-daily", ".accent-editor"]) {
    assert.ok(css.includes(hook) || read("css/app.css").includes(hook), `${hook} has no styles`);
  }
});

test("screens: the accent field is a hex box, not a colour wheel", () => {
  const settings = read("js/settings.js");
  assert.ok(settings.includes('id="accentHex"'), "hex input missing");
  assert.ok(settings.includes("normaliseAccent"), "hex validation missing");
  assert.ok(!settings.includes('type="color"'), "native colour picker should be gone");
});

test("composer: the inline tray is wired up", () => {
  const html = read("index.html");
  const app = read("js/app.js");
  const css = read("css/modules/18-composer.css");
  const sw = read("sw.js");
  assert.ok(html.includes('id="composerTray"'), "tray markup missing");
  assert.ok(html.includes('data-tray="image"') && html.includes('data-tray="more"'));
  assert.ok(html.includes('id="trayEmoji"'), "emoji row missing");
  assert.ok(css.includes(".composer-tray") && css.includes(".tray-emoji-btn"));
  assert.ok(app.includes("setComposerTray") && app.includes("insertEmoji"), "handlers missing");
  assert.ok(sw.includes("css/modules/18-composer.css"), "stylesheet not precached");
  /* opening a chat or a tab must not leave the tray hanging open */
  assert.ok(app.includes("setComposerTray(false)"));
});
