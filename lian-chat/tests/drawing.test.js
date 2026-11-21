import test from "node:test";
import assert from "node:assert/strict";
import {
  DRAWING_LIMITS,
  adoptStoredDrawings,
  buildHtmlDocument,
  buildSvgDataUri,
  drawingBytes,
  drawingLabel,
  ensureSvgSize,
  extractDrawings,
  isHtmlDrawing,
  isSvgDrawing,
  stripActiveHtml,
  stripSvgSource,
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

test("a bare svg with no fence is a drawing too", () => {
  /* the phone case: the model answered a "画SVG小猫" request with plain <svg>
     markup, no ``` fence, and every blank line became a new bubble */
  const out = extractDrawings(`画好了。\n\n${SVG}\n\n希望你会喜欢。`);
  assert.equal(out.drawings.length, 1);
  assert.ok(out.drawings[0].markup.startsWith("<svg"));
  assert.ok(out.text.includes("画好了。"));
  assert.ok(out.text.includes("希望你会喜欢。"));
  assert.ok(!out.text.includes("<svg"));
});

test("a bare svg cut off before </svg> is stripped, not printed", () => {
  const out = extractDrawings('在睡觉。\n<svg viewBox="0 0 320 320">\n<ellipse cx="160" cy="222"');
  assert.equal(out.drawings.length, 0);
  assert.equal(out.broken, 1);
  assert.equal(out.text, "在睡觉。");
});

test("a passing mention of the tag is not a drawing", () => {
  const out = extractDrawings("svg 里的 <svg> 标签就是画布。");
  assert.equal(out.drawings.length, 0);
  assert.ok(out.text.includes("<svg>"));
});

test("a fenced js block is still shown as code", () => {
  const out = extractDrawings("```js\nconsole.log(1)\n```");
  assert.equal(out.drawings.length, 0);
  assert.ok(out.text.includes("console.log(1)"));
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

test("parseReply pulls drawings out whether or not the switch is on", () => {
  const raw = `看这个。\n\`\`\`svg\n${SVG}\n\`\`\``;

  /* the switch only decides whether the prompt *offers* drawings; a model that
     draws anyway must never paint its source into the chat */
  const off = defaultState();
  off.settings.apiKey = "test";
  off.settings.optimize.autoSticker = false;
  const parsedOff = parseReply(raw, off);
  assert.equal(parsedOff.drawings.length, 1);
  assert.equal(parsedOff.text, "看这个。");
  assert.ok(!parsedOff.text.includes("<svg"));

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

test("with drawings off, a complete picture is still drawn instead of printed", () => {
  const s = defaultState();
  s.settings.apiKey = "test";
  s.settings.optimize.autoSticker = false;
  const parsed = parseReply(`给你画了：\n\`\`\`svg\n${SVG}\n\`\`\``, s);
  assert.equal(parsed.drawings.length, 1);
  assert.ok(!parsed.text.includes("<svg"));
  assert.equal(parsed.drawingBroken, false);
});

test("the render guard strips svg source out of any text", () => {
  assert.equal(stripSvgSource("画好了。\n<svg viewBox=\"0 0 10 10\"><rect/></svg>\n喜欢吗"), "画好了。\n\n喜欢吗");
  assert.equal(stripSvgSource("在睡觉。\n<svg viewBox=\"0 0 10 10\"><ellipse"), "在睡觉。");
  assert.equal(stripSvgSource("```svg\n<svg viewBox=\"0 0 10 10\"></svg>\n```"), "");
  assert.equal(stripSvgSource("普通的一句话"), "普通的一句话");
  assert.ok(!stripSvgSource("前言<svg viewBox=\"0 0 1 1\"/>后记").includes("<svg"));
});

test("a reply saved as raw svg is repaired into words plus a picture", () => {
  /* history written before 1.9.14 still holds `text` messages full of markup */
  const messages = [
    { id: "m1", role: "assistant", kind: "text", text: `给你画好啦🐱\n\n${SVG}`, ts: 11 },
    { id: "m2", role: "user", kind: "text", text: "谢谢", ts: 12 },
  ];
  const out = adoptStoredDrawings(messages, { note: "（没画完）" });
  assert.equal(out.changed, true);
  assert.equal(out.messages.length, 3);
  assert.equal(out.messages[0].id, "m1");
  assert.equal(out.messages[0].kind, "text");
  assert.equal(out.messages[0].text, "给你画好啦🐱");
  assert.equal(out.messages[1].kind, "drawing");
  assert.equal(out.messages[1].drawing.type, "svg");
  assert.equal(out.messages[1].id, "m1_art");
  assert.equal(out.messages[2].id, "m2");
});

test("a repaired reply that was nothing but a picture keeps its id", () => {
  const out = adoptStoredDrawings([{ id: "only", role: "assistant", kind: "text", text: SVG, ts: 1 }], { note: "x" });
  assert.equal(out.messages.length, 1);
  assert.equal(out.messages[0].id, "only");
  assert.equal(out.messages[0].kind, "drawing");
});

test("a saved reply whose drawing never finished keeps only its words", () => {
  const out = adoptStoredDrawings(
    [{ id: "m1", role: "assistant", kind: "text", text: '在睡觉。\n<svg viewBox="0 0 320 320"><ellipse', ts: 1 }],
    { note: "（没画完）" },
  );
  assert.equal(out.messages.length, 1);
  assert.equal(out.messages[0].kind, "text");
  assert.equal(out.messages[0].text, "在睡觉。");
});

test("adopting history is idempotent and ignores normal messages", () => {
  const plain = [
    { id: "m1", role: "assistant", kind: "text", text: "普通消息", ts: 1 },
    { id: "m2", role: "user", kind: "sticker", stickerId: "mk_ok", ts: 2 },
  ];
  const untouched = adoptStoredDrawings(plain, { note: "x" });
  assert.equal(untouched.changed, false);
  assert.deepEqual(untouched.messages, plain);

  const once = adoptStoredDrawings([{ id: "a", role: "assistant", kind: "text", text: `hi\n${SVG}`, ts: 1 }], { note: "x" });
  const twice = adoptStoredDrawings(once.messages, { note: "x" });
  assert.equal(twice.changed, false);
  assert.equal(twice.messages.length, once.messages.length);
});

test("adopting history can be limited to assistant drawings", () => {
  /* 用户自己贴的 svg 源码不是模型的画，不能转成图片 */
  const paste = { id: "u1", role: "user", kind: "text", text: `这段哪错了？\n${SVG}`, ts: 1 };
  const out = adoptStoredDrawings([paste], { note: "x", roles: ["assistant"] });
  assert.equal(out.changed, false);
  assert.deepEqual(out.messages, [paste]);

  const reply = { id: "a1", role: "assistant", kind: "text", text: `画好了\n${SVG}`, ts: 2 };
  const fixed = adoptStoredDrawings([paste, reply], { note: "x", roles: ["assistant"] });
  assert.equal(fixed.changed, true);
  assert.equal(fixed.messages.length, 3);
  assert.equal(fixed.messages[0].kind, "text");
  assert.equal(fixed.messages[1].kind, "text");
  assert.equal(fixed.messages[2].kind, "drawing");
});
