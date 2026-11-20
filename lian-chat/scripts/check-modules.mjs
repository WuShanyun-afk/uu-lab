/* Static module audit for the Lian web app.
 *
 * Catches the "PROVIDERS is not defined" boot crash that unit tests miss:
 *   - a named import that the target module does not export
 *   - an ALL_CAPS / PascalCase constant used but never imported or declared
 * Plus warnings for imports that are never used.
 *
 * Usage:
 *   node scripts/check-modules.mjs          # human report, exit 1 on error
 *   node scripts/check-modules.mjs --json
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const JS_DIR = process.env.AUDIT_DIR
  ? path.resolve(process.env.AUDIT_DIR)
  : path.resolve(HERE, "..", "js");

const GLOBALS = new Set([
  "window", "document", "navigator", "location", "history", "screen", "localStorage",
  "sessionStorage", "indexedDB", "caches", "console", "fetch", "Request", "Response",
  "Headers", "FormData", "Blob", "File", "FileReader", "Image", "Audio", "Worker",
  "ServiceWorker", "ServiceWorkerRegistration", "Notification", "NotificationEvent",
  "PushManager", "URL", "URLSearchParams", "TextEncoder", "TextDecoder", "AbortController",
  "AbortSignal", "CustomEvent", "Event", "EventTarget", "MouseEvent", "KeyboardEvent",
  "PointerEvent", "TouchEvent", "DragEvent", "ClipboardEvent", "InputEvent", "FocusEvent",
  "MutationObserver", "IntersectionObserver", "ResizeObserver", "performance", "crypto",
  "requestAnimationFrame", "cancelAnimationFrame", "setTimeout", "clearTimeout",
  "setInterval", "clearInterval", "queueMicrotask", "structuredClone", "atob", "btoa",
  "matchMedia", "getComputedStyle", "alert", "confirm", "prompt", "open", "close",
  "scrollTo", "scrollBy", "innerWidth", "innerHeight", "devicePixelRatio", "orientation",
  "addEventListener", "removeEventListener", "dispatchEvent", "postMessage", "self", "top",
  "parent", "frames", "frameElement", "origin", "opener", "DOMRect", "Range", "Selection",
  "getSelection", "CSS", "DOMParser", "XMLSerializer", "CanvasRenderingContext2D",
  "OffscreenCanvas", "Path2D", "ImageData", "ImageBitmap", "AudioContext",
  "SpeechSynthesisUtterance", "speechSynthesis", "Option", "Element", "HTMLElement",
  "Node", "NodeList", "Text", "Comment", "DocumentFragment", "HTMLInputElement",
  "HTMLTextAreaElement", "HTMLSelectElement", "HTMLCanvasElement", "HTMLImageElement",
  "HTMLVideoElement", "HTMLAnchorElement", "MediaQueryList", "Storage", "IDBDatabase",
  "IDBKeyRange", "MessageChannel", "Intl", "JSON", "Math", "Number", "String", "Boolean",
  "Array", "Object", "Date", "RegExp", "Map", "Set", "WeakMap", "WeakSet", "Promise",
  "Symbol", "Proxy", "Reflect", "Error", "TypeError", "RangeError", "SyntaxError",
  "ReferenceError", "AggregateError", "parseInt", "parseFloat", "isNaN", "isFinite",
  "encodeURIComponent", "decodeURIComponent", "encodeURI", "decodeURI", "BigInt",
  "ArrayBuffer", "SharedArrayBuffer", "DataView", "Uint8Array", "Uint16Array",
  "Uint32Array", "Int8Array", "Int16Array", "Int32Array", "Float32Array", "Float64Array",
  "Uint8ClampedArray", "globalThis", "NaN", "Infinity", "undefined", "eval", "Function",
  "WebSocket", "EventSource", "BroadcastChannel", "structuredClone", "NodeFilter",
  "requestIdleCallback", "cancelIdleCallback", "visualViewport", "AudioBuffer",
  "MediaStream", "MediaRecorder", "Notification", "Vibration",
]);

const KEYWORDS = new Set([
  "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
  "do", "else", "export", "extends", "finally", "for", "function", "if", "import", "in",
  "instanceof", "let", "new", "return", "super", "switch", "this", "throw", "try", "typeof",
  "var", "void", "while", "with", "yield", "async", "await", "of", "static", "get", "set",
  "true", "false", "null", "arguments", "from", "as",
]);

const REGEX_PREFIX = new Set([
  "(", ",", "=", ":", "[", "!", "&", "|", "?", "{", "}", ";", "+", "-", "*", "%", "^",
  "~", "<", ">", "===", "!==", "==", "=>", "return", "typeof", "case", "delete", "void",
  "throw", "new", "in", "of", "instanceof", "do", "else", "yield", "await",
]);

/* ------------------------------------------------------------------ lexer */

function lex(source) {
  const chars = source.split("");
  const blank = (from, to) => {
    for (let k = from; k < to; k += 1) if (chars[k] !== "\n") chars[k] = " ";
  };
  const tokens = [];
  const stack = [{ kind: "code", depth: 0 }];
  let i = 0;
  let last = "";
  const n = source.length;

  const push = (type, value, start) => {
    tokens.push({ type, value, start });
    last = value;
  };

  while (i < n) {
    const c = source[i];
    const top = stack[stack.length - 1];
    if (c === "\n" || c === " " || c === "\t" || c === "\r") { i += 1; continue; }
    if (top.kind === "tpl") {
      if (c === "\\") { blank(i, i + 2); i += 2; continue; }
      if (c === "`") { blank(i, i + 1); stack.pop(); i += 1; last = "`"; continue; }
      if (c === "$" && source[i + 1] === "{") {
        blank(i, i + 2);
        stack.push({ kind: "code", depth: 1 });
        i += 2;
        last = "{";
        continue;
      }
      blank(i, i + 1);
      i += 1;
      continue;
    }
    if (stack.length > 1) {
      if (c === "{" || c === "}" || c === "(" || c === ")" || c === "[" || c === "]") {
        if (c === "{") top.depth += 1;
        if (c === "}") top.depth -= 1;
        blank(i, i + 1);
        if (top.depth === 0) { stack.pop(); i += 1; last = "}"; continue; }
        push("punct", c, i);
        i += 1;
        continue;
      }
      if (c === "`") { blank(i, i + 1); stack.push({ kind: "tpl" }); i += 1; last = "`"; continue; }
    }
    if (c === "/" && source[i + 1] === "/") {
      const end = source.indexOf("\n", i);
      const stop = end === -1 ? n : end;
      blank(i, stop);
      i = stop;
      continue;
    }
    if (c === "/" && source[i + 1] === "*") {
      const end = source.indexOf("*/", i + 2);
      const stop = end === -1 ? n : end + 2;
      blank(i, stop);
      i = stop;
      continue;
    }
    if (c === "'" || c === '"') {
      let j = i + 1;
      while (j < n && source[j] !== c) {
        if (source[j] === "\\") j += 1;
        if (source[j] === "\n") break;
        j += 1;
      }
      blank(i + 1, Math.min(j, n));
      i = Math.min(j + 1, n);
      last = "str";
      continue;
    }
    if (c === "`") {
      blank(i, i + 1);
      i += 1;
      stack.push({ kind: "tpl" });
      last = "`";
      continue;
    }
    if (c === "/" && REGEX_PREFIX.has(last)) {
      let j = i + 1;
      let inClass = false;
      while (j < n) {
        const ch = source[j];
        if (ch === "\\") { j += 2; continue; }
        if (ch === "[") inClass = true;
        else if (ch === "]") inClass = false;
        else if (ch === "/" && !inClass) break;
        else if (ch === "\n") break;
        j += 1;
      }
      blank(i + 1, Math.min(j, n));
      i = Math.min(j + 1, n);
      while (i < n && /[a-z]/i.test(source[i])) { blank(i, i + 1); i += 1; }
      last = "regex";
      continue;
    }
    if (/[A-Za-z_$]/.test(c)) {
      let j = i + 1;
      while (j < n && /[\w$]/.test(source[j])) j += 1;
      push("id", source.slice(i, j), i);
      i = j;
      continue;
    }
    if (/[0-9]/.test(c)) {
      let j = i + 1;
      while (j < n && /[\w.$]/.test(source[j])) j += 1;
      push("num", source.slice(i, j), i);
      i = j;
      continue;
    }
    // multi-char punctuation we care about
    const three = source.slice(i, i + 3);
    const two = source.slice(i, i + 2);
    const punct = ["===", "!==", ">>>", "**=", "...", "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "?.", "++", "--", "+=", "-=", "*=", "/=", "%=", "**"].find((p) => source.startsWith(p, i));
    if (punct) { push("punct", punct, i); i += punct.length; continue; }
    push("punct", c, i);
    i += 1;
  }
  return { tokens, code: chars.join("") };
}

function lineOf(source, index) {
  let line = 1;
  for (let i = 0; i < index; i += 1) if (source[i] === "\n") line += 1;
  return line;
}

/* ------------------------------------------------------------- analysis */

function collectDeclared(code) {
  const declared = new Set();
  for (const m of code.matchAll(/\b(?:const|let|var|function|class)\s+([A-Za-z_$][\w$]*)/g)) declared.add(m[1]);
  for (const m of code.matchAll(/import\s+([^;]+?)\s+from\s+["'][^"']+["']/g)) {
    for (const part of m[1].replace(/[{}]/g, ",").split(",")) {
      const piece = part.trim();
      if (!piece) continue;
      const star = piece.match(/^\*\s+as\s+([\w$]+)$/);
      if (star) { declared.add(star[1]); continue; }
      const name = piece.split(/\s+as\s+/).pop().trim();
      if (/^[\w$]+$/.test(name)) declared.add(name);
    }
  }
  for (const m of code.matchAll(/export\s*\{([^}]*)\}/g)) {
    for (const part of m[1].split(",")) {
      const name = part.trim().split(/\s+as\s+/)[0].trim();
      if (/^[\w$]+$/.test(name)) declared.add(name);
    }
  }
  for (const m of code.matchAll(/\b(?:const|let|var)\s*[{[]([^}\]\n]*)[}\]]\s*=/g)) {
    for (const part of m[1].split(",")) {
      const piece = part.trim().replace(/^\.\.\./, "");
      if (!piece) continue;
      const name = piece.split(":").pop().split("=")[0].trim();
      if (/^[A-Za-z_$][\w$]*$/.test(name)) declared.add(name);
    }
  }
  for (const m of code.matchAll(/(?:function\s*[\w$]*\s*|\(|,)\s*([A-Za-z_$][\w$]*)\s*[,)=]/g)) {
    if (!KEYWORDS.has(m[1])) declared.add(m[1]);
  }
  for (const m of code.matchAll(/catch\s*\(\s*([\w$]+)/g)) declared.add(m[1]);
  for (const m of code.matchAll(/\bfor\s*\(\s*(?:const|let|var)\s+([\w$]+)/g)) declared.add(m[1]);
  return declared;
}

function exportedNames(source) {
  const names = new Set();
  for (const m of source.matchAll(/export\s+(?:async\s+)?(?:function|class|const|let|var)\s+([A-Za-z_$][\w$]*)/g)) names.add(m[1]);
  for (const m of source.matchAll(/export\s*\{([^}]*)\}/g)) {
    for (const part of m[1].split(",")) {
      const piece = part.trim();
      if (!piece) continue;
      const alias = piece.split(/\s+as\s+/);
      names.add((alias[1] || alias[0]).trim());
    }
  }
  if (/export\s+default/.test(source)) names.add("default");
  return names;
}

if (process.env.AUDIT_FIND) {
  const dbg = fs.readFileSync(path.join(JS_DIR, process.env.AUDIT_FIND), "utf8");
  const { code } = lex(dbg);
  for (const probe of process.env.AUDIT_NAMES.split(",")) {
    const inSource = dbg.split(probe).length - 1;
    const inCode = code.split(probe).length - 1;
    console.log(`${probe}: source=${inSource} code=${inCode}`);
  }
  process.exit(0);
}

if (process.env.AUDIT_CODE) {
  const dbg = fs.readFileSync(path.join(JS_DIR, process.env.AUDIT_CODE), "utf8");
  const { code } = lex(dbg);
  const lines = dbg.split("\n");
  const start = Number(process.env.AUDIT_FROM || 1);
  const end = Number(process.env.AUDIT_TO || lines.length);
  for (let i = start; i <= end; i += 1) console.log(String(i).padStart(4), JSON.stringify(code.split("\n")[i - 1]));
  process.exit(0);
}

const files = fs.readdirSync(JS_DIR).filter((f) => f.endsWith(".js")).sort();
const sources = new Map(files.map((f) => [f, fs.readFileSync(path.join(JS_DIR, f), "utf8")]));
const exportsByFile = new Map([...sources].map(([f, s]) => [f, exportedNames(s)]));

const errors = [];
const warnings = [];

for (const [file, source] of sources) {
  const { tokens, code } = lex(source);
  const declared = collectDeclared(code);

  // 1. named imports must exist in the target module
  for (const m of source.matchAll(/import\s*\{([^}]*)\}\s*from\s*["'](\.\/[^"']+)["']/g)) {
    const target = m[2].replace(/^\.\//, "");
    const known = exportsByFile.get(target);
    if (!known) continue;
    for (const part of m[1].split(",")) {
      const piece = part.trim();
      if (!piece) continue;
      const name = piece.split(/\s+as\s+/)[0].trim();
      if (!known.has(name)) {
        errors.push(`${file}:${lineOf(source, m.index)} imports { ${name} } from ${target}, but it is not exported there`);
      }
    }
  }

  // 2. ALL_CAPS / PascalCase-with-digit constants that are used but never declared
  for (let k = 0; k < tokens.length; k += 1) {
    const tok = tokens[k];
    if (tok.type !== "id") continue;
    const name = tok.value;
    if (!/^([A-Z][A-Z0-9_]{2,}|[A-Z][a-zA-Z0-9]*[0-9][a-zA-Z0-9]*)$/.test(name)) continue;
    if (declared.has(name) || GLOBALS.has(name) || KEYWORDS.has(name)) continue;
    const prev = tokens[k - 1];
    if (prev && prev.type === "punct" && (prev.value === "." || prev.value === "?.")) continue;
    const next = tokens[k + 1];
    if (next && next.type === "punct" && next.value === ":") continue; // object key
    if (prev && prev.type === "punct" && (prev.value === "." || prev.value === "?.")) continue;
    errors.push(`${file}:${lineOf(source, tok.start)} uses "${name}" but never imports or declares it`);
  }

  // 3. named imports that are never used (dead import)
  for (const m of code.matchAll(/import\s*\{([^}]*)\}\s*from\s*["'][^"']+["']/g)) {
    const body = code.slice(0, m.index) + code.slice(m.index + m[0].length);
    for (const part of m[1].split(",")) {
      const piece = part.trim();
      if (!piece) continue;
      const name = piece.split(/\s+as\s+/).pop().trim();
      const escaped = name.replace(/\$/g, "\\$");
      // a bare reference, or a spread (`...name`): the lookbehind below skips
      // member access, so spreads need their own test.
      const used =
        new RegExp(`(?<![.\\w$])${escaped}(?![\\w$])`).test(body) ||
        new RegExp(`\\.\\.\\.\\s*${escaped}(?![\\w$])`).test(body);
      if (!used) {
        warnings.push(`${file}:${lineOf(code, m.index)} imports { ${name} } but never uses it`);
      }
    }
  }
}

if (process.argv.includes("--json")) {
  console.log(JSON.stringify({ errors: [...new Set(errors)], warnings: [...new Set(warnings)] }, null, 2));
} else {
  for (const w of [...new Set(warnings)]) console.log(`warn  ${w}`);
  for (const e of [...new Set(errors)]) console.log(`ERROR ${e}`);
  console.log(`\n${files.length} modules scanned, ${[...new Set(errors)].length} error(s), ${[...new Set(warnings)].length} warning(s)`);
}
if ([...new Set(errors)].length) process.exit(1);
