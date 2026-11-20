import test from "node:test";
import assert from "node:assert/strict";
import { defaultState } from "../js/config.js";
import { SCENE_IDS, sceneSvg } from "../js/scenes.js";
import { buildReportFromRaw, normaliseBlocks, reportBlocksHtml } from "../js/report.js";
import { buildReportMessages } from "../js/prompt.js";

test("every scene renders a self-contained, script-free SVG", () => {
  for (const id of SCENE_IDS) {
    const svg = sceneSvg(id);
    assert.ok(svg.startsWith("<svg"), id);
    assert.ok(svg.includes('viewBox="0 0 96 96"'), id);
    assert.ok(!/<script|href=|foreignObject|onload=/i.test(svg), id);
  }
  assert.equal(sceneSvg("not-a-scene"), "");
});

test("report blocks keep only plain text and a whitelisted scene", () => {
  const blocks = normaliseBlocks([
    { text: "  <b>煎了两个蛋</b>，蛋黄还是流心的。 ", scene: "egg" },
    { text: "窗外在下雨。", scene: "rain" },
    { text: "", scene: "cat" },
    { text: "写了个假场景。", scene: "unicorn" },
    { text: 42 },
    { text: "第六段会被截掉", scene: "none" },
  ]);
  assert.equal(blocks.length, 5);
  assert.equal(blocks[0].text, "煎了两个蛋，蛋黄还是流心的。");
  assert.equal(blocks[0].scene, "egg");
  assert.equal(blocks[3].scene, "");
  assert.equal(blocks[4].text, "第六段会被截掉");
});

test("report block markup includes the scene art and escapes the text", () => {
  const html = reportBlocksHtml([
    { text: "吃了鸡蛋<script>alert(1)</script>", scene: "egg" },
    { text: "没有画面的段落", scene: "" },
  ]);
  assert.ok(html.includes('class="report-scene"'));
  assert.ok(html.includes("<svg"));
  assert.ok(html.includes("&lt;script&gt;"));
  assert.ok(!html.includes("<script>"));
  assert.ok(html.includes("report-block is-text"));
});

test("report JSON with blocks wins over html and keeps 2+ paragraphs", () => {
  const raw = JSON.stringify({
    title: "窗边的下午",
    summary: "吃完蛋，天就暗了。",
    blocks: [
      { text: "下午煎了两个蛋。", scene: "egg" },
      { text: "窗外开始下雨。", scene: "rain" },
      { text: "想你了。", scene: "heart" },
    ],
    html: "<p>不应该被使用</p>",
  });
  const report = buildReportFromRaw(raw);
  assert.equal(report.title, "窗边的下午");
  assert.equal(report.blocks.length, 3);
  assert.equal(report.blocks[1].scene, "rain");
  assert.equal(report.html, "");
});

test("report prompt asks for blocks and lists every scene id", () => {
  const state = defaultState();
  state.settings.aiName = "沈言";
  const messages = buildReportMessages(state);
  const all = JSON.stringify(messages);
  assert.ok(all.includes("blocks"));
  assert.ok(all.includes("scene"));
  for (const id of SCENE_IDS) assert.ok(all.includes(`${id}（`), id);
  assert.ok(all.includes("none"));
  assert.ok(!all.includes("【HTML 规则】"));
});
