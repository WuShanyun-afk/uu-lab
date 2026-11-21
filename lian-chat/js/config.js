export const APP_VERSION = 1;
export const APP_NAME = "Lian";

export const PROVIDERS = {
  mimo: {
    id: "mimo",
    label: "MiMo（小米）",
    short: "MiMo",
    baseUrl: "https://api.xiaomimimo.com/v1",
    model: "mimo-v2.6-flash",
    visionModel: "mimo-v2.6-flash",
    note: "填 Key 即用 · 默认全模态",
  },
  openai: {
    id: "openai",
    label: "OpenAI",
    short: "OpenAI",
    baseUrl: "https://api.openai.com/v1",
    model: "gpt-4o-mini",
    visionModel: "gpt-4o-mini",
    note: "需允许浏览器跨域",
  },
  deepseek: {
    id: "deepseek",
    label: "DeepSeek",
    short: "DeepSeek",
    baseUrl: "https://api.deepseek.com/v1",
    model: "deepseek-flash",
    visionModel: "deepseek-flash",
    note: "V4.1 Flash · 原生联网 / 深度思考",
  },
  custom: {
    id: "custom",
    label: "自定义（OpenAI 兼容）",
    short: "自定义",
    baseUrl: "",
    model: "",
    visionModel: "",
    note: "任何 OpenAI 格式接口",
  },
};

/* `bubble` pins the two bubble colours for themes whose palette is deliberately
   pale (a saturated accent would fight the whole page). `statusBar` tints the
   meta theme-color / native system bars; without it the chrome stays white. */
export const THEMES = [
  { id: "line", label: "LINE", labelEn: "LINE", accent: "#06C755", bg: "#E9ECE5", swatch: "linear-gradient(150deg,#eef1e9 0 52%,#06c755 53%)" },
  {
    id: "paper",
    label: "纸间",
    labelEn: "Paper",
    accent: "#0D8B4D",
    bg: "#EEF0E8",
    swatch: "linear-gradient(150deg,#fffefb 0%,#f2efe4 58%,#0d8b4d 100%)",
  },
  { id: "ink", label: "墨黑", labelEn: "Ink", accent: "#1B1B1B", bg: "#F0F0EC", swatch: "linear-gradient(150deg,#f2f2ef 0 52%,#1b1b1b 53%)" },
  { id: "latte", label: "拿铁", labelEn: "Latte", accent: "#A9784F", bg: "#EFE8DD", swatch: "linear-gradient(150deg,#f3ece1 0 52%,#a9784f 53%)" },
  { id: "sakura", label: "樱雾", labelEn: "Sakura", accent: "#D77D92", bg: "#F3E8E8", swatch: "linear-gradient(150deg,#f7edee 0 52%,#d77d92 53%)" },
  { id: "ocean", label: "海盐", labelEn: "Sea salt", accent: "#3E7F9E", bg: "#E7EFF1", swatch: "linear-gradient(150deg,#eaf1f3 0 52%,#3e7f9e 53%)" },
  {
    id: "snow",
    label: "雪站",
    labelEn: "Snow station",
    accent: "#0A84FF",
    bg: "#20252C",
    immersive: true,
    defaultBg: "assets/backgrounds/snow-station.svg",
    swatch: "radial-gradient(circle at 50% 26%, #f5f9fa 0 12%, transparent 13%), linear-gradient(155deg,#dce4e7 0%,#93a2ac 43%,#39434c 72%,#1c2127 100%)",
  },
  /* ---- 2.0：从「低饱和 + 细边」的路子补进来的八套 ---- */
  {
    id: "mint",
    label: "薄荷",
    labelEn: "Mint soda",
    accent: "#2F9E75",
    bg: "#E9F4EE",
    statusBar: "#F4F9F6",
    bubble: { bg: "#D6F0E2", ink: "#0F4531" },
    swatch: "linear-gradient(150deg,#f4fbf7 0 52%,#2f9e75 53%)",
  },
  {
    id: "berry",
    label: "莓奶",
    labelEn: "Berry milk",
    accent: "#C05A79",
    bg: "#F6E7EC",
    statusBar: "#FBF4F6",
    bubble: { bg: "#FBD9E2", ink: "#6B1F35" },
    swatch: "linear-gradient(150deg,#fdf3f6 0 52%,#c05a79 53%)",
  },
  {
    id: "butter",
    label: "奶油",
    labelEn: "Butter",
    accent: "#BE8B3C",
    bg: "#F4E9D2",
    statusBar: "#FBF6E9",
    bubble: { bg: "#FAE6BE", ink: "#5A3B08" },
    swatch: "linear-gradient(150deg,#fdf8ec 0 52%,#be8b3c 53%)",
  },
  {
    id: "lilac",
    label: "丁香",
    labelEn: "Lilac",
    accent: "#7A69C0",
    bg: "#E9E4F7",
    statusBar: "#F5F3FB",
    bubble: { bg: "#E6DFF9", ink: "#35276B" },
    swatch: "linear-gradient(150deg,#f6f3fd 0 52%,#7a69c0 53%)",
  },
  {
    id: "sky",
    label: "晴空",
    labelEn: "Clear sky",
    accent: "#4E8FB8",
    bg: "#DFEDF9",
    statusBar: "#F0F6FB",
    bubble: { bg: "#BFDCF5", ink: "#123A56" },
    swatch: "linear-gradient(150deg,#f1f8fd 0 52%,#4e8fb8 53%)",
  },
  {
    id: "dawn",
    label: "暮光",
    labelEn: "Dusk",
    accent: "#D08A76",
    bg: "#F3E4EE",
    statusBar: "#FDF4EF",
    bubble: { bg: "#FBD6C9", ink: "#5E2A1B" },
    swatch: "linear-gradient(160deg,#fff3ea 0%,#f9e6ef 52%,#d08a76 100%)",
  },
  {
    id: "mono",
    label: "墨白",
    labelEn: "Mono",
    accent: "#23242A",
    bg: "#EAEAEE",
    statusBar: "#EFEFF1",
    bubble: { bg: "#1C1D22", ink: "#FFFFFF" },
    swatch: "linear-gradient(150deg,#f4f4f6 0 52%,#1c1d22 53%)",
  },
  {
    id: "neo",
    label: "拟态",
    labelEn: "Neumorph",
    accent: "#A79C8C",
    bg: "#EEECE7",
    statusBar: "#EEECE7",
    bubble: { bg: "#EEECE7", ink: "#4A453D" },
    swatch: "radial-gradient(circle at 34% 30%,#fbf9f4 0 24%,transparent 25%),linear-gradient(145deg,#f2f0ea,#ded9d0)",
  },
  /* ---- 助理：给「纯 AI 助理」模式用的冷白 + 蓝 ---- */
  {
    id: "assistant",
    label: "助理",
    labelEn: "Assistant",
    accent: "#2F6BFF",
    bg: "#F2F5FA",
    statusBar: "#F7F9FC",
    bubble: { bg: "#DCE7FF", ink: "#12325F" },
    swatch: "linear-gradient(150deg,#f7f9fc 0 52%,#2f6bff 53%)",
  },
];

/* Chat page layouts — each one rewrites the header, the bubble anatomy and the
   composer, not just the colours. css/modules/16-layouts.css does the work. */
export const CHAT_LAYOUTS = [
  { id: "line", label: "经典 / LINE" },
  { id: "imessage", label: "讯息 / iMessage" },
  { id: "letter", label: "信笺 / Letter" },
  { id: "bubble", label: "泡泡 / Bubble" },
  { id: "plain", label: "素页 / Plain" },
  { id: "journal", label: "手账 / Journal" },
  { id: "timeline", label: "时间轴 / Timeline" },
  { id: "comic", label: "漫画 / Comic" },
];

/** Theme name in the UI language, falling back to the Chinese label. */
export function themeLabel(theme, lang = "zh") {
  if (!theme) return "";
  return lang === "en" && theme.labelEn ? theme.labelEn : theme.label || "";
}

export const FONTS = [
  { id: "sans", label: "黑体 / Sans" },
  { id: "serif", label: "宋体 / Serif" },
  { id: "rounded", label: "圆体 / Rounded" },
];

export const AI_LANGS = [
  { id: "auto", label: "跟随我" },
  { id: "zh", label: "中文" },
  { id: "en", label: "English" },
  { id: "ja", label: "日本語" },
];

export const UI_LANGS = [
  { id: "zh", label: "简体中文" },
  { id: "en", label: "English" },
];

/* 表情分组。工具盘按组切换，组内顺序就是顺手程度排的，不是在别处排序过的。
   EMOJIS 仍然是这些组的并集：表情面板的九宫格继续用它。 */
export const EMOJI_GROUPS = [
  { id: "face", label: "笑脸", labelEn: "Faces", items: ["😊", "😂", "🥰", "😌", "😴", "🙂", "😉", "🥹"] },
  { id: "soft", label: "撒娇", labelEn: "Soft", items: ["🥺", "😭", "😳", "😤", "🙃", "😢"] },
  { id: "heart", label: "心意", labelEn: "Hearts", items: ["❤️", "🫶", "💕", "💗", "💌", "🌸"] },
  { id: "hand", label: "手势", labelEn: "Hands", items: ["👍", "🙌", "👏", "✌️", "🤝", "👉"] },
  { id: "daily", label: "日常", labelEn: "Daily", items: ["☕", "🍰", "🌙", "✨", "💤", "🎉", "🐱", "🌱", "💬", "🫧"] },
];

export const EMOJIS = EMOJI_GROUPS.flatMap((group) => group.items);

/** Emoji group name in the UI language, falling back to the Chinese label. */
export function emojiGroupLabel(group, lang = "zh") {
  if (!group) return "";
  return lang === "en" && group.labelEn ? group.labelEn : group.label || "";
}

/* Built-in packs supplied by the user. These files are local, transparent
   WebP cut-outs and never count toward the 24-image import limit.
   Adding a pack = one entry here plus its files in assets/stickers/. */
export const BUILTIN_PACKS = [
  {
    id: "menhera_kun",
    name: "menhera君",
    nameEn: "Menhera-kun",
    stickers: [
      { id: "mk_hello", name: "打招呼", file: "mk_hello.webp", mood: "hello" },
      { id: "mk_hello-shy", name: "社恐招呼", file: "mk_hello-shy.webp", mood: "shy" },
      { id: "mk_bye", name: "拜拜", file: "mk_bye.webp", mood: "hello" },
      { id: "mk_morning", name: "早安", file: "mk_morning.webp", mood: "hello" },
      { id: "mk_ok", name: "OK", file: "mk_ok.webp", mood: "ok" },
      { id: "mk_like", name: "点赞", file: "mk_like.webp", mood: "ok" },
      { id: "mk_cheer", name: "加油", file: "mk_cheer.webp", mood: "cheer" },
      { id: "mk_clap", name: "鼓掌", file: "mk_clap.webp", mood: "party" },
      { id: "mk_chuckle", name: "轻笑", file: "mk_chuckle.webp", mood: "laugh" },
      { id: "mk_silly", name: "笨蛋", file: "mk_silly.webp", mood: "laugh" },
      { id: "mk_scheme", name: "鬼点子", file: "mk_scheme.webp", mood: "laugh" },
      { id: "mk_bleh", name: "略~", file: "mk_bleh.webp", mood: "laugh" },
      { id: "mk_watch", name: "看戏", file: "mk_watch.webp", mood: "laugh" },
      { id: "mk_think", name: "思考", file: "mk_think.webp", mood: "question" },
      { id: "mk_what", name: "疑问", file: "mk_what.webp", mood: "question" },
      { id: "mk_peek", name: "偷偷看", file: "mk_peek.webp", mood: "shy" },
      { id: "mk_hide", name: "社恐遮脸", file: "mk_hide.webp", mood: "shy" },
      { id: "mk_box", name: "躲起来", file: "mk_box.webp", mood: "shy" },
      { id: "mk_shy", name: "害羞", file: "mk_shy.webp", mood: "shy" },
      { id: "mk_cat", name: "吸猫", file: "mk_cat.webp", mood: "happy" },
      { id: "mk_meow", name: "喵~", file: "mk_meow.webp", mood: "happy" },
      { id: "mk_yay", name: "耶", file: "mk_yay.webp", mood: "happy" },
      { id: "mk_expect", name: "期待", file: "mk_expect.webp", mood: "happy" },
      { id: "mk_cry", name: "哭哭", file: "mk_cry.webp", mood: "sad" },
      { id: "mk_wronged", name: "委屈", file: "mk_wronged.webp", mood: "sad" },
      { id: "mk_sad", name: "伤心", file: "mk_sad.webp", mood: "sad" },
      { id: "mk_shutdown", name: "自闭", file: "mk_shutdown.webp", mood: "sad" },
      { id: "mk_plead", name: "求求了", file: "mk_plead.webp", mood: "love" },
      { id: "mk_adopt", name: "求收养", file: "mk_adopt.webp", mood: "love" },
      { id: "mk_shock", name: "惊吓", file: "mk_shock.webp", mood: "shock" },
      { id: "mk_surprised", name: "惊讶", file: "mk_surprised.webp", mood: "shock" },
      { id: "mk_wow", name: "哇啊", file: "mk_wow.webp", mood: "shock" },
      { id: "mk_sleep", name: "睡觉", file: "mk_sleep.webp", mood: "sleepy" },
      { id: "mk_sleepy", name: "困", file: "mk_sleepy.webp", mood: "sleepy" },
      { id: "mk_drowsy", name: "犯困", file: "mk_drowsy.webp", mood: "sleepy" },
      { id: "mk_goodnight", name: "晚安", file: "mk_goodnight.webp", mood: "night" },
      { id: "mk_bored", name: "无聊", file: "mk_bored.webp", mood: "bored" },
      { id: "mk_lie", name: "躺平", file: "mk_lie.webp", mood: "bored" },
      { id: "mk_phone", name: "玩手机", file: "mk_phone.webp", mood: "bored" },
      { id: "mk_spy", name: "窥屏", file: "mk_spy.webp", mood: "question" },
      { id: "mk_stare", name: "盯", file: "mk_stare.webp", mood: "angry" },
      { id: "mk_sulk", name: "赌气", file: "mk_sulk.webp", mood: "angry" },
      { id: "mk_hiss", name: "哈气", file: "mk_hiss.webp", mood: "angry" },
      { id: "mk_nope", name: "不行", file: "mk_nope.webp", mood: "angry" },
    ],
  },
  {
    id: "menhera_jiang",
    name: "menhera酱",
    nameEn: "Menhera-chan",
    stickers: [
      { id: "mj_hello", name: "我来啦", file: "mj_hello.webp", mood: "hello" },
      { id: "mj_morning", name: "早啊", file: "mj_morning.webp", mood: "hello" },
      { id: "mj_ok", name: "OK~", file: "mj_ok.webp", mood: "ok" },
      { id: "mj_like", name: "点赞", file: "mj_like.webp", mood: "ok" },
      { id: "mj_agree", name: "赞成", file: "mj_agree.webp", mood: "ok" },
      { id: "mj_promise", name: "交给我", file: "mj_promise.webp", mood: "cheer" },
      { id: "mj_happy", name: "开心", file: "mj_happy.webp", mood: "happy" },
      { id: "mj_peace", name: "比耶", file: "mj_peace.webp", mood: "happy" },
      { id: "mj_meow", name: "喵~", file: "mj_meow.webp", mood: "happy" },
      { id: "mj_love", name: "喜欢", file: "mj_love.webp", mood: "love" },
      { id: "mj_adore", name: "最爱", file: "mj_adore.webp", mood: "love" },
      { id: "mj_pat", name: "摸摸", file: "mj_pat.webp", mood: "love" },
      { id: "mj_plead", name: "祈求", file: "mj_plead.webp", mood: "love" },
      { id: "mj_peek", name: "偷看", file: "mj_peek.webp", mood: "shy" },
      { id: "mj_hmph", name: "哼", file: "mj_hmph.webp", mood: "angry" },
      { id: "mj_angry", name: "生气", file: "mj_angry.webp", mood: "angry" },
      { id: "mj_ng", name: "不行", file: "mj_ng.webp", mood: "angry" },
      { id: "mj_wail", name: "呜呜呜", file: "mj_wail.webp", mood: "sad" },
      { id: "mj_cry", name: "哭泣", file: "mj_cry.webp", mood: "sad" },
      { id: "mj_sorry", name: "对不起", file: "mj_sorry.webp", mood: "sad" },
      { id: "mj_fault", name: "犯错", file: "mj_fault.webp", mood: "sad" },
      { id: "mj_stay", name: "陪我嘛", file: "mj_stay.webp", mood: "sad" },
      { id: "mj_sleepy", name: "困", file: "mj_sleepy.webp", mood: "sleepy" },
      { id: "mj_goodnight", name: "晚安", file: "mj_goodnight.webp", mood: "night" },
      { id: "mj_huh", name: "诶？", file: "mj_huh.webp", mood: "question" },
    ],
  },
];

export const BUILTIN_STICKERS = BUILTIN_PACKS.flatMap((pack) =>
  pack.stickers.map((sticker) => ({ ...sticker, packId: pack.id })),
);

export function builtinPackLabel(pack, lang = "zh") {
  if (!pack) return "";
  return lang === "en" && pack.nameEn ? pack.nameEn : pack.name;
}

/* 1.5–1.9 shipped this character as "猫耳少年" with bi_* ids, and those ids are
   still sitting in saved messages. They resolve through this map, never the
   other way round, so a stored chat keeps its stickers after the rename. */
export const LEGACY_STICKER_IDS = {
  bi_hello: "mk_hello",
  "bi_hello-shy": "mk_hello-shy",
  bi_ok: "mk_ok",
  bi_like: "mk_like",
  bi_cheer: "mk_cheer",
  bi_chuckle: "mk_chuckle",
  bi_silly: "mk_silly",
  bi_think: "mk_think",
  bi_peek: "mk_peek",
  bi_hide: "mk_hide",
  bi_box: "mk_box",
  bi_shy: "mk_shy",
  bi_cat: "mk_cat",
  bi_sleep: "mk_sleep",
  bi_sleepy: "mk_sleepy",
  bi_goodnight: "mk_goodnight",
  bi_phone: "mk_phone",
  bi_bored: "mk_bored",
  bi_cry: "mk_cry",
  bi_wronged: "mk_wronged",
  bi_sad: "mk_sad",
  bi_shutdown: "mk_shutdown",
  bi_shock: "mk_shock",
};

export const USER_STICKER_LIMIT = 24;

export const DEFAULT_GREETING = "你来啦。今天过得怎么样？";

export function defaultState() {
  return {
    version: APP_VERSION,
    onboarded: false,
    setupStep: 0,
    activeChatId: "",
    activeKeyId: "",
    chats: [],
    /* 每个模块最后打开的那条会话：{ companion, roleplay, assistant }。
       会话本身存在 chats[] 里，用 chat.mode 标记归属（见 roleplay.js 的 modeOfChat）。 */
    activeByMode: { companion: "", roleplay: "", assistant: "" },
    keys: [],
    settings: {
      provider: "mimo",
      apiKey: "",
      baseUrl: PROVIDERS.mimo.baseUrl,
      model: PROVIDERS.mimo.model,
      visionModel: "",
      aiName: "Lian",
      aiAvatar: "",
      userName: "你",
      userAvatar: "",
      relationship: "",
      persona: "",
      /* companion：原来的恋人/朋友聊天；roleplay：剧本扮演，允许 *动作* 与（旁白）；
         assistant：纯 AI 助理，没有亲昵称呼，允许列表与代码块。 */
      mode: "companion",
      /* 进助理模式前的那套配色，退出助理模式时换回来 */
      modeTheme: "paper",
      modeAccent: "",
      /* 助理页的两个开关：联网搜索、深度思考（MiMo 原生支持） */
      assistant: { web: false, thinking: false },
      greeting: DEFAULT_GREETING,
      theme: "line",
      accent: THEMES[0].accent,
      font: "sans",
      layout: "line",
      uiLang: "zh",
      aiLang: "auto",
      chatBg: "",
      chatBgOpacity: 0.24,
      optimize: {
        noActions: true,
        segments: false,
        autoSticker: true,
        emoji: true,
        shortReplies: true,
        quotes: true,
        streaming: true,
        drawings: false,
      },
      realism: {
        enabled: true,
        typing: true,
        autoDelay: true,
        minDelay: 1.2,
        maxDelay: 4.5,
        segmentDelay: 0.85,
      },
      blocking: {
        enabled: false,
        minutes: 30,
        mode: "silent",
      },
      memory: {
        auto: false,
      },
      notifications: {
        enabled: false,
        background: false,
      },
      proactive: {
        enabled: false,
        interval: 45,
        lastAt: 0,
      },
    },
    block: null,
    blockFollowUp: null,
    messages: [],
    memories: [],
    memoryMeta: {
      lastUserCount: 0,
      lastAttemptAt: 0,
      lastAt: 0,
    },
    customStickers: [],
    /* 工具盘「最近」用的计数：{ e: 表情, n: 次数, at: 最后一次的时间 }，
       按 at 倒序存，最多 12 条（见 store.js 的清洗与 app.js 的 EMOJI_RECENT_MAX）。 */
    emojiUsage: [],
    stickerStudio: {
      packs: [],
      style: "auto",
      direction: "",
      lastAt: 0,
    },
    meta: {
      createdAt: Date.now(),
      lastUsedAt: 0,
      totalTokens: 0,
      totalCalls: 0,
      lastError: "",
    },
  };
}

export function stickerSrc(sticker) {
  if (!sticker) return "";
  if (sticker.dataUrl) return sticker.dataUrl;
  if (sticker.file) return `assets/stickers/${sticker.file}`;
  return "";
}

export function getSticker(id, customStickers = []) {
  const key = String(id || "").trim();
  if (!key) return null;
  const lower = key.toLowerCase();
  const direct =
    customStickers.find((s) => s.id === key) ||
    customStickers.find((s) => String(s.id || "").toLowerCase() === lower) ||
    BUILTIN_STICKERS.find((s) => s.id === key) ||
    BUILTIN_STICKERS.find((s) => s.id.toLowerCase() === lower);
  if (direct) return direct;
  const renamed = LEGACY_STICKER_IDS[key] || LEGACY_STICKER_IDS[lower];
  return renamed ? BUILTIN_STICKERS.find((s) => s.id === renamed) || null : null;
}

export function estimateReportTokens(messages = []) {
  // A deliberately transparent, approximate number. The provider statement is authoritative.
  // Based on a real MiMo report call: ~730 tokens for a chat with 10 recent messages.
  const context = Math.min(1100, 120 + messages.length * 24);
  return context + 560;
}

export function estimateStickerPackTokens() {
  // Six small JSON recipes, plus a short persona/context prompt.
  return { min: 700, max: 1700 };
}
