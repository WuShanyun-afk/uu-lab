import test from "node:test";
import assert from "node:assert/strict";
import { chatHaystack, countMatches, matchMessageIndexes, matchSnippet, normaliseQuery, splitByMatches } from "../js/search.js";

test("splitByMatches marks every occurrence and keeps the original text", () => {
  const parts = splitByMatches("降温了，记得带外套。外套在门口。", "外套");
  assert.equal(parts.filter((p) => p.hit).length, 2);
  assert.equal(parts.map((p) => p.text).join(""), "降温了，记得带外套。外套在门口。");
  assert.deepEqual(parts[0], { text: "降温了，记得带", hit: false });
});

test("splitByMatches is case-insensitive and safe on empty input", () => {
  assert.deepEqual(splitByMatches("Hello Hello", "hello").filter((p) => p.hit).length, 2);
  assert.deepEqual(splitByMatches("", "x"), [{ text: "", hit: false }]);
  assert.deepEqual(splitByMatches("abc", ""), [{ text: "abc", hit: false }]);
});

test("normaliseQuery trims and lowercases", () => {
  assert.equal(normaliseQuery("  外套 "), "外套");
  assert.equal(normaliseQuery(null), "");
  assert.equal(countMatches("aAaa", "a"), 4);
});

test("chatHaystack joins name, relationship and preview", () => {
  assert.equal(chatHaystack({ name: "沈言", relationship: "恋人" }, "晚上吃面"), "沈言 · 恋人 · 晚上吃面");
  assert.equal(chatHaystack({}, ""), "");
});

test("chatHaystack also searches recent message history", () => {
  const haystack = chatHaystack({ name: "沈言" }, "最后一条", [
    { kind: "text", text: "晚上吃了碗热汤面" },
    { kind: "sticker", stickerId: "mk_shy" },
    { kind: "report", report: { title: "周末", blocks: [{ text: "煎了两个蛋" }] } },
  ]);
  assert.ok(haystack.includes("热汤面"));
  assert.ok(haystack.includes("煎了两个蛋"));
  assert.ok(haystack.startsWith("沈言 · 最后一条"));
});

test("matchSnippet explains a history-only match", () => {
  const messages = [
    { kind: "text", text: "今天降温了" },
    { kind: "text", text: "先说一件小事，晚上吃了碗热汤面，还加了个蛋。这里再补一些字让片段被截断一下下。" },
  ];
  const snippet = matchSnippet(messages, "汤面", 20);
  assert.ok(snippet.includes("汤面"), snippet);
  assert.ok(snippet.startsWith("…"), snippet);
  assert.equal(matchSnippet(messages, "不存在"), "");
  assert.equal(matchSnippet(messages, ""), "");
});

test("matchMessageIndexes finds text and report blocks, skips stickers", () => {
  const messages = [
    { role: "user", kind: "text", text: "今天降温了" },
    { role: "assistant", kind: "sticker", stickerId: "mk_shy" },
    { role: "assistant", kind: "report", report: { title: "周末", blocks: [{ text: "煎了两个蛋" }] } },
    { role: "user", kind: "text", text: "明天见" },
  ];
  assert.deepEqual(matchMessageIndexes(messages, "降温"), [0]);
  assert.deepEqual(matchMessageIndexes(messages, "煎蛋"), []);
  assert.deepEqual(matchMessageIndexes(messages, "煎了两个蛋"), [2]);
  assert.deepEqual(matchMessageIndexes(messages, "明天"), [3]);
  assert.deepEqual(matchMessageIndexes(messages, ""), []);
});
