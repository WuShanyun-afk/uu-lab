export function uid(prefix = "m") {
  return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function escapeHtml(value = "") {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function formatBytes(bytes = 0) {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 KB";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(bytes < 10 * 1024 ? 1 : 0)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

export function dataUrlBytes(dataUrl = "") {
  const comma = dataUrl.indexOf(",");
  if (comma < 0) return 0;
  const body = dataUrl.slice(comma + 1);
  return Math.floor((body.length * 3) / 4) - (body.endsWith("==") ? 2 : body.endsWith("=") ? 1 : 0);
}

export function fileToDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = () => reject(reader.error || new Error("read failed"));
    reader.readAsDataURL(file);
  });
}

export async function compressImage(file, { max = 1440, quality = 0.82, square = false } = {}) {
  const dataUrl = await fileToDataUrl(file);
  const img = await loadImage(dataUrl);
  const srcW = img.naturalWidth || img.width;
  const srcH = img.naturalHeight || img.height;
  let targetW = srcW;
  let targetH = srcH;
  if (square) {
    targetW = Math.min(max, srcW, srcH);
    targetH = targetW;
  } else if (srcW > max || srcH > max) {
    const ratio = Math.min(max / srcW, max / srcH);
    targetW = Math.round(srcW * ratio);
    targetH = Math.round(srcH * ratio);
  }
  const canvas = document.createElement("canvas");
  canvas.width = targetW;
  canvas.height = targetH;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, targetW, targetH);
  if (square) {
    const side = Math.min(srcW, srcH);
    const sx = (srcW - side) / 2;
    const sy = (srcH - side) / 2;
    ctx.drawImage(img, sx, sy, side, side, 0, 0, targetW, targetH);
  } else {
    ctx.drawImage(img, 0, 0, targetW, targetH);
  }
  const out = canvas.toDataURL("image/jpeg", quality);
  return { dataUrl: out, width: targetW, height: targetH };
}

export function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error("image load failed"));
    img.src = src;
  });
}

export function formatTime(ts) {
  const d = new Date(ts);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

export function isSameDay(a, b) {
  const da = new Date(a);
  const db = new Date(b);
  return da.getFullYear() === db.getFullYear() && da.getMonth() === db.getMonth() && da.getDate() === db.getDate();
}

export function dateLabel(ts, labels) {
  const now = new Date();
  const date = new Date(ts);
  if (isSameDay(now, date)) return labels.today;
  const y = new Date(now);
  y.setDate(y.getDate() - 1);
  if (isSameDay(y, date)) return labels.yesterday;
  if (now.getFullYear() === date.getFullYear()) {
    return `${date.getMonth() + 1}/${date.getDate()} ${labels.weekday || ""}`.trim();
  }
  return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
}

const EMOJI_ONLY_RE = /^(?:\p{Extended_Pictographic}|\p{Regional_Indicator}|\uFE0F|\u200D|\p{Emoji_Modifier}|\s)+$/u;
const HAS_EMOJI_RE = /\p{Extended_Pictographic}/u;

export function isEmojiOnly(text = "") {
  const trimmed = text.trim();
  return Boolean(trimmed) && EMOJI_ONLY_RE.test(trimmed) && HAS_EMOJI_RE.test(trimmed) && [...trimmed].length <= 16;
}

export function hasEmoji(text = "") {
  return HAS_EMOJI_RE.test(String(text));
}

export function escapeRegExp(value = "") {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function renderRichText(text = "") {
  const escaped = escapeHtml(text).replace(/\r\n?/g, "\n");
  const linked = escaped.replace(/(https?:\/\/[^\s<]+[^\s<.,:;!?，。！？；：])/g, (url) => {
    const safe = url.replaceAll("&amp;", "&");
    return `<a href="${safe}" target="_blank" rel="noopener noreferrer">${url}</a>`;
  });
  return linked.replaceAll("\n", "<br>");
}

export function downloadBlob(filename, content, type = "application/json") {
  const blob = content instanceof Blob ? content : new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}

export function isImageDataUrl(value = "") {
  return /^data:image\/(?:png|jpe?g|webp|gif|svg\+xml);base64,[a-z0-9+/=\s]+$/i.test(String(value || "").slice(0, 2_000_000));
}

export function isRasterDataUrl(value = "") {
  return /^data:image\/(?:png|jpe?g|webp|gif);base64,[a-z0-9+/=\s]+$/i.test(String(value || "").slice(0, 2_000_000));
}

export function dataUrlToBlob(dataUrl) {
  const [header, body] = dataUrl.split(",");
  const mime = /data:([^;]+)/.exec(header)?.[1] || "application/octet-stream";
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return new Blob([bytes], { type: mime });
}

export function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

export function simpleHash(text = "") {
  let hash = 0;
  for (let i = 0; i < text.length; i += 1) hash = (hash * 31 + text.charCodeAt(i)) | 0;
  return Math.abs(hash);
}
