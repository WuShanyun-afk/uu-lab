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
/* A reply that ran into the token limit stops mid-markup: no closing ``` ever
   arrives. Those still have to be taken out of the text, or the bubble shows
   raw <svg> source. */
const OPEN_FENCE = /```[ \t]*(svg|html)[ \t]*\r?\n([\s\S]*)$/i;

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

/** Cut everything after the last `</svg>`: models like to add a note in the fence. */
function svgTail(markup) {
  const text = String(markup || "");
  const closes = [...text.matchAll(/<\/svg\s*>/gi)];
  if (!closes.length) return text;
  const last = closes[closes.length - 1];
  return text.slice(0, last.index + last[0].length);
}

/* `<svg` + a real attribute: a picture, not a passing mention of the tag. */
const LOOSE_SVG_START = /<svg\b[^>]*\s(?:viewBox|xmlns|width|height)\s*=/i;

/**
 * Find a bare (unfenced) svg in the text. `closed` is false when the reply was
 * cut off before `</svg>`, in which case everything from the tag to the end
 * belongs to the failed drawing.
 */
function looseSvgSpan(text) {
  const source = String(text || "");
  const match = LOOSE_SVG_START.exec(source);
  if (!match) return null;
  const start = match.index;
  const rest = source.slice(start);
  const close = /<\/svg\s*>/i.exec(rest);
  if (!close) return { start, end: source.length, body: rest, closed: false };
  const end = start + close.index + close[0].length;
  return { start, end, body: source.slice(start, end), closed: true };
}

export function isSvgDrawing(body) {
  const text = svgTail(svgStart(body));
  if (!SVG_HINT.test(text)) return false;
  if (!/<\/svg\s*>$/i.test(text)) return false;
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
    return { type: "svg", markup: svgTail(svgStart(body)) };
  }
  if (!isHtmlDrawing(body)) return null;
  return { type: "html", markup: stripActiveHtml(body).trim() };
}

/**
 * Pull drawings out of a model reply.
 *
 * Two shapes arrive in practice: a ```` ```svg ```` fence, and — more often on
 * small models — the bare `<svg …</svg>` with no fence at all. Both have to be
 * taken out, because whatever is left in the text becomes chat bubbles and the
 * raw markup is unreadable there. The fence is the only thing that ever reaches
 * the text when a reply is *not* a drawing (a `js` fence stays as code).
 */
export function extractDrawings(raw, { limit = DRAWING_LIMITS.maxPerReply } = {}) {
  const drawings = [];
  let broken = 0;
  let text = String(raw || "");
  text = text.replace(FENCE, (match, lang, body) => {
    const made = drawings.length >= limit ? null : makeDrawing(String(lang || "").toLowerCase(), body);
    if (made) {
      drawings.push(made);
      return "\n";
    }
    broken += 1;
    return "\n";
  });
  text = text.replace(OPEN_FENCE, () => {
    broken += 1;
    return "\n";
  });
  /* Bare svg: only trust it when the opening tag carries a real attribute, so a
     passing mention of "<svg>" in prose is not mistaken for a picture. */
  for (let guard = 0; guard < 4; guard += 1) {
    const loose = looseSvgSpan(text);
    if (!loose) break;
    const made = drawings.length >= limit ? null : makeDrawing("svg", loose.body);
    if (made) drawings.push(made);
    else broken += 1;
    text = `${text.slice(0, loose.start)}\n${text.slice(loose.end)}`;
  }
  text = text.replace(/\n{3,}/g, "\n\n").trim();
  return { text, drawings, broken };
}

export function drawingLabel(drawing) {
  if (!drawing) return "";
  return drawing.type === "html" ? "HTML" : "SVG";
}

/**
 * Last line of defence for text that is about to be printed: remove any svg
 * source, complete or cut off. Stored history from older versions and anything
 * that slipped past extraction go through here.
 */
export function stripSvgSource(text) {
  return String(text || "")
    .replace(/<svg\b[\s\S]*?<\/svg\s*>/gi, "\n")
    .replace(/<svg\b[\s\S]*$/i, "")
    .replace(/```[ \t]*(?:svg|html)[ \t]*\n[\s\S]*?(?:```|$)/gi, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/**
 * Older versions stored a drawing reply as plain text (fences and all), so the
 * chat history still holds bubbles full of `<svg …>`. Rewrite those stored
 * messages once: keep the words, put the picture next to them, and if the
 * markup never completed, drop the source and leave the note.
 *
 * Pure and idempotent: a message that is not text, or that does not contain
 * svg markup, is returned untouched.
 */
export function adoptStoredDrawings(messages, { note = "", roles = null } = {}) {
  if (!Array.isArray(messages)) return { changed: false, messages };
  const allowed = Array.isArray(roles) && roles.length ? new Set(roles) : null;
  let changed = false;
  const out = [];
  for (const message of messages) {
    if (!message || message.kind !== "text" || typeof message.text !== "string" || !/<svg\b/i.test(message.text)) {
      out.push(message);
      continue;
    }
    /* 用户自己贴的源码不是「模型画的画」：默认只修旧版本里 AI 的画。 */
    if (allowed && !allowed.has(message.role)) {
      out.push(message);
      continue;
    }
    const { text, drawings } = extractDrawings(message.text);
    if (!drawings.length && text === message.text) {
      out.push(message);
      continue;
    }
    changed = true;
    const words = text.trim();
    const drawing = drawings[0] ? { ...drawings[0], createdAt: message.ts || Date.now() } : null;
    if (!drawing) {
      out.push({ ...message, text: words || note || "" });
      continue;
    }
    if (words) out.push({ ...message, text: words });
    out.push({
      ...message,
      id: words ? `${message.id}_art` : message.id,
      kind: "drawing",
      text: "",
      drawing,
    });
  }
  return { changed, messages: out };
}

/** Rough byte size, used by the settings hint and by the state-size guard. */
export function drawingBytes(drawing) {
  return new Blob([String(drawing?.markup || "")]).size;
}
