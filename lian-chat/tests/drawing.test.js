import test from "node:test";
import assert from "node:assert/strict";
import {
  DRAWING_LIMITS,
  buildHtmlDocument,
  buildSvgDataUri,
  drawingBytes,
  drawingLabel,
  ensureSvgSize,
  extractDrawings,
  isHtmlDrawing,
  isSvgDrawing,
  stripActiveHtml,
} from "../js/drawing.js";
import { defaultState } from "../js/config.js";
import { buildSystemPrompt, parseReply } from "../js/prompt.js";

const SVG = '<svg viewBox="0 0 320 320"><rect width="320" height="320" fill="#fdf6e3"/><circle cx="160" cy="140" r="60" fill="#e99"/></svg>';

test("a fenced svg drawing is pulled out of the reply", () => {
  const { text, drawings } = extractDrawings(`给你看窗外。\n\n\`\`\`svg\n${SVG}\n\`\`\``);
  assert.equal(text, "给你看窗外。");
  assert.equal(drawings.length, 1);
  assert.equal(drawings[0].type, "svg");
  assert.ok(drawings[0].markup.startsWith("<svg"));
});

test("a fenced html drawing is pulled out too", () => {
  const html = `<div class="sky"><span></span></div><style>.sky{width:200px;height:200px;background:#cfe}span{display:block;width:20px;height:20px;border-radius:50%;background:#fc9;animation:float 3s ease-in-out infinite}@keyframes float{50%{transform:translateY(-16px)}}</style>`;
  const { text, drawings } = extractDrawings(`给你画个会飘的：\n\`\`\`html\n${html}\n\`\`\``);
  assert.equal(drawings.length, 1);
  assert.equal(drawings[0].type, "html");
  assert.ok(drawings[0].markup.includes("@keyframes float"));
  assert.equal(text, "给你画个会飘的：");
});

test("code that is not a drawing stays in the text", () => {
  const snippet = "```svg\n<svg>\n```";
  const plain = "```js\nconsole.log(1)\n```";
  assert.equal(extractDrawings(snippet).drawings.length, 0);
  assert.equal(extractDrawings(plain).drawings.length, 0);
  assert.ok(extractDrawings(plain).text.includes("console.log(1)"));
  // an svg block that never closes is not a drawing either
  assert.equal(isSvgDrawing('<svg viewBox="0 0 10 10"><circle r="2"/></svg'), false);
  assert.equal(isHtmlDrawing("just words"), false);
});

test("only one drawing per reply, and oversized ones are refused", () => {
  const two = `\`\`\`svg\n${SVG}\n\`\`\`\n\`\`\`svg\n${SVG}\n\`\`\``;
  const { drawings } = extractDrawings(two);
  assert.equal(drawings.length, 1);

  const huge = `<svg viewBox="0 0 320 320">${"<circle r='1'/>".repeat(2000)}</svg>`;
  assert.ok(huge.length > DRAWING_LIMITS.maxSvgChars);
  assert.equal(isSvgDrawing(huge), false);
  assert.equal(extractDrawings(`\`\`\`svg\n${huge}\n\`\`\``).drawings.length, 0);
});

test("a reply cut off mid-drawing never leaks its svg source", () => {
  /* this is the phone bug: max_tokens stopped the reply inside <svg>, the
     closing fence never arrived, and the raw source showed up in a bubble */
  const out = extractDrawings('看这个。\n```svg\n<svg viewBox="0 0 320 320"><circle cx="160"');
  assert.equal(out.drawings.length, 0);
  assert.equal(out.broken, 1);
  assert.equal(out.text, "看这个。");
  assert.ok(!out.text.includes("<svg"));
});

test("a fence with a note after </svg> still renders", () => {
  const out = extractDrawings(`\`\`\`svg\n${SVG}\n<!-- 画好了 -->\n\`\`\``);
  assert.equal(out.drawings.length, 1);
  assert.ok(out.drawings[0].markup.endsWith("</svg>"));
  assert.ok(!out.drawings[0].markup.includes("画好了"));
});

test("the html sandbox document forbids scripts, links and external loads", () => {
  const doc = buildHtmlDocument(`<script>alert(1)</script><a href="javascript:alert(2)" onclick="x()">hi</a><img src="https://example.com/x.png"><link rel="stylesheet" href="//cdn/x.css">`);
  assert.ok(!/<script/i.test(doc));
  assert.ok(!/onclick/i.test(doc));
  assert.ok(!/javascript:/i.test(doc));
  assert.ok(!/<link/i.test(doc));
  assert.ok(doc.includes("Content-Security-Policy"));
  assert.ok(doc.includes("script-src 'none'"));
  assert.ok(doc.includes("default-src 'none'"));
  assert.ok(doc.includes(">hi<"));
});

test("stripActiveHtml only removes active bits", () => {
  const kept = stripActiveHtml('<div class="a" data-x="1"><p style="color:red">你好</p><style>.a{padding:4px}</style></div>');
  assert.ok(kept.includes("<p style=\"color:red\">你好</p>"));
  assert.ok(kept.includes("<style>.a{padding:4px}</style>"));
  assert.equal(stripActiveHtml('<div onclick="evil()">x</div>'), "<div>x</div>");
  assert.equal(stripActiveHtml('<iframe src="//x"></iframe><b>ok</b>'), "<b>ok</b>");
});

test("svg data URIs are percent-encoded and stay self-contained", () => {
  const svg = `<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><text>你好</text></svg>`;
  const uri = buildSvgDataUri(svg);
  assert.ok(uri.startsWith("data:image/svg+xml;charset=utf-8,"));
  assert.ok(!uri.includes("<?xml"));
  assert.ok(uri.includes(encodeURIComponent("你好")));
  assert.ok(!uri.includes("<svg")); // must be encoded, not raw
});

test("a square viewBox is stamped on the svg so it is not squashed", () => {
  const sized = ensureSvgSize('<svg viewBox="0 0 320 320"><rect/></svg>');
  assert.ok(sized.includes('width="320"'));
  assert.ok(sized.includes('height="320"'));
  // explicit sizes are left alone
  const explicit = ensureSvgSize('<svg width="120" height="90" viewBox="0 0 320 320"></svg>');
  assert.equal(explicit, '<svg width="120" height="90" viewBox="0 0 320 320"></svg>');
  // no viewBox: nothing to stamp
  assert.equal(ensureSvgSize("<svg></svg>"), "<svg></svg>");
});

test("drawing metadata helpers agree on type and size", () => {
  assert.equal(drawingLabel({ type: "svg" }), "SVG");
  assert.equal(drawingLabel({ type: "html" }), "HTML");
  assert.ok(drawingBytes({ markup: SVG }) > 10);
  assert.equal(drawingBytes(null), 0);
});

test("the prompt only offers drawings when the switch is on", () => {
  const off = defaultState();
  off.settings.apiKey = "test";
  assert.equal(off.settings.optimize.drawings, false);
  assert.ok(!buildSystemPrompt(off).includes("【现场画画面】"));
  assert.ok(buildSystemPrompt(off).includes("不主动发链接、图片、HTML 或代码"));

  const on = defaultState();
  on.settings.apiKey = "test";
  on.settings.optimize.drawings = true;
  const prompt = buildSystemPrompt(on);
  assert.ok(prompt.includes("【现场画画面】"));
  assert.ok(prompt.includes("```svg"));
  assert.ok(prompt.includes("```html"));
  assert.ok(!prompt.includes("不主动发链接、图片、HTML 或代码"));
});

test("parseReply skips drawing fences unless enabled", () => {
  const raw = `看这个。\n\`\`\`svg\n${SVG}\n\`\`\``;

  const off = defaultState();
  off.settings.apiKey = "test";
  off.settings.optimize.autoSticker = false;
  const parsedOff = parseReply(raw, off);
  assert.equal(parsedOff.drawings.length, 0);
  assert.ok(parsedOff.text.includes("<svg"));

  const on = defaultState();
  on.settings.apiKey = "test";
  on.settings.optimize.autoSticker = false;
  on.settings.optimize.drawings = true;
  const parsedOn = parseReply(raw, on);
  assert.equal(parsedOn.drawings.length, 1);
  assert.equal(parsedOn.text, "看这个。");
  assert.deepEqual(parsedOn.parts, ["看这个。"]);
});

test("a cut-off drawing leaves clean words and a flag, never raw markup", () => {
  const s = defaultState();
  s.settings.apiKey = "test";
  s.settings.optimize.autoSticker = false;
  s.settings.optimize.drawings = true;
  const parsed = parseReply('在睡觉。拍糊了。\n\n```svg\n<svg viewBox="0 0 320 320"><path d="M100 130 L82', s);
  assert.equal(parsed.drawings.length, 0);
  assert.equal(parsed.drawingBroken, true);
  assert.equal(parsed.text, "在睡觉。拍糊了。");
  assert.ok(!parsed.text.includes("```"));
  assert.ok(!parsed.text.includes("<svg"));
  assert.deepEqual(parsed.parts, ["在睡觉。拍糊了。"]);
});

test("with drawings off the markers go but the code the user asked for stays", () => {
  const s = defaultState();
  s.settings.apiKey = "test";
  s.settings.optimize.autoSticker = false;
  const parsed = parseReply(`给你代码：\n\`\`\`svg\n${SVG}\n\`\`\``, s);
  assert.ok(!parsed.text.includes("```"));
  assert.ok(parsed.text.includes("<svg"));
  assert.equal(parsed.drawingBroken, false);
});
