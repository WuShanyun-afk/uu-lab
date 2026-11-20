/* AI 现场画画面
 *
 * 模型在回复里用 ```svg 或 ```html 代码块画一张图。这里负责把它从文字里摘出来、
 * 卡住尺寸，并把它变成能安全嵌进聊天里的东西：
 *
 *   SVG  -> data: URI，放进 <img>。SVG 在 <img> 里不执行脚本、不加载外链，
 *           样式也被隔离，不会污染整页。
 *   HTML -> 一整篇文档，放进 <iframe sandbox="">（不给任何权限）+ 严格 CSP。
 *           所以动效只能用 CSS，JS 不执行，也不能碰到 App 的 DOM。
 *
 * 纯字符串处理，不依赖 DOM / DOMParser，Node 里可以直接单测。
 */

export const DRAWING_LIMITS = {
  maxPerReply: 1,
  maxSvgChars: 18000,
  maxHtmlChars: 18000,
};

const FENCE = /```[ \t]*(svg|html)[ \t]*\r?\n([\s\S]*?)```/gi;

const HTML_HINT = /<(html|body|style|div|section|main|svg|p|span|h1|h2|h3)\b/i;
const SVG_HINT = /^<svg\b/i;

/** Strip the XML prolog / doctype / leading comments so `<svg` can be detected. */
function svgStart(body) {
  return String(body || "")
    .replace(/^\uFEFF/, "")
    .replace(/<\?xml[\s\S]*?\?>/gi, "")
    .replace(/<!doctype[\s\S]*?>/gi, "")
    .replace(/<!--[\s\S]*?-->/g, "")
    .trim();
}

export function isSvgDrawing(body) {
  const text = svgStart(body);
  if (!SVG_HINT.test(text)) return false;
  if (!/<\/svg\s*>\s*$/i.test(text)) return false;
  return text.length <= DRAWING_LIMITS.maxSvgChars;
}

export function isHtmlDrawing(body) {
  const text = String(body || "").trim();
  if (!text) return false;
  if (!HTML_HINT.test(text)) return false;
  return text.length <= DRAWING_LIMITS.maxHtmlChars;
}

/** Everything the model sends as active HTML, removed before it reaches the frame. */
export function stripActiveHtml(fragment) {
  return String(fragment || "")
    .replace(/<script\b[\s\S]*?<\/script\s*>/gi, "")
    .replace(/<script\b[^>]*\/?>/gi, "")
    .replace(/<(iframe|object|embed)\b[\s\S]*?<\/\1\s*>/gi, "")
    .replace(/<(iframe|object|embed|link|meta|base)\b[^>]*\/?>/gi, "")
    .replace(/\son[a-z]+\s*=\s*"[^"]*"/gi, "")
    .replace(/\son[a-z]+\s*=\s*'[^']*'/gi, "")
    .replace(/\son[a-z]+\s*=\s*[^\s>]+/gi, "")
    .replace(/javascript:/gi, "");
}

const HTML_BASE_CSS = `
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; }
  body {
    display: grid;
    place-items: center;
    background: #fbfaf6;
    color: #23221f;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
    font-size: 14px;
    line-height: 1.5;
    overflow: hidden;
  }
`;

/** Wrap the model's fragment in a locked-down document for a sandboxed iframe. */
export function buildHtmlDocument(fragment) {
  const safe = stripActiveHtml(fragment).trim();
  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; script-src 'none'; base-uri 'none'; form-action 'none'">
<title>picture</title>
<style>${HTML_BASE_CSS}</style>
</head>
<body>${safe}</body>
</html>`;
}

/** An SVG with a viewBox but no width/height renders at 300×150, which would
 * squash a square drawing inside the bubble. Stamp the viewBox size on it. */
export function ensureSvgSize(markup) {
  const text = String(markup || "");
  const box = text.match(/viewBox\s*=\s*["']\s*[-\d.]+[\s,]+[-\d.]+[\s,]+([-\d.]+)[\s,]+([-\d.]+)\s*["']/i);
  if (!box) return text;
  const width = Number(box[1]);
  const height = Number(box[2]);
  if (!(width > 0 && height > 0)) return text;
  return text.replace(/<svg\b([^>]*)>/i, (tag, attrs) => {
    let next = attrs;
    if (!/\bwidth\s*=/i.test(next)) next += ` width="${width}"`;
    if (!/\bheight\s*=/i.test(next)) next += ` height="${height}"`;
    return `<svg${next}>`;
  });
}

export function buildSvgDataUri(svg) {
  const text = ensureSvgSize(svgStart(svg));
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(text)}`;
}

function makeDrawing(type, body) {
  if (type === "svg") {
    if (!isSvgDrawing(body)) return null;
    return { type: "svg", markup: svgStart(body) };
  }
  if (!isHtmlDrawing(body)) return null;
  return { type: "html", markup: stripActiveHtml(body).trim() };
}

/**
 * Pull drawing fences out of a model reply.
 * Anything that does not look like a drawing is left in the text untouched,
 * so "write me an SVG snippet" still shows the code instead of eating it.
 */
export function extractDrawings(raw, { limit = DRAWING_LIMITS.maxPerReply } = {}) {
  const drawings = [];
  let text = String(raw || "");
  text = text.replace(FENCE, (match, lang, body) => {
    if (drawings.length >= limit) return match;
    const made = makeDrawing(String(lang || "").toLowerCase(), body);
    if (!made) return match;
    drawings.push(made);
    return "\n";
  });
  text = text.replace(/\n{3,}/g, "\n\n").trim();
  return { text, drawings };
}

export function drawingLabel(drawing) {
  if (!drawing) return "";
  return drawing.type === "html" ? "HTML" : "SVG";
}

/** Rough byte size, used by the settings hint and by the state-size guard. */
export function drawingBytes(drawing) {
  return new Blob([String(drawing?.markup || "")]).size;
}
