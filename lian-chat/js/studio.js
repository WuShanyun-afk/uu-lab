import { parseJsonReply } from "./prompt.js";

export const FACE_OPTIONS = [
  "hello",
  "happy",
  "love",
  "shy",
  "sad",
  "angry",
  "sleepy",
  "ok",
  "question",
  "party",
  "eat",
  "miss",
];

export const PROP_OPTIONS = ["none", "heart", "star", "tears", "zzz", "check", "question", "bowl", "moon", "anger", "sweat"];

/** The soft, chunky "nienie" family. Kept for old packs and the plush renderer. */
export const ANIMAL_OPTIONS = ["blackcat", "cat", "rabbit", "bear", "chick", "seal", "dog"];

export const STICKER_STYLE_OPTIONS = [
  { id: "auto", labelKey: "studio.styleAuto", hintKey: "studio.styleAutoHint" },
  { id: "kaomoji", labelKey: "studio.styleKaomoji", hintKey: "studio.styleKaomojiHint" },
  { id: "plush", labelKey: "studio.stylePlush", hintKey: "studio.stylePlushHint" },
  { id: "emoji", labelKey: "studio.styleEmoji", hintKey: "studio.styleEmojiHint" },
];

const EMOJI_FALLBACKS = {
  normal: "🙂",
  happy: "😊",
  love: "🥰",
  shy: "😳",
  sad: "🥲",
  angry: "😠",
  sleepy: "😴",
  ok: "👌",
  question: "🤔",
  party: "🎉",
  eat: "🍚",
  miss: "💭",
  shock: "😮",
  proud: "😎",
  cute: "🥺",
  peace: "✌️",
};

/**
 * The new default: one black cat head, with the whole expression carried by
 * a kaomoji. These are the user's own reference expressions. Keep the exact
 * punctuation; the renderer only chooses the type size.
 */
export const KAOMOJI_FACES = {
  normal: { label: "冷脸萌·平常", kao: "ᗜ - ᗜ", prop: "none" },
  shy: { label: "害羞", kao: ",,ᗜ - ᗜ,,", prop: "none" },
  happy: { label: "开心", kao: "ᗜ ᴗ ᗜ", prop: "star" },
  sad: { label: "不开心", kao: "ᗜ ‸ ᗜ", prop: "tears" },
  angry: { label: "生气", kao: "ᗜ - ᗜ💢", prop: "none" },
  rage: { label: "爆发", kao: "( ╯－︿－)╯╧╧", prop: "anger" },
  sleepy: { label: "睡着", kao: "ᶻz ₍ _    _ ₎", prop: "zzz" },
  peace: { label: "比耶", kao: "✌︎ ᗜ ֊ ᗜ◞", prop: "star" },
  cute: { label: "卖萌", kao: "ᗜ 𖥥 ᗜ", prop: "blush" },
  proud: { label: "被夸暗爽", kao: "（ᗜ ֊ ᗜ）", prop: "star" },
  love: { label: "贴贴", kao: "ᗜ ♡ ᗜ", prop: "heart" },
  miss: { label: "想你", kao: "ᗜ ‸ ᗜ ♡", prop: "heart" },
  ok: { label: "收到", kao: "ᗜ ◡ ᗜ", prop: "check" },
  question: { label: "疑惑", kao: "ᗜ ﹏ ᗜ ?", prop: "question" },
  party: { label: "庆祝", kao: "ᗜ ᴗ ᗜ ✧", prop: "star" },
  eat: { label: "干饭", kao: "ᗜ 〰 ᗜ", prop: "none" },
  shock: { label: "惊吓", kao: "ᗜ o ᗜ", prop: "sweat" },
};

export const KAOMOJI_FACE_OPTIONS = Object.keys(KAOMOJI_FACES);

const FACE_ALIASES = {
  hello: "normal",
  happy: "happy",
  love: "love",
  shy: "shy",
  sad: "sad",
  angry: "angry",
  sleepy: "sleepy",
  ok: "ok",
  question: "question",
  party: "party",
  eat: "eat",
  miss: "miss",
  冷脸: "normal",
  平常: "normal",
  开心: "happy",
  难过: "sad",
  不开心: "sad",
  生气: "angry",
  爆发: "rage",
  睡着: "sleepy",
  比耶: "peace",
  卖萌: "cute",
  被夸暗爽: "proud",
  贴贴: "love",
  想你: "miss",
  收到: "ok",
  疑惑: "question",
  庆祝: "party",
  干饭: "eat",
  惊吓: "shock",
};

const INK = "#5A4632";
const CREAM = "#FFF8E8";
const PINK = "#F3A6A6";
const MOUTH = "#8C4A4A";
const CAT = "#332D2B";
const CAT_DEEP = "#241F1D";
const CAT_CREAM = "#FFF6E9";

function escapeXml(value = "") {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function hex(value, fallback) {
  return /^#[0-9a-f]{6}$/i.test(String(value || "")) ? String(value) : fallback;
}

function mixWithWhite(value, amount = 0.5) {
  const clean = value.replace("#", "");
  const r = parseInt(clean.slice(0, 2), 16);
  const g = parseInt(clean.slice(2, 4), 16);
  const b = parseInt(clean.slice(4, 6), 16);
  const mix = (channel) => Math.round(channel + (255 - channel) * amount);
  return `#${[mix(r), mix(g), mix(b)].map((n) => n.toString(16).padStart(2, "0")).join("")}`;
}

function shade(value, amount = 0.12) {
  const clean = value.replace("#", "");
  const r = parseInt(clean.slice(0, 2), 16);
  const g = parseInt(clean.slice(2, 4), 16);
  const b = parseInt(clean.slice(4, 6), 16);
  const mix = (channel) => Math.round(channel * (1 - amount));
  return `#${[mix(r), mix(g), mix(b)].map((n) => n.toString(16).padStart(2, "0")).join("")}`;
}

function animalBehind(animal, body, inner) {
  if (animal === "cat" || animal === "blackcat") {
    return `<g stroke="${INK}" stroke-width="8" stroke-linejoin="round">
      <path d="M104 158 C82 122 78 80 98 68 C118 56 144 92 162 114 Z" fill="${body}"/>
      <path d="M296 158 C318 122 322 80 302 68 C282 56 256 92 238 114 Z" fill="${body}"/>
      <path d="M112 138 C100 114 100 94 108 86 C118 78 134 98 146 114 Z" fill="${inner}" opacity=".72" stroke="none"/>
      <path d="M288 138 C300 114 300 94 292 86 C282 78 266 98 254 114 Z" fill="${inner}" opacity=".72" stroke="none"/>
    </g>`;
  }
  if (animal === "rabbit") {
    return `<g stroke="${INK}" stroke-width="8">
      <ellipse cx="140" cy="92" rx="35" ry="92" transform="rotate(-12 140 92)" fill="${body}"/>
      <ellipse cx="260" cy="92" rx="35" ry="92" transform="rotate(12 260 92)" fill="${body}"/>
      <ellipse cx="142" cy="94" rx="15" ry="66" transform="rotate(-12 142 94)" fill="${PINK}" opacity=".34" stroke="none"/>
      <ellipse cx="258" cy="94" rx="15" ry="66" transform="rotate(12 258 94)" fill="${PINK}" opacity=".34" stroke="none"/>
    </g>`;
  }
  if (animal === "bear") {
    return `<g stroke="${INK}" stroke-width="8">
      <circle cx="108" cy="104" r="46" fill="${body}"/>
      <circle cx="292" cy="104" r="46" fill="${body}"/>
      <circle cx="108" cy="104" r="24" fill="${inner}" opacity=".68" stroke="none"/>
      <circle cx="292" cy="104" r="24" fill="${inner}" opacity=".68" stroke="none"/>
    </g>`;
  }
  if (animal === "dog") {
    return `<g stroke="${INK}" stroke-width="8">
      <ellipse cx="86" cy="206" rx="42" ry="80" transform="rotate(20 86 206)" fill="${body}"/>
      <ellipse cx="314" cy="206" rx="42" ry="80" transform="rotate(-20 314 206)" fill="${body}"/>
      <ellipse cx="96" cy="214" rx="18" ry="48" transform="rotate(20 96 214)" fill="${inner}" opacity=".55" stroke="none"/>
      <ellipse cx="304" cy="214" rx="18" ry="48" transform="rotate(-20 304 214)" fill="${inner}" opacity=".55" stroke="none"/>
    </g>`;
  }
  if (animal === "seal") {
    return `<g stroke="${INK}" stroke-width="8">
      <ellipse cx="102" cy="330" rx="43" ry="21" transform="rotate(26 102 330)" fill="${body}"/>
      <ellipse cx="298" cy="330" rx="43" ry="21" transform="rotate(-26 298 330)" fill="${body}"/>
    </g>`;
  }
  if (animal === "chick") {
    return `<path d="M184 106 q-14 -42 6 -56 q10 22 22 38 q0 -30 16 -34 q8 24 2 52" fill="none" stroke="${INK}" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>`;
  }
  return "";
}

function animalFront(animal, accent, ink = INK) {
  if (animal === "chick") {
    return `<path d="M184 230 L200 246 L216 230 Z" fill="${accent}" stroke="${INK}" stroke-width="5" stroke-linejoin="round"/>`;
  }
  if (animal === "cat" || animal === "blackcat") {
    return `<g stroke="${ink}" stroke-width="3" stroke-linecap="round" opacity="${animal === "blackcat" ? ".62" : ".42"}">
      <path d="M80 238 L124 244"/><path d="M80 258 L124 258"/>
      <path d="M320 238 L276 244"/><path d="M320 258 L276 258"/>
    </g>`;
  }
  if (animal === "dog") {
    return `<ellipse cx="200" cy="250" rx="44" ry="32" fill="${CREAM}" opacity=".55" stroke="none"/>`;
  }
  if (animal === "seal") {
    return `<g stroke="${ink}" stroke-width="3" stroke-linecap="round" opacity=".38">
      <path d="M96 240 L130 246"/><path d="M96 258 L130 258"/>
      <path d="M304 240 L270 246"/><path d="M304 258 L270 258"/>
    </g>`;
  }
  return "";
}

function eyes(face, ink = INK, shineColor = "#fff") {
  const shine = (x, y) => (shineColor ? `<circle cx="${x + 4}" cy="${y - 5}" r="4" fill="${shineColor}"/>` : "");
  const open = `<ellipse cx="150" cy="207" rx="13" ry="15" fill="${ink}"/>${shine(150, 207)}
    <ellipse cx="250" cy="207" rx="13" ry="15" fill="${ink}"/>${shine(250, 207)}`;
  const happy = `<path d="M132 211 Q150 189 168 211" fill="none" stroke="${ink}" stroke-width="8" stroke-linecap="round"/>
    <path d="M232 211 Q250 189 268 211" fill="none" stroke="${ink}" stroke-width="8" stroke-linecap="round"/>`;
  const love = `<path d="M150 219 C139 211 133 204 133 195 C133 186 144 183 150 192 C156 183 167 186 167 195 C167 204 161 211 150 219Z" fill="#F27C8D" stroke="${ink}" stroke-width="4"/>
    <path d="M250 219 C239 211 233 204 233 195 C233 186 244 183 250 192 C256 183 267 186 267 195 C267 204 261 211 250 219Z" fill="#F27C8D" stroke="${ink}" stroke-width="4"/>`;
  const shy = `<path d="M136 211 Q150 202 164 211" fill="none" stroke="${ink}" stroke-width="7" stroke-linecap="round"/>
    <path d="M236 211 Q250 202 264 211" fill="none" stroke="${ink}" stroke-width="7" stroke-linecap="round"/>`;
  const sleepy = `<path d="M134 209 Q150 218 166 209" fill="none" stroke="${ink}" stroke-width="7" stroke-linecap="round"/>
    <path d="M234 209 Q250 218 266 209" fill="none" stroke="${ink}" stroke-width="7" stroke-linecap="round"/>`;
  const sad = `<path d="M134 212 Q150 202 166 212" fill="none" stroke="${ink}" stroke-width="7" stroke-linecap="round"/>
    <path d="M234 212 Q250 202 266 212" fill="none" stroke="${ink}" stroke-width="7" stroke-linecap="round"/>
    <path d="M132 187 Q150 178 168 187" fill="none" stroke="${ink}" stroke-width="5" stroke-linecap="round" opacity=".7"/>
    <path d="M232 187 Q250 178 268 187" fill="none" stroke="${ink}" stroke-width="5" stroke-linecap="round" opacity=".7"/>`;
  const angry = `<path d="M132 189 L168 199" fill="none" stroke="${ink}" stroke-width="7" stroke-linecap="round"/>
    <path d="M268 189 L232 199" fill="none" stroke="${ink}" stroke-width="7" stroke-linecap="round"/>
    <ellipse cx="150" cy="212" rx="11" ry="13" fill="${ink}"/><ellipse cx="250" cy="212" rx="11" ry="13" fill="${ink}"/>`;
  const wink = `<path d="M132 211 Q150 191 168 211" fill="none" stroke="${ink}" stroke-width="8" stroke-linecap="round"/>
    <ellipse cx="250" cy="207" rx="13" ry="15" fill="${ink}"/>${shine(250, 207)}`;
  const question = `<ellipse cx="150" cy="207" rx="13" ry="15" fill="${ink}"/>${shine(150, 207)}
    <path d="M232 211 Q250 202 268 211" fill="none" stroke="${ink}" stroke-width="7" stroke-linecap="round"/>
    <path d="M232 181 Q250 172 268 184" fill="none" stroke="${ink}" stroke-width="5" stroke-linecap="round" opacity=".7"/>`;
  switch (face) {
    case "happy":
    case "party":
    case "eat":
      return happy;
    case "love":
    case "miss":
      return love;
    case "shy":
      return shy;
    case "sleepy":
      return sleepy;
    case "sad":
      return sad;
    case "angry":
      return angry;
    case "ok":
    case "hello":
      return wink;
    case "question":
      return question;
    default:
      return open;
  }
}

function mouth(face, fill = MOUTH, line = INK) {
  if (["happy", "party", "eat", "love", "hello"].includes(face)) {
    return `<path d="M180 253 Q200 271 220 253 Q216 289 200 289 Q184 289 180 253Z" fill="${fill}" stroke="${line}" stroke-width="4" stroke-linejoin="round"/>
      <path d="M191 279 Q200 286 209 279" fill="${PINK}"/>`;
  }
  if (["sad", "angry"].includes(face)) {
    return `<path d="M181 265 Q200 252 219 265" fill="none" stroke="${line}" stroke-width="5" stroke-linecap="round"/>`;
  }
  if (face === "sleepy") {
    return `<ellipse cx="200" cy="260" rx="7" ry="9" fill="${fill}" stroke="${line}" stroke-width="3"/>`;
  }
  return `<path d="M183 253 Q191 262 200 253 Q209 262 217 253" fill="none" stroke="${line}" stroke-width="5" stroke-linecap="round"/>`;
}

function propMarkup(prop, accent) {
  const outline = `stroke="${INK}" stroke-linejoin="round" stroke-linecap="round"`;
  switch (prop) {
    case "heart":
      return `<path d="M318 135 C300 121 288 111 288 96 C288 84 304 78 318 91 C332 78 348 84 348 96 C348 111 336 121 318 135Z" fill="#F27C8D" ${outline} stroke-width="5"/>`;
    case "star":
      return `<path d="M326 70 q4 17 20 20 q-16 4 -20 20 q-4 -16 -20 -20 q16 -3 20 -20Z" fill="${accent}" ${outline} stroke-width="5"/>`;
    case "tears":
      return `<path d="M126 224 q-7 16 2 23 q10 -7 4 -23" fill="#8ED6F0" ${outline} stroke-width="3"/>
        <path d="M270 224 q7 16 -2 23 q-10 -7 -4 -23" fill="#8ED6F0" ${outline} stroke-width="3"/>`;
    case "zzz":
      return `<text x="292" y="104" font-family="Arial Rounded MT Bold, Arial, sans-serif" font-size="30" font-weight="700" fill="${INK}" opacity=".62">z</text>
        <text x="319" y="75" font-family="Arial Rounded MT Bold, Arial, sans-serif" font-size="21" font-weight="700" fill="${INK}" opacity=".45">z</text>`;
    case "check":
      return `<circle cx="326" cy="116" r="25" fill="${accent}" ${outline} stroke-width="5"/>
        <path d="M313 116 l10 11 l18 -21" fill="none" stroke="${INK}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>`;
    case "question":
      return `<text x="302" y="124" font-family="Arial Rounded MT Bold, Arial, sans-serif" font-size="68" font-weight="700" fill="${accent}" ${outline} stroke-width="3">?</text>`;
    case "bowl":
      return `<g ${outline} stroke-width="5">
        <path d="M150 347 q50 22 100 0 q-8 28 -50 28 q-42 0 -50 -28Z" fill="#E9B86A"/>
        <circle cx="178" cy="347" r="5" fill="${CREAM}"/><circle cx="200" cy="351" r="5" fill="${CREAM}"/><circle cx="222" cy="347" r="5" fill="${CREAM}"/>
      </g>`;
    case "moon":
      return `<path d="M332 78 a30 30 0 1 0 22 40 a25 25 0 0 1 -22 -40Z" fill="#F2D58A" ${outline} stroke-width="4"/>`;
    default:
      return "";
  }
}

function noseMarkup(animal, line) {
  if (animal === "chick") return "";
  if (animal === "cat" || animal === "blackcat") {
    return `<path d="M192 231 L208 231 L200 241 Z" fill="#E98F9C" stroke="${line}" stroke-width="3" stroke-linejoin="round"/>`;
  }
  return `<ellipse cx="200" cy="235" rx="14" ry="10" fill="#FFFDF8" stroke="${line}" stroke-width="5"/>`;
}

function resolveKaomojiFace(value) {
  const raw = String(value || "").trim();
  if (KAOMOJI_FACES[raw]) return raw;
  if (FACE_ALIASES[raw]) return FACE_ALIASES[raw];
  const byLabel = Object.entries(KAOMOJI_FACES).find(
    ([, item]) => item.kao === raw || item.label === raw,
  );
  return byLabel ? byLabel[0] : "normal";
}

function kaomojiUnits(value) {
  let units = 0;
  for (const ch of [...value]) {
    if (/\s/.test(ch)) {
      units += 0.55;
      continue;
    }
    const code = ch.codePointAt(0) || 0;
    const wide =
      /\p{Extended_Pictographic}/u.test(ch) ||
      (code >= 0x1100 && code <= 0x115f) ||
      (code >= 0x2e80 && code <= 0xa4cf) ||
      (code >= 0xac00 && code <= 0xd7a3) ||
      (code >= 0xf900 && code <= 0xfaff) ||
      (code >= 0xfe30 && code <= 0xfe4f) ||
      (code >= 0xff00 && code <= 0xff60) ||
      (code >= 0xffe0 && code <= 0xffe6);
    units += wide ? 1.9 : 1;
  }
  return units;
}

function kaomojiType(kao) {
  const units = kaomojiUnits(kao);
  const size = Math.max(21, Math.min(58, Math.floor(248 / (units * 0.56))));
  const width = Math.round(units * size * 0.56);
  return {
    size,
    textLength: width > 250 ? ` textLength="246" lengthAdjust="spacingAndGlyphs"` : "",
  };
}

function kaoPropMarkup(prop) {
  const outline = `stroke="${INK}" stroke-linejoin="round" stroke-linecap="round"`;
  switch (prop) {
    case "heart":
      return `<path d="M322 128 C305 115 294 105 294 91 C294 79 309 74 322 86 C335 74 350 79 350 91 C350 105 339 115 322 128Z" fill="#F27C8D" ${outline} stroke-width="4"/>`;
    case "star":
      return `<path d="M330 68 q4 17 20 20 q-16 4 -20 20 q-4 -16 -20 -20 q16 -3 20 -20Z" fill="#F4D47A" ${outline} stroke-width="4"/>`;
    case "tears":
      return `<path d="M108 268 q-8 18 2 26 q12 -8 5 -26" fill="#8ED6F0" ${outline} stroke-width="3"/>
        <path d="M288 268 q8 18 -2 26 q-12 -8 -5 -26" fill="#8ED6F0" ${outline} stroke-width="3"/>`;
    case "zzz":
      return `<text x="304" y="106" font-family="Arial Rounded MT Bold, Arial, sans-serif" font-size="27" font-weight="700" fill="${CAT_CREAM}" opacity=".64">z</text>
        <text x="330" y="79" font-family="Arial Rounded MT Bold, Arial, sans-serif" font-size="18" font-weight="700" fill="${CAT_CREAM}" opacity=".46">z</text>`;
    case "check":
      return `<circle cx="326" cy="112" r="23" fill="#A9D6B8" ${outline} stroke-width="4"/>
        <path d="M314 112 l9 10 l17 -20" fill="none" stroke="${INK}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>`;
    case "question":
      return `<text x="306" y="120" font-family="Arial Rounded MT Bold, Arial, sans-serif" font-size="58" font-weight="700" fill="#F4D47A" ${outline} stroke-width="3">?</text>`;
    case "anger":
      return `<g stroke="#EF7D7D" stroke-width="6" stroke-linecap="round">
        <path d="M318 84 L342 108"/><path d="M342 84 L318 108"/>
        <path d="M316 96 L344 96" opacity=".55"/>
      </g>`;
    case "sweat":
      return `<path d="M310 126 q-8 18 2 26 q12 -8 5 -26" fill="#9BD8EE" ${outline} stroke-width="3"/>`;
    default:
      return "";
  }
}

export function renderKaomojiStickerSvg(recipe = {}) {
  const face = resolveKaomojiFace(recipe.face);
  const kao = String(recipe.kaomoji || KAOMOJI_FACES[face].kao).slice(0, 40);
  const prop = PROP_OPTIONS.includes(recipe.prop) ? recipe.prop : KAOMOJI_FACES[face].prop;
  const label = escapeXml(String(recipe.caption || recipe.name || KAOMOJI_FACES[face].label).slice(0, 14));
  const type = kaomojiType(kao);
  const font = "'Segoe UI Symbol','Segoe UI','Microsoft YaHei','Apple Symbols','Noto Sans Symbols 2','Arial Unicode MS',sans-serif";

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" role="img" aria-label="${label}">
  <defs>
    <radialGradient id="kaoBlush" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="${PINK}" stop-opacity=".8"/>
      <stop offset="100%" stop-color="${PINK}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <ellipse cx="200" cy="362" rx="108" ry="14" fill="#8E7B68" opacity=".2"/>
  <g stroke-linejoin="round" stroke-linecap="round">
    <path d="M60 204 C46 160 52 100 78 78 C102 58 139 106 170 146 Z" fill="${CAT}" stroke="${CAT_CREAM}" stroke-width="11"/>
    <path d="M340 204 C354 160 348 100 322 78 C298 58 261 106 230 146 Z" fill="${CAT}" stroke="${CAT_CREAM}" stroke-width="11"/>
    <path d="M60 204 C46 160 52 100 78 78 C102 58 139 106 170 146 Z" fill="none" stroke="${INK}" stroke-width="4" opacity=".9"/>
    <path d="M340 204 C354 160 348 100 322 78 C298 58 261 106 230 146 Z" fill="none" stroke="${INK}" stroke-width="4" opacity=".9"/>
    <path d="M80 178 C69 140 75 108 91 91 C108 78 132 114 153 142 Z" fill="${PINK}" opacity=".72"/>
    <path d="M320 178 C331 140 325 108 309 91 C292 78 268 114 247 142 Z" fill="${PINK}" opacity=".72"/>
    <path d="M56 232 C56 159 104 120 200 120 C296 120 344 159 344 232 C344 295 298 344 200 344 C102 344 56 295 56 232 Z" fill="${CAT}" stroke="${CAT_CREAM}" stroke-width="11"/>
    <path d="M56 232 C56 159 104 120 200 120 C296 120 344 159 344 232 C344 295 298 344 200 344 C102 344 56 295 56 232 Z" fill="none" stroke="${INK}" stroke-width="4" opacity=".9"/>
    <path d="M112 162 C134 132 162 120 194 120" fill="none" stroke="${CAT_CREAM}" stroke-width="5" opacity=".14"/>
  </g>
  <ellipse cx="101" cy="286" rx="36" ry="20" fill="url(#kaoBlush)" stroke="none"/>
  <ellipse cx="299" cy="286" rx="36" ry="20" fill="url(#kaoBlush)" stroke="none"/>
  <path d="M193 310 L207 310 L200 319 Z" fill="#E98F9C" stroke="${CAT_DEEP}" stroke-width="2.5" stroke-linejoin="round"/>
  <g stroke="${CAT_CREAM}" stroke-width="2.2" stroke-linecap="round" opacity=".3">
    <path d="M70 278 L126 284"/><path d="M72 298 L127 293"/>
    <path d="M330 278 L274 284"/><path d="M328 298 L273 293"/>
  </g>
  <text x="200" y="228" text-anchor="middle" dominant-baseline="middle" xml:space="preserve"${type.textLength}
    font-family="${font}" font-size="${type.size}" font-weight="600" letter-spacing=".4"
    fill="${CAT_CREAM}">${escapeXml(kao)}</text>
  ${kaoPropMarkup(prop)}
  </svg>`;
}

function inkOn(value) {
  const clean = hex(value, "#FFF4D6").replace("#", "");
  const r = parseInt(clean.slice(0, 2), 16) / 255;
  const g = parseInt(clean.slice(2, 4), 16) / 255;
  const b = parseInt(clean.slice(4, 6), 16) / 255;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.62 ? "#312A23" : "#FFFDF6";
}

function cleanEmoji(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  // Keep one visible glyph (including common ZWJ / variation sequences).
  const match = raw.match(/\p{Extended_Pictographic}(?:\uFE0F|\u200D\p{Extended_Pictographic})*/u);
  return (match?.[0] || [...raw][0] || "").slice(0, 16);
}

function emojiText(value) {
  const emoji = cleanEmoji(value);
  if (emoji) return emoji;
  const face = resolveKaomojiFace(value);
  return EMOJI_FALLBACKS[face] || "🙂";
}

export function renderEmojiStickerSvg(recipe = {}) {
  const emoji = emojiText(recipe.emoji || recipe.face || recipe.caption);
  const caption = escapeXml(String(recipe.caption || recipe.name || "").trim().slice(0, 10));
  const bg = hex(recipe.color, "#FFF2D8");
  const accent = hex(recipe.accent, "#E9A9A0");
  const ink = inkOn(bg);
  const font = "'Segoe UI Emoji','Apple Color Emoji','Noto Color Emoji','Android Emoji',sans-serif";
  const captionInk = inkOn("#FFFDF7");
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" role="img" aria-label="${escapeXml(caption || emoji)}">
  <defs>
    <radialGradient id="emojiGlow" cx="50%" cy="36%" r="62%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity=".82"/>
      <stop offset="100%" stop-color="${bg}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="emojiEdge" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="${accent}" stop-opacity=".55"/>
      <stop offset="100%" stop-color="${accent}" stop-opacity=".08"/>
    </linearGradient>
  </defs>
  <rect x="8" y="8" width="384" height="384" rx="58" fill="${bg}"/>
  <rect x="8" y="8" width="384" height="384" rx="58" fill="none" stroke="${accent}" stroke-width="6" opacity=".6"/>
  <circle cx="200" cy="158" r="136" fill="url(#emojiGlow)"/>
  <circle cx="63" cy="76" r="24" fill="url(#emojiEdge)"/>
  <circle cx="334" cy="310" r="35" fill="url(#emojiEdge)"/>
  <path d="M318 62 l5 15 15 5 -15 5 -5 15 -5 -15 -15 -5 15 -5Z" fill="${accent}" opacity=".55"/>
  <text x="200" y="190" text-anchor="middle" dominant-baseline="middle"
    font-family="${font}" font-size="150">${escapeXml(emoji)}</text>
  ${caption ? `<rect x="82" y="302" width="236" height="54" rx="27" fill="#FFFDF7" opacity=".93"/>
  <text x="200" y="330" text-anchor="middle" dominant-baseline="middle"
    font-family="'Segoe UI','PingFang SC','Microsoft YaHei',sans-serif" font-size="24" font-weight="650"
    fill="${captionInk}">${caption}</text>` : ""}
  </svg>`;
}

export function renderStickerSvg(recipe = {}) {
  if (recipe.style === "emoji" || recipe.emoji) return renderEmojiStickerSvg(recipe);
  if (recipe.style === "kaomoji" || recipe.kaomoji) return renderKaomojiStickerSvg(recipe);
  return renderPlushStickerSvg(recipe);
}

function renderPlushStickerSvg(recipe = {}) {
  const face = FACE_OPTIONS.includes(recipe.face) ? recipe.face : "happy";
  const prop = PROP_OPTIONS.includes(recipe.prop) ? recipe.prop : "none";
  const animal = ANIMAL_OPTIONS.includes(recipe.animal) ? recipe.animal : "blackcat";
  const isBlackCat = animal === "blackcat";
  const body = isBlackCat ? "#332D2B" : mixWithWhite(hex(recipe.color, "#F3DFC9"), 0.28);
  const inner = isBlackCat ? mixWithWhite(hex(recipe.accent, "#F4A7B1"), 0.16) : mixWithWhite(hex(recipe.accent, "#F4A7B1"), 0.3);
  const deep = shade(body, 0.08);
  const ink = isBlackCat ? "#FFF6E9" : INK;
  const mouthFill = isBlackCat ? "#DDA6A8" : MOUTH;
  const label = escapeXml(String(recipe.caption || recipe.name || "捏捏").slice(0, 10));
  const isChick = animal === "chick";
  const headRx = isChick ? 132 : 145;
  const headRy = isChick ? 118 : 125;
  const bodyRx = isChick ? 72 : 82;
  const bodyRy = isChick ? 54 : 60;
  const bodyY = isChick ? 312 : 308;

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" role="img" aria-label="${label}">
  <defs>
    <radialGradient id="blush" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="${PINK}" stop-opacity=".72"/>
      <stop offset="100%" stop-color="${PINK}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="belly" cx="50%" cy="38%" r="70%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="${isBlackCat ? ".62" : ".85"}"/>
      <stop offset="100%" stop-color="${CREAM}" stop-opacity=".25"/>
    </radialGradient>
  </defs>
  <ellipse cx="200" cy="369" rx="112" ry="15" fill="#8E7B68" opacity=".2"/>
  ${animalBehind(animal, body, inner)}
  <g stroke="${INK}" stroke-width="8">
    <ellipse cx="164" cy="354" rx="31" ry="19" fill="${body}"/>
    <ellipse cx="236" cy="354" rx="31" ry="19" fill="${body}"/>
    <ellipse cx="126" cy="300" rx="28" ry="21" transform="rotate(-18 126 300)" fill="${body}"/>
    <ellipse cx="274" cy="300" rx="28" ry="21" transform="rotate(18 274 300)" fill="${body}"/>
    <ellipse cx="200" cy="${bodyY}" rx="${bodyRx}" ry="${bodyRy}" fill="${body}"/>
  </g>
  <ellipse cx="200" cy="${bodyY + 8}" rx="${bodyRx - 30}" ry="${bodyRy - 25}" fill="url(#belly)" stroke="none"/>
  <ellipse cx="200" cy="212" rx="${headRx}" ry="${headRy}" fill="${body}" stroke="${INK}" stroke-width="8"/>
  <path d="M92 238 Q200 270 308 238" fill="none" stroke="${deep}" stroke-width="3" opacity=".25"/>
  ${animalFront(animal, inner, ink)}
  ${eyes(face, ink, isBlackCat ? "" : "#fff")}
  ${noseMarkup(animal, ink)}
  ${mouth(face, mouthFill, ink)}
  <ellipse cx="112" cy="249" rx="31" ry="18" fill="url(#blush)" stroke="none"/>
  <ellipse cx="288" cy="249" rx="31" ry="18" fill="url(#blush)" stroke="none"/>
  ${propMarkup(prop, inner)}
  </svg>`;
}

export function svgToDataUrl(svg) {
  const bytes = new TextEncoder().encode(svg);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return `data:image/svg+xml;base64,${btoa(binary)}`;
}

export function parseStickerPack(raw, { style: requestedStyle = "auto" } = {}) {
  let data;
  try {
    data = typeof raw === "string" ? parseJsonReply(raw) : raw;
  } catch {
    throw new Error("invalid JSON");
  }
  if (!data || typeof data !== "object") throw new Error("invalid pack");
  const name = String(data.name || "").trim().slice(0, 24) || "TA 的表情";
  const theme = String(data.theme || "").trim().slice(0, 80);
  const rows = Array.isArray(data.stickers) ? data.stickers.slice(0, 6) : [];
  if (rows.length < 4) throw new Error("pack needs at least 4 stickers");

  const validStyle = (value) => ["kaomoji", "plush", "emoji"].includes(value);
  const forced = validStyle(requestedStyle) ? requestedStyle : "";
  const guessed = rows.some((row) => cleanEmoji(row?.emoji))
    ? "emoji"
    : data.animal || rows.some((row) => row?.animal)
      ? "plush"
      : "kaomoji";
  const style = forced || (validStyle(data.style) ? data.style : guessed);

  if (style === "kaomoji") {
    const stickers = rows.map((row, index) => {
      const face = resolveKaomojiFace(row?.face || row?.name || row?.caption);
      const customKao = String(row?.kaomoji || "").replace(/[\r\n<>]/g, "").trim().slice(0, 32);
      const caption =
        String(row?.caption || row?.name || KAOMOJI_FACES[face].label).trim().slice(0, 10) ||
        KAOMOJI_FACES[face].label;
      const stickerName = String(row?.name || caption).trim().slice(0, 12) || caption;
      return {
        name: stickerName,
        caption,
        face,
        kaomoji: customKao || KAOMOJI_FACES[face].kao,
        animal: "blackcat",
        prop: PROP_OPTIONS.includes(row?.prop) ? row.prop : KAOMOJI_FACES[face].prop,
        style: "kaomoji",
        index,
      };
    });
    return { name, theme, style: "kaomoji", stickers };
  }

  if (style === "emoji") {
    const stickers = rows.map((row, index) => {
      const face = resolveKaomojiFace(row?.face || row?.name || row?.caption);
      const emoji = cleanEmoji(row?.emoji) || EMOJI_FALLBACKS[face] || "🙂";
      const caption =
        String(row?.caption || row?.name || "").trim().slice(0, 10) ||
        String(row?.name || "").trim().slice(0, 10) ||
        "…";
      const stickerName = String(row?.name || caption).trim().slice(0, 12) || caption;
      return {
        name: stickerName,
        caption,
        emoji,
        face,
        color: hex(row?.color, "#FFF2D8"),
        accent: hex(row?.accent, "#E9A9A0"),
        style: "emoji",
        index,
      };
    });
    return { name, theme, style: "emoji", stickers };
  }

  const packAnimal = ANIMAL_OPTIONS.includes(data.animal)
    ? data.animal
    : data.animal
      ? "blackcat"
      : ANIMAL_OPTIONS.includes(rows[0]?.animal)
        ? rows[0].animal
        : "blackcat";
  const stickers = rows.map((row, index) => {
    const face = FACE_OPTIONS.includes(row?.face) ? row.face : "happy";
    const prop = PROP_OPTIONS.includes(row?.prop) ? row.prop : "none";
    const animal = ANIMAL_OPTIONS.includes(row?.animal) && data.style !== "plush"
      ? row.animal
      : packAnimal;
    const caption = String(row?.caption || row?.name || "").trim().slice(0, 10) || "捏捏";
    const stickerName = String(row?.name || caption).trim().slice(0, 12) || caption;
    return {
      name: stickerName,
      caption,
      face,
      animal,
      prop,
      color: hex(row?.color, "#F3DFC9"),
      accent: hex(row?.accent, "#F4A7B1"),
      style: "plush",
      index,
    };
  });
  return { name, theme, style: "plush", stickers };
}

export function buildStickerPackMessages(state, { style = "auto", direction = "" } = {}) {
  const s = state.settings;
  const recent = (state.messages || [])
    .filter((m) => m.kind === "text" && m.text)
    .slice(-6)
    .map((m) => `${m.role === "user" ? "对方" : "我"}：${m.text.slice(0, 80)}`)
    .join("\n");
  const expressions = Object.entries(KAOMOJI_FACES)
    .map(([id, item]) => `${id} ${item.label}：${item.kao}`)
    .join("\n");
  const requestedStyle = ["kaomoji", "plush", "emoji"].includes(style) ? style : "";
  const userDirection = String(direction || "").trim().slice(0, 180);
  const directionLine = userDirection || "没有指定，按角色气质自行决定。";
  const styleRule = requestedStyle
    ? `本次固定为 ${requestedStyle}，不要改成其他 style。`
    : "本次不固定风格。请从 kaomoji / plush / emoji 里选一种最适合角色和方向的，不要默认画黑猫颜文字。如果方向里提到具体动物、食物、物品或人物，优先用 plush（可用的动物）或 emoji（任意对象）。";
  const schema = requestedStyle === "emoji"
    ? `{"name":"6–12 字表情包名","theme":"一句风格说明","style":"emoji","stickers":[
  {"name":"短名","caption":"图上文字 2–6 字","emoji":"一个 emoji","color":"#FFF2D8","accent":"#E9A9A0"}
]}`
    : requestedStyle === "plush"
      ? `{"name":"6–12 字表情包名","theme":"一句风格说明","style":"plush","animal":"blackcat|cat|rabbit|bear|chick|seal|dog","stickers":[
  {"name":"短名","caption":"2–6 字","face":"happy","prop":"none","color":"#F3DFC9","accent":"#F4A7B1"}
]}`
      : requestedStyle === "kaomoji"
        ? `{"name":"6–12 字表情包名","theme":"一句风格说明","style":"kaomoji","stickers":[
  {"name":"短名","caption":"2–6 字","face":"normal","kaomoji":"可留空，或写一句颜文字"}
]}`
        : `{"name":"6–12 字表情包名","theme":"一句风格说明","style":"kaomoji|plush|emoji","stickers":[
  {"name":"短名","caption":"2–6 字","face":"可选","kaomoji":"仅 kaomoji 用","animal":"仅 plush 用","prop":"仅 kaomoji/plush 用","emoji":"仅 emoji 用","color":"#F3DFC9","accent":"#F4A7B1"}
]}`;
  const kaomojiDetail = `- kaomoji：一颗黑色猫猫头，情绪由奶白颜文字承担。可用 face：\n${expressions}\n  自定义 kaomoji 最多 32 字，必须是一行纯文本，不能有 HTML。`;
  const plushDetail = `- plush：软萌动物捏捏，可选 animal：${ANIMAL_OPTIONS.join("、")}；face：${FACE_OPTIONS.join("、")}；prop：${PROP_OPTIONS.join("、")}。`;
  const emojiDetail = "- emoji：任意一个 emoji + 一句图上文字，适合具体物件、食物、动物或梗。";
  const styleDetails = requestedStyle === "kaomoji"
    ? kaomojiDetail
    : requestedStyle === "plush"
      ? plushDetail
      : requestedStyle === "emoji"
        ? emojiDetail
        : `${kaomojiDetail}\n${plushDetail}\n${emojiDetail}`;
  const system = `你是角色「${s.aiName || "Lian"}」的私人表情包设计师。为 TA 设计一套 6 张聊天表情，风格由下面这次的要求决定，不要套用固定模板。

【角色设定】
${s.persona || "一个自然、克制、有生活感的人。"}
${s.relationship ? `关系：${s.relationship}` : ""}
${recent ? `【最近的聊天，仅供语气参考】\n${recent}` : ""}

【这次怎么画】
- 风格：${styleRule}
- 用户给的方向：${directionLine}
- 画面干净、留白、可爱但不幼齿；不要 3D、写实、复杂光影、低俗或攻击性内容。
- 6 张必须是同一套画风、同一个角色或主题，像同一套表情。
- 不要输出颜色以外的多余解释。颜色必须是 6 位 hex。

【可用素材】
${styleDetails}

【设计原则】
- 根据角色说话的气质和用户方向选 6 个不同的情绪，不要 6 张都开心。
- name 是表情名（2–4 字），caption 是发送时显示的小标签（2–6 字）。
- 画面里不要写 caption；它只作为名称。
- 不要画文字说明、对话框、水印或二维码。emoji 风格只画一个 emoji 和 caption。

【输出】
只输出一个合法 JSON 对象，不要 Markdown，不要解释：
${schema}
必须正好 6 个。`;
  return [
    { role: "system", content: system },
    {
      role: "user",
      content: userDirection
        ? `请按这个方向做 6 张表情：${userDirection}。只输出 JSON。`
        : "请按角色气质自由决定类型，做 6 张表情。只输出 JSON。",
    },
  ];
}

export function makeStickersFromSpecs(specs, packId) {
  return specs.map((spec, index) => {
    const svg = renderStickerSvg(spec);
    const id = `ai_${packId}_${index}`;
    return {
      id,
      name: spec.name,
      caption: spec.caption,
      dataUrl: svgToDataUrl(svg),
      svg,
      packId,
      ai: true,
      style: spec.style || "",
      face: spec.face || "",
      kaomoji: spec.kaomoji || "",
      emoji: spec.emoji || "",
      animal: spec.animal || "",
      prop: spec.prop || "",
      color: spec.color || "",
      accent: spec.accent || "",
      createdAt: Date.now(),
    };
  });
}
