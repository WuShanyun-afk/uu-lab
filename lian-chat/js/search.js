/* =========================================================
   search — 纯函数，负责把「查到哪」和「怎么高亮」算清楚
   ========================================================= */

export function normaliseQuery(value) {
  return String(value || "").trim().toLowerCase();
}

/** Split text into [{ text, hit }] so the caller can escape and wrap <mark>. */
export function splitByMatches(text, query) {
  const source = String(text || "");
  const needle = normaliseQuery(query);
  if (!source || !needle) return [{ text: source, hit: false }];
  const lower = source.toLowerCase();
  const out = [];
  let cursor = 0;
  for (;;) {
    const at = lower.indexOf(needle, cursor);
    if (at < 0) break;
    if (at > cursor) out.push({ text: source.slice(cursor, at), hit: false });
    out.push({ text: source.slice(at, at + needle.length), hit: true });
    cursor = at + needle.length;
  }
  if (!out.length) return [{ text: source, hit: false }];
  if (cursor < source.length) out.push({ text: source.slice(cursor), hit: false });
  return out;
}

export function countMatches(text, query) {
  return splitByMatches(text, query).filter((part) => part.hit).length;
}

/** The text a chat is searchable by: name, relationship, last message and a
    window of recent message text (so old topics are still findable). */
export function chatHaystack(chat, lastText = "", messages = []) {
  const recent = (messages || [])
    .slice(-200)
    .map((message) => messageHaystack(message))
    .filter(Boolean)
    .join(" ");
  return [chat?.name, chat?.relationship, lastText, recent].filter(Boolean).join(" · ");
}

/** The text a message is searchable by, including report titles. */
export function messageHaystack(message) {
  if (!message) return "";
  const bits = [message.text];
  if (message.kind === "report") {
    bits.push(message.report?.title, message.report?.summary);
    for (const block of message.report?.blocks || []) bits.push(block?.text);
  }
  if (message.file?.name) bits.push(message.file.name);
  return bits.filter(Boolean).join(" ");
}

/**
 * A short excerpt around the newest match, so a list row can explain why it
 * matched even when the match is not in the last message.
 */
export function matchSnippet(messages, query, max = 46) {
  const needle = normaliseQuery(query);
  if (!needle) return "";
  const list = messages || [];
  for (let index = list.length - 1; index >= 0; index -= 1) {
    const text = messageHaystack(list[index] || {});
    const at = text.toLowerCase().indexOf(needle);
    if (at < 0) continue;
    const start = Math.max(0, at - Math.floor((max - needle.length) / 2));
    const end = Math.min(text.length, start + max);
    const prefix = start > 0 ? "…" : "";
    const suffix = end < text.length ? "…" : "";
    return `${prefix}${text.slice(start, end)}${suffix}`;
  }
  return "";
}

/**
 * Message indexes matching the query, oldest first.
 * @param {Array<object>} messages
 * @param {string} query
 * @returns {number[]}
 */
export function matchMessageIndexes(messages, query) {
  const needle = normaliseQuery(query);
  if (!needle) return [];
  const out = [];
  (messages || []).forEach((message, index) => {
    if (!message || message.kind === "sticker") return;
    if (messageHaystack(message).toLowerCase().includes(needle)) out.push(index);
  });
  return out;
}
