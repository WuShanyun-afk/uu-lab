import { getSticker } from "./config.js";
import { escapeRegExp, uid } from "./utils.js";

function oneLine(value, max = 180) {
  return String(value || "").replace(/\s+/g, " ").trim().slice(0, max);
}

function transcriptLine(message, state) {
  if (message.kind === "sticker") {
    const sticker = getSticker(message.stickerId, state.customStickers);
    return `${message.role === "user" ? "对方" : "我"}：[表情：${sticker?.name || "表情"}]`;
  }
  if (message.kind === "image") return `${message.role === "user" ? "对方" : "我"}：[图片]${message.text ? ` ${oneLine(message.text, 100)}` : ""}`;
  if (message.kind === "file") return `${message.role === "user" ? "对方" : "我"}：[文件：${message.file?.name || "文件"}]${message.text ? ` ${oneLine(message.text, 100)}` : ""}`;
  if (message.kind === "report") return `${message.role === "user" ? "对方" : "我"}：[日常报备]`;
  if (message.kind === "drawing") return `${message.role === "user" ? "对方" : "我"}：[发了一张自己画的画面]${message.text ? ` ${oneLine(message.text, 100)}` : ""}`;
  return `${message.role === "user" ? "对方" : "我"}：${oneLine(message.text, 240)}`;
}

/**
 * Build a compact, one-off prompt for turning a recent conversation into
 * durable notes. This is intentionally separate from the chat prompt so it
 * cannot affect the roleplay voice.
 */
export function buildMemoryMessages(state) {
  const s = state.settings;
  const recent = (state.messages || [])
    .filter((message) => (message.role === "user" || message.role === "assistant") && message.kind !== "error")
    .slice(-40)
    .map((message) => transcriptLine(message, state))
    .join("\n");
  const existing = (state.memories || []).map((memory) => `- ${oneLine(memory.text, 160)}`).join("\n");
  const system = `你是「${s.aiName || "Lian"}」的记忆整理器。你的任务是从最近的聊天里，找出值得长期记住的、关于「${s.userName || "对方"}」的稳定事实。

【规则】
- 只记录对方明确说过的、以后仍然有用的事实：偏好、习惯、重要的人/事、计划、边界、称呼、身体状况等。
- 不要记录一次性的情绪、寒暄、玩笑、猜测，也不要编造。
- 不要把角色自己说过的话当成对方的事实。
- 不要记录敏感密码、API Key、身份证号、银行卡等隐私凭证。
- 每条 6–40 字，用陈述句，第三人称写对方，例如「小满喝咖啡不加糖」。
- 最多输出 6 条；没有值得记住的内容就输出空数组。
- 不要重复已有记忆。
${existing ? `\n【已有记忆】\n${existing}` : ""}

【输出】
只输出合法 JSON，不要 Markdown，不要解释：
{"memories":["一条新记忆","另一条新记忆"]}`;
  return [
    { role: "system", content: system },
    { role: "user", content: `【最近的聊天】\n${recent || "（还没有聊天）"}\n\n请整理值得长期记住的新记忆。只输出 JSON。` },
  ];
}

function parseLooseLines(raw) {
  return String(raw || "")
    .split(/\r?\n/)
    .map((line) => line.replace(/^\s*(?:[-*•·]|\d+[.、)])\s*/, "").trim())
    .filter((line) => line && !/^[{\[\]}"',:]+$/.test(line));
}

export function parseMemoryReply(raw) {
  let text = String(raw || "").trim();
  text = text.replace(/^\s*```(?:json)?\s*/i, "").replace(/\s*```\s*$/i, "");
  let data = null;
  const objectStart = text.indexOf("{");
  const objectEnd = text.lastIndexOf("}");
  const arrayStart = text.indexOf("[");
  const arrayEnd = text.lastIndexOf("]");
  try {
    if (objectStart >= 0 && objectEnd > objectStart) data = JSON.parse(text.slice(objectStart, objectEnd + 1));
    else if (arrayStart >= 0 && arrayEnd > arrayStart) data = JSON.parse(text.slice(arrayStart, arrayEnd + 1));
  } catch {
    data = null;
  }
  let rows = [];
  if (Array.isArray(data)) rows = data;
  else if (Array.isArray(data?.memories)) rows = data.memories;
  else if (Array.isArray(data?.items)) rows = data.items;
  else rows = parseLooseLines(text);

  const seen = new Set();
  return rows
    .map((row) => (typeof row === "string" ? row : row?.text || row?.memory || ""))
    .map((row) => oneLine(row, 180))
    .filter((row) => {
      if (row.length < 2) return false;
      const key = normalizeForCompare(row);
      if (!key || seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, 6);
}

function normalizeForCompare(value) {
  return String(value || "")
    .toLowerCase()
    .replace(new RegExp(escapeRegExp("　"), "g"), " ")
    .replace(/[\s，。！？、,.!?;；:：'"“”‘’「」『』【】()（）]+/g, "");
}

/** Merge new notes into the existing memory list, de-duplicating near copies. */
export function mergeMemories(existing, candidates, limit = 60) {
  const out = Array.isArray(existing) ? [...existing] : [];
  const keys = out.map((memory) => normalizeForCompare(memory.text));
  let added = 0;
  for (const text of candidates || []) {
    const clean = oneLine(text, 180);
    const key = normalizeForCompare(clean);
    if (clean.length < 2 || !key) continue;
    if (keys.some((old) => old === key || (old.length >= 6 && key.includes(old)) || (key.length >= 6 && old.includes(key)))) {
      continue;
    }
    out.push({ id: uid("mem"), text: clean, createdAt: Date.now(), source: "ai" });
    keys.push(key);
    added += 1;
    if (out.length >= limit) break;
  }
  return { memories: out.slice(-limit), added };
}
