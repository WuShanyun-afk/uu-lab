/* =========================================================
   M3 · palette — 气泡配色的对比度推导
   ---------------------------------------------------------
   品牌绿 #06C755 配白字只有 2.27:1，远低于 WCAG AA 的 4.5:1。
   这里不改品牌色本身（按钮、选中态继续用 --accent），只推导
   一个「压深到可读」的气泡底色，并把结果写进
   --bubble-mine / --bubble-mine-ink。
   纯函数、无 DOM 依赖，方便单元测试。
   ========================================================= */

const WHITE = "#ffffff";
const BLACK = "#000000";
const MIN_RATIO = 4.5;

export function parseHex(value) {
  const text = String(value || "").trim().replace("#", "");
  if (!/^[0-9a-f]{6}$/i.test(text)) return null;
  return {
    r: parseInt(text.slice(0, 2), 16),
    g: parseInt(text.slice(2, 4), 16),
    b: parseInt(text.slice(4, 6), 16),
  };
}

export function toHex({ r, g, b }) {
  const part = (n) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, "0");
  return `#${part(r)}${part(g)}${part(b)}`;
}

export function relativeLuminance(value) {
  const rgb = parseHex(value);
  if (!rgb) return 0;
  const channel = (n) => {
    const c = n / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(rgb.r) + 0.7152 * channel(rgb.g) + 0.0722 * channel(rgb.b);
}

export function contrastRatio(a, b) {
  if (!parseHex(a) || !parseHex(b)) return 0;
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  const light = Math.max(la, lb);
  const dark = Math.min(la, lb);
  return Math.round(((light + 0.05) / (dark + 0.05)) * 100) / 100;
}

export function mixHex(from, to, ratio) {
  const a = parseHex(from);
  const b = parseHex(to);
  if (!a || !b) return String(from || "").trim() || WHITE;
  const t = Math.max(0, Math.min(1, Number(ratio) || 0));
  return toHex({ r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t });
}

/**
 * Accept what people actually type into a 色号 field: `#06c755`, `06C755`,
 * `#0a0`, with stray spaces — and return `#RRGGBB` uppercase, or "" if invalid.
 */
export function normaliseAccent(value) {
  const text = String(value || "").trim().replace(/^#+/, "").replace(/\s+/g, "");
  if (/^[0-9a-f]{3}$/i.test(text)) {
    return `#${text
      .split("")
      .map((char) => char + char)
      .join("")
      .toUpperCase()}`;
  }
  if (/^[0-9a-f]{6}$/i.test(text)) return `#${text.toUpperCase()}`;
  return "";
}

/**
 * Pick a readable bubble background for a given accent.
 * White ink is preferred (that is what the app ships), and the background is
 * darkened toward black only as much as needed to reach the target ratio.
 * @param {string} accent
 * @param {{ min?: number, maxMix?: number, step?: number }} [options]
 * @returns {{ bg: string, ink: string, ratio: number, changed: boolean }}
 */
export function mineBubble(accent, options = {}) {
  const min = Number(options.min) || MIN_RATIO;
  const maxMix = Number(options.maxMix) || 0.55;
  const step = Number(options.step) || 0.02;
  const base = parseHex(accent) ? String(accent).trim() : "#06C755";
  const ink = "#ffffff";
  if (contrastRatio(base, ink) >= min) {
    return { bg: base, ink, ratio: contrastRatio(base, ink), changed: false };
  }
  for (let mix = step; mix <= maxMix + 1e-9; mix += step) {
    const bg = mixHex(base, BLACK, mix);
    const ratio = contrastRatio(bg, ink);
    if (ratio >= min) return { bg, ink, ratio, changed: true };
  }
  const bg = mixHex(base, BLACK, maxMix);
  return { bg, ink, ratio: contrastRatio(bg, ink), changed: true };
}

/** Same helper for dark surfaces (text on near-black). */
export function readableInk(background, { dark = "#141310", light = "#ffffff", min = MIN_RATIO } = {}) {
  const bg = String(background || "");
  if (!parseHex(bg)) return light;
  return contrastRatio(bg, dark) >= contrastRatio(bg, light) ? dark : light;
}

/**
 * A darkened variant of the accent that is safe as *text* on white/paper.
 * Used for the active tab label, links and small labels; decorative fills keep
 * the original brand colour.
 */
export function accentStrong(accent, { min = MIN_RATIO, maxMix = 0.6, step = 0.02 } = {}) {
  const base = parseHex(accent) ? String(accent).trim() : "#06C755";
  if (contrastRatio(base, WHITE) >= min) return base;
  for (let mix = step; mix <= maxMix + 1e-9; mix += step) {
    const candidate = mixHex(base, BLACK, mix);
    if (contrastRatio(candidate, WHITE) >= min) return candidate;
  }
  return mixHex(base, BLACK, maxMix);
}
