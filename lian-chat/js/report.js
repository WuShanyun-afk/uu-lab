import { escapeHtml } from "./utils.js";
import { isScene, sceneSvg } from "./scenes.js";

const MAX_BLOCKS = 5;
const MAX_BLOCK_CHARS = 220;

const ALLOWED_TAGS = new Set([
  "SECTION",
  "DIV",
  "HEADER",
  "H1",
  "H2",
  "H3",
  "H4",
  "P",
  "UL",
  "OL",
  "LI",
  "STRONG",
  "B",
  "EM",
  "I",
  "SPAN",
  "SMALL",
  "BLOCKQUOTE",
  "HR",
  "BR",
]);

const DROP_TAGS = new Set(["SCRIPT", "STYLE", "IFRAME", "OBJECT", "EMBED", "LINK", "META", "SVG", "FORM", "INPUT", "TEXTAREA", "SELECT", "BUTTON"]);

export function sanitizeReportHtml(fragment) {
  const parser = new DOMParser();
  const doc = parser.parseFromString(`<div id="report-root">${String(fragment || "")}</div>`, "text/html");
  const root = doc.getElementById("report-root");
  if (!root) return "";

  const walk = (node) => {
    for (const child of [...node.childNodes]) {
      if (child.nodeType === Node.COMMENT_NODE) {
        child.remove();
        continue;
      }
      if (child.nodeType !== Node.ELEMENT_NODE) continue;
      if (DROP_TAGS.has(child.tagName)) {
        child.remove();
        continue;
      }
      if (!ALLOWED_TAGS.has(child.tagName)) {
        // Unknown wrappers such as <article> are unwrapped, preserving their text.
        const parent = child.parentNode;
        while (child.firstChild) parent.insertBefore(child.firstChild, child);
        child.remove();
        continue;
      }
      for (const attr of [...child.attributes]) child.removeAttribute(attr.name);
      walk(child);
    }
  };
  walk(root);
  return root.innerHTML.trim();
}

export function reportDocument({ title, html, aiName = "Lian", accent = "#06C755", createdAt = Date.now() }) {
  const safeTitle = escapeHtml(title || "今天的报备");
  const safeName = escapeHtml(aiName || "Lian");
  const time = new Date(createdAt).toLocaleString("zh-CN", {
    month: "long",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  const safeAccent = /^#[0-9a-f]{6}$/i.test(accent) ? accent : "#06C755";
  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'">
<title>${safeTitle}</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  html, body { margin: 0; }
  body {
    min-height: 100vh;
    padding: 28px 24px 30px;
    background: #f5f4ef;
    color: #20201d;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
    font-size: 15px;
    line-height: 1.78;
  }
  .sheet {
    max-width: 560px;
    margin: 0 auto;
    background: #fffefa;
    border: 1px solid #e8e5dc;
    border-radius: 20px;
    padding: 30px 27px 26px;
    box-shadow: 0 20px 50px rgba(35, 33, 28, .07);
  }
  .kicker {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 17px;
    color: #8c8a82;
    font-size: 11px;
    letter-spacing: .14em;
    text-transform: uppercase;
  }
  .kicker::before { content: ""; width: 20px; height: 1px; background: ${safeAccent}; }
  h1, h2 { margin: 0 0 18px; font-family: Georgia, "Songti SC", serif; font-weight: 600; letter-spacing: -.01em; }
  h1 { font-size: 30px; line-height: 1.25; }
  h2 { font-size: 23px; line-height: 1.35; }
  h3 { margin: 24px 0 8px; font-size: 15px; letter-spacing: .02em; }
  p { margin: 0 0 13px; }
  ul, ol { margin: 4px 0 16px; padding-left: 1.2em; }
  li { margin: 3px 0; }
  blockquote {
    margin: 20px 0;
    padding: 15px 17px;
    background: #f7f4eb;
    border-left: 2px solid ${safeAccent};
    border-radius: 0 10px 10px 0;
    color: #4d4b44;
    font-size: 14px;
  }
  hr { margin: 24px 0; border: 0; border-top: 1px solid #ebe7dc; }
  small { display: block; margin-top: 24px; color: #96938a; font-size: 11.5px; line-height: 1.7; }
  strong { font-weight: 650; }
  em { font-style: normal; color: #6b6960; }
  .meta {
    display: flex;
    justify-content: space-between;
    gap: 14px;
    margin-top: 26px;
    padding-top: 14px;
    border-top: 1px solid #efebe2;
    color: #99968c;
    font-size: 11px;
    letter-spacing: .04em;
  }
  @media (max-width: 420px) {
    body { padding: 14px 12px 18px; }
    .sheet { padding: 24px 20px 20px; border-radius: 17px; }
    h1 { font-size: 26px; }
    h2 { font-size: 21px; }
  }
</style>
</head>
<body>
  <main class="sheet">
    <div class="kicker">${safeName} · daily note</div>
    ${html || `<h1>${safeTitle}</h1><p>今天也有一点小事，想慢慢讲给你听。</p>`}
    <div class="meta"><span>只属于你们的日常</span><span>${escapeHtml(time)}</span></div>
  </main>
</body>
</html>`;
}

export function buildReportFromRaw(raw, state) {
  let parsed;
  try {
    parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
  } catch {
    throw new Error("invalid JSON");
  }
  if (!parsed || typeof parsed !== "object") throw new Error("invalid JSON");
  const title = String(parsed.title || "").trim().slice(0, 60) || "今天的报备";
  const summary = String(parsed.summary || "").trim().slice(0, 160);
  const blocks = normaliseBlocks(parsed.blocks);
  if (blocks.length >= 2) return { title, summary, blocks, html: "" };
  /* A failed parse used to hand the raw JSON to sanitizeReportHtml, which keeps
     text as text — so the viewer showed `{"title":"…"` verbatim. JSON is never
     report content, and it is checked before the DOM sanitiser runs. */
  const rawHtml = String(parsed.html || "").trim();
  const safeHtml = rawHtml && !looksLikeJson(rawHtml) ? sanitizeReportHtml(rawHtml) : "";
  if (blocks.length === 1 && !safeHtml) return { title, summary, blocks, html: "" };
  if (safeHtml) return { title, summary, blocks: [], html: safeHtml };
  const salvaged = salvageReport(rawHtml || summary || "");
  return {
    title: title || salvaged.title,
    summary: summary || salvaged.summary,
    blocks: salvaged.blocks,
    html: "",
  };
}

const JSON_LOOK = /^\s*[\{\[]/;

export function looksLikeJson(text) {
  return JSON_LOOK.test(String(text || ""));
}

function unescapeJsonText(text) {
  try {
    return JSON.parse(`"${text}"`);
  } catch {
    return String(text).replace(/\\(["\\/nrt])/g, (match, code) =>
      ({ '"': '"', "\\": "\\", "/": "/", n: "\n", r: "\r", t: "\t" })[code] || match,
    );
  }
}

function readJsonString(raw, key) {
  const closed = new RegExp(`"${key}"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"`, "i").exec(raw);
  if (closed) return unescapeJsonText(closed[1]);
  /* a value cut off by max_tokens has no closing quote */
  const open = new RegExp(`"${key}"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)$`, "i").exec(raw);
  return open ? unescapeJsonText(open[1]) : "";
}

/**
 * Last resort when the model's JSON never becomes valid (cut off mid-string,
 * wrapped in prose, wrong shape). Pull out whatever fields are readable and
 * never let the raw source reach the viewer.
 */
export function salvageReport(raw) {
  const content = String(raw || "")
    .replace(/^[ \t]*```[a-z]*[ \t]*$/gim, "")
    .trim();
  const title = readJsonString(content, "title").trim().slice(0, 60);
  const summary = readJsonString(content, "summary").trim().slice(0, 160);
  const blockTexts = [...content.matchAll(/"text"\s*:\s*"((?:[^"\\]|\\.)*)"/gi)]
    .map((match) => unescapeJsonText(match[1]).replace(/<[^>]*>/g, "").trim())
    .filter(Boolean);
  /* the last block may be cut off mid-sentence, so it has no closing quote */
  const cutBlock = /"text"\s*:\s*"((?:[^"\\]|\\.)*)$/i.exec(content);
  if (cutBlock) {
    const text = unescapeJsonText(cutBlock[1]).replace(/<[^>]*>/g, "").trim();
    if (text) blockTexts.push(text);
  }
  if (blockTexts.length) {
    return {
      title,
      summary,
      blocks: blockTexts.slice(0, MAX_BLOCKS).map((text) => ({ text: text.slice(0, MAX_BLOCK_CHARS), scene: "" })),
    };
  }
  if (title || summary) return { title, summary, blocks: [] };
  if (looksLikeJson(content)) return { title: "", summary: "", blocks: [] };
  const paragraphs = content
    .split(/\n{2,}/)
    .map((part) => part.replace(/\s+/g, " ").trim())
    .filter(Boolean)
    .slice(0, MAX_BLOCKS);
  return { title: "", summary: "", blocks: paragraphs.map((text) => ({ text: text.slice(0, MAX_BLOCK_CHARS), scene: "" })) };
}

/**
 * Keep only plain text plus a whitelisted scene id. The model never supplies
 * markup for the new report format, so this is the only shape we accept.
 */
export function normaliseBlocks(raw) {
  if (!Array.isArray(raw)) return [];
  const blocks = [];
  for (const item of raw) {
    if (!item) continue;
    const text = String(typeof item === "string" ? item : item.text || item.p || "")
      .replace(/<[^>]*>/g, "")
      .trim()
      .slice(0, MAX_BLOCK_CHARS);
    if (!text) continue;
    const scene = typeof item === "object" && isScene(item.scene) ? item.scene : "";
    blocks.push({ text, scene });
    if (blocks.length >= MAX_BLOCKS) break;
  }
  return blocks;
}

export function reportBlocksHtml(blocks) {
  if (!Array.isArray(blocks) || !blocks.length) return "";
  return blocks
    .map((block) => {
      const art = block.scene ? sceneSvg(block.scene) : "";
      return `<div class="report-block${art ? "" : " is-text"}">
      ${art ? `<div class="report-scene" aria-hidden="true">${art}</div>` : ""}
      <p>${escapeHtml(block.text)}</p>
    </div>`;
    })
    .join("");
}
