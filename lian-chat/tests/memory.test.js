import test from "node:test";
import assert from "node:assert/strict";
import { defaultState } from "../js/config.js";
import { buildMemoryMessages, mergeMemories, parseMemoryReply } from "../js/memory.js";

function state() {
  const s = defaultState();
  s.settings.aiName = "沈言";
  s.settings.userName = "小满";
  s.messages = [
    { id: "a", role: "user", kind: "text", text: "我喝咖啡不加糖，周三晚上有课。", ts: 1 },
    { id: "b", role: "assistant", kind: "text", text: "记住了。", ts: 2 },
  ];
  return s;
}

test("memory prompt contains recent chat and existing notes", () => {
  const s = state();
  s.memories = [{ id: "m1", text: "小满怕黑。", createdAt: 0 }];
  const messages = buildMemoryMessages(s);
  const all = JSON.stringify(messages);
  assert.ok(all.includes("我喝咖啡不加糖"));
  assert.ok(all.includes("小满怕黑"));
  assert.ok(all.includes("只输出合法 JSON"));
});

test("memory JSON parser tolerates fences and de-duplicates rows", () => {
  const rows = parseMemoryReply("```json\n{\"memories\":[\"小满不喝加糖咖啡\",\"小满不喝加糖咖啡\",\"\"]}\n```");
  assert.deepEqual(rows, ["小满不喝加糖咖啡"]);
  assert.deepEqual(parseMemoryReply("[\"周三晚上有课\"]"), ["周三晚上有课"]);
});

test("memory merger skips duplicates and caps the list", () => {
  const existing = [
    { id: "m1", text: "小满不喝加糖咖啡", createdAt: 0 },
    { id: "m2", text: "周三晚上有课", createdAt: 0 },
  ];
  const merged = mergeMemories(existing, ["小满不喝加糖咖啡", "小满喜欢猫", "小满喜欢猫"], 3);
  assert.equal(merged.added, 1);
  assert.equal(merged.memories.length, 3);
  assert.equal(merged.memories.at(-1).text, "小满喜欢猫");
  assert.equal(merged.memories.at(-1).source, "ai");
});
