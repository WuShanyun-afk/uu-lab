import {
  BUILTIN_PACKS,
  DEFAULT_GREETING,
  EMOJIS,
  EMOJI_GROUPS,
  PROVIDERS,
  THEMES,
  USER_STICKER_LIMIT,
  builtinPackLabel,
  defaultState,
  emojiGroupLabel,
  estimateReportTokens,
  getSticker,
  stickerSrc,
} from "./config.js";
import { t, setLang } from "./i18n.js";
import { chatCompletion, errorText } from "./api.js";
import { loadState, resetStorage, saveNow, scheduleSave } from "./store.js";
import {
  availableStickers,
  buildChatMessages,
  buildQuoteCatalog,
  buildReportMessages,
  chooseAutoSticker,
  moodFromText,
  parseJsonReply,
  parseReply,
} from "./prompt.js";
import { buildMemoryMessages, mergeMemories, parseMemoryReply } from "./memory.js";
import { adoptStoredDrawings, buildHtmlDocument, buildSvgDataUri, drawingLabel, stripSvgSource } from "./drawing.js";
import { CHAT_MODES, MODE_THREADS, ROLEPLAY_PRESETS, chatModeOf, modeOfChat, parseNarration } from "./roleplay.js";
import { accentStrong, mineBubble, normaliseAccent, relativeLuminance } from "./palette.js";
import { buildReportFromRaw, reportBlocksHtml, salvageReport, sanitizeReportHtml } from "./report.js";
import { chatHaystack, matchMessageIndexes, matchSnippet, normaliseQuery, splitByMatches } from "./search.js";
import { chatStats, dailyQuestionIndex, greetingPeriod } from "./insights.js";
import { renderSetup } from "./setup.js";
import { refreshNativeBackgroundUI, renderSettings } from "./settings.js";
import { buildStickerPackMessages, makeStickersFromSpecs, parseStickerPack, svgToDataUrl } from "./studio.js";
import {
  assetBytes,
  assetTypeLabel,
  hostSticker,
  listSandbox,
  removeSandboxAsset,
  sandboxHostStatus,
  sandboxUrl,
  waitForSandboxHost,
} from "./sandbox.js";
import {
  avatarMarkup,
  bindLayerScaffolding,
  closeAllOverlays,
  closeModal,
  closeSheet,
  confirmDialog,
  icon,
  lightboxImage,
  openModal,
  openSheet,
  paintAvatar,
  setLoading,
  showScreen,
  toast,
} from "./ui.js";
import {
  clamp,
  compressImage,
  dataUrlBytes,
  downloadBlob,
  escapeHtml,
  fileToDataUrl,
  formatBytes,
  isEmojiOnly,
  isImageDataUrl,
  isRasterDataUrl,
  loadImage,
  renderRichText,
  sleep,
  uid,
} from "./utils.js";

/* 与 index.html 的 __LIAN_HTML_BUILD__ 对齐；不一致时由页内脚本清缓存重载。 */
window.__LIAN_APP_BUILD__ = "1.9.28";

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

const DEMO_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);

let state = null;
let demoMode = false;
let sending = false;
let reporting = false;
let studioGenerating = false;
let proactiveBusy = false;
let abortController = null;
let segmentAbort = false;
let activeAttachment = null;
let activeQuote = null;
let pendingAvatarRole = null;
let stickerTab = "builtin";
let stickerPack = "all";
let lastFailed = null;
let proactiveTimer = 0;
let blockTicker = 0;
let blockExpiring = false;
let blockCycle = 0;
let blockFollowUpBusy = false;
let blockFollowUpTimer = 0;
let memoryBusy = false;
let memoryTimer = 0;
let headsTimer = 0;
let nativeSnapshotTimer = 0;
let nativePollTimer = 0;
let notificationPrompted = false;
let renderedIds = new Set();
let lastRenderedDay = "";
let typingVisible = false;
let settingsReturnScreen = "chat";
let homeSignature = "";

/* =========================================================
   Multi-chat / multi-key helpers
   ========================================================= */

function currentChat() {
  return state?.chats?.find((chat) => chat.id === state.activeChatId) || null;
}

/** 按 id 找会话。异步任务回来时用它确认目标会话还在。 */
function chatById(id) {
  if (!id) return null;
  return (state?.chats || []).find((chat) => chat.id === id) || null;
}

/** 异步任务出发时的快照：回来时如果 activeChatId 变了，结果要写回原会话。 */
function threadContext() {
  const chat = currentChat();
  return { chat, chatId: chat?.id || "", mode: chatModeOf(state.settings) };
}

function threadStillActive(context) {
  return Boolean(context?.chat) && state.activeChatId === context.chatId
    && (state.chats || []).some((chat) => chat.id === context.chatId);
}

/** 这条会话现在还在冷战里吗（按会话查，不看当前页）。 */
function threadBlocked(context) {
  const block = threadStillActive(context) ? state.block : context?.chat?.block;
  return Boolean(block && Number(block.until) > Date.now());
}

/**
 * 把异步任务的产出写回它出发时的那条会话。
 * 返回 true 表示用户还停在那条会话上（可以立即重画界面）。
 */
function pushToThread(context, message) {
  const target = chatById(context?.chatId) || context?.chat || null;
  if (!target || !Array.isArray(target.messages)) return false;
  target.messages.push(message);
  target.updatedAt = Number(message?.ts) || Date.now();
  return threadStillActive(context);
}

/* =========================================================
   模块会话：陪伴 / 角色扮演 / AI 助理 各自一条线索
   会话存在 state.chats 里，用 chat.mode 标记归属，
   state.activeByMode 记住每个模块最后打开的那条。
   ========================================================= */

function modeThreads(mode) {
  return (state?.chats || []).filter((chat) => modeOfChat(chat) === mode);
}

/** 某个模块当前该打开哪条会话：优先上次打开的那条，否则取最近更新的。 */
function modeThread(mode) {
  const threads = modeThreads(mode);
  if (!threads.length) return null;
  const rememberedId = state.activeByMode?.[mode];
  return threads.find((chat) => chat.id === rememberedId)
    || threads.slice().sort((a, b) => Number(b.updatedAt || 0) - Number(a.updatedAt || 0))[0];
}

function rememberModeThread(mode, id) {
  if (!state.activeByMode || typeof state.activeByMode !== "object") {
    state.activeByMode = { companion: "", roleplay: "", assistant: "" };
  }
  state.activeByMode[mode] = id || "";
}

/** 新建某个模块的第一条会话时用的种子。 */
function modeThreadSeed(mode) {
  const s = state.settings;
  const meta = MODE_THREADS[mode] || MODE_THREADS.companion;
  if (mode === "assistant" || mode === "roleplay") {
    return {
      name: meta.threadNameKey ? t(meta.threadNameKey) : s.aiName || "Lian",
      relationship: "",
      persona: "",
      greeting: meta.greetingKey ? t(meta.greetingKey) : "",
    };
  }
  return {
    name: s.aiName || "Lian",
    relationship: s.relationship || "",
    persona: s.persona || "",
    greeting: s.greeting || DEFAULT_GREETING,
  };
}

function ensureModeThread(mode) {
  const found = modeThread(mode);
  if (found) return found;
  const seed = modeThreadSeed(mode);
  const chat = {
    id: uid("chat"),
    mode,
    kind: mode === "companion" ? "" : "module",
    name: seed.name,
    avatar: "",
    relationship: seed.relationship,
    persona: seed.persona,
    greeting: seed.greeting,
    keyId: state.activeKeyId || "",
    messages: [],
    memories: [],
    memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
    proactiveLastAt: 0,
    block: null,
    blockFollowUp: null,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
  if (seed.greeting) {
    chat.messages.push({ id: uid("m"), role: "assistant", kind: "text", text: seed.greeting, ts: Date.now(), greeting: true });
  }
  state.chats.push(chat);
  rememberModeThread(mode, chat.id);
  return chat;
}

/** 进助理页换「助理」配色，离开时换回进来之前那套（主题 + 色号）。 */
function applyModeTheme(previous, next) {
  const s = state.settings;
  if (previous === next) return;
  if (next === "assistant" && s.theme !== "assistant") {
    s.modeTheme = s.theme || "line";
    /* 色号单独记一份：自定义主题（theme=custom）不在 THEMES 里，
       只存 id 回来时会掉进 THEMES[0]（LINE），用户的颜色就丢了。 */
    s.modeAccent = s.accent || "";
    s.theme = "assistant";
    s.accent = "#2F6BFF";
  } else if (previous === "assistant" && s.theme === "assistant") {
    const back = THEMES.find((theme) => theme.id === s.modeTheme);
    if (back) {
      s.theme = back.id;
      s.accent = back.accent;
    } else {
      s.theme = "custom";
      s.accent = normaliseAccent(s.modeAccent) || THEMES[0].accent;
    }
  }
}

function providerShort(provider) {
  return PROVIDERS[provider]?.short || PROVIDERS[provider]?.label || "Key";
}

/** 服务商 id：设置里选了「自定义」但填的是官方地址时，按地址认回来。 */
function providerIdOf(settings = state?.settings) {
  if (!settings) return "custom";
  const id = settings.provider || "custom";
  if (PROVIDERS[id] && id !== "custom") return id;
  const base = String(settings.baseUrl || "");
  if (/deepseek\.com/i.test(base)) return "deepseek";
  if (/xiaomimimo\.com/i.test(base)) return "mimo";
  if (/api\.openai\.com/i.test(base)) return "openai";
  return id;
}

/** 页头徽记 / 欢迎卡上的字母：一眼看出是哪家服务。 */
function providerMonogram(provider) {
  if (provider === "mimo") return "M";
  if (provider === "openai") return "O";
  if (provider === "deepseek") return "D";
  return t("assistant.monogramCustom") || "AI";
}

/** 一条会话用哪家服务商：由会话绑定的 key 决定，老数据回落到当前设置。 */
function providerOfChat(chat) {
  const key = (state?.keys || []).find((item) => item.id === (chat?.keyId || state.activeKeyId));
  return providerIdOf(key || state?.settings || {});
}

/** 助理页显示服务商名（MiMo / OpenAI / DeepSeek / 自定义）；其它模块用会话自己的名字。 */
function chatDisplayName(chat) {
  if (modeOfChat(chat) === "assistant") return providerShort(providerOfChat(chat));
  return chat?.name || "Lian";
}

/** 联网 / 深度思考由服务商的原生插件提供：MiMo 与 DeepSeek 都支持。 */
function isMimoService(settings = state?.settings) {
  return providerIdOf(settings) === "mimo";
}

function isDeepSeekService(settings = state?.settings) {
  return providerIdOf(settings) === "deepseek";
}

function assistantCapabilities(settings = state?.settings) {
  const provider = providerIdOf(settings);
  const native = provider === "mimo" || provider === "deepseek";
  return { web: native, thinking: native };
}

/** 老 Key 里可能还存着 deepseek-chat / deepseek-reasoner（2026-07 已下线）。 */
function modelForRequest(settings, { vision = false } = {}) {
  let model = String((vision ? settings.visionModel : settings.model) || "").trim();
  const provider = providerIdOf(settings);
  if (provider === "deepseek") {
    if (!model || /^deepseek-(chat|reasoner)$/i.test(model)) model = "deepseek-flash";
    /* 联网工具目前只有 deepseek-flash 支持。 */
    if (settings.assistant?.web) model = "deepseek-flash";
  }
  return model;
}

function keyFromSettings() {
  const s = state.settings;
  return {
    id: uid("key"),
    name: providerShort(s.provider),
    provider: s.provider || "custom",
    apiKey: String(s.apiKey || ""),
    baseUrl: String(s.baseUrl || ""),
    model: String(s.model || ""),
    visionModel: String(s.visionModel || ""),
    createdAt: Date.now(),
  };
}

function applyKeyToSettings(key) {
  if (!key) return;
  state.activeKeyId = key.id;
  const s = state.settings;
  s.provider = key.provider || s.provider;
  s.apiKey = String(key.apiKey || "");
  s.baseUrl = String(key.baseUrl || "");
  s.model = String(key.model || "");
  s.visionModel = String(key.visionModel || "");
}

function chatFromActive() {
  const s = state.settings;
  return {
    id: uid("chat"),
    mode: chatModeOf(s),
    kind: chatModeOf(s) === "companion" ? "" : "module",
    name: s.aiName || "Lian",
    avatar: s.aiAvatar || "",
    relationship: s.relationship || "",
    persona: s.persona || "",
    greeting: s.greeting || DEFAULT_GREETING,
    keyId: state.activeKeyId || "",
    messages: state.messages,
    memories: state.memories,
    memoryMeta: state.memoryMeta,
    proactiveLastAt: Number(s.proactive?.lastAt) || 0,
    block: state.block,
    blockFollowUp: state.blockFollowUp,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
}

function ensureChatState() {
  if (!state) return false;
  let migrated = false;
  if (!Array.isArray(state.keys)) state.keys = [];
  if (!Array.isArray(state.chats)) state.chats = [];
  if (!state.activeByMode || typeof state.activeByMode !== "object") {
    state.activeByMode = { companion: "", roleplay: "", assistant: "" };
    migrated = true;
  }
  for (const mode of CHAT_MODES) {
    if (typeof state.activeByMode[mode] !== "string") {
      state.activeByMode[mode] = "";
      migrated = true;
    }
  }
  if (!state.keys.length && state.settings.apiKey) {
    const key = keyFromSettings();
    state.keys.push(key);
    state.activeKeyId = key.id;
    migrated = true;
  }
  if (!state.activeKeyId && state.keys.length) state.activeKeyId = state.keys[0].id;
  if (state.chats.length) {
    if (!state.chats.some((chat) => chat.id === state.activeChatId)) {
      state.activeChatId = state.chats[0].id;
    }
    const activeChat = currentChat();
    if (activeChat) {
      if (!activeChat.keyId) activeChat.keyId = state.activeKeyId || "";
      if (!state.activeKeyId && activeChat.keyId) state.activeKeyId = activeChat.keyId;
      const mode = modeOfChat(activeChat);
      if (!state.activeByMode[mode]) {
        state.activeByMode[mode] = activeChat.id;
        migrated = true;
      }
    }
  } else if (state.onboarded) {
    const chat = chatFromActive();
    state.chats.push(chat);
    state.activeChatId = chat.id;
    rememberModeThread(modeOfChat(chat), chat.id);
    migrated = true;
  }
  const activeKey = state.keys.find((key) => key.id === state.activeKeyId);
  if (activeKey && !state.settings.apiKey) applyKeyToSettings(activeKey);
  /* 老数据 / 导入的数据里顶层 messages 可能比会话里的更全（1.9.17 之前两者是同一个数组）。
     只有会话是空的才接手，免得覆盖用户刚清空的对话。 */
  const active = currentChat();
  if (active && !(Array.isArray(active.messages) && active.messages.length) && state.messages?.length) {
    active.messages = state.messages;
    migrated = true;
  }
  if (currentChat()) syncActiveThread();
  return migrated;
}

/**
 * 让顶部 state.messages / memories / block 指向「当前会话」。
 * 每个模块一条线索之后，这三样不能再和别的模块共用，所以启动和切换都要走这里。
 */
function syncActiveThread({ force = false } = {}) {
  const chat = currentChat();
  if (!chat) return false;
  const needsLoad = force
    || state.messages !== chat.messages
    || chatModeOf(state.settings) !== modeOfChat(chat);
  if (!needsLoad) {
    syncActiveChat();
    return false;
  }
  loadChatIntoActive(chat);
  return true;
}

function syncActiveKey() {
  if (!state) return;
  if (!Array.isArray(state.keys)) state.keys = [];
  let key = state.keys.find((item) => item.id === state.activeKeyId);
  if (!key && state.settings.apiKey) {
    key = keyFromSettings();
    state.keys.push(key);
    state.activeKeyId = key.id;
  }
  if (!key && state.keys.length) {
    key = state.keys[0];
    applyKeyToSettings(key);
  }
  if (!key) return;
  const s = state.settings;
  key.provider = s.provider || key.provider;
  key.apiKey = String(s.apiKey || "");
  key.baseUrl = String(s.baseUrl || "");
  key.model = String(s.model || "");
  key.visionModel = String(s.visionModel || "");
}

function syncActiveChat() {
  const chat = currentChat();
  if (!chat) return;
  const s = state.settings;
  chat.name = s.aiName || "Lian";
  chat.avatar = s.aiAvatar || "";
  chat.relationship = s.relationship || "";
  chat.persona = s.persona || "";
  chat.greeting = s.greeting || "";
  chat.keyId = state.activeKeyId || "";
  chat.proactiveLastAt = Number(s.proactive?.lastAt) || 0;
  chat.messages = state.messages;
  chat.memories = state.memories;
  chat.memoryMeta = state.memoryMeta;
  chat.block = state.block;
  chat.blockFollowUp = state.blockFollowUp;
  chat.updatedAt = Date.now();
}

function loadChatIntoActive(chat) {
  if (!chat) return;
  const s = state.settings;
  const previousMode = chatModeOf(s);
  const nextMode = modeOfChat(chat);
  state.activeChatId = chat.id;
  s.mode = nextMode;
  applyModeTheme(previousMode, nextMode);
  s.aiName = chat.name || "Lian";
  s.aiAvatar = chat.avatar || "";
  s.relationship = chat.relationship || "";
  s.persona = chat.persona || "";
  /* 陪伴会话没有开场白时补一句默认的；助理 / 剧本要保留「有意留空」，
     否则空的剧本会话会在下次启动被 addGreeting() 写成一句陪伴开场白。 */
  s.greeting = chat.greeting || (nextMode === "companion" ? DEFAULT_GREETING : "");
  state.messages = Array.isArray(chat.messages) ? chat.messages : [];
  state.memories = Array.isArray(chat.memories) ? chat.memories : [];
  state.memoryMeta = chat.memoryMeta && typeof chat.memoryMeta === "object"
    ? chat.memoryMeta
    : { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 };
  state.settings.proactive.lastAt = Number(chat.proactiveLastAt) || 0;
  state.block = chat.block || null;
  state.blockFollowUp = chat.blockFollowUp || null;
  const key = state.keys.find((item) => item.id === chat.keyId)
    || state.keys.find((item) => item.id === state.activeKeyId);
  if (key) applyKeyToSettings(key);
  else {
    state.activeKeyId = "";
    s.apiKey = "";
  }
  rememberModeThread(nextMode, chat.id);
  typingVisible = false;
}

function refreshActiveView() {
  applyAppearance();
  renderHeader();
  updateBlockUI();
  startBlockTicker();
  renderChat({ forceScroll: true });
  startProactiveTimer();
  scheduleNativeSnapshot();
}

function switchChat(id) {
  const chat = state.chats.find((item) => item.id === id);
  if (!chat) return;
  if (id !== state.activeChatId) {
    syncActiveKey();
    syncActiveChat();
    loadChatIntoActive(chat);
    persist();
  }
  showScreen("chat");  closeChatSearch();
  setComposerTray(false);
  refreshActiveView();
  restoreDraft(chat);
  clearUnread(chat);
  requestAnimationFrame(() => $("#messageInput")?.focus());
}

function openChatList() {  openTab("list");
}

function openTab(name) {
  if (!state || !["list", "contacts", "home", "module"].includes(name)) return;
  setComposerTray(false);
  syncActiveKey();
  syncActiveChat();
  persist();
  typingVisible = false;
  showScreen(name);
  document.title = name === "home" ? `${t("tab.home")} · Lian` : name === "contacts" ? `${t("tab.contacts")} · Lian` : name === "module" ? `${t("module.title")} · Lian` : "Lian";
  if (name === "contacts") renderContacts();
  else if (name === "home") renderHome();
  else if (name === "module") {
    try {
      renderModuleHome();
    } catch (error) {
      console.error("module screen failed", error);
      const box = $("#moduleBody");
      if (box) box.innerHTML = `<p class="module-error">模块加载失败，请彻底关闭应用后重新打开。</p>`;
    }
  } else renderChatList();
  startProactiveTimer();
}

function createChat({ name, relationship = "", persona = "", greeting = "", keyId = "", mode = "" }) {
  syncActiveKey();
  syncActiveChat();
  const cleanName = String(name || "").trim().slice(0, 80) || "Lian";
  /* 在角色扮演里新建 = 新开一个剧本；其它情况都是陪伴角色。 */
  const chatMode = CHAT_MODES.includes(mode)
    ? mode
    : chatModeOf(state.settings) === "roleplay" ? "roleplay" : "companion";
  const selectedKey = state.keys.find((item) => item.id === keyId) || state.keys.find((item) => item.id === state.activeKeyId);
  /* 剧本模块第一次打开时建的空会话只是个占位：挑场景时直接用它，
     否则它会永远留在列表里（现在还没有删除会话的入口）。 */
  const placeholder = currentChat();
  const reusePlaceholder = chatMode === "roleplay"
    && placeholder
    && modeOfChat(placeholder) === "roleplay"
    && placeholder.kind === "module"
    && !(placeholder.messages || []).length;
  const chat = reusePlaceholder ? placeholder : {
    id: uid("chat"),
    mode: chatMode,
    kind: chatMode === "companion" ? "" : "module",
    name: cleanName,
    avatar: "",
    relationship: String(relationship || "").slice(0, 300),
    persona: String(persona || "").slice(0, 1200),
    greeting: String(greeting || DEFAULT_GREETING).slice(0, 500),
    keyId: selectedKey?.id || "",
    messages: [],
    memories: [],
    memoryMeta: { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
    proactiveLastAt: 0,
    block: null,
    blockFollowUp: null,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
  if (reusePlaceholder) {
    Object.assign(chat, {
      mode: chatMode,
      kind: "module",
      name: cleanName,
      avatar: "",
      relationship: String(relationship || "").slice(0, 300),
      persona: String(persona || "").slice(0, 1200),
      greeting: String(greeting || DEFAULT_GREETING).slice(0, 500),
      keyId: selectedKey?.id || "",
      updatedAt: Date.now(),
    });
  } else {
    state.chats.push(chat);
  }
  loadChatIntoActive(chat);
  if (chat.greeting) addGreeting();
  persist();
  showScreen("chat");
  refreshActiveView();
  requestAnimationFrame(() => $("#messageInput")?.focus());
}

/* 列表预览不能把 ```js 这类围栏原样露出来；助理的代码块在预览里只留一个记号。 */
function previewSafe(text) {
  return String(text || "")
    .replace(/```[^\n]*\n?[\s\S]*?(```|$)/gi, "〔代码〕")
    .replace(/\s+/g, " ")
    .trim();
}

function chatPreview(chat) {
  const last = chat.messages?.at(-1);
  if (!last) return chat.relationship || t("chat.noMessages");
  if (last.kind === "sticker") {
    const sticker = getSticker(last.stickerId, state.customStickers);
    return `${t("chat.stickerSent")} · ${sticker?.name || ""}`.trim();
  }
  if (last.kind === "image") return last.text || t("chat.photoSent");
  if (last.kind === "file") return last.file?.name || last.text || t("chat.fileSent");
  if (last.kind === "report") return last.report?.title || t("chat.report");
  if (last.kind === "drawing") return last.text || t("chat.drawingSent");
  /* 助理页的招呼统一成一句，旧会话在列表里也不显示旧文案。 */
  if (last.greeting && modeOfChat(chat) === "assistant") return t("module.assistantHello");
  return previewSafe(last.text).slice(0, 60) || t("chat.noMessages");
}

/** 列表里给助理 / 剧本会话加一枚小徽标；陪伴是默认，不加。 */
function modeBadgeMarkup(chat) {
  const mode = modeOfChat(chat);
  const meta = MODE_THREADS[mode];
  if (!meta || mode === "companion") return "";
  return `<i class="chat-mode-badge" data-mode="${mode}">${escapeHtml(t(meta.badgeKey))}</i>`;
}

let listQuery = "";

function searchMarkup(text, query) {
  const source = String(text ?? "");
  if (!query) return escapeHtml(source);
  return splitByMatches(source, query)
    .map((part) => (part.hit ? `<mark class="search-hit">${escapeHtml(part.text)}</mark>` : escapeHtml(part.text)))
    .join("");
}

let listFilter = "all";

function greetingLabel(hour) {
  return t(`list.${greetingPeriod(hour)}`);
}

function renderListHero() {
  const hero = $("#listHero");
  if (!hero) return;
  const stats = chatStats(state.chats);
  const name = state.settings.userName || t("chat.you");
  const date = new Date();
  const dateLabel = date.toLocaleDateString(state.settings.uiLang === "en" ? "en-US" : "zh-CN", {
    month: "short",
    day: "numeric",
    weekday: "short",
  });
  const headline = stats.today
    ? t("list.heroTalked", { name, n: stats.today })
    : t("list.heroQuiet", { name });
  hero.innerHTML = `
    <div class="hero-top">
      <span class="hero-hello">${escapeHtml(greetingLabel(date.getHours()))}</span>
      <span class="hero-date">${escapeHtml(dateLabel)}</span>
    </div>
    <h1 class="hero-title">${escapeHtml(headline)}</h1>
    <div class="hero-chips">
      ${stats.streak ? `<span class="hero-chip is-warm">${icon("sparkle")}${escapeHtml(t("list.streak", { n: stats.streak }))}</span>` : ""}
      <span class="hero-chip">${icon("chat")}${escapeHtml(t("list.chats", { n: stats.chats }))}</span>
      ${stats.unread ? `<span class="hero-chip is-alert">${escapeHtml(t("list.unread", { n: stats.unread }))}</span>` : ""}
    </div>`;
}

function renderListFilters() {
  const box = $("#listFilters");
  if (!box) return;
  const total = state.chats.length;
  const unread = state.chats.reduce((sum, chat) => sum + Math.max(0, Number(chat.unread) || 0), 0);
  if (total <= 1 && !unread) {
    box.hidden = true;
    box.innerHTML = "";
    return;
  }
  box.hidden = false;
  box.innerHTML = `
    <button type="button" class="list-filter ${listFilter === "all" ? "is-on" : ""}" data-list-filter="all">${escapeHtml(t("list.filterAll", { n: total }))}</button>
    <button type="button" class="list-filter ${listFilter === "unread" ? "is-on" : ""}" data-list-filter="unread">${escapeHtml(t("list.filterUnread", { n: unread }))}</button>`;
}

function renderChatList() {
  if (!state) return;
  ensureChatState();
  document.title = "Lian";
  const list = $("#chatList");
  if (!list) return;
  renderListHero();
  renderListFilters();
  const query = normaliseQuery(listQuery);
  const matched = query
    ? state.chats.filter((chat) => `${chatHaystack(chat, chatPreview(chat), chat.messages)} ${chatDisplayName(chat)}`.toLowerCase().includes(query))
    : state.chats;
  const visible = listFilter === "unread" ? matched.filter((chat) => Number(chat.unread) > 0) : matched;
  if (!state.chats.length) {
    list.innerHTML = `<div class="chat-list-empty">
      <span class="empty-symbol">${icon("heart")}</span>
      <b>${escapeHtml(t("chatList.emptyTitle"))}</b>
      <p>${escapeHtml(t("chatList.emptyBody"))}</p>
      <button type="button" class="btn btn-primary" data-new-chat>${escapeHtml(t("chatList.newChat"))}</button>
    </div>`;
    return;
  }
  if (!visible.length) {
    const unreadOnly = listFilter === "unread" && !query;
    list.innerHTML = `<div class="chat-list-empty">
      <span class="empty-symbol">${icon(unreadOnly ? "chat" : "search")}</span>
      <b>${escapeHtml(t(unreadOnly ? "chatList.noUnread" : "chatList.searchEmpty"))}</b>
    </div>`;
    return;
  }
  list.innerHTML = visible
    .slice()
    .sort((a, b) => Number(b.updatedAt || 0) - Number(a.updatedAt || 0))
    .map((chat) => {
      const key = state.keys.find((item) => item.id === chat.keyId);
      const unread = Number(chat.unread) || 0;
      const displayName = chatDisplayName(chat);
      const preview = query ? matchSnippet(chat.messages, query) || chatPreview(chat) : chatPreview(chat);
      return `<button type="button" class="chat-row ${chat.id === state.activeChatId ? "is-active" : ""} ${unread ? "has-unread" : ""}" data-chat-open="${escapeHtml(chat.id)}">
        <span class="chat-row-avatar">${avatarMarkup({ src: chat.avatar, role: "ai", name: displayName, size: 46 })}</span>
        <span class="chat-row-copy">
          <span class="chat-row-top"><b>${searchMarkup(displayName, query)}</b>${modeBadgeMarkup(chat)}${unread ? `<i class="chat-unread">${unread > 99 ? "99+" : unread}</i>` : ""}<time>${escapeHtml(timeLabel(chat.updatedAt || chat.createdAt))}</time></span>
          <small>${searchMarkup(preview, query)}</small>
          <span class="chat-row-foot">${escapeHtml(chat.relationship || t("chatList.noRelation"))}${key ? ` · ${escapeHtml(key.name)}` : ""}</span>
        </span>
      </button>`;
    })
    .join("");
  updateTabBadge();
}

/* =========================================================
   Search — chat list filter + in-chat jump
   ========================================================= */

let chatSearchQuery = "";
let chatMatches = [];
let chatMatchAt = 0;

function openChatSearch() {
  const bar = $("#chatSearchBar");
  if (!bar) return;
  bar.hidden = false;
  const input = $("#chatSearchInput");
  if (input) {
    input.value = "";
    input.focus();
  }
  chatSearchQuery = "";
  chatMatches = [];
  chatMatchAt = 0;
  updateChatSearchCount();
}

function closeChatSearch() {
  const bar = $("#chatSearchBar");
  if (!bar || bar.hidden) return;
  bar.hidden = true;
  const input = $("#chatSearchInput");
  if (input) input.value = "";
  chatSearchQuery = "";
  chatMatches = [];
  chatMatchAt = 0;
  for (const node of Array.from($("#messageList")?.querySelectorAll(".msg.is-hit") || [])) {
    node.classList.remove("is-hit");
  }
}

function updateChatSearchCount() {
  const label = $("#chatSearchCount");
  if (!label) return;
  if (!chatSearchQuery) {
    label.textContent = "";
    return;
  }
  if (!chatMatches.length) {
    label.textContent = t("chat.searchEmpty");
    return;
  }
  label.textContent = t("chat.searchCount", { i: chatMatchAt + 1, n: chatMatches.length });
}

function jumpToChatMatch(index, { instant = false } = {}) {
  const target = chatMatches[index];
  if (target == null) return;
  if (target < renderStart) {
    renderStart = Math.max(0, target - 20);
    rebuildChatWindow();
  }
  const message = state.messages[target];
  if (!message) return;
  const node = Array.from($("#messageList")?.querySelectorAll(".msg") || []).find((el) => el.dataset.message === message.id);
  if (!node) return;
  node.scrollIntoView({ block: "center", behavior: instant ? "auto" : "smooth" });
  node.classList.add("is-hit");
  window.setTimeout(() => node.classList.remove("is-hit"), 1600);
}

function runChatSearch(value) {
  chatSearchQuery = normaliseQuery(value);
  chatMatches = chatSearchQuery ? matchMessageIndexes(state.messages, chatSearchQuery) : [];
  chatMatchAt = chatMatches.length ? chatMatches.length - 1 : 0;
  updateChatSearchCount();
  if (chatMatches.length) jumpToChatMatch(chatMatchAt, { instant: true });
}

function stepChatMatch(delta) {
  if (!chatMatches.length) return;
  chatMatchAt = (chatMatchAt + delta + chatMatches.length) % chatMatches.length;
  updateChatSearchCount();
  jumpToChatMatch(chatMatchAt);
}

function bindSearch() {
  const listInput = $("#listSearchInput");
  listInput?.addEventListener("input", () => {
    listQuery = listInput.value;
    const clear = $("#listSearchClear");
    if (clear) clear.hidden = !listInput.value.trim();
    if (document.body.dataset.screen === "list") renderChatList();
  });
  $("#listSearchClear")?.addEventListener("click", () => {
    listQuery = "";
    if (listInput) {
      listInput.value = "";
      listInput.focus();
    }
    const clear = $("#listSearchClear");
    if (clear) clear.hidden = true;
    renderChatList();
  });

  /* 全部 / 未读 */
  $("#listFilters")?.addEventListener("click", (event) => {
    const chip = event.target.closest("[data-list-filter]");
    if (!chip) return;
    listFilter = chip.dataset.listFilter === "unread" ? "unread" : "all";
    renderChatList();
  });

  $("#btnChatSearch")?.addEventListener("click", () => {
    const bar = $("#chatSearchBar");
    if (!bar) return;
    if (bar.hidden) openChatSearch();
    else $("#chatSearchInput")?.focus();
  });
  const input = $("#chatSearchInput");
  input?.addEventListener("input", () => runChatSearch(input.value));
  input?.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      stepChatMatch(event.shiftKey ? -1 : 1);
    } else if (event.key === "Escape") {
      event.preventDefault();
      closeChatSearch();
    }
  });
  $("#chatSearchNext")?.addEventListener("click", () => stepChatMatch(1));
  $("#chatSearchPrev")?.addEventListener("click", () => stepChatMatch(-1));
  $("#chatSearchClose")?.addEventListener("click", () => closeChatSearch());
  document.addEventListener("keydown", (event) => {
    if (!(event.ctrlKey || event.metaKey) || String(event.key).toLowerCase() !== "f") return;
    if (document.body.dataset.screen !== "chat") return;
    event.preventDefault();
    openChatSearch();
  });
}

let contactsQuery = "";
let contactsSort = "recent";

function contactsMatch(chat, query) {
  if (!query) return true;
  const haystack = [
    chatDisplayName(chat),
    chat.relationship || "",
    chat.persona || "",
    chatPreview(chat),
  ].join(" ").toLowerCase();
  return haystack.includes(query);
}

function renderContacts() {
  if (!state) return;
  ensureChatState();
  const list = $("#contactsList");
  if (!list) return;
  /* 通讯录只放「角色」；助理 / 剧本是独立模块，不混进角色列表。 */
  const characters = state.chats.filter((chat) => modeOfChat(chat) === "companion");
  const query = normaliseQuery(contactsQuery);
  const meta = $("#contactsMeta");
  if (meta) {
    meta.textContent = query
      ? t("contacts.searchMeta", { n: characters.filter((chat) => contactsMatch(chat, query)).length })
      : t("contacts.meta", { n: characters.length });
  }
  const input = $("#contactsSearchInput");
  if (input && input.value !== contactsQuery) input.value = contactsQuery;
  const clear = $("#contactsSearchClear");
  if (clear) clear.hidden = !contactsQuery;
  $$("#contactsSort [data-contacts-sort]").forEach((button) => {
    button.setAttribute("aria-pressed", button.dataset.contactsSort === contactsSort ? "true" : "false");
  });
  if (!characters.length) {
    list.innerHTML = `<div class="chat-list-empty contacts-empty">
      <span class="empty-symbol">${icon("contacts")}</span>
      <b>${escapeHtml(t("contacts.emptyTitle"))}</b>
      <p>${escapeHtml(t("contacts.emptyBody"))}</p>
      <button type="button" class="btn btn-primary" data-new-contact>${escapeHtml(t("contacts.new"))}</button>
    </div>`;
    return;
  }
  const filtered = characters.filter((chat) => contactsMatch(chat, query));
  if (!filtered.length) {
    list.innerHTML = `<div class="chat-list-empty contacts-empty">
      <span class="empty-symbol">${icon("search")}</span>
      <b>${escapeHtml(t("contacts.searchEmptyTitle"))}</b>
      <p>${escapeHtml(t("contacts.searchEmptyBody"))}</p>
      <button type="button" class="btn btn-ghost btn-small" data-contacts-clear>${escapeHtml(t("contacts.clearSearch"))}</button>
    </div>`;
    return;
  }
  const sorted = filtered.slice().sort((a, b) => {
    if (contactsSort === "name") {
      return chatDisplayName(a).localeCompare(chatDisplayName(b), state.settings.uiLang === "en" ? "en" : "zh-CN");
    }
    return Number(b.updatedAt || 0) - Number(a.updatedAt || 0)
      || chatDisplayName(a).localeCompare(chatDisplayName(b), state.settings.uiLang === "en" ? "en" : "zh-CN");
  });
  const group = query ? t("contacts.searchGroup") : "";
  list.innerHTML = `${group ? `<p class="contacts-group-label">${escapeHtml(group)}</p>` : ""}${sorted
    .map((chat) => {
      const last = chat.messages?.at(-1);
      const key = state.keys.find((item) => item.id === chat.keyId);
      const lines = chat.messages?.length || 0;
      const memories = chat.memories?.length || 0;
      const displayName = chatDisplayName(chat);
      const chips = [];
      if (lines) chips.push(t("contacts.lines", { n: lines }));
      if (memories) chips.push(t("contacts.memories", { n: memories }));
      chips.push(last
        ? `${timeLabel(last.ts)}${key ? ` · ${key.name}` : ""}`
        : `${t("chat.noMessages")}${key ? ` · ${key.name}` : ""}`);
      return `<button type="button" class="contact-row ${chat.id === state.activeChatId ? "is-active" : ""}" data-chat-open="${escapeHtml(chat.id)}">
        <span class="contact-avatar">${avatarMarkup({ src: chat.avatar, role: "ai", name: displayName, size: 48 })}</span>
        <span class="contact-copy">
          <span class="contact-top"><b>${escapeHtml(displayName)}</b>${modeBadgeMarkup(chat)}${chat.id === state.activeChatId ? `<i class="contact-now">${escapeHtml(t("contacts.current"))}</i>` : ""}</span>
          <small>${escapeHtml(chat.relationship || t("contacts.noRelation"))}</small>
          <span class="contact-line">${escapeHtml(chatPreview(chat))}</span>
          <span class="contact-chips">
            ${chips.map((chip) => `<i>${escapeHtml(chip)}</i>`).join("")}
          </span>
        </span>
        <span class="contact-enter">›</span>
      </button>`;
    })
    .join("")}
    ${query ? "" : `<button type="button" class="contact-add" data-new-contact>
      <span class="contact-add-icon">${icon("plus")}</span>
      <span><b>${escapeHtml(t("contacts.new"))}</b><small>${escapeHtml(t("contacts.newHint"))}</small></span>
    </button>`}`;
}

function homeRow(action, iconName, title, hint) {
  return `<button type="button" class="home-row" data-home-action="${escapeHtml(action)}">
    <span class="home-row-icon">${icon(iconName)}</span>
    <span class="home-row-copy"><b>${escapeHtml(title)}</b><small>${escapeHtml(hint)}</small></span>
    <span class="home-row-chevron">›</span>
  </button>`;
}

/* 今日一问：每天固定一道（按日期取模），可以当场换一个，点了会填进输入框 */
let dailyShift = 0;

function dailyQuestion() {
  return t(`daily.q${dailyQuestionIndex(Date.now(), dailyShift)}`);
}

function askDailyQuestion() {
  const chat = state.chats.find((item) => item.id === state.activeChatId) || state.chats[0];
  if (!chat) {
    openNewChatSheet();
    return;
  }
  switchChat(chat.id);
  const question = dailyQuestion();
  window.setTimeout(() => {
    const input = $("#messageInput");
    if (!input) return;
    input.value = question;
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.focus();
    input.setSelectionRange(question.length, question.length);
  }, 140);
}

function renderHome(force = false) {
  if (!state) return;
  ensureChatState();
  const body = $("#homeBody");
  if (!body) return;
  const s = state.settings;
  const chatCount = state.chats.length;
  const messageCount = state.chats.reduce((sum, chat) => sum + (chat.messages?.length || 0), 0);
  const memoryCount = state.chats.reduce((sum, chat) => sum + (chat.memories?.length || 0), 0);
  const activeKey = state.keys.find((item) => item.id === state.activeKeyId);
  // Rebuilding this page on every tab switch re-creates 60+ nodes, reloads the
  // avatar <img> and resets the scroll position. Only re-render when something
  // the page actually shows has changed.
  const signature = [
    s.uiLang, s.userName, s.userAvatar,
    chatCount, messageCount, memoryCount, state.memories.length,
    activeKey?.id || "", activeKey?.name || "",
    dailyShift, Math.floor(Date.now() / 86400000),
  ].join("\u0001");
  if (!force && signature === homeSignature && body.childElementCount) return;
  homeSignature = signature;
  body.innerHTML = `
    <section class="home-user-card">
      <div class="home-user-main">
        ${avatarMarkup({ src: s.userAvatar, role: "user", name: s.userName || t("chat.you"), size: 62 })}
        <div class="home-user-copy">
          <span class="home-eyebrow">${escapeHtml(t("home.eyebrow"))}</span>
          <h1>${escapeHtml(s.userName || t("chat.you"))}</h1>
        </div>
        <button type="button" class="home-edit" data-home-action="persona">${escapeHtml(t("home.edit"))}</button>
      </div>
      <div class="home-stats">
        <span><b>${chatCount}</b><small>${escapeHtml(t("home.statChats"))}</small></span>
        <span><b>${messageCount}</b><small>${escapeHtml(t("home.statMessages"))}</small></span>
        <span><b>${memoryCount}</b><small>${escapeHtml(t("home.statMemories"))}</small></span>
      </div>
    </section>

    <section class="home-daily">
      <div class="home-daily-top">
        <span class="home-daily-eyebrow">${escapeHtml(t("home.dailyTitle"))}</span>
        <button type="button" class="home-daily-shuffle" data-daily-shuffle>${icon("sparkle")}${escapeHtml(t("home.dailyShuffle"))}</button>
      </div>
      <p class="home-daily-q">${escapeHtml(dailyQuestion())}</p>
      <button type="button" class="home-daily-ask" data-daily-ask>${escapeHtml(t("home.dailyAsk"))}</button>
    </section>

    <section class="home-panel">
      <div class="home-panel-head"><b>${escapeHtml(t("home.quick"))}</b><small>${escapeHtml(t("home.quickHint"))}</small></div>
      <div class="home-quick-grid">
        <button type="button" class="home-quick" data-home-action="studio">
          <span class="home-quick-icon studio">${icon("sparkle")}</span>
          <b>${escapeHtml(t("studio.title"))}</b>
          <small>${escapeHtml(t("home.quickStudio"))}</small>
        </button>
        <button type="button" class="home-quick" data-home-action="proactive">
          <span class="home-quick-icon warm">${icon("moon")}</span>
          <b>${escapeHtml(t("settings.proactive"))}</b>
          <small>${escapeHtml(t("home.quickProactive"))}</small>
        </button>
        <button type="button" class="home-quick" data-home-action="notifications">
          <span class="home-quick-icon cool">${icon("chat")}</span>
          <b>${escapeHtml(t("settings.notifications"))}</b>
          <small>${escapeHtml(t("home.quickNotify"))}</small>
        </button>
        <button type="button" class="home-quick" data-home-action="report">
          <span class="home-quick-icon paper">${icon("doc")}</span>
          <b>${escapeHtml(t("report.title"))}</b>
          <small>${escapeHtml(t("home.quickReport"))}</small>
        </button>
      </div>
    </section>

    <section class="home-panel">
      <div class="home-panel-head"><b>${escapeHtml(t("home.manage"))}</b><small>${activeKey ? escapeHtml(activeKey.name) : escapeHtml(t("chat.missingKey"))}</small></div>
      <div class="home-menu">
        ${homeRow("persona", "heart", t("settings.persona"), t("settings.personaHint"))}
        ${homeRow("memory", "sparkle", t("settings.memory"), t("settings.memoryHint", { n: state.memories.length }))}
        ${homeRow("experience", "sticker", t("settings.experience"), t("settings.experienceHint"))}
        ${homeRow("realism", "moon", t("settings.realism"), t("settings.realismHint"))}
        ${homeRow("blocking", "moon", t("settings.blocking"), t("settings.blockingHint"))}
        ${homeRow("appearance", "image", t("settings.appearance"), t("settings.appearanceHint"))}
        ${homeRow("connection", "settings", t("settings.connection"), t("settings.connectionHint"))}
        ${homeRow("data", "share", t("settings.data"), t("settings.dataHint"))}
        ${homeRow("about", "doc", t("settings.about"), t("settings.aboutHint"))}
      </div>
    </section>
    <p class="home-foot">${escapeHtml(t("settings.version", { v: "1.9.21" }))} · ${escapeHtml(t("home.localOnly"))}</p>`;
}

/* =========================================================
   Boot
   ========================================================= */

function syncAppHeight() {
  const viewport = window.visualViewport;
  if (!viewport) return;
  const apply = () => {
    const height = Math.round(viewport.height || window.innerHeight || 0);
    if (height > 0) document.documentElement.style.setProperty("--app-height", `${height}px`);
  };
  apply();
  viewport.addEventListener("resize", apply, { passive: true });
}

async function init() {
  bindLayerScaffolding();
  bindGlobalEvents();
  bindMessageMenu();
  bindSearch();
  bindModuleScreen();
  syncAppHeight();

  const params = new URLSearchParams(location.search);
  const preview = DEMO_HOSTS.has(location.hostname) ? params.get("preview") : null;
  const stored = await loadState();

  if (preview) {
    state = makeDemoState(preview);
    demoMode = true;
  } else {
    state = stored || defaultState();
  }

  if (!demoMode) {
    // Upgrading from 1.8 only has settings.apiKey; turn it into a real key and
    // save right away so a force-kill cannot drop the migrated key/chat.
    if (ensureChatState()) persist();
  }
  setLang(state.settings.uiLang);
  /* Old saved replies may still be raw <svg> text from before 1.9.14; turn
     them into pictures (or a note) once, so history stops looking broken. */
  if (adoptDrawingHistory()) persist();
  if (!demoMode) {
    pullNativeMessages();
    reconcileNativeBlockFollowUp();
  }
  applyStaticI18n();
  applyAppearance();
  renderHeader();

  if (demoMode) {
    showScreen(["list", "contacts", "home"].includes(preview) ? preview : "chat");
    if (preview === "setup") {
      state = defaultState();
      demoMode = true;
      showSetup(0);
    } else {
      if (preview === "list") renderChatList();
      else if (preview === "contacts") renderContacts();
      else if (preview === "home") renderHome();
      else renderChat({ forceScroll: true });
      if (preview === "settings") {
        openSettings(params.get("section") || "persona");
      } else if (preview === "studio") {
        openSettings("studio");
      } else if (preview === "report") {
        const report = state.messages.find((m) => m.kind === "report");
        if (report) setTimeout(() => openReportViewer(report), 160);
      }
    }
  } else if (!state.onboarded) {
    showSetup(state.setupStep === 1 ? 1 : 0);
  } else {
    if (!state.messages.length) addGreeting();
    showScreen("list");
    applyAppearance();
    renderChatList();
  }

  updateBlockUI();
  startBlockTicker();
  if (!demoMode && state.blockFollowUp?.pending) {
    window.setTimeout(sendBlockFollowUp, 1200);
  }

  // Reveal on the next frame instead of an artificial 220ms delay, then drop
  // the splash as soon as the fade ends so it cannot hold the first paint.
  requestAnimationFrame(() => requestAnimationFrame(() => {
    const boot = $("#boot");
    if (!boot) return;
    boot.classList.add("is-done");
    window.setTimeout(() => boot.remove(), 240);
  }));

  // Neither of these affects the first screen: run them after it is visible.
  window.setTimeout(() => {
    if (!demoMode) {
      syncNativeRuntime();
      scheduleNativeSnapshot();
      startProactiveTimer();
    }
    if ("serviceWorker" in navigator && location.protocol.startsWith("http")) {
      navigator.serviceWorker.register("sw.js").catch(() => {});
    }
  }, 0);
}

function makeDemoState(kind) {
  const s = defaultState();
  s.onboarded = true;
  s.settings.apiKey = "demo";
  s.settings.aiName = "沈言";
  s.settings.userName = "小满";
  s.settings.relationship = "认识三年的恋人";
  s.settings.persona = "表面冷静克制，实际很会照顾人。说话简短，偶尔嘴硬，习惯先问对方有没有吃饭。";
  s.settings.greeting = "醒了吗？今天不用太赶。";
  s.settings.theme = "line";
  s.settings.optimize.segments = true;
  s.settings.optimize.autoSticker = true;
  s.memories = [
    { id: "mem_demo_1", text: "小满喝咖啡不加糖。", createdAt: Date.now() },
    { id: "mem_demo_2", text: "周三晚上有课，通常会晚一点回消息。", createdAt: Date.now() },
  ];
  const demoPackId = "demo_ai_pack";
  const demoStickers = makeStickersFromSpecs(
    [
      { name: "在", caption: "平常", face: "normal", style: "kaomoji" },
      { name: "好", caption: "开心", face: "happy", style: "kaomoji" },
      { name: "收到", caption: "收到", face: "ok", style: "kaomoji" },
      { name: "贴贴", caption: "贴贴", face: "love", style: "kaomoji" },
      { name: "暗爽", caption: "被夸", face: "proud", style: "kaomoji" },
      { name: "先睡", caption: "睡着", face: "sleepy", style: "kaomoji" },
    ],
    demoPackId,
  );
  const demoEmojiPackId = "demo_emoji_pack";
  const demoEmojiStickers = makeStickersFromSpecs(
    [
      { name: "无语", caption: "无语", emoji: "🙄", color: "#FFF0D9", accent: "#D8A46C", style: "emoji" },
      { name: "收到", caption: "收到", emoji: "🫡", color: "#EAF1E4", accent: "#7FA37B", style: "emoji" },
      { name: "吃瓜", caption: "吃瓜", emoji: "🍉", color: "#FBE7E1", accent: "#D68B82", style: "emoji" },
      { name: "问号", caption: "问号", emoji: "❓", color: "#EDEAF7", accent: "#8B7FB8", style: "emoji" },
      { name: "晚安", caption: "晚安", emoji: "🌙", color: "#E7EAF4", accent: "#7184A7", style: "emoji" },
      { name: "开心", caption: "开心", emoji: "😄", color: "#FFF3CD", accent: "#D6A84F", style: "emoji" },
    ],
    demoEmojiPackId,
  );
  s.customStickers = [...demoStickers, ...demoEmojiStickers];
  s.stickerStudio = {
    packs: [
      {
        id: demoPackId,
        name: "猫猫头的日常",
        theme: "只有一颗深炭黑猫猫头，情绪全交给奶白颜文字；粉色小鼻子和腮红。",
        source: "ai",
        createdAt: Date.now(),
        stickerIds: demoStickers.map((sticker) => sticker.id),
        assetIds: [],
        equipped: true,
      },
      {
        id: demoEmojiPackId,
        name: "奶油柴犬的吐槽",
        theme: "不是猫。奶油色、欠欠的 emoji 梗图，专治聊天里的无语瞬间。",
        source: "ai",
        createdAt: Date.now() - 7200_000,
        stickerIds: demoEmojiStickers.map((sticker) => sticker.id),
        assetIds: [],
        equipped: true,
      },
    ],
    style: "auto",
    direction: "想要一套奶油色柴犬的吐槽表情，不要猫",
    lastAt: Date.now(),
  };
  const now = Date.now();
  const mins = (n) => now - n * 60 * 1000;
  s.keys = [{
    id: "key_demo",
    name: "MiMo 主号",
    provider: "mimo",
    apiKey: "demo",
    baseUrl: "https://api.xiaomimimo.com/v1",
    model: "mimo-v2.6-flash",
    visionModel: "",
    createdAt: now,
  }];
  s.activeKeyId = "key_demo";
  s.messages = [
    { id: "demo_1", role: "assistant", kind: "text", text: "醒了吗？今天不用太赶。", ts: mins(58) },
    { id: "demo_2", role: "user", kind: "text", text: "刚醒……不想起床 😴", ts: mins(55) },
    { id: "demo_3", role: "assistant", kind: "text", text: "那就再赖五分钟。", ts: mins(54) },
    { id: "demo_3b", role: "assistant", kind: "text", text: "我帮你看着时间。", ts: mins(54) },
    { id: "demo_4", role: "assistant", kind: "sticker", stickerId: demoStickers[5].id, ts: mins(54) },
    {
      id: "demo_5",
      role: "user",
      kind: "text",
      text: "你今天忙吗",
      ts: mins(41),
      quote: { id: "demo_3", role: "assistant", name: "沈言", text: "那就再赖五分钟。" },
    },
    { id: "demo_6", role: "assistant", kind: "text", text: "上午有个会，其他还好。", ts: mins(40) },
    { id: "demo_7", role: "assistant", kind: "text", text: "午饭记得吃。", ts: mins(40) },
    { id: "demo_8", role: "assistant", kind: "sticker", stickerId: demoStickers[1].id, ts: mins(40) },
    { id: "demo_9", role: "user", kind: "text", text: "🥺", ts: mins(18) },
    {
      id: "demo_10",
      role: "assistant",
      kind: "text",
      text: "怎么了，没睡好吗？",
      ts: mins(17),
      quote: { id: "demo_9", role: "user", name: "小满", text: "🥺" },
    },
    { id: "demo_10b", role: "assistant", kind: "sticker", stickerId: "mk_chuckle", ts: mins(16) },
    {
      id: "demo_report",
      role: "assistant",
      kind: "report",
      ts: mins(6),
      report: {
        title: "窗边的一点光",
        summary: "会开完了，窗外的光很好。想把这一刻留给你。",
        html: `<h2>窗边的一点光</h2><p>会刚结束。会议室的人走光了，我没有立刻起身，坐了一会儿。</p><p>窗外那棵树被风吹得很轻，光落在桌角。忽然想起你早上说不想起床，不知道现在有没有好好吃饭。</p><blockquote>我这边一切都好。你不用急着回。</blockquote><small>下午还有一点事，忙完就来找你。</small>`,
      },
    },
  ];
  s.chats = [{
    id: "chat_demo",
    name: s.settings.aiName,
    avatar: "",
    relationship: s.settings.relationship,
    persona: s.settings.persona,
    greeting: s.settings.greeting,
    keyId: s.activeKeyId,
    messages: s.messages,
    memories: s.memories,
    memoryMeta: s.memoryMeta,
    block: null,
    blockFollowUp: null,
    createdAt: now,
    updatedAt: now,
  }, {
    id: "chat_demo_2",
    name: "林知夏",
    avatar: "",
    relationship: "楼下的花店老板",
    persona: "说话轻，喜欢用短句，记得别人随口提过的小事。",
    greeting: "今天路过花店，看到一束很像你的颜色。",
    keyId: s.activeKeyId,
    messages: [
      { id: "demo2_1", role: "assistant", kind: "text", text: "今天路过花店，看到一束很像你的颜色。", ts: now - 3 * 60 * 60 * 1000 },
      { id: "demo2_2", role: "user", kind: "text", text: "什么颜色", ts: now - 2.8 * 60 * 60 * 1000 },
      { id: "demo2_3", role: "assistant", kind: "text", text: "很浅的橘色。像下午四点的光。", ts: now - 2.7 * 60 * 60 * 1000 },
    ],
    memories: [],
    memoryMeta: { lastUserCount: 1, lastAttemptAt: 0, lastAt: 0 },
    block: null,
    blockFollowUp: null,
    createdAt: now - 4 * 60 * 60 * 1000,
    updatedAt: now - 2.7 * 60 * 60 * 1000,
  }];
  s.activeChatId = "chat_demo";
  return s;
}

/* =========================================================
   Appearance / language / header
   ========================================================= */

function contrastInk(hex) {
  const value = String(hex || "").replace("#", "");
  if (!/^[0-9a-f]{6}$/i.test(value)) return "#fff";
  const r = parseInt(value.slice(0, 2), 16) / 255;
  const g = parseInt(value.slice(2, 4), 16) / 255;
  const b = parseInt(value.slice(4, 6), 16) / 255;
  const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return lum > 0.58 ? "#111111" : "#ffffff";
}

function applyAppearance() {
  if (!state) return;
  const s = state.settings;
  const theme = THEMES.find((item) => item.id === s.theme);
  const immersive = Boolean(theme?.immersive);
  const accent = /^#[0-9a-f]{6}$/i.test(s.accent || "") ? s.accent : theme?.accent || "#06C755";
  const root = document.documentElement;
  root.style.setProperty("--accent", accent);
  root.style.setProperty("--accent-ink", contrastInk(accent));
  const bubble = theme?.bubble
    ? { bg: theme.bubble.bg, ink: theme.bubble.ink }
    : mineBubble(accent);
  root.style.setProperty("--bubble-mine", bubble.bg);
  root.style.setProperty("--bubble-mine-ink", bubble.ink);
  root.style.setProperty("--accent-strong", accentStrong(accent));
  root.style.setProperty("--chat-bg", theme?.bg || (s.theme === "custom" ? "#efefea" : "#e9ece5"));
  document.body.dataset.font = s.font || "sans";
  document.body.dataset.theme = s.theme || "line";
  document.body.dataset.layout = s.layout || "line";
  document.body.dataset.mode = chatModeOf(s);
  syncChatCrest();
  const background = s.chatBg || (immersive ? new URL(theme.defaultBg, document.baseURI).href : "");
  if (background) {
    root.style.setProperty("--chat-bg-image", `url("${background}")`);
    root.style.setProperty("--chat-bg-opacity", immersive ? "1" : String(clamp(Number(s.chatBgOpacity) || 0.24, 0.05, 0.75)));
  } else {
    root.style.removeProperty("--chat-bg-image");
    root.style.setProperty("--chat-bg-opacity", "0");
  }
  syncThemeColor();
  bindThemeColor();
  document.title = state.onboarded && s.aiName ? `${s.aiName} · Lian` : "Lian";
}

/* =========================================================
   模块：AI 助理 / 角色扮演 的入口页
   ========================================================= */

const MODULE_CARDS = [
  { id: "assistant", icon: "sparkle", nameKey: "module.assistantName", descKey: "module.assistantDesc" },
  { id: "roleplay", icon: "heart", nameKey: "module.roleplayName", descKey: "module.roleplayDesc" },
];

function moduleThreadInfo(mode) {
  const thread = modeThread(mode);
  if (!thread) return { text: t("module.threadEmpty"), count: 0 };
  const messages = thread.messages || [];
  const preview = messages.length ? chatPreview(thread) : "";
  const short = preview.length > 24 ? `${preview.slice(0, 24)}…` : preview;
  return {
    text: `${t("module.threadCount", { n: messages.length })}${short ? ` · ${short}` : ""}`,
    count: messages.length,
  };
}

function renderModuleHome() {
  const box = $("#moduleBody");
  if (!box || !state) return;
  const current = chatModeOf(state.settings);
  const scripts = state.chats.filter((chat) => modeOfChat(chat) === "roleplay").length;
  box.innerHTML = MODULE_CARDS.map((card) => {
    const on = card.id === current;
    const info = moduleThreadInfo(card.id);
    const thread = modeThread(card.id);
    let meta = info.text;
    if (card.id === "assistant" && thread) {
      const key = state.keys.find((item) => item.id === (thread.keyId || state.activeKeyId));
      const provider = providerShort(providerOfChat(thread));
      const model = String(key?.model || state.settings.model || "").trim();
      meta = [provider, model].filter(Boolean).join(" · ");
      if (info.count) meta += ` · ${t("module.threadCount", { n: info.count })}`;
    } else if (card.id === "roleplay") {
      const count = scripts ? t("module.scriptCount", { n: scripts }) : t("module.scriptEmpty");
      meta = info.count ? `${count} · ${info.text}` : count;
    }
    return `<button type="button" class="module-card${on ? " is-on" : ""}" data-module-pick="${card.id}" aria-pressed="${on}">
      <span class="module-card-icon">${icon(card.icon)}</span>
      <span class="module-card-copy">
        <b>${escapeHtml(t(card.nameKey))}</b>
        <small>${escapeHtml(t(card.descKey))}</small>
        <em class="module-card-thread">${escapeHtml(meta)}</em>
      </span>
      <span class="module-card-state">${escapeHtml(on ? t("module.current") : info.count ? t("module.use") : t("module.start"))}</span>
    </button>`;
  }).join("") + `<button type="button" class="module-characters" data-module-characters>${escapeHtml(t("module.charactersNote"))} <span aria-hidden="true">→</span></button>`;
}

function openModuleChat() {
  if (state.chats?.length) {
    showScreen("chat");
    renderHeader();
    renderChat({ force: true, forceScroll: true });
    return;
  }
  openTab("list");
}

function bindModuleScreen() {
  $("#moduleBody")?.addEventListener("click", (event) => {
    if (event.target.closest("[data-module-characters]")) {
      openTab("contacts");
      return;
    }
    const card = event.target.closest("[data-module-pick]");
    if (!card) return;
    setChatMode(card.dataset.modulePick);
    openModuleChat();
  });
  $("#btnModuleChat")?.addEventListener("click", () => openModuleChat());
  /* 消息列表里只剩代码复制、助理回答的「⋯」和剧本页的「挑剧本」。 */
  $("#messageList")?.addEventListener("click", (event) => {
    const more = event.target.closest("[data-msg-menu]");
    if (more) {
      openMessageMenu(more.dataset.msgMenu, more);
      return;
    }
    const button = event.target.closest("[data-copy-code]");
    if (button) {
      const code = button.closest(".msg-code")?.querySelector("code")?.textContent || "";
      if (code) copyText(code);
      return;
    }
    if (event.target.closest("[data-open-scenes]")) openNewChatSheet();
  });
}

/* 切换模块：每个模块有自己的会话（chats[].mode），
   所以这里不只是换提示词，而是把当前会话存起来、把目标模块的会话读进来。
   进助理页顺手换成「助理」主题，退出时换回原来的那套（见 applyModeTheme）。 */
function setChatMode(mode) {
  if (!state) return;
  const next = CHAT_MODES.includes(mode) ? mode : "companion";
  const previous = chatModeOf(state.settings);
  const alreadyThere = next === previous && modeOfChat(currentChat()) === next;
  if (alreadyThere) return;
  syncActiveKey();
  syncActiveChat();
  const target = ensureModeThread(next);
  loadChatIntoActive(target);
  persist();
  applyAppearance();
  renderHeader();
  updateBlockUI();
  startBlockTicker();
  startProactiveTimer();
  /* narration styling is baked into each bubble, so the list must be rebuilt */
  renderChat({ force: true, forceScroll: true });
  renderSettings(settingsCallbacks());
  if (document.body.dataset.screen === "module") renderModuleHome();
  toast(t(`mode.toast.${next}`));
}

/* The letter layout opens with a small "the two of you" crest above the sheet.
   Built from settings so it follows avatar / name changes; every other layout
   keeps the node empty and hidden. */
function syncChatCrest() {
  const crest = document.querySelector("#chatCrest");
  if (!crest || !state) return;
  const s = state.settings;
  if ((s.layout || "line") !== "letter") {
    crest.hidden = true;
    crest.innerHTML = "";
    return;
  }
  crest.hidden = false;
  crest.innerHTML = `
    <div class="crest-pair">
      ${avatarMarkup({ src: s.aiAvatar, role: "ai", name: s.aiName, size: 50, extra: "crest-avatar" })}
      ${avatarMarkup({ src: s.userAvatar, role: "user", name: s.userName, size: 50, extra: "crest-avatar" })}
    </div>
    <p class="crest-names"><b>${escapeHtml(s.aiName || "Lian")}</b><i>·</i><b>${escapeHtml(s.userName || "你")}</b></p>
    <p class="crest-note">${escapeHtml(s.relationship || "")}</p>`;
}

/* Status-bar / browser chrome colour. The meta tag cannot be driven by CSS, so
   it follows the same rules as the surfaces: immersive themes use their own
   colour, 纸间 switches to 夜幕纸 in dark mode, everything else is white. */
const darkScheme = typeof window.matchMedia === "function" ? window.matchMedia("(prefers-color-scheme: dark)") : null;
let themeColorBound = false;

function syncThemeColor() {
  if (!state) return;
  const theme = THEMES.find((item) => item.id === state.settings.theme);
  const dark = Boolean(darkScheme?.matches);
  let color = "#ffffff";
  if (theme?.statusBar) color = theme.statusBar;
  else if (theme?.immersive) color = theme.bg;
  else if (theme?.id === "paper") color = dark ? "#14130d" : "#fbf9f1";
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.content = color;
  syncNativeSystemBars(color);
}

/* Inside the APK there is no browser chrome, so the meta tag does nothing;
   the system bars are painted by MainActivity. Keep them in step. */
function syncNativeSystemBars(color) {
  const bridge = typeof window.LianNative !== "undefined" ? window.LianNative : null;
  if (!bridge || typeof bridge.setSystemBars !== "function") return;
  try {
    bridge.setSystemBars(color, relativeLuminance(color) > 0.5);
  } catch {
    /* bridge is best-effort; a failure must never break boot */
  }
}

function bindThemeColor() {
  if (themeColorBound || !darkScheme) return;
  themeColorBound = true;
  const onChange = () => syncThemeColor();
  if (typeof darkScheme.addEventListener === "function") darkScheme.addEventListener("change", onChange);
  else if (typeof darkScheme.addListener === "function") darkScheme.addListener(onChange);
}

function applyStaticI18n() {
  if (!state) return;
  setLang(state.settings.uiLang);
  document.documentElement.lang = state.settings.uiLang === "en" ? "en" : "zh-CN";
  $$("[data-i18n]").forEach((el) => {
    const key = el.dataset.i18n;
    const value = t(key);
    /* 缺词时保留 HTML 里的中文，绝不把 key 直接印到界面上。 */
    if (value && value !== key) el.textContent = value;
  });
  $$("[data-i18n-ph]").forEach((el) => {
    const value = t(el.dataset.i18nPh);
    if (value && value !== el.dataset.i18nPh) el.placeholder = value;
  });
  $$("[data-i18n-aria]").forEach((el) => {
    const value = t(el.dataset.i18nAria);
    if (value && value !== el.dataset.i18nAria) el.setAttribute("aria-label", value);
  });
  const input = $("#messageInput");
  if (input) {
    input.placeholder = chatModeOf(state.settings) === "assistant" ? t("chat.placeholderAssistant") : t("chat.placeholder");
    autoResizeInput(input);
  }
}

function renderHeader() {
  if (!state) return;
  const s = state.settings;
  const assistant = chatModeOf(s) === "assistant";
  /* 助理页不继承恋人名字：标题直接显示服务商，避免「沈砚 · AI 助理」这种混搭。 */
  const name = assistant ? providerShort(providerIdOf(s)) : s.aiName || "Lian";
  const aiAvatar = $("#headerAvatar");
  paintAvatar(aiAvatar, { src: s.aiAvatar, role: "ai", name });
  const peerName = $("#peerName");
  if (peerName) peerName.textContent = name;
  /* 页头徽记：深墨砖 + 服务商首字母，比通用星形更有产品身份。 */
  const mark = $("#peerMark");
  if (mark) {
    const provider = providerIdOf(s);
    mark.dataset.provider = provider;
    mark.textContent = assistant ? providerMonogram(provider) : "";
  }
  /* 助理页页头只留徽记 + 服务商名：不挂「AI 助理」小标、不挂模型副标题。 */
  const badge = $("#peerBadge");
  if (badge) badge.hidden = true;
  const sub = $("#peerSub");
  if (sub) {
    sub.textContent = "";
    sub.hidden = true;
  }
  syncAssistantTools();
  updatePeerStatus();
  const input = $("#messageInput");
  if (input) input.placeholder = assistant ? t("chat.placeholderAssistant") : t("chat.placeholder");
  const screen = document.body.dataset.screen;
  if (screen === "chat") document.title = state.onboarded ? `${name} · Lian` : "Lian";
  else if (screen === "contacts") document.title = `${t("tab.contacts")} · Lian`;
  else if (screen === "home") document.title = `${t("tab.home")} · Lian`;
  else document.title = "Lian";
}

function updatePeerStatus() {
  if (!state) return;
  const status = $("#peerStatus");
  const note = $("#peerNote");
  document.body.dataset.thinking = typingVisible ? "1" : "0";
  syncAssistantThinking();
  if (status) {
    const typing = typingVisible && state.settings.realism?.typing !== false;
    const blocked = isBlocked();
    const mode = state.block?.mode || state.settings.blocking?.mode;
    status.textContent = typing
      ? t("chat.typing")
      : blocked
        ? t(mode === "reject" ? "chat.coldWarReject" : "chat.coldWarSilent")
        : t("chat.online");
    status.classList.toggle("is-typing", typing);
    status.classList.toggle("is-blocked", blocked);
  }
  if (note) note.textContent = demoMode ? t("chat.demoMode") : "";
}

/* =========================================================
   Setup
   ========================================================= */

function setupCallbacks() {
  return {
    state,
    onChange: () => {
      persist();
      renderHeader();
    },
    onStart: () => {
      if (!state.messages.length) addGreeting();
      state.onboarded = true;
      ensureChatState();
      persist();
      showScreen("chat");
      applyAppearance();
      renderHeader();
      renderChat({ forceScroll: true });
      updateBlockUI();
      startBlockTicker();
      startProactiveTimer();
      requestAnimationFrame(() => $("#messageInput")?.focus());
    },
    onPickAvatar: (role) => pickAvatar(role),
    onDemo: () => {},
  };
}

function showSetup(step = 0) {
  state.setupStep = step === 1 ? 1 : 0;
  showScreen("setup");
  renderSetup(setupCallbacks());
}

function addGreeting() {
  /* 只有陪伴会「没有开场白也补一句」；助理 / 剧本的空会话要一直空着
     （剧本先挑场景，助理的问候在建会话时就写好了）。 */
  const fallback = chatModeOf(state.settings) === "companion" ? DEFAULT_GREETING : "";
  const text = String(state.settings.greeting || fallback).trim();
  if (!text) return;
  state.messages.push({
    id: uid("m"),
    role: "assistant",
    kind: "text",
    text,
    ts: Date.now(),
    greeting: true,
  });
  persist();
}

/* =========================================================
   Chat rendering
   ========================================================= */

function dayLabel(ts) {
  const d = new Date(ts);
  const now = new Date();
  const same = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  if (same(d, now)) return t("chat.today");
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (same(d, yesterday)) return t("chat.yesterday");
  try {
    return new Intl.DateTimeFormat(state.settings.uiLang === "en" ? "en-US" : "zh-CN", {
      month: "short",
      day: "numeric",
      weekday: "short",
    }).format(d);
  } catch {
    return d.toLocaleDateString();
  }
}

function timeLabel(ts) {
  const d = new Date(ts);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

function notificationPreview(message) {
  if (!message) return "";
  if (message.kind === "sticker") {
    const sticker = getSticker(message.stickerId, state.customStickers);
    return `${t("chat.stickerSent")} · ${sticker?.name || ""}`.trim();
  }
  if (message.kind === "image") return message.text || t("chat.photoSent");
  if (message.kind === "file") return message.file?.name || message.text || t("chat.fileSent");
  if (message.kind === "report") return message.report?.title || t("chat.report");
  if (message.kind === "drawing") return message.text || t("chat.drawingSent");
  return String(message.text || "").trim().slice(0, 140);
}

function hideHeadsUp() {
  clearTimeout(headsTimer);
  const box = $("#headsUp");
  if (!box) return;
  box.classList.remove("is-on");
  window.setTimeout(() => {
    if (box.classList.contains("is-on")) return;
    box.hidden = true;
  }, 220);
}

function showHeadsUp(message) {
  const box = $("#headsUp");
  if (!box || !state) return;
  clearTimeout(headsTimer);
  const avatar = $("#headsAvatar");
  const title = $("#headsTitle");
  const body = $("#headsBody");
  if (avatar) {
    avatar.innerHTML = avatarMarkup({
      src: state.settings.aiAvatar,
      role: "ai",
      name: state.settings.aiName || "Lian",
      size: 36,
    });
  }
  if (title) title.textContent = state.settings.aiName || "Lian";
  if (body) body.textContent = notificationPreview(message) || t("chat.notifyTitle", { name: state.settings.aiName || "Lian" });
  box.dataset.message = message?.id || "";
  box.hidden = false;
  requestAnimationFrame(() => box.classList.add("is-on"));
  headsTimer = window.setTimeout(hideHeadsUp, 4800);
}

async function showSystemNotification(message) {
  if (!state?.settings.notifications?.enabled) return;
  const title = t("chat.notifyTitle", { name: state.settings.aiName || "Lian" });
  const body = notificationPreview(message);
  if (window.LianNative?.notify) {
    try {
      window.LianNative.notify(title, body);
      return;
    } catch {
      // fall through to the browser notification API
    }
  }
  if (!("Notification" in window) || Notification.permission !== "granted") return;
  try {
    if (navigator.serviceWorker?.ready) {
      const registration = await navigator.serviceWorker.ready;
      await registration.showNotification(title, {
        body,
        icon: "assets/icons/icon-192.png",
        badge: "assets/icons/favicon.png",
        tag: "lian-message",
        data: { messageId: message?.id || "" },
      });
    } else {
      const notice = new Notification(title, { body, icon: "assets/icons/icon-192.png", tag: "lian-message" });
      notice.onclick = () => window.focus();
    }
  } catch {
    // Notifications are best-effort; the in-app UI still works.
  }
}

function notifyUser(message) {
  if (!state?.settings.notifications?.enabled) return;
  if (document.visibilityState === "visible") showHeadsUp(message);
  else showSystemNotification(message);
}

function messageAvatar(message) {
  const s = state.settings;
  /* The user's own avatar is rendered but hidden by default: app.css keeps
     .msg.user .avatar switched off, and the "both" avatar mode shows it. */
  if (message.role === "user") {
    return avatarMarkup({ src: s.userAvatar, role: "user", name: s.userName, size: 28, extra: "msg-avatar" });
  }
  return avatarMarkup({ src: s.aiAvatar, role: "ai", name: s.aiName, size: 28, extra: "msg-avatar" });
}

function fileCard(message) {
  const file = message.file || {};
  const label = escapeHtml(file.name || t("chat.file"));
  const size = escapeHtml(file.sizeLabel || formatBytes(file.size || 0));
  const data = file.dataUrl || "";
  const action = data
    ? `<a class="file-dl" href="${escapeHtml(data)}" download="${label}" aria-label="download">${icon("download")}</a>`
    : `<span class="file-dl">${icon("file")}</span>`;
  return `<div class="file-card">
    <span class="file-icon">${icon("file")}</span>
    <span class="file-meta"><span class="file-name">${label}</span><span class="file-size">${size}</span></span>
    ${action}
  </div>`;
}

function imageBubble(message) {
  const image = message.image || {};
  if (!image.dataUrl) {
    return `<div class="bubble-image" style="padding:14px;max-width:180px"><span class="hint-inline">${escapeHtml(t("chat.image"))}</span></div>`;
  }
  return `<button type="button" class="bubble-image" data-image="${escapeHtml(message.id)}" aria-label="${escapeHtml(message.text || t("chat.image"))}">
    <img src="${escapeHtml(image.dataUrl)}" alt="${escapeHtml(message.text || t("chat.image"))}"
         width="${Number(image.width) || 1}" height="${Number(image.height) || 1}">
  </button>`;
}

function stickerMarkup(message) {
  const sticker = getSticker(message.stickerId, state.customStickers);
  if (!sticker) return `<div class="bubble is-missing">${escapeHtml(t("chat.stickerMissing"))}</div>`;
  return `<button type="button" class="msg-sticker" data-sticker-view="${escapeHtml(message.id)}" aria-label="${escapeHtml(sticker.name || "sticker")}">
    <img src="${escapeHtml(stickerSrc(sticker))}" alt="${escapeHtml(sticker.name || "")}" loading="lazy">
  </button>`;
}

function reportMarkup(message) {
  const report = message.report || {};
  return `<button type="button" class="report-card" data-report="${escapeHtml(message.id)}">
    <span class="report-card-top">
      <span class="report-badge">${escapeHtml(t("chat.reportBadge"))}</span>
      <span class="report-mini">${escapeHtml(timeLabel(message.ts))}</span>
    </span>
    <h3>${escapeHtml(report.title || t("report.titleFallback"))}</h3>
    <p>${escapeHtml(report.summary || "")}</p>
    <span class="report-card-foot"><span>${escapeHtml(t("chat.report"))}</span><b>${escapeHtml(t("report.view"))} →</b></span>
  </button>`;
}

function drawingMarkup(message) {
  const drawing = message.drawing || {};
  const label = escapeHtml(t("chat.drawing"));
  const open = escapeHtml(t("chat.drawingOpen"));
  if (drawing.type === "html") {
    // sandbox="" gives the frame no scripts, no same-origin access, no forms.
    return `<div class="msg-art is-html">
      <iframe class="msg-art-frame" sandbox="" referrerpolicy="no-referrer" scrolling="no" title="${label}" srcdoc="${escapeHtml(buildHtmlDocument(drawing.markup || ""))}"></iframe>
      <button type="button" class="msg-art-zoom" data-drawing-view="${escapeHtml(message.id)}" aria-label="${open}">${icon("expand")}</button>
    </div>`;
  }
  return `<button type="button" class="msg-art is-svg" data-drawing-view="${escapeHtml(message.id)}" aria-label="${label}">
    <img src="${escapeHtml(buildSvgDataUri(drawing.markup || ""))}" alt="${label}" loading="lazy" draggable="false">
  </button>`;
}

function quoteBlockMarkup(quote) {
  if (!quote?.text) return "";
  const name = quote.name || (quote.role === "user" ? state.settings.userName : state.settings.aiName) || t("chat.you");
  return `<div class="msg-quote ${quote.role === "user" ? "from-user" : "from-ai"}">
    <span class="msg-quote-name">${escapeHtml(name)}</span>
    <span class="msg-quote-text">${escapeHtml(String(quote.text).slice(0, 120))}</span>
  </div>`;
}

/* Two messages from the same speaker within this window are rendered as one
   group (single avatar, tighter spacing). */
const GROUP_WINDOW = 4 * 60 * 1000;

function sameGroup(previous, message) {
  if (!previous) return false;
  if (previous.role !== message.role) return false;
  if (previous.kind === "report" || message.kind === "report") return false;
  const gap = Math.abs(Number(message.ts || 0) - Number(previous.ts || 0));
  return gap > 0 && gap <= GROUP_WINDOW;
}

function renderNarrationMarkup(text) {
  const blocks = [];
  for (const line of String(text || "").split("\n")) {
    if (!line.trim()) continue;
    for (const piece of parseNarration(line)) {
      if (piece.type === "action") blocks.push(`<p class="rp-action">${escapeHtml(piece.text)}</p>`);
      else if (piece.type === "narration") blocks.push(`<p class="rp-narration">${escapeHtml(piece.text)}</p>`);
      else blocks.push(`<p class="rp-line">${renderRichText(piece.text)}</p>`);
    }
  }
  return blocks.join("");
}

/* 助理页面：正文按段落铺开，代码块单独成块并给一个复制按钮。
 * 1.9.20 起再往前一步：标题 / 列表 / 引用 / 表格 / 粗斜体都认，
 * 代码块带头部语言、行数和复制，答案下面有「复制 / 重新生成」。 */
const ASSISTANT_CODE_LANGS = new Set([
  "js", "jsx", "ts", "tsx", "html", "css", "json", "bash", "sh", "zsh", "shell",
  "py", "python", "sql", "java", "go", "rust", "rs", "c", "cpp", "csharp", "cs",
  "yaml", "yml", "md", "markdown", "diff", "text", "txt",
]);

/** 行内格式：先抽出代码与链接，避免 `*` / `_` 误伤 URL，再还原。 */
function assistantInline(text) {
  const codes = [];
  const links = [];
  let html = escapeHtml(String(text || ""));
  html = html.replace(/`([^`\n]{1,200})`/g, (match, code) => {
    codes.push(code);
    return `\u0000C${codes.length - 1}\u0000`;
  });
  html = html.replace(/(https?:\/\/[^\s<]+[^\s<.,:;!?，。！？；：])/g, (match, url) => {
    links.push(url);
    return `\u0000L${links.length - 1}\u0000`;
  });
  html = html
    .replace(/\*\*([^*\n]{1,180})\*\*/g, "<strong>$1</strong>")
    .replace(/__([^_\n]{1,180})__/g, "<strong>$1</strong>")
    .replace(/(^|[^*])\*([^*\n]{1,180})\*(?!\*)/g, "$1<em>$2</em>")
    .replace(/(^|[^_])_([^_\n]{1,180})_(?!_)/g, "$1<em>$2</em>");
  html = html.replace(/\u0000C(\d+)\u0000/g, (match, index) => `<code class="as-inline">${codes[Number(index)]}</code>`);
  return html.replace(/\u0000L(\d+)\u0000/g, (match, index) => {
    const url = links[Number(index)];
    const safe = url.replaceAll("&amp;", "&");
    return `<a href="${safe}" target="_blank" rel="noopener noreferrer">${url}</a>`;
  });
}

function assistantCodeBlock(lang, body) {
  const language = String(lang || "code").toLowerCase();
  const code = String(body || "").replace(/\s+$/, "");
  const lines = code ? code.split("\n").length : 0;
  return `<div class="msg-code" data-lang="${escapeHtml(language)}">
    <div class="msg-code-head">
      <span class="msg-code-lang">${escapeHtml(language)}</span>
      <em class="msg-code-lines">${escapeHtml(t("assistant.codeLines", { n: lines }))}</em>
      <button type="button" class="msg-code-copy" data-copy-code>${escapeHtml(t("common.copy"))}</button>
    </div>
    <pre><code>${escapeHtml(code)}</code></pre>
  </div>`;
}

function assistantTableMarkup(header, rows) {
  return `<div class="as-table-wrap"><table class="as-table">
    <thead><tr>${header.map((cell) => `<th>${assistantInline(cell)}</th>`).join("")}</tr></thead>
    <tbody>${rows
      .map((row) => `<tr>${header.map((cell, index) => `<td>${assistantInline(row[index] || "")}</td>`).join("")}</tr>`)
      .join("")}</tbody>
  </table></div>`;
}

/** 段落 / 标题 / 列表 / 引用 / 表格 / 分隔线，逐行解析。 */
function renderAssistantBlocks(text) {
  const lines = String(text || "").split("\n");
  const out = [];
  let index = 0;
  const rowCells = (line) => line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((cell) => cell.trim());
  while (index < lines.length) {
    const line = lines[index];
    if (!line.trim()) {
      index += 1;
      continue;
    }
    const heading = line.match(/^(#{1,4})\s+(.+)$/);
    if (heading) {
      const level = Math.min(4, heading[1].length + 1);
      out.push(`<h${level} class="as-h as-h${heading[1].length}">${assistantInline(heading[2].trim())}</h${level}>`);
      index += 1;
      continue;
    }
    if (/^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/.test(line)) {
      out.push('<hr class="as-rule">');
      index += 1;
      continue;
    }
    if (line.includes("|") && index + 1 < lines.length && /^\s*\|?[\s:|-]+\|?\s*$/.test(lines[index + 1]) && lines[index + 1].includes("-")) {
      const header = rowCells(line);
      const rows = [];
      index += 2;
      while (index < lines.length && lines[index].includes("|") && lines[index].trim()) {
        rows.push(rowCells(lines[index]));
        index += 1;
      }
      out.push(assistantTableMarkup(header, rows));
      continue;
    }
    if (/^\s*[-*•]\s+/.test(line)) {
      const items = [];
      while (index < lines.length && /^\s*[-*•]\s+/.test(lines[index])) {
        items.push(lines[index].replace(/^\s*[-*•]\s+/, ""));
        index += 1;
      }
      out.push(`<ul class="as-list">${items.map((item) => `<li>${assistantInline(item)}</li>`).join("")}</ul>`);
      continue;
    }
    if (/^\s*\d+[.)]\s+/.test(line)) {
      const items = [];
      while (index < lines.length && /^\s*\d+[.)]\s+/.test(lines[index])) {
        items.push(lines[index].replace(/^\s*\d+[.)]\s+/, ""));
        index += 1;
      }
      out.push(`<ol class="as-list">${items.map((item) => `<li>${assistantInline(item)}</li>`).join("")}</ol>`);
      continue;
    }
    if (/^\s*>\s?/.test(line)) {
      const quote = [];
      while (index < lines.length && /^\s*>\s?/.test(lines[index])) {
        quote.push(lines[index].replace(/^\s*>\s?/, ""));
        index += 1;
      }
      out.push(`<blockquote class="as-quote">${quote.map((item) => assistantInline(item)).join("<br>")}</blockquote>`);
      continue;
    }
    out.push(`<p class="as-line">${assistantInline(line.trim())}</p>`);
    index += 1;
  }
  return out.join("");
}

function renderAssistantMarkup(text) {
  const source = String(text || "");
  const parts = [];
  const fence = /```([\w+#.-]*)[ \t]*\r?\n([\s\S]*?)```/g;
  let index = 0;
  let match = fence.exec(source);
  while (match) {
    if (match.index > index) parts.push(renderAssistantBlocks(source.slice(index, match.index)));
    parts.push(assistantCodeBlock(match[1], match[2]));
    index = match.index + match[0].length;
    match = fence.exec(source);
  }
  if (index < source.length) parts.push(renderAssistantBlocks(source.slice(index)));
  return parts.join("") || assistantInline(source);
}

/** 深度思考的折叠面板：默认收起，不挡住答案。 */
function assistantReasoningMarkup(message) {
  const text = String(message.reasoning || "").trim().slice(0, 12000);
  if (!text) return "";
  const chars = [...String(message.reasoning || "").trim()].length;
  return `<details class="as-think">
    <summary><span>${escapeHtml(t("assistant.reasoning"))}</span><em>${escapeHtml(t("assistant.reasoningChars", { n: chars }))}</em></summary>
    <div class="as-think-body">${escapeHtml(text).replace(/\n/g, "<br>")}</div>
  </details>`;
}

/** 联网来源：只留站点名，点开新窗口；不加载远端 favicon。 */
function assistantSourcesMarkup(message) {
  const sources = (message.sources || []).filter((source) => source?.url && /^https?:\/\//i.test(source.url));
  if (!sources.length) return "";
  return `<div class="as-sources">
    <span class="as-sources-label">${escapeHtml(t("assistant.webSources"))}</span>
    ${sources
      .slice(0, 5)
      .map((source) => {
        let host = "";
        try { host = new URL(source.url).hostname.replace(/^www\./, ""); } catch { host = ""; }
        const label = source.siteName || host || source.title || source.url;
        return `<a href="${escapeHtml(source.url)}" target="_blank" rel="noopener noreferrer" title="${escapeHtml(source.title || label)}">${escapeHtml(label)}</a>`;
      })
      .join("")}
  </div>`;
}

function syncAssistantThinking() {
  const list = $("#messageList");
  if (!list || !state) return;
  const show = chatModeOf(state.settings) === "assistant" && typingVisible;
  const caps = assistantCapabilities();
  const toggles = state.settings.assistant || {};
  const label = caps.thinking && toggles.thinking
    ? t("assistant.deepThinking")
    : caps.web && toggles.web ? t("assistant.webSearching") : t("assistant.thinking");
  const existing = list.querySelector("#asThinking");
  if (!show) {
    existing?.remove();
    return;
  }
  if (existing) {
    const textNode = existing.querySelector("span:last-child");
    if (textNode) textNode.textContent = label;
    return;
  }
  const node = document.createElement("div");
  node.id = "asThinking";
  node.className = "as-thinking";
  node.innerHTML = `<span class="as-thinking-dots" aria-hidden="true"><i></i><i></i><i></i></span><span>${escapeHtml(label)}</span>`;
  list.append(node);
  scrollToBottom(false);
}

/** 输入栏上方的「联网 / 深度思考」两个开关；非助理模式整条收起。 */
function syncAssistantTools() {
  const box = $("#assistantTools");
  if (!box || !state) return;
  const assistant = chatModeOf(state.settings) === "assistant";
  box.hidden = !assistant;
  if (!assistant) return;
  const caps = assistantCapabilities();
  const toggles = state.settings.assistant || {};
  box.querySelectorAll("[data-assistant-tool]").forEach((button) => {
    const key = button.dataset.assistantTool;
    const supported = Boolean(caps[key]);
    button.disabled = !supported;
    button.setAttribute("aria-pressed", supported && toggles[key] ? "true" : "false");
    button.title = supported ? "" : t("assistant.capabilityMimoOnly");
  });
}

/** 助理页只留两个能力开关和等待提示，其余装饰全部收掉。 */
function syncAssistantExtras() {
  if (!state) return;
  syncAssistantThinking();
  syncAssistantTools();
  /* 招呼只在空会话里出现：第一句提问之后，即使列表是增量追加，
     也要把已经渲染的招呼节点摘掉。 */
  if (chatModeOf(state.settings) === "assistant" && (state.messages || []).some((item) => item.role === "user")) {
    $("#messageList")?.querySelectorAll(".as-hello").forEach((node) => node.remove());
  }
}

function messageMarkup(message, isNew, previous = null) {
  const s = state.settings;
  const mode = chatModeOf(s);
  /* 助理页的招呼只在真正空着时出现；一旦有过提问，它就从列表里退场。 */
  if (mode === "assistant" && message.greeting
    && (state.messages || []).some((item) => item.role === "user")) return "";
  const role = message.role === "user" ? "user" : "assistant";
  const side = role === "user" ? "user" : "ai";
  const avatar = messageAvatar(message);
  const quote = quoteBlockMarkup(message.quote);
  const refused = message.delivery === "refused";
  const deliveryNote = refused
    ? `<span class="delivery-note"><i>!</i>${escapeHtml(t("chat.refused"))}</span>`
    : "";
  let content = "";
  let extraClass = "";

  if (message.kind === "sticker") {
    content = stickerMarkup(message);
  } else if (message.kind === "image") {
    content = imageBubble(message);
  } else if (message.kind === "file") {
    content = fileCard(message);
  } else if (message.kind === "report") {
    content = reportMarkup(message);
  } else if (message.kind === "drawing") {
    content = drawingMarkup(message);
  } else {
    let text = String(message.text || "");
    if (mode === "assistant" && message.greeting) {
      /* 助理页不摆欢迎卡：打开就是一句「你好，需要什么帮助吗？」 */
      content = `<div class="as-hello">${escapeHtml(t("module.assistantHello"))}</div>`;
    } else {
      /* roleplay: 旁白、动作、台词各占一行；assistant: 段落 + 代码块 */
      /* a stray svg block must never be printed as text, whatever the source.
         助理页例外：那里代码就是内容，问「这段 svg 哪错了」时必须看得见源码。 */
      if (mode !== "assistant" && /<svg\b/i.test(text)) text = stripSvgSource(text) || t("chat.drawingBroken");
      const emoji = isEmojiOnly(text);
      extraClass = emoji ? "is-emoji" : "";
      const body = emoji
        ? renderRichText(text)
        : mode === "roleplay"
          ? renderNarrationMarkup(text)
          : mode === "assistant"
            ? renderAssistantMarkup(text)
            : renderRichText(text);
      content = `<div class="bubble ${extraClass}">${body}</div>`;
    }
  }
  if ((message.kind === "image" || message.kind === "file") && String(message.text || "").trim()) {
    content += `<div class="bubble">${renderRichText(String(message.text).trim())}</div>`;
  }
  /* 助理页只留思考过程和来源；时间、小标、复制 / 重新生成都收进长按菜单。
     流式预览只是临时气泡，不挂这些。 */
  if (mode === "assistant" && message.kind !== "report" && message.id !== "live_preview" && !message.greeting) {
    const reasoning = message.kind === "text" ? assistantReasoningMarkup(message) : "";
    const sources = message.kind === "text" ? assistantSourcesMarkup(message) : "";
    content = `${reasoning}${content}${sources}`;
    /* 回答末尾一枚很轻的「⋯」：不用长按也能找到复制 / 重新生成。 */
    if (role === "assistant" && message.kind === "text" && String(message.text || "").trim()) {
      content += `<div class="as-more-row"><button type="button" class="as-more" data-msg-menu="${escapeHtml(message.id)}" aria-label="${escapeHtml(t("common.more"))}">${icon("more")}</button></div>`;
    }
  }

  const time = message.kind === "sticker" || message.kind === "report" ? "" : `<span class="msg-time">${escapeHtml(timeLabel(message.ts))}</span>`;
  const grouped = sameGroup(previous, message);
  /* The bubble layout labels every group with who is speaking, the way QQ does.
     The node always exists so switching layouts never needs a re-render. */
  const senderName = role === "user" ? s.userName : s.aiName;
  return `<div class="msg ${side} ${refused ? "is-refused" : ""} ${grouped ? "is-grouped" : ""} ${isNew ? "is-new" : ""}" data-message="${escapeHtml(message.id)}">
    ${avatar}
    <div class="msg-body">
      <div class="msg-stack"><span class="msg-name">${escapeHtml(senderName || "")}</span>${quote}${content}${deliveryNote}</div>
      ${time}
    </div>
    <button type="button" class="msg-reply" data-quote="${escapeHtml(message.id)}" title="${escapeHtml(t("chat.quoteReply"))}" aria-label="${escapeHtml(t("chat.quoteReply"))}">${icon("reply")}</button>
  </div>`;
}

const RENDER_WINDOW = 120;
let renderedChatId = "";
let renderStart = 0;
let renderedEnd = 0;
let renderedSig = "";

function messageSignature(message) {
  return [
    message.id,
    message.kind || "",
    message.delivery || "",
    String(message.text || "").length,
    message.ts || 0,
    message.report?.createdAt || 0,
    message.stickerId || "",
    String(message.reasoning || "").length,
    (message.sources || []).length,
  ].join(":");
}

function rangeSignature(messages, from, to) {
  let signature = `${from}|`;
  for (let index = from; index < to; index += 1) signature += `${messageSignature(messages[index])};`;
  return signature;
}

function chatEmptyMarkup() {
  const mode = chatModeOf(state.settings);
  /* 助理页空着时不摆图标和按钮，只有一句招呼。 */
  if (mode === "assistant") {
    return `<div class="as-hello">${escapeHtml(t("module.assistantHello"))}</div>`;
  }
  const hint = mode === "roleplay" ? t("chat.emptyRoleplay") : t("chat.emptyHint");
  /* 剧本页空着的时候，第一步不是打字，是挑一张剧本。 */
  const action = mode === "roleplay"
    ? `<button type="button" class="btn btn-ghost btn-small empty-action" data-open-scenes>${escapeHtml(t("chat.pickScene"))}</button>`
    : "";
  return `<div class="empty-chat">
      <img class="empty-mark" src="assets/icons/icon.svg" alt="">
      <p>${escapeHtml(hint)}</p>
      ${action}
    </div>`;
}

function chatMessagesMarkup(messages, from, { animateId = null } = {}) {
  let html = "";
  let lastDay = from > 0 ? lastRenderedDay : "";
  const newIds = new Set();
  for (let index = from; index < messages.length; index += 1) {
    const message = messages[index];
    const day = new Date(message.ts).toDateString();
    if (day !== lastDay) {
      const label = dayLabel(message.ts);
      if (label !== lastDay) html += `<div class="date-sep"><span>${escapeHtml(label)}</span></div>`;
      lastDay = day;
    }
    const isNew = !renderedIds.has(message.id);
    if (isNew) newIds.add(message.id);
    html += messageMarkup(message, isNew || animateId === message.id, messages[index - 1]);
  }
  if (lastDay) lastRenderedDay = lastDay;
  for (const id of newIds) renderedIds.add(id);
  return html;
}

function loadEarlierMarkup() {
  if (renderStart <= 0) return "";
  return `<button type="button" class="load-earlier" data-load-earlier>${escapeHtml(t("chat.loadEarlier"))}</button>`;
}

function rebuildChatWindow({ forceScroll = false, animateId = null } = {}) {
  const list = $("#messageList");
  const scroll = $("#chatScroll");
  const messages = state.messages;
  list.innerHTML = loadEarlierMarkup() + chatMessagesMarkup(messages, renderStart, { animateId });
  renderedEnd = messages.length;
  renderedSig = rangeSignature(messages, renderStart, renderedEnd);
  if (forceScroll) scrollToBottom(false);
  updateJumpButton();
}

function renderChat({ forceScroll = false, animateId = null, force = false } = {}) {
  const list = $("#messageList");
  const scroll = $("#chatScroll");
  if (!list || !scroll) return;
  const messages = state.messages;
  const previousDistance = scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight;
  const wasNearBottom = previousDistance < 180;

  const chatChanged = renderedChatId !== state.activeChatId;
  if (chatChanged) {
    renderedIds = new Set();
    lastRenderedDay = "";
    renderedChatId = state.activeChatId;
    renderStart = Math.max(0, messages.length - RENDER_WINDOW);
    renderedEnd = renderStart;
    renderedSig = "";
  }

  if (!messages.length) {
    list.innerHTML = chatEmptyMarkup();
    renderedIds = new Set();
    lastRenderedDay = "";
    renderedEnd = 0;
    renderStart = 0;
    renderedSig = "";
    syncAssistantExtras();
    updateJumpButton();
    return;
  }

  const stillSame = !force && !chatChanged && renderedEnd >= renderStart && renderedEnd <= messages.length
    && renderedSig === rangeSignature(messages, renderStart, renderedEnd);

  // Nothing new on screen: keep the DOM untouched (this is the common case
  // after a message was already appended by the caller).
  if (stillSame && renderedEnd === messages.length) {
    syncAssistantExtras();
    if (forceScroll) scrollToBottom(false);
    updateJumpButton();
    return;
  }

  // Only new messages at the tail: append instead of re-parsing the whole list.
  if (stillSame && renderedEnd < messages.length) {
    list.insertAdjacentHTML("beforeend", chatMessagesMarkup(messages, renderedEnd, { animateId }));
    renderedEnd = messages.length;
    renderedSig = rangeSignature(messages, renderStart, renderedEnd);
    syncAssistantExtras();
    if (forceScroll || wasNearBottom) scrollToBottom(false);
    updateJumpButton();
    return;
  }

  rebuildChatWindow({ forceScroll: forceScroll || wasNearBottom, animateId });
  syncAssistantExtras();
  if (forceScroll || wasNearBottom) scrollToBottom(false);
}

function loadEarlierMessages() {
  if (renderStart <= 0) return;
  const scroll = $("#chatScroll");
  const keep = scroll ? scroll.scrollHeight - scroll.scrollTop : 0;
  renderStart = Math.max(0, renderStart - 80);
  rebuildChatWindow();
  requestAnimationFrame(() => {
    if (scroll) scroll.scrollTop = scroll.scrollHeight - keep;
    updateJumpButton();
  });
}

function scrollToBottom(smooth = false) {
  const scroll = $("#chatScroll");
  if (!scroll) return;
  requestAnimationFrame(() => {
    scroll.scrollTo({ top: scroll.scrollHeight, behavior: smooth ? "smooth" : "auto" });
    updateJumpButton();
  });
}

function updateJumpButton() {
  const scroll = $("#chatScroll");
  const button = $("#jumpLatest");
  if (!scroll || !button) return;
  const distance = scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight;
  button.hidden = distance < 220 || state.messages.length === 0;
}

function showTyping(show) {
  const next = Boolean(show && state?.settings?.realism?.typing !== false);
  if (typingVisible === next) return;
  typingVisible = next;
  updatePeerStatus();
}

function isBlocked() {
  return Boolean(state?.block && Number(state.block.until) > Date.now());
}

function blockRemainingLabel(ms) {
  const total = Math.max(0, Math.ceil(ms / 1000));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  if (hours > 0) return `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function updateSettingsBlockStatus() {
  if (document.body.dataset.screen !== "settings") return;
  const row = document.querySelector("[data-blocked-row]");
  if (!row) return;
  if (!isBlocked()) {
    row.remove();
    return;
  }
  const label = row.querySelector("[data-blocked-label]");
  if (label) {
    label.textContent = t("settings.blockingActive", {
      time: blockRemainingLabel(state.block.until - Date.now()),
    });
  }
}

function expireBlockIfNeeded() {
  if (!state?.block || isBlocked() || blockExpiring) return false;
  blockExpiring = true;
  try {
    // Do not clear the block here: the old implementation silently dropped
    // the follow-up when a render happened before the 1s ticker.
    clearBlock({ silent: true, followUp: true });
  } finally {
    blockExpiring = false;
  }
  return true;
}

function updateBlockUI() {
  if (!state) return;
  if (state.block && !isBlocked()) {
    expireBlockIfNeeded();
    return;
  }
  const blocked = isBlocked();
  const row = $("#composerRow");
  // Both block styles keep the composer usable: silent mode sends normally
  // without a reply, reject mode marks the outgoing message as refused.
  if (row) row.hidden = false;
  document.body.classList.toggle("is-blocked", blocked);
  updatePeerStatus();
  updateSendButton();
}

function startBlockTicker() {
  clearInterval(blockTicker);
  blockTicker = 0;
  if (!isBlocked()) return;
  blockTicker = window.setInterval(() => {
    if (!isBlocked()) {
      expireBlockIfNeeded();
      return;
    }
    updateSettingsBlockStatus();
  }, 1000);
}

function applyBlock(minutes, { chatId = "" } = {}) {
  const safeMinutes = Math.min(1440, Math.max(1, Number(minutes) || 30));
  const block = {
    until: Date.now() + safeMinutes * 60_000,
    minutes: safeMinutes,
    createdAt: Date.now(),
    mode: state.settings.blocking?.mode === "reject" ? "reject" : "silent",
  };
  /* 回复可能在用户切走之后才回来：冷战要落在发起那场对话里，不能改别人。 */
  if (chatId && chatId !== state.activeChatId) {
    const target = chatById(chatId);
    if (!target) return;
    target.block = block;
    target.blockFollowUp = null;
    persist();
    return;
  }
  blockCycle += 1;
  clearTimeout(blockFollowUpTimer);
  blockFollowUpTimer = 0;
  state.block = block;
  state.blockFollowUp = null;
  activeQuote = null;
  activeAttachment = null;
  renderQuotePreview();
  renderAttachmentPreview();
  $("#messageInput")?.blur();
  persist();
  updateBlockUI();
  startBlockTicker();
  toast(t("block.started", { minutes: safeMinutes }), { timeout: 5200 });
}

function clearBlock({ silent = false, followUp = false } = {}) {
  const wasBlocked = Boolean(state?.block);
  if (state) {
    state.block = null;
    if (wasBlocked) blockCycle += 1;
    if (wasBlocked && followUp) {
      state.blockFollowUp = { pending: true, endedAt: Date.now(), attempts: 0 };
    }
  }
  clearInterval(blockTicker);
  blockTicker = 0;
  persist();
  updateBlockUI();
  if (wasBlocked && !silent) toast(t("block.ended"));
  if (document.body.dataset.screen === "settings") renderSettings(settingsCallbacks());
  if (wasBlocked && followUp) sendBlockFollowUp();
}

function scheduleBlockFollowUp(delay = 30_000) {
  clearTimeout(blockFollowUpTimer);
  blockFollowUpTimer = window.setTimeout(() => {
    blockFollowUpTimer = 0;
    if (!state?.blockFollowUp?.pending || isBlocked()) return;
    sendBlockFollowUp();
  }, delay);
}

async function sendBlockFollowUp() {
  if (!state?.blockFollowUp?.pending || blockFollowUpBusy) return;
  if (demoMode || !state.settings.apiKey) {
    state.blockFollowUp = null;
    persist();
    return;
  }
  if (sending || reporting || studioGenerating) {
    scheduleBlockFollowUp(1500);
    return;
  }
  blockFollowUpBusy = true;
  const cycle = blockCycle;
  if (state.blockFollowUp) state.blockFollowUp.inFlight = true;
  persist();
  proactiveBusy = true;
  try {
    await requestAssistant(null, { proactive: true, afterBlock: true });
    if (cycle !== blockCycle || isBlocked()) return;
    if (lastFailed?.afterBlock) {
      // Keep pending=true so closing the app during a failed request will
      // retry on the next launch instead of silently losing the message.
      if (state.blockFollowUp) {
        state.blockFollowUp.pending = true;
        state.blockFollowUp.inFlight = false;
        state.blockFollowUp.attempts = Number(state.blockFollowUp.attempts || 0) + 1;
        persist();
      }
      scheduleBlockFollowUp(Math.min(120_000, 20_000 * Math.max(1, state.blockFollowUp?.attempts || 1)));
      return;
    }
    if (state.blockFollowUp) {
      state.blockFollowUp.pending = false;
      state.blockFollowUp.inFlight = false;
      state.blockFollowUp.endedAt = Date.now();
      persist();
    }
  } finally {
    blockFollowUpBusy = false;
    proactiveBusy = false;
  }
}

/* =========================================================
   Persistence
   ========================================================= */

function persist() {
  if (!state || demoMode) return;
  syncActiveKey();
  syncActiveChat();
  scheduleSave(state);
  scheduleNativeSnapshot();
}

/**
 * One-time repair of replies saved as raw svg text (before 1.9.14). Returns
 * true when something changed so the caller can save.
 */
function adoptDrawingHistory() {
  if (!state) return false;
  const note = t("chat.drawingBroken");
  let changed = false;
  const fix = (list) => {
    /* 只修「AI 以前把画存成文字」的情况；用户贴的代码原样保留。 */
    const result = adoptStoredDrawings(list, { note, roles: ["assistant"] });
    if (result.changed) changed = true;
    return result.messages;
  };
  /* 助理页是要看代码的：把那里的历史转成画等于把源码删了。 */
  for (const chat of state.chats || []) {
    if (modeOfChat(chat) === "assistant") continue;
    chat.messages = fix(chat.messages);
  }
  const active = currentChat();
  state.messages = active ? active.messages : fix(state.messages);
  return changed;
}

function nativeSnapshot() {
  if (!state) return null;
  const s = state.settings;
  return {
    chatId: state.activeChatId || "",
    chatName: s.aiName || "Lian",
    settings: {
      provider: s.provider,
      apiKey: s.apiKey,
      baseUrl: s.baseUrl,
      model: s.model,
      aiName: s.aiName,
      userName: s.userName,
      /* 后台主动消息只在陪伴模式发；原生层按这个字段判断。 */
      mode: chatModeOf(s),
      relationship: s.relationship,
      persona: s.persona,
      greeting: s.greeting,
      optimize: s.optimize,
      realism: s.realism,
      blocking: s.blocking,
      notifications: s.notifications,
      proactive: s.proactive,
    },
    messages: (state.messages || []).slice(-30).map((message) => ({
      id: message.id,
      role: message.role,
      kind: message.kind,
      text: String(message.text || "").slice(0, 600),
      ts: message.ts,
      stickerId: message.stickerId || "",
      file: message.file ? { name: message.file.name } : null,
      report: message.report ? { title: message.report.title } : null,
      delivery: message.delivery || "",
    })),
    memories: (state.memories || []).map((memory) => ({ id: memory.id, text: memory.text })),
    block: state.block,
    blockFollowUp: state.blockFollowUp,
  };
}

function scheduleNativeSnapshot() {
  clearTimeout(nativeSnapshotTimer);
  nativeSnapshotTimer = window.setTimeout(() => {
    nativeSnapshotTimer = 0;
    if (demoMode || !window.LianNative?.saveSnapshot) return;
    try {
      window.LianNative.saveSnapshot(JSON.stringify(nativeSnapshot()));
    } catch {
      // The bridge is optional; web builds simply skip it.
    }
  }, 350);
}

function flushNativeSnapshot() {
  clearTimeout(nativeSnapshotTimer);
  nativeSnapshotTimer = 0;
  if (demoMode || !window.LianNative?.saveSnapshot) return;
  try {
    window.LianNative.saveSnapshot(JSON.stringify(nativeSnapshot()));
  } catch {
    // The bridge is optional; web builds simply skip it.
  }
}

function syncNativeRuntime() {
  if (!state) return;
  startNativePoll();
  if (window.LianNative?.setBackgroundEnabled) {
    try {
      window.LianNative.setBackgroundEnabled(Boolean(state.settings.notifications?.background));
    } catch {
      // ignore
    }
  }
  if (state.settings.notifications?.enabled && !notificationPrompted) {
    notificationPrompted = true;
    if (window.LianNative?.requestNotificationPermission) {
      try {
        window.LianNative.requestNotificationPermission();
      } catch {
        // ignore
      }
    } else if ("Notification" in window && Notification.permission === "default") {
      Notification.requestPermission().catch(() => {});
    }
  }
  window.setTimeout(() => refreshNativeBackgroundUI(), 500);
}

function startNativePoll() {
  clearInterval(nativePollTimer);
  nativePollTimer = 0;
  if (demoMode || !window.LianNative?.takePendingMessages) return;
  if (!state?.settings.notifications?.background) return;
  nativePollTimer = window.setInterval(pullNativeMessages, 20000);
}

function pullNativeMessages() {
  if (demoMode || !window.LianNative?.takePendingMessages) return;
  let rows = [];
  try {
    const raw = window.LianNative.takePendingMessages();
    rows = JSON.parse(raw || "[]");
  } catch {
    rows = [];
  }
  if (!Array.isArray(rows) || !rows.length) return;
  const seen = new Set(state.messages.map((message) => message.id));
  const added = [];
  let addedElsewhere = false;
  for (const row of rows) {
    if (!row?.id || !row.text || seen.has(row.id)) continue;
    const chatId = String(row.chatId || "");
    const target = chatId
      ? state.chats.find((chat) => chat.id === chatId)
      : currentChat();
    if (!target) continue;
    const bucket = target.id === state.activeChatId ? state.messages : target.messages;
    if (!Array.isArray(bucket)) continue;
    const message = {
      id: String(row.id),
      role: "assistant",
      kind: "text",
      text: String(row.text).slice(0, 1200),
      ts: Number(row.ts) || Date.now(),
    };
    bucket.push(message);
    target.updatedAt = message.ts;
    seen.add(message.id);
    if (target.id === state.activeChatId) added.push(message);
    else addedElsewhere = true;
  }
  if (!added.length && !addedElsewhere) return;
  persist();
  if (addedElsewhere) renderChatList();
  if (!added.length) return;
  window.setTimeout(() => {
    renderChat({ forceScroll: true, animateId: added.at(-1).id });
    showHeadsUp(added.at(-1));
  }, 500);
}

function reconcileNativeBlockFollowUp() {
  if (!state?.blockFollowUp?.pending) return;
  const until = Number(state.blockFollowUp.endedAt) || 0;
  if (!until) return;
  try {
    const handled = window.LianNative?.isBlockFollowUpHandledFor
      ? window.LianNative.isBlockFollowUpHandledFor(until, state.activeChatId || "")
      : window.LianNative?.isBlockFollowUpHandled?.(until);
    if (handled) {
      // The native service already sent the after-block message while the
      // WebView was gone; do not send a second one on startup.
      state.blockFollowUp = null;
      persist();
    }
  } catch {
    // Older APKs do not expose this method.
  }
}

function recordUsage(usage = {}) {
  const total = Number(usage.total || 0);
  state.meta.totalTokens = Number(state.meta.totalTokens || 0) + total;
  state.meta.totalCalls = Number(state.meta.totalCalls || 0) + 1;
  state.meta.lastUsedAt = Date.now();
}

function requireApi() {
  if (demoMode) {
    toast(t("toast.demo"));
    return false;
  }
  if (!state.settings.apiKey) {
    toast(t("chat.missingKey"), {
      action: t("chat.missingKeyAction"),
      onAction: () => openSettings("connection"),
      timeout: 5000,
    });
    return false;
  }
  return true;
}

/* =========================================================
   Composer
   ========================================================= */

function autoResizeInput(input = $("#messageInput")) {
  if (!input) return;
  input.style.height = "auto";
  input.style.height = `${Math.min(132, Math.max(38, input.scrollHeight))}px`;
}

function updateSendButton() {
  const button = $("#btnSend");
  const input = $("#messageInput");
  if (!button || !input) return;
  if (sending) {
    button.disabled = false;
    button.classList.add("is-stop");
    button.setAttribute("aria-label", t("common.cancel"));
    button.innerHTML = `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="6.5" y="6.5" width="11" height="11" rx="2" fill="currentColor" stroke="none"/></svg>`;
    return;
  }
  button.classList.remove("is-stop");
  button.setAttribute("aria-label", t("chat.send"));
  button.innerHTML = icon("send");
  button.disabled = !input.value.trim() && !activeAttachment;
}

/* =========================================================
   Drafts & unread
   ========================================================= */

function activeChatRecord() {
  return state?.chats?.find((chat) => chat.id === state.activeChatId) || null;
}

function saveDraft(value) {
  const chat = activeChatRecord();
  if (!chat) return;
  const text = String(value || "");
  if (chat.draft === text) return;
  if (text) chat.draft = text;
  else delete chat.draft;
  persist();
}

function restoreDraft(chat) {
  const input = $("#messageInput");
  if (!input) return;
  input.value = chat?.draft || "";
  autoResizeInput(input);
  updateSendButton();
}

function totalUnread() {
  return (state?.chats || []).reduce((sum, chat) => sum + (Number(chat.unread) || 0), 0);
}

function updateTabBadge() {
  const tab = document.querySelector('.tab-item[data-tab="list"]');
  if (!tab) return;
  const total = totalUnread();
  tab.classList.toggle("has-unread", total > 0);
  tab.dataset.unread = total > 99 ? "99+" : String(total);
}

function bumpUnread(chatId) {
  const chat = state?.chats?.find((item) => item.id === chatId);
  if (!chat) return;
  chat.unread = Math.max(0, Number(chat.unread) || 0) + 1;
  persist();
  updateTabBadge();
}

function clearUnread(chat) {
  if (!chat) return;
  if (!chat.unread) return;
  chat.unread = 0;
  persist();
  updateTabBadge();
}

function clearComposer() {
  const input = $("#messageInput");
  if (input) {
    input.value = "";
    autoResizeInput(input);
  }
  saveDraft("");
  activeAttachment = null;
  activeQuote = null;
  renderAttachmentPreview();
  renderQuotePreview();
  updateSendButton();
}

function quoteFromMessage(message) {
  if (!message) return null;
  const name =
    message.role === "user"
      ? state.settings.userName || t("chat.you")
      : state.settings.aiName || "Lian";
  let text = "";
  if (message.kind === "sticker") {
    const sticker = getSticker(message.stickerId, state.customStickers);
    text = `[${t("common.sticker")}] ${sticker?.name || ""}`.trim();
  } else if (message.kind === "image") {
    text = `[${t("chat.image")}] ${message.text || ""}`.trim();
  } else if (message.kind === "file") {
    text = `[${t("chat.file")}] ${message.file?.name || message.text || ""}`.trim();
  } else if (message.kind === "report") {
    text = `[${t("chat.report")}] ${message.report?.title || ""}`.trim();
  } else if (message.kind === "drawing") {
    text = `[${t("chat.drawing")}] ${drawingLabel(message.drawing)}`.trim();
  } else {
    text = String(message.text || "").trim();
  }
  return {
    id: message.id,
    role: message.role === "user" ? "user" : "assistant",
    name,
    text: text.slice(0, 120),
  };
}

function startQuote(messageId) {
  const message = state.messages.find((item) => item.id === messageId);
  const quote = quoteFromMessage(message);
  if (!quote) return;
  activeQuote = quote;
  renderQuotePreview();
  closeAllOverlays();
  const input = $("#messageInput");
  input?.focus();
  scrollToBottom(true);
}

function cancelQuote() {
  activeQuote = null;
  renderQuotePreview();
  updateSendButton();
}

/* =========================================================
   Message actions — long press / right click
   ========================================================= */

const LONG_PRESS_MS = 460;
let messageMenu = null;
let messageMenuOpenedAt = 0;

function messagePlainText(message) {
  if (!message) return "";
  if (message.kind === "sticker") return "";
  if (message.kind === "report") {
    const title = message.report?.title || "";
    const summary = message.report?.summary || "";
    return [title, summary].filter(Boolean).join("\n").trim();
  }
  return String(message.text || "").trim();
}

function messageMenuItems(message) {
  const items = [];
  const text = messagePlainText(message);
  if (text) items.push({ id: "copy", label: t("chat.copy"), icon: "doc" });
  if (message.kind !== "report") items.push({ id: "quote", label: t("chat.quoteReply"), icon: "reply" });
  if (message.role === "assistant" && message.kind !== "report") {
    items.push({
      id: "regen",
      label: message.kind === "drawing" ? t("chat.redraw") : t("chat.regenerate"),
      icon: "sparkle",
    });
  }
  items.push({ id: "delete", label: t("common.delete"), icon: "trash", danger: true });
  return items;
}

function closeMessageMenu() {
  if (!messageMenu) return;
  messageMenu.remove();
  messageMenu = null;
  document.body.classList.remove("has-msg-menu");
}

function openMessageMenu(messageId, anchor) {
  const message = state.messages.find((item) => item.id === messageId);
  if (!message) return;
  closeMessageMenu();
  const items = messageMenuItems(message);
  if (!items.length) return;
  const layer = document.createElement("div");
  layer.className = "msg-menu-layer";
  layer.dataset.closeMsgMenu = "1";
  const menu = document.createElement("div");
  menu.className = "msg-menu";
  menu.setAttribute("role", "menu");
  menu.innerHTML = items
    .map(
      (item) => `<button type="button" role="menuitem" class="msg-menu-item ${item.danger ? "is-danger" : ""}" data-menu="${item.id}">
        ${icon(item.icon)}<span>${escapeHtml(item.label)}</span></button>`,
    )
    .join("");
  layer.append(menu);
  document.body.append(layer);
  document.body.classList.add("has-msg-menu");
  messageMenu = layer;
  messageMenuOpenedAt = Date.now();

  const rect = (anchor || menu).getBoundingClientRect();
  const size = menu.getBoundingClientRect();
  const margin = 8;
  let top = rect.top - size.height - margin;
  if (top < margin) top = Math.min(rect.bottom + margin, window.innerHeight - size.height - margin);
  let left = rect.left + rect.width / 2 - size.width / 2;
  left = Math.max(margin, Math.min(left, window.innerWidth - size.width - margin));
  menu.style.top = `${Math.round(Math.max(margin, top))}px`;
  menu.style.left = `${Math.round(left)}px`;

  menu.addEventListener("click", (event) => {
    const button = event.target.closest("[data-menu]");
    if (!button) return;
    event.preventDefault();
    event.stopPropagation();
    handleMessageAction(button.dataset.menu, message);
  });
}

function handleMessageAction(action, message) {
  closeMessageMenu();
  if (action === "copy") {
    copyText(messagePlainText(message));
    return;
  }
  if (action === "quote") {
    startQuote(message.id);
    return;
  }
  if (action === "regen") {
    regenerateFrom(message);
    return;
  }
  if (action === "delete") {
    deleteMessage(message);
  }
}

async function copyText(text) {
  const value = String(text || "");
  if (!value) return;
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(value);
      toast(t("chat.copyDone"));
      return;
    }
  } catch {
    /* fall back to execCommand below */
  }
  const area = document.createElement("textarea");
  area.value = value;
  area.style.position = "fixed";
  area.style.top = "-100px";
  area.style.opacity = "0";
  document.body.append(area);
  area.select();
  try {
    document.execCommand("copy");
    toast(t("chat.copyDone"));
  } catch {
    toast(t("error.generic"));
  }
  area.remove();
}

function deleteMessage(message) {
  const index = state.messages.findIndex((item) => item.id === message.id);
  if (index < 0) return;
  state.messages.splice(index, 1);
  persist();
  renderChat({ force: true });
  toast(t("common.delete"));
}

async function regenerateFrom(message) {
  if (sending || reporting || studioGenerating) {
    toast(t("chat.busy"));
    return;
  }
  if (isBlocked()) return;
  if (state.settings.apiKey === "demo" || demoMode) {
    toast(t("toast.demo"));
    return;
  }
  if (!state.settings.apiKey) {
    requireApi();
    return;
  }
  const context = threadContext();
  const originChat = context.chat;
  const originSettings = { ...state.settings };
  const all = originChat ? originChat.messages : state.messages;
  const index = all.findIndex((item) => item.id === message.id);
  if (index < 0) return;
  const target = all[index];
  let userIndex = -1;
  for (let i = index - 1; i >= 0; i -= 1) {
    if (all[i].role === "user") {
      userIndex = i;
      break;
    }
  }
  if (userIndex < 0) return;
  const userMessage = all[userIndex];
  const wantedDrawing = target.kind === "drawing";
  const note = wantedDrawing
    ? "[系统旁白：上一张画面对方不满意，请重新画一张。仍然只输出一个 ```svg 或 ```html 代码块，不要解释，不要重复上一张的构图。]"
    : "[系统旁白：请把刚才那句话重新说一遍，换一种说法，意思和语气可以保持，不要提到这条说明。]";

  const node = document.querySelector(`.msg[data-message="${target.id.replace(/["\\]/g, "\\$&")}"]`);
  node?.classList.add("is-regenerating");
  sending = true;
  segmentAbort = false;
  hideError();
  updateSendButton();
  const controller = new AbortController();
  abortController = controller;
  /* 历史必须停在这条回答对应的提问：以前是临时把全局 state.messages 换成
     截断数组，再在 finally 还原——这中间只要切了会话，switchChat 的
     syncActiveChat() 就会把截断后的历史写进原会话，切回来的数组又会写进新会话。
     现在只给请求构造一份浅副本，全局引用全程不动。 */
  const requestState = { ...state, settings: originSettings, messages: all.slice(0, userIndex + 1) };
  try {
    const result = await chatCompletion({
      settings: originSettings,
      model: originSettings.model,
      messages: buildChatMessages(requestState, userMessage, { note }),
      maxTokens: wantedDrawing ? 900 : 720,
      temperature: 0.9,
      signal: controller.signal,
    });
    const parsed = parseReply(result.content, { ...requestState, messages: all }, { autoSticker: false });
    const parts = (parsed.parts || []).map((part) => String(part || "").trim()).filter(Boolean);
    const drawing = parsed.drawings?.[0] || null;
    if (wantedDrawing && !drawing) {
      toast(t("chat.redrawFailed"));
      return;
    }
    if (drawing) {
      target.kind = "drawing";
      target.drawing = { type: drawing.type, markup: drawing.markup, createdAt: Date.now() };
      target.text = "";
    } else if (!parts.length && parsed.stickerIds.length) {
      target.kind = "sticker";
      target.stickerId = parsed.stickerIds[0];
      target.text = "";
      target.drawing = null;
    } else if (parts.length) {
      target.kind = "text";
      target.text = parts.join("\n");
      target.drawing = null;
    } else {
      toast(t("error.empty"));
      return;
    }
    if (result.usage) target.usage = result.usage;
    /* 重新生成走的是普通请求，旧的思考过程与联网来源不能留在新答案上。 */
    delete target.reasoning;
    delete target.sources;
    if (originChat) originChat.updatedAt = Date.now();
    persist();
    if (threadStillActive(context)) renderChat({ force: true });
    toast(wantedDrawing ? t("chat.redrawn") : t("chat.regenerated"));
  } catch (error) {
    if (threadStillActive(context)) showError(t("chat.retry", { msg: errorText(error) }));
    else toast(t("chat.retry", { msg: errorText(error) }));
  } finally {
    sending = false;
    abortController = null;
    updateSendButton();
    document.querySelector(`.msg[data-message="${target.id.replace(/["\\]/g, "\\$&")}"]`)?.classList.remove("is-regenerating");
  }
}

function bindMessageMenu() {
  const list = $("#messageList");
  if (!list) return;
  let timer = 0;
  let origin = null;
  let pendingId = "";
  const cancel = () => {
    window.clearTimeout(timer);
    timer = 0;
    origin = null;
    pendingId = "";
  };
  const nodeFor = (id) => Array.from(list.querySelectorAll(".msg")).find((el) => el.dataset.message === id) || null;

  list.addEventListener(
    "pointerdown",
    (event) => {
      if (event.pointerType === "mouse" && event.button !== 0) return;
      /* 助理页的答案操作条 / 快捷提问 / 思考面板 / 来源是普通控件，不要顺手把长按菜单叫出来 */
      if (event.target.closest(".as-think, .as-sources, [data-msg-menu]")) return;
      const holder = event.target.closest(".msg[data-message]");
      if (!holder || holder.classList.contains("is-live")) return;
      cancel();
      pendingId = holder.dataset.message;
      origin = { x: event.clientX, y: event.clientY };
      timer = window.setTimeout(() => {
        timer = 0;
        const node = nodeFor(pendingId);
        if (!node) return;
        openMessageMenu(pendingId, node.querySelector(".bubble") || node);
        try {
          navigator.vibrate?.(8);
        } catch {
          /* vibration is optional */
        }
      }, LONG_PRESS_MS);
    },
    { passive: true },
  );
  list.addEventListener(
    "pointermove",
    (event) => {
      if (!origin) return;
      if (Math.hypot(event.clientX - origin.x, event.clientY - origin.y) > 12) cancel();
    },
    { passive: true },
  );
  list.addEventListener("pointerup", cancel);
  list.addEventListener("pointercancel", cancel);
  list.addEventListener("scroll", cancel, { passive: true });
  list.addEventListener("contextmenu", (event) => {
    const holder = event.target.closest(".msg[data-message]");
    if (!holder) return;
    event.preventDefault();
    openMessageMenu(holder.dataset.message, holder.querySelector(".bubble") || holder);
  });
  document.addEventListener("click", (event) => {
    if (!messageMenu) return;
    if (Date.now() - messageMenuOpenedAt < 320) return;
    if (event.target.closest(".msg-menu")) return;
    closeMessageMenu();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeMessageMenu();
  });
}

function renderQuotePreview() {
  const box = $("#quotePreview");
  if (!box) return;
  if (!activeQuote) {
    box.hidden = true;
    box.innerHTML = "";
    return;
  }
  box.hidden = false;
  box.innerHTML = `<span class="quote-preview-line"></span>
    <span class="quote-preview-copy">
      <b>${escapeHtml(t("chat.quoteFrom", { name: activeQuote.name }))}</b>
      <small>${escapeHtml(activeQuote.text)}</small>
    </span>
    <button type="button" class="quote-preview-close" id="cancelQuote" aria-label="${escapeHtml(t("chat.quoteCancel"))}">${icon("close")}</button>`;
  $("#cancelQuote")?.addEventListener("click", cancelQuote);
}

function renderAttachmentPreview() {
  const box = $("#attachmentPreview");
  if (!box) return;
  if (!activeAttachment) {
    box.hidden = true;
    box.innerHTML = "";
    return;
  }
  box.hidden = false;
  if (activeAttachment.kind === "image") {
    box.innerHTML = `
      <img src="${escapeHtml(activeAttachment.dataUrl)}" alt="">
      <span class="attachment-copy"><b>${escapeHtml(t("chat.attachmentImage"))}</b><small>${escapeHtml(formatBytes(activeAttachment.size))}</small></span>
      <button type="button" class="attachment-remove" id="removeAttachment" aria-label="${escapeHtml(t("chat.removeAttachment"))}">${icon("close")}</button>
    `;
  } else {
    box.innerHTML = `
      <span class="file-icon">${icon("file")}</span>
      <span class="attachment-copy"><b>${escapeHtml(activeAttachment.name)}</b><small>${escapeHtml(formatBytes(activeAttachment.size))}</small></span>
      <button type="button" class="attachment-remove" id="removeAttachment" aria-label="${escapeHtml(t("chat.removeAttachment"))}">${icon("close")}</button>
    `;
  }
  $("#removeAttachment")?.addEventListener("click", () => {
    activeAttachment = null;
    renderAttachmentPreview();
    updateSendButton();
  });
}

async function handleSend() {
  if (studioGenerating) {
    toast(t("common.loading"));
    return;
  }
  if (sending || reporting) return;
  const input = $("#messageInput");
  const text = input?.value.trim() || "";
  if (!text && !activeAttachment) {
    toast(t("toast.needText"));
    return;
  }
  if (!requireApi()) return;
  const attachment = activeAttachment;
  const quote = activeQuote ? { ...activeQuote } : null;
  const blockedMode = isBlocked()
    ? ((state.block?.mode || state.settings.blocking?.mode) === "reject" ? "reject" : "silent")
    : "";
  let kind = "text";
  let message = null;
  if (attachment?.kind === "image") {
    kind = "image";
    message = {
      id: uid("m"),
      role: "user",
      kind,
      text,
      ts: Date.now(),
      image: {
        dataUrl: attachment.dataUrl,
        width: attachment.width,
        height: attachment.height,
        name: attachment.name,
        size: attachment.size,
      },
    };
  } else if (attachment?.kind === "file") {
    kind = "file";
    message = {
      id: uid("m"),
      role: "user",
      kind,
      text,
      ts: Date.now(),
      file: {
        name: attachment.name,
        size: attachment.size,
        sizeLabel: formatBytes(attachment.size),
        mime: attachment.mime,
        dataUrl: attachment.dataUrl,
        textPreview: attachment.textPreview || "",
      },
    };
  } else {
    message = { id: uid("m"), role: "user", kind: "text", text, ts: Date.now() };
  }
  if (quote) message.quote = quote;
  if (blockedMode) message.delivery = blockedMode === "reject" ? "refused" : "silent";
  state.messages.push(message);
  clearComposer();
  hideError();
  persist();
  renderChat({ forceScroll: true, animateId: message.id });
  if (blockedMode) return;
  await requestAssistant(message);
}

async function sendSticker(stickerId) {
  if (sending || reporting || studioGenerating) {
    toast(t("chat.busy"));
    return;
  }
  if (!requireApi()) return;
  const sticker = getSticker(stickerId, state.customStickers);
  if (!sticker) {
    toast(t("chat.stickerMissing"));
    return;
  }
  const blockedMode = isBlocked()
    ? ((state.block?.mode || state.settings.blocking?.mode) === "reject" ? "reject" : "silent")
    : "";
  const quote = activeQuote ? { ...activeQuote } : null;
  const message = { id: uid("m"), role: "user", kind: "sticker", stickerId, text: "", ts: Date.now() };
  if (quote) message.quote = quote;
  if (blockedMode) message.delivery = blockedMode === "reject" ? "refused" : "silent";
  activeQuote = null;
  renderQuotePreview();
  state.messages.push(message);
  closeSheet();
  hideError();
  persist();
  renderChat({ forceScroll: true, animateId: message.id });
  if (blockedMode) return;
  await requestAssistant(message);
}

function insertEmoji(emoji) {
  const input = $("#messageInput");
  if (!input) return;
  const start = input.selectionStart ?? input.value.length;
  const end = input.selectionEnd ?? input.value.length;
  input.value = `${input.value.slice(0, start)}${emoji}${input.value.slice(end)}`;
  const pos = start + emoji.length;
  input.setSelectionRange(pos, pos);
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.focus();
  recordEmojiUse(emoji);
}

/* =========================================================
   API / replies
   ========================================================= */

function showError(message, retry = true) {
  const bar = $("#errorBar");
  const text = $("#errorText");
  const button = $("#btnRetry");
  if (!bar || !text) return;
  text.textContent = message;
  bar.hidden = false;
  if (button) button.hidden = !retry;
}

function hideError() {
  const bar = $("#errorBar");
  if (bar) bar.hidden = true;
}

/* =========================================================
   Streaming live reply
   A temporary bubble shows the text as the model produces it. It is never
   written to state: when the stream ends the bubble is removed and the normal
   parseReply() path creates the real messages.
   ========================================================= */

let liveReplyNode = null;

function stripLiveMarkup(raw) {
  let text = String(raw || "");
  text = text.replace(/!\[[^\]]*\]\([^)]*\)/g, "");
  text = text.replace(/\[\[[^\]]*\]\]/g, ""); // complete markers: sticker / quote / block / report
  text = text.replace(/\[\[[^\]]*$/, ""); // a marker still being typed
  text = text.replace(/\[\[?$/, "");
  text = text.replace(/```[\s\S]*?```/g, ""); // a finished drawing / code fence
  text = text.replace(/```[\s\S]*$/, ""); // a fence that is still being written
  /* a bare <svg> (no fence) is still a picture: keep its source out of the
     live bubble too */
  text = text.replace(/<svg\b[^>]*\s(?:viewBox|xmlns|width|height)\s*=[\s\S]*$/i, "");
  return text.replace(/[ \t]+\n/g, "\n").trim();
}

function beginLiveReply(chatId = "") {
  const list = $("#messageList");
  if (!list) return null;
  /* 流式气泡只能出现在发起请求的那条会话里：用户在等第一个字的时候切走，
     不能把半截回答画到别人的聊天页上。 */
  if (chatId && chatId !== state.activeChatId) return null;
  endLiveReply();
  const holder = document.createElement("div");
  holder.innerHTML = messageMarkup({ id: "live_preview", role: "assistant", kind: "text", text: "", ts: Date.now() }, false);
  const node = holder.firstElementChild;
  if (!node) return null;
  node.classList.add("is-live");
  node.dataset.message = "live_preview";
  list.appendChild(node);
  liveReplyNode = node;
  scrollToBottom(false);
  return node.querySelector(".bubble");
}

function updateLiveReply(raw) {
  if (!liveReplyNode) return;
  const bubble = liveReplyNode.querySelector(".bubble");
  if (!bubble) return;
  const text = stripLiveMarkup(raw);
  if (bubble.textContent !== text) bubble.textContent = text;
  const scroll = $("#chatScroll");
  if (scroll && scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 240) scrollToBottom(false);
}

function endLiveReply() {
  if (!liveReplyNode) return;
  liveReplyNode.remove();
  liveReplyNode = null;
}

function typingDelayMs(text) {  const realism = state.settings.realism || {};
  if (realism.enabled === false) return 0;
  const min = clamp(Number(realism.minDelay) || 0, 0, 20) * 1000;
  const max = Math.max(min, clamp(Number(realism.maxDelay) || 0, 0, 30) * 1000);
  if (max <= 0) return 0;
  if (realism.autoDelay === false) return min + Math.random() * (max - min);
  const length = [...String(text || "")].length;
  const ratio = clamp(length / 72, 0.1, 1);
  const jitter = 0.88 + Math.random() * 0.24;
  return clamp(min + (max - min) * ratio * jitter, min, max);
}

function segmentDelayMs(message) {
  const realism = state.settings.realism || {};
  if (realism.enabled === false) return message.kind === "sticker" ? 240 : 360;
  const base = clamp(Number(realism.segmentDelay) || 0, 0, 8) * 1000;
  return message.kind === "sticker" ? Math.min(base, 700) : base;
}

const STRONG_ABUSE_RE = /(废物|闭嘴|滚|去死|傻逼|傻B|贱人|神经病|畜生|垃圾东西|操你|你妈|fuck|shut up)/i;
const DIRECT_ABUSE_RE = /(废物|闭嘴|滚开|滚蛋|去死|傻逼|傻B|贱人|神经病|畜生|垃圾东西|操你|你妈|fuck|shut up|(^|[，。！？\s])滚([，。！？\s]|$))/i;
const BOUNDARY_STOP_RE = /(过界|越界|停一下|先停|不想吵|冷静|不想说|到此为止|打住|别说了|再说吧|不想理|不奉陪)/i;

function shouldBlockFromReply(userMessage, parsed) {
  if (!state.settings.blocking?.enabled) return false;
  if (parsed.blockRequested) return true;
  const userText = String(userMessage?.text || "");
  const replyText = String(parsed.text || "");
  // The model sometimes forgets [[block]] on a direct insult. Keep a
  // deterministic safety net so repeated cold wars still trigger.
  if (DIRECT_ABUSE_RE.test(userText)) return true;
  // Safety net for models that say "停一下/过界了" but forget the marker.
  return STRONG_ABUSE_RE.test(userText) && BOUNDARY_STOP_RE.test(replyText);
}

async function waitAbortable(ms) {
  const end = Date.now() + Math.max(0, ms);
  while (Date.now() < end) {
    if (segmentAbort) return false;
    await sleep(Math.min(90, end - Date.now()));
  }
  return !segmentAbort;
}

async function requestAssistant(userMessage, { proactive = false, manual = false, retry = false, afterBlock = false } = {}) {
  if (sending || reporting || studioGenerating) return;
  if (!proactive && isBlocked()) return;
  if (!proactive && proactiveBusy) return;
  if (!state.settings.apiKey && !demoMode) {
    requireApi();
    return;
  }
  if (state.settings.apiKey === "demo" || demoMode) {
    toast(t("toast.demo"));
    return;
  }
  /* 请求可能跑十几秒：记住它属于哪条会话、用哪套设置，回来时不再假设
     用户还停在原地。 */
  const context = threadContext();
  const originSettings = { ...state.settings };
  /* 助理页的两个能力：MiMo 与 DeepSeek 的原生插件；陪伴 / 剧本永远不带这些参数。 */
  const provider = providerIdOf(originSettings);
  const caps = assistantCapabilities(originSettings);
  const assistantMode = chatModeOf(originSettings) === "assistant";
  const useWeb = Boolean(assistantMode && caps.web && originSettings.assistant?.web);
  const useThinking = Boolean(assistantMode && caps.thinking && originSettings.assistant?.thinking);
  const extraBody = {};
  if (assistantMode && caps.thinking) {
    /* 两家默认都开深度思考（MiMo v2.6 / DeepSeek V4），不开时要显式关掉。 */
    extraBody.thinking = { type: useThinking ? "enabled" : "disabled" };
  }
  if (assistantMode && provider === "deepseek" && useThinking) {
    extraBody.reasoning_effort = "high";
  }
  if (useWeb) {
    if (provider === "mimo") {
      extraBody.tools = [{ type: "web_search", max_keyword: 3, force_search: true, limit: 1 }];
      extraBody.tool_choice = "auto";
    } else if (provider === "deepseek") {
      /* DeepSeek 的服务端联网工具，搜索 / 抓取都在服务端完成。
         tool_choice 不能强制指定这两个工具，交给模型决定。 */
      extraBody.tools = [{ type: "deepseek_web_search" }, { type: "deepseek_read_url" }];
    }
  }
  sending = true;
  segmentAbort = false;
  hideError();
  updateSendButton();
  showTyping(true);
  const startedAt = Date.now();
  const controller = new AbortController();
  abortController = controller;
  try {
    const useVision = userMessage?.kind === "image" && originSettings.visionModel?.trim();
    const model = modelForRequest(originSettings, { vision: useVision });
    const messages = buildChatMessages(state, userMessage, { proactive, afterBlock });
    const quoteCatalog = buildQuoteCatalog(state, userMessage?.id);
    const streamable = !useVision && !proactive && !afterBlock && originSettings.optimize?.streaming !== false;
    let streamedAny = false;
    const baseTokens = afterBlock
      ? 260
      : proactive
        ? 220
        : originSettings.optimize?.drawings || /(画|绘制|插画|svg|draw|illustrat)/i.test(String(userMessage?.text || ""))
          ? 2600
          : 720;
    const body = {
      settings: originSettings,
      messages,
      model,
      /* 深度思考的 reasoning tokens 也算在完成额度里，留足空间。 */
      maxTokens: useThinking ? 4096 : useWeb ? Math.max(2400, baseTokens) : baseTokens,
      temperature: afterBlock ? 0.82 : proactive ? 0.92 : 0.88,
      signal: controller.signal,
      extraBody,
      onDelta: streamable
        ? (full) => {
            if (!streamedAny) {
              streamedAny = true;
              beginLiveReply(context.chatId);
              showTyping(false);
            }
            updateLiveReply(full);
          }
        : null,
    };
    let result;
    try {
      result = await chatCompletion(body);
    } catch (error) {
      /* 联网工具被服务商拒绝（常见：插件未开通、400 参数校验）时，
         不把整条回答丢掉：退一步用普通请求，并说明原因。 */
      if (useWeb && Number(error?.status) === 400) {
        const fallback = { ...extraBody };
        delete fallback.tools;
        delete fallback.tool_choice;
        toast(t("assistant.webFallback"), { timeout: 5200 });
        result = await chatCompletion({ ...body, extraBody: fallback });
      } else {
        throw error;
      }
    }
    endLiveReply();
    recordUsage(result.usage);
    const parsed = parseReply(result.content, { ...state, settings: originSettings }, { quoteCatalog });
    const allowedStickerIds = new Set(availableStickers(state).map((sticker) => sticker.id));
    let parts = (parsed.parts || []).filter((part) => String(part || "").trim());
    let stickers = parsed.stickerIds.filter((id) => allowedStickerIds.has(id));
    if (proactive) {
      parts = parts.slice(0, 1);
      // A proactive / after-block message is one bubble. If the model
      // returned words plus a sticker, the words win; otherwise use one
      // sticker. Never send both.
      stickers = parts.length ? [] : stickers.slice(0, 1);
    }
    if (!stickers.length && /\[\[\s*(?:sticker|表情)/i.test(result.content)) {
      const fallback = chooseAutoSticker(parsed.text, state);
      if (fallback) stickers = [fallback];
    }
    // A proactive / after-block message is one bubble; a drawing there would
    // arrive out of nowhere, so it is dropped rather than half-rendered.
    const drawings = proactive ? [] : parsed.drawings || [];
    /* The model tried to draw but the markup was cut off or malformed. The
       source was already stripped, so say one line instead of going silent. */
    if (parsed.drawingBroken && !parts.length && !stickers.length && !drawings.length && !proactive) {
      parts = [t("chat.drawingBroken")];
    }
    if (!parts.length && !stickers.length && !drawings.length && !(parsed.blockRequested && originSettings.blocking?.enabled)) {
      throw new Error(t("error.empty"));
    }
    if (!parts.length && !stickers.length && !drawings.length) {
      if (proactive) throw new Error(t("error.empty"));
      // A cold-war marker with no visible words: keep the block, but never
      // create an empty message bubble.
      if (parsed.blockRequested && originSettings.blocking?.enabled) {
        if (shouldBlockFromReply(userMessage, parsed)) {
          applyBlock(originSettings.blocking.minutes, { chatId: context.chatId });
        }
        return;
      }
      throw new Error(t("error.empty"));
    }
    // A new cold-war cycle may have started while this after-block request
    // was in flight. Discard the old follow-up rather than posting it into
    // the new cycle.
    if (afterBlock && threadBlocked(context)) return;

    // The network call may already have taken longer than a human would.
    // Only top up the remaining time, never slow a slow model down further.
    if (!proactive && !streamedAny) {
      const target = typingDelayMs(parts.join(" ") || "表情");
      const remaining = target - (Date.now() - startedAt);
      if (remaining > 0 && !(await waitAbortable(remaining))) {
        toast(t("chat.stopped"));
        return;
      }
    }
    if (segmentAbort) {
      toast(t("chat.stopped"));
      return;
    }
    showTyping(false);

    const now = Date.now();
    const created = [];
    parts.forEach((part, index) => {
      created.push({
        id: uid("m"),
        role: "assistant",
        kind: "text",
        text: part,
        ts: now + index * 1000,
        usage: index === 0 ? result.usage : null,
      });
    });
    stickers.forEach((stickerId, index) => {
      created.push({
        id: uid("m"),
        role: "assistant",
        kind: "sticker",
        stickerId,
        text: "",
        ts: now + (parts.length + index) * 1000,
        usage: !parts.length && index === 0 ? result.usage : null,
      });
    });
    drawings.forEach((drawing, index) => {
      created.push({
        id: uid("m"),
        role: "assistant",
        kind: "drawing",
        drawing: { type: drawing.type, markup: drawing.markup, createdAt: now },
        text: "",
        ts: now + (parts.length + stickers.length + index) * 1000,
        usage: !parts.length && !stickers.length && index === 0 ? result.usage : null,
      });
    });

    if (parsed.quote && created.length) {
      created[0].quote = {
        id: parsed.quote.messageId,
        role: parsed.quote.role || "user",
        name: parsed.quote.name || originSettings.userName || t("chat.you"),
        text: parsed.quote.text,
      };
    }
    /* 思考过程与联网来源挂在第一条回答上；历史里的旧消息没有这两个字段。 */
    const reasoning = String(result.reasoning || "").trim();
    const sources = Array.isArray(result.sources) ? result.sources.filter((source) => source?.url).slice(0, 5) : [];
    if (created.length && reasoning) created[0].reasoning = reasoning;
    if (created.length && sources.length) created[0].sources = sources;

    let stillActive = threadStillActive(context);
    for (let i = 0; i < created.length; i += 1) {
      if (segmentAbort) break;
      const message = created[i];
      /* 写到发起请求的那条会话；用户已经切走时不要重画别人的界面。 */
      stillActive = pushToThread(context, message);
      persist();
      if (stillActive) renderChat({ forceScroll: true, animateId: message.id });
      if (i < created.length - 1 && !streamedAny) {
        showTyping(true);
        const ok = await waitAbortable(segmentDelayMs(message));
        showTyping(false);
        if (!ok) break;
      }
    }
    if (!stillActive && created.length && context.chatId) {
      bumpUnread(context.chatId);
      if (document.body.dataset.screen === "list") renderChatList();
    } else if (stillActive && document.body.dataset.screen !== "chat" && state.activeChatId) {
      bumpUnread(state.activeChatId);
    }
    if (segmentAbort) toast(t("chat.stopped"));
    else {
      if (!proactive && shouldBlockFromReply(userMessage, parsed)) {
        applyBlock(originSettings.blocking?.minutes, { chatId: context.chatId });
      }
      if (proactive && created.length && stillActive) {
        notifyUser(created.filter((message) => notificationPreview(message)).at(-1));
      }
      if (proactive && manual && !afterBlock) toast(t("chat.proactiveDone", { tokens: result.usage.total || "?" }));
    }
    if (threadStillActive(context)) {
      lastFailed = null;
      hideError();
    }
  } catch (error) {
    const aborted = controller.signal.aborted || error?.code === "aborted";
    if (aborted) {
      toast(t("toast.aborted"));
    } else {
      const message = errorText(error, t);
      if (threadStillActive(context)) {
        showError(t("chat.retry", { msg: message }));
        lastFailed = { userMessage, proactive, manual, afterBlock };
      } else {
        /* 用户已经离开了这场对话：错误提示不能盖到别人的聊天页上，
           原会话的提问还在，回去可以重新生成。 */
        toast(t("chat.retry", { msg: message }));
      }
      state.meta.lastError = message;
      persist();
    }
  } finally {
    endLiveReply();
    sending = false;
    segmentAbort = false;
    abortController = null;
    showTyping(false);
    updateSendButton();
    if (proactive && !afterBlock) {
      if (threadStillActive(context)) state.settings.proactive.lastAt = Date.now();
      else if (context.chat) context.chat.proactiveLastAt = Date.now();
    }
    persist();
    if (!proactive && threadStillActive(context)) maybeAutoMemory();
  }
}

function stopGeneration() {
  segmentAbort = true;
  abortController?.abort();
  showTyping(false);
}

/* =========================================================
   Memory / context
   ========================================================= */

function userMessageCount() {
  return (state.messages || []).filter((message) => message.role === "user").length;
}

async function organizeMemories({ button = null, silent = false } = {}) {
  if (memoryBusy) return;
  if (demoMode) {
    if (!silent) toast(t("toast.demo"));
    return;
  }
  if (!state.settings.apiKey) {
    if (!silent) requireApi();
    return;
  }
  if (sending || reporting || studioGenerating) {
    if (!silent) toast(t("chat.busy"));
    return;
  }
  const context = threadContext();
  const originSettings = { ...state.settings };
  memoryBusy = true;
  const countAtStart = userMessageCount();
  if (button) setLoading(button, true, t("settings.memoryOrganizing"));
  try {
    const result = await chatCompletion({
      settings: originSettings,
      messages: buildMemoryMessages({ ...state, settings: originSettings }),
      model: originSettings.model,
      maxTokens: 800,
      temperature: 0.25,
      json: true,
    });
    recordUsage(result.usage);
    const candidates = parseMemoryReply(result.content);
    /* 记忆属于发起整理的那条会话：等模型回答时用户可能已经切走了。 */
    const target = chatById(context.chatId) || context.chat;
    if (!target) return;
    const merged = mergeMemories(target.memories || [], candidates);
    const now = Date.now();
    target.memories = merged.memories;
    target.memoryMeta = {
      ...(target.memoryMeta && typeof target.memoryMeta === "object" ? target.memoryMeta : {}),
      lastAt: now,
      lastAttemptAt: now,
      lastUserCount: countAtStart,
    };
    if (threadStillActive(context)) {
      state.memories = target.memories;
      state.memoryMeta = target.memoryMeta;
      if (document.body.dataset.screen === "settings") renderSettings(settingsCallbacks());
    }
    persist();
    if (!silent) {
      toast(
        merged.added
          ? t("settings.memoryOrganized", { n: merged.added })
          : t("settings.memoryNoNew"),
      );
    }
  } catch (error) {
    const target = chatById(context.chatId) || context.chat;
    if (target) {
      target.memoryMeta = {
        ...(target.memoryMeta && typeof target.memoryMeta === "object" ? target.memoryMeta : {}),
        lastAttemptAt: Date.now(),
        ...(silent ? { lastUserCount: countAtStart } : {}),
      };
      if (threadStillActive(context)) state.memoryMeta = target.memoryMeta;
    }
    persist();
    if (!silent) {
      toast(t("settings.memoryOrganizeFail", { msg: errorText(error, t) }), { timeout: 5000 });
    }
  } finally {
    memoryBusy = false;
    if (button) setLoading(button, false);
  }
}

function maybeAutoMemory() {
  if (!state || demoMode || memoryBusy || isBlocked()) return;
  if (!state.settings.memory?.auto) return;
  if (!state.settings.apiKey) return;
  const count = userMessageCount();
  const last = Number(state.memoryMeta?.lastUserCount || 0);
  if (count - last < 8) return;
  clearTimeout(memoryTimer);
  memoryTimer = window.setTimeout(() => organizeMemories({ silent: true }), 1800);
}

function contextTranscript() {
  const packet = buildChatMessages(state, null);
  return packet
    .map((message) => {
      const role = message.role === "system" ? "SYSTEM" : message.role === "user" ? "USER" : "ASSISTANT";
      const content = Array.isArray(message.content)
        ? message.content
            .map((part) => (part.type === "text" ? part.text : `[${part.type === "image_url" ? "图片" : part.type}]`))
            .join("\n")
        : String(message.content || "");
      return `[${role}]\n${content}`;
    })
    .join("\n\n");
}

function openContextViewer() {
  const text = contextTranscript();
  const chars = text.length;
  const modal = openModal(`<div class="modal-head">
      <div class="modal-title"><h2>${escapeHtml(t("settings.memoryContextTitle"))}</h2><small>${escapeHtml(
        t("settings.memoryContextMeta", { memories: state.memories.length, chars }),
      )}</small></div>
      <button type="button" class="sheet-close" data-close-context aria-label="${escapeHtml(t("common.close"))}">${icon("close")}</button>
    </div>
    <div class="context-body">
      <p class="field-hint">${escapeHtml(t("settings.memoryContextHint"))}</p>
      <pre class="context-pre">${escapeHtml(text || t("settings.memoryContextEmpty"))}</pre>
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" id="copyContext">${escapeHtml(t("context.copy"))}</button>
      </div>
    </div>`, {
    className: "context-modal",
    onMount: (modalEl) => {
      modalEl.querySelector("[data-close-context]")?.addEventListener("click", closeModal);
      modalEl.querySelector("#copyContext")?.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(text);
          toast(t("context.copied"));
        } catch {
          toast(t("settings.shareFail"));
        }
      });
    },
  });
  modal?.querySelector(".modal-head")?.addEventListener("dblclick", closeModal, { once: true });
}

/* =========================================================
   Settings screen
   ========================================================= */

function settingsCallbacks() {
  return {
    state,
    onChange: () => {
      persist();
      syncNativeRuntime();
      renderHeader();
      startProactiveTimer();
    },
    onAppearance: () => {
      applyAppearance();
      renderHeader();
    },
    onMode: (mode) => setChatMode(mode),
    onUiLanguage: () => {
      applyStaticI18n();
      applyAppearance();
      renderHeader();
      renderChat();
      updateBlockUI();
      renderSettings(settingsCallbacks());
    },
    onPickAvatar: (role) => pickAvatar(role),
    onPickBackground: () => pickBackground(),
    onRemoveBackground: () => {
      state.settings.chatBg = "";
      persist();
      applyAppearance();
      toast(t("settings.backgroundRemove"));
      renderSettings(settingsCallbacks());
    },
    onExport: () => exportProfile(),
    onImport: () => $("#importInput")?.click(),
    onShare: () => shareApp(),
    onClearChat: () => clearChat(),
    onClearAll: () => clearAllData(),
    onOpenContext: () => openContextViewer(),
    onOrganizeMemory: (button) => organizeMemories({ button }),
    onUnblock: () => clearBlock(),
    onOpenReport: () => {
      closeAllOverlays();
      showScreen("chat");
      openReportSheet();
    },
    onProactiveNow: () => sendProactive({ manual: true }),
    onRestartSetup: () => {
      closeAllOverlays();
      showSetup(0);
    },
  };
}

function openSettings(section = "", returnTo = "") {
  const current = document.body.dataset.screen;
  settingsReturnScreen = returnTo || (["list", "contacts", "home"].includes(current) ? current : "chat");
  /* the tool tray belongs to the composer: don't let it wait behind the settings page */
  setComposerTray(false);
  applyAppearance();
  renderSettings(settingsCallbacks());
  showScreen("settings");
  const scroll = $(".settings-scroll");
  if (scroll) scroll.scrollTop = 0;
  if (section) {
    requestAnimationFrame(() => {
      const details = document.querySelector(`#settingsBody [data-group="${section}"]`);
      if (details) {
        details.open = true;
        details.scrollIntoView({ block: "start" });
      }
    });
  }
}

function closeSettings() {
  if (settingsReturnScreen === "list") {
    showScreen("list");
    applyAppearance();
    renderChatList();
    startProactiveTimer();
    return;
  }
  if (settingsReturnScreen === "contacts") {
    showScreen("contacts");
    applyAppearance();
    renderContacts();
    startProactiveTimer();
    return;
  }
  if (settingsReturnScreen === "home") {
    showScreen("home");
    applyAppearance();
    renderHome();
    startProactiveTimer();
    return;
  }
  showScreen("chat");
  applyAppearance();
  renderHeader();
  updateBlockUI();
  renderChat();
  startProactiveTimer();
}

/* =========================================================
   Menus, sheets, stickers
   ========================================================= */

function openNewChatSheet() {
  if (!state) return;
  const keys = Array.isArray(state.keys) ? state.keys : [];
  const keyOptions = keys.length
    ? keys.map((key) => `<option value="${escapeHtml(key.id)}" ${key.id === state.activeKeyId ? "selected" : ""}>${escapeHtml(key.name)} · ${escapeHtml((key.apiKey || "").slice(-4) || "…")}</option>`).join("")
    : "";
  openSheet(`<div class="sheet-handle"></div>
    <div class="sheet-head">
      <div><h2 class="sheet-title">${escapeHtml(t("chatList.newChat"))}</h2><p class="sheet-sub">${escapeHtml(t("chatList.newChatSub"))}</p></div>
      <button type="button" class="sheet-close" data-close-sheet aria-label="${escapeHtml(t("common.close"))}">${icon("close")}</button>
    </div>
    <form class="new-chat-form" id="newChatForm">
      ${
        chatModeOf(state.settings) === "roleplay"
          ? `<p class="field-label">${escapeHtml(t("newChat.presets"))}</p>
      <div class="preset-chips" id="newChatPresets">
        <button type="button" class="preset-chip" data-preset="custom">${escapeHtml(t("newChat.customScript"))}<small>${escapeHtml(t("newChat.customScriptTag"))}</small></button>
        ${ROLEPLAY_PRESETS.map((preset) => `<button type="button" class="preset-chip" data-preset="${escapeHtml(preset.id)}">${escapeHtml(state.settings.uiLang === "en" ? preset.titleEn : preset.title)}<small>${escapeHtml(state.settings.uiLang === "en" ? preset.tagEn : preset.tag)}</small></button>`).join("")}
      </div>
      <p class="field-hint" style="margin:6px 0 12px">${escapeHtml(t("newChat.presetsHint"))}</p>`
          : ""
      }
      <label class="field-label" for="newChatName">${escapeHtml(t("chatList.name"))}</label>
      <input class="input" id="newChatName" maxlength="80" autocomplete="off" placeholder="${escapeHtml(t("chatList.namePh"))}" required>
      <label class="field-label" for="newChatRelation">${escapeHtml(t("settings.relationship"))}</label>
      <input class="input" id="newChatRelation" maxlength="300" placeholder="${escapeHtml(t("chatList.relationPh"))}">
      <label class="field-label" for="newChatPersona">${escapeHtml(t("settings.persona"))}</label>
      <textarea class="textarea" id="newChatPersona" maxlength="1200" rows="3" placeholder="${escapeHtml(t("chatList.personaPh"))}"></textarea>
      <label class="field-label" for="newChatGreeting">${escapeHtml(t("settings.greeting"))}</label>
      <input class="input" id="newChatGreeting" maxlength="500" value="${escapeHtml(DEFAULT_GREETING)}">
      <label class="field-label" for="newChatKey">${escapeHtml(t("chatList.key"))}</label>
      ${keys.length
        ? `<select class="select" id="newChatKey">${keyOptions}</select>`
        : `<div class="new-chat-nokey"><span>${escapeHtml(t("chatList.noKey"))}</span><button type="button" class="btn btn-ghost btn-small" data-new-chat-settings>${escapeHtml(t("chatList.goKeys"))}</button></div>`}
      <div class="modal-actions">
        <button type="submit" class="btn btn-primary">${escapeHtml(t("chatList.create"))}</button>
      </div>
    </form>`, {
    onMount: (sheet) => {
      sheet.querySelector("#newChatPresets")?.addEventListener("click", (event) => {
        const chip = event.target.closest("[data-preset]");
        if (!chip) return;
        const fill = (id, value) => {
          const input = sheet.querySelector(id);
          if (input) input.value = value;
        };
        if (chip.dataset.preset === "custom") {
          /* 自定义剧本：清空预设，只留下自己的角色、场景和开场白。 */
          fill("#newChatName", "");
          fill("#newChatRelation", "");
          fill("#newChatPersona", "");
          fill("#newChatGreeting", "");
          sheet.querySelector("#newChatName")?.focus();
        } else {
          const preset = ROLEPLAY_PRESETS.find((item) => item.id === chip.dataset.preset);
          if (!preset) return;
          fill("#newChatName", preset.name);
          fill("#newChatRelation", preset.relationship);
          fill("#newChatPersona", preset.persona);
          fill("#newChatGreeting", preset.greeting);
        }
        sheet.querySelectorAll("[data-preset]").forEach((node) => node.classList.toggle("is-on", node === chip));
      });
      sheet.querySelector("[data-new-chat-settings]")?.addEventListener("click", () => {
        closeSheet();
        openSettings("connection", "list");
      });
      sheet.querySelector("#newChatForm")?.addEventListener("submit", (event) => {
        event.preventDefault();
        const name = sheet.querySelector("#newChatName")?.value.trim();
        if (!name) {
          sheet.querySelector("#newChatName")?.focus();
          return;
        }
        const keyId = sheet.querySelector("#newChatKey")?.value || "";
        const relationship = sheet.querySelector("#newChatRelation")?.value.trim() || "";
        const persona = sheet.querySelector("#newChatPersona")?.value.trim() || "";
        const fallbackGreeting = chatModeOf(state.settings) === "roleplay" ? "" : DEFAULT_GREETING;
        const greeting = sheet.querySelector("#newChatGreeting")?.value.trim() || fallbackGreeting;
        closeSheet();
        createChat({ name, relationship, persona, greeting, keyId });
        toast(t("chatList.created", { name }));
      });
    },
  });
}

function openChatMenu() {
  openSheet(`<div class="sheet-handle"></div>
    <div class="sheet-head"><div><h2 class="sheet-title">${escapeHtml(t("common.more"))}</h2></div>
      <button type="button" class="sheet-close" data-close-sheet aria-label="${escapeHtml(t("common.close"))}">${icon("close")}</button>
    </div>
    <div class="menu-list">
      <button type="button" class="menu-item" data-menu="settings">${icon("settings")}<span>${escapeHtml(t("menu.settings"))}</span></button>
      <button type="button" class="menu-item" data-menu="memory">${icon("heart")}<span>${escapeHtml(t("menu.memory"))}</span><small>${escapeHtml(t("settings.memoryHint", { n: state.memories.length }))}</small></button>
      <button type="button" class="menu-item" data-menu="report">${icon("doc")}<span>${escapeHtml(t("menu.report"))}</span><small>${escapeHtml(t("report.costTitle"))}</small></button>
      <button type="button" class="menu-item" data-menu="studio">${icon("sparkle")}<span>${escapeHtml(t("menu.studio"))}</span><small>${escapeHtml(t("studio.costShort"))}</small></button>
      <button type="button" class="menu-item" data-menu="background">${icon("image")}<span>${escapeHtml(t("menu.background"))}</span></button>
      <button type="button" class="menu-item" data-menu="share">${icon("share")}<span>${escapeHtml(t("menu.share"))}</span></button>
      <button type="button" class="menu-item" data-menu="export">${icon("download")}<span>${escapeHtml(t("menu.export"))}</span></button>
      <button type="button" class="menu-item danger" data-menu="clear">${icon("trash")}<span>${escapeHtml(t("menu.clear"))}</span></button>
    </div>`, {
    onMount: (sheet) => {
      sheet.querySelectorAll("[data-menu]").forEach((button) => {
        button.addEventListener("click", () => {
          const action = button.dataset.menu;
          closeSheet();
          if (action === "settings") openSettings();
          else if (action === "memory") openSettings("memory");
          else if (action === "report") openReportSheet();
          else if (action === "studio") openStudioSettings();
          else if (action === "background") pickBackground();
          else if (action === "share") shareApp();
          else if (action === "export") exportProfile();
          else if (action === "clear") clearChat(true);
        });
      });
    },
  });
}

function openAttachSheet() {
  openSheet(`<div class="sheet-handle"></div>
    <div class="sheet-head"><div><h2 class="sheet-title">${escapeHtml(t("chat.attach"))}</h2></div>
      <button type="button" class="sheet-close" data-close-sheet aria-label="${escapeHtml(t("common.close"))}">${icon("close")}</button>
    </div>
    <div class="attach-grid">
      <button type="button" class="attach-tile" data-attach="photo">
        <span class="tile-icon">${icon("image")}</span><span>${escapeHtml(t("common.photo"))}</span><small>${escapeHtml(t("setup.visionHint"))}</small>
      </button>
      <button type="button" class="attach-tile" data-attach="file">
        <span class="tile-icon">${icon("file")}</span><span>${escapeHtml(t("common.file"))}</span><small>${escapeHtml(t("chat.fileSent"))}</small>
      </button>
      <button type="button" class="attach-tile cost" data-attach="report">
        <span class="tile-icon">${icon("doc")}</span><span>${escapeHtml(t("chat.report"))}</span><small>${escapeHtml(t("report.costTitle"))}</small>
      </button>
    </div>`, {
    onMount: (sheet) => {
      sheet.querySelectorAll("[data-attach]").forEach((button) => {
        button.addEventListener("click", () => {
          const kind = button.dataset.attach;
          closeSheet();
          if (kind === "photo") {
            const input = $("#imageInput");
            input.value = "";
            input.click();
          } else if (kind === "file") {
            const input = $("#fileInput");
            input.value = "";
            input.click();
          } else if (kind === "report") {
            openReportSheet();
          }
        });
      });
    },
  });
}

/* ---- 输入栏工具盘：+ 展开，图片 / 文件 / 表情 / 日常 / 更多 + 分组快捷表情 ---- */
const EMOJI_RECENT_MAX = 12;

/* 当前停在哪个表情分组上。只在这次会话里有意义，所以不写进 state；
   空字符串 = 跟着「最近」走（有历史就停在最近，没有就停在第一组）。 */
let trayEmojiGroup = "";
let trayEmojiShown = "";

function recentEmojis() {
  return Array.isArray(state?.emojiUsage) ? state.emojiUsage.map((item) => item.e) : [];
}

function trayEmojiGroups() {
  if (!state) return [];
  const recent = recentEmojis();
  const groups = [];
  if (recent.length) groups.push({ id: "recent", label: t("composer.recent"), items: recent });
  for (const group of EMOJI_GROUPS) {
    groups.push({ id: group.id, label: emojiGroupLabel(group, state.settings.uiLang), items: group.items });
  }
  return groups;
}

function renderTrayEmojis() {
  const head = $("#trayEmojiHead");
  const box = $("#trayEmoji");
  if (!state || !box) return;
  const groups = trayEmojiGroups();
  if (!groups.some((group) => group.id === trayEmojiGroup)) trayEmojiGroup = groups[0]?.id || "face";
  const active = groups.find((group) => group.id === trayEmojiGroup) || groups[0];
  const keepScroll = active?.id === trayEmojiShown ? box.scrollLeft : 0;
  if (head) {
    head.innerHTML = groups
      .map(
        (group) =>
          `<button type="button" class="tray-emoji-tab${group.id === active?.id ? " is-on" : ""}" data-emoji-group="${escapeHtml(group.id)}" aria-pressed="${group.id === active?.id}">${escapeHtml(group.label)}</button>`,
      )
      .join("");
  }
  box.innerHTML = (active?.items || [])
    .map(
      (emoji) =>
        `<button type="button" class="tray-emoji-btn" data-emoji="${escapeHtml(emoji)}" aria-label="${escapeHtml(emoji)}">${escapeHtml(emoji)}</button>`,
    )
    .join("");
  box.scrollLeft = keepScroll;
  trayEmojiShown = active?.id || "";
}

/* 记一次使用：最近用过的排最前，顺手把「最近」分组刷新出来。 */
function recordEmojiUse(emoji) {
  if (!state || !emoji) return;
  const list = Array.isArray(state.emojiUsage) ? state.emojiUsage : [];
  const existing = list.find((item) => item.e === emoji);
  if (existing) {
    existing.n = Math.min(999, (Number(existing.n) || 0) + 1);
    existing.at = Date.now();
  } else {
    list.push({ e: emoji, n: 1, at: Date.now() });
  }
  list.sort((a, b) => b.at - a.at);
  state.emojiUsage = list.slice(0, EMOJI_RECENT_MAX);
  /* through persist(): it keeps demo mode out of real storage */
  persist();
  renderTrayEmojis();
}

function initComposerTray() {
  const tray = $("#composerTray");
  if (!tray) return;
  renderTrayEmojis();
  if (tray.dataset.ready) return;
  tray.dataset.ready = "1";
  $("#trayEmojiHead")?.addEventListener("click", (event) => {
    const tab = event.target.closest("[data-emoji-group]");
    if (!tab) return;
    trayEmojiGroup = tab.dataset.emojiGroup;
    renderTrayEmojis();
  });
}

function setComposerTray(open) {
  const tray = $("#composerTray");
  if (!tray) return;
  initComposerTray();
  tray.hidden = !open;
  $("#btnAttach")?.setAttribute("aria-expanded", open ? "true" : "false");
  $("#composer")?.classList.toggle("tray-open", open);
}

function openStickerSheet(tab = stickerTab) {
  stickerTab = tab === "emoji" ? "emoji" : tab === "custom" ? "custom" : "builtin";
  tab = stickerTab;
  const custom = state.customStickers;
  let grid = "";
  if (tab === "builtin") {
    const lang = state.settings.uiLang;
    // a saved filter can outlive a pack (or arrive from a future version)
    if (stickerPack !== "all" && !BUILTIN_PACKS.some((pack) => pack.id === stickerPack)) stickerPack = "all";
    const filter = BUILTIN_PACKS.length > 1 ? stickerPack : "all";
    const visible = BUILTIN_PACKS.filter((pack) => filter === "all" || pack.id === filter);
    const totalAll = BUILTIN_PACKS.reduce((sum, pack) => sum + pack.stickers.length, 0);
    const chips =
      BUILTIN_PACKS.length > 1
        ? `<div class="sticker-packs">${[
            ["all", `${t("chat.builtinAll")} · ${totalAll}`],
            ...BUILTIN_PACKS.map((pack) => [pack.id, `${builtinPackLabel(pack, lang)} · ${pack.stickers.length}`]),
          ]
            .map(
              ([id, label]) =>
                `<button type="button" class="sticker-pack-chip ${filter === id ? "is-on" : ""}" data-sticker-pack="${escapeHtml(id)}">${escapeHtml(label)}</button>`,
            )
            .join("")}</div>`
        : "";
    const cells = (pack) =>
      `<p class="sticker-group-label pack">${escapeHtml(
        t("chat.builtinCount", { name: builtinPackLabel(pack, lang), n: pack.stickers.length }),
      )}</p>${pack.stickers
        .map(
          (sticker) => `<button type="button" class="sticker-cell builtin" data-sticker="${escapeHtml(sticker.id)}" title="${escapeHtml(sticker.name)}">
          <img src="${escapeHtml(stickerSrc(sticker))}" alt="${escapeHtml(sticker.name)}" loading="lazy">
          <span class="cell-name">${escapeHtml(sticker.name)}</span>
        </button>`,
        )
        .join("")}`;
    grid = chips + visible.map(cells).join("");
  } else if (tab === "custom") {
    const aiStickers = custom.filter((sticker) => sticker.ai);
    const userStickers = custom.filter((sticker) => !sticker.ai);
    const aiCells = aiStickers
      .map(
        (sticker) => `<button type="button" class="sticker-cell custom ai-sticker" data-sticker="${escapeHtml(sticker.id)}" title="${escapeHtml(sticker.name)}">
          <img src="${escapeHtml(stickerSrc(sticker))}" alt="${escapeHtml(sticker.name)}" loading="lazy">
          <span class="ai-sticker-badge">AI</span>
          <span class="cell-name">${escapeHtml(sticker.name)}</span>
        </button>`,
      )
      .join("");
    const userCells = userStickers
      .map(
        (sticker) => `<button type="button" class="sticker-cell custom" data-sticker="${escapeHtml(sticker.id)}" title="${escapeHtml(sticker.name)}">
          <img src="${escapeHtml(stickerSrc(sticker))}" alt="${escapeHtml(sticker.name)}" loading="lazy">
          <span class="remove-sticker" data-remove-sticker="${escapeHtml(sticker.id)}" role="button" aria-label="remove">${icon("close")}</span>
          <span class="cell-name">${escapeHtml(sticker.name)}</span>
        </button>`,
      )
      .join("");
    grid = `${aiStickers.length ? `<p class="sticker-group-label">${escapeHtml(t("studio.madeByAi"))}</p>${aiCells}` : ""}
      <p class="sticker-group-label">${escapeHtml(t("studio.myStickers"))}</p>
      ${userCells || `<p class="sticker-group-empty">${escapeHtml(t("studio.noMyStickers"))}</p>`}
      <button type="button" class="sticker-cell add" id="addSticker" aria-label="${escapeHtml(t("chat.stickerImport"))}">
        <span class="add-plus">＋</span><span class="add-label">${escapeHtml(t("chat.stickerImportShort"))}</span>
      </button>
      <button type="button" class="sticker-cell ai-make" id="aiMakeSticker" title="${escapeHtml(t("studio.makeOne"))}">
        <span class="ai-make-icon">${icon("sparkle")}</span><span>${escapeHtml(t("studio.makeShort"))}</span>
      </button>`;
  } else {
    grid = `<div class="emoji-grid" style="grid-column:1/-1">${EMOJIS.map(
      (emoji) => `<button type="button" class="emoji-cell" data-emoji="${emoji}" aria-label="${emoji}">${emoji}</button>`,
    ).join("")}</div>`;
  }
  openSheet(`<div class="sheet-handle"></div>
    <div class="sheet-head">
      <div><h2 class="sheet-title">${escapeHtml(t("common.sticker"))}</h2><p class="sheet-sub">${escapeHtml(tab === "emoji" ? t("chat.emojiHint") : t("chat.stickerSent"))}</p></div>
      <button type="button" class="sheet-close" data-close-sheet aria-label="${escapeHtml(t("common.close"))}">${icon("close")}</button>
    </div>
    <div class="sticker-tabs">
      <button type="button" class="sticker-tab ${tab === "custom" ? "is-on" : ""}" data-sticker-tab="custom">${escapeHtml(t("chat.myStickers"))}</button>
      <button type="button" class="sticker-tab ${tab === "builtin" ? "is-on" : ""}" data-sticker-tab="builtin">${escapeHtml(t("chat.builtinTab"))}</button>
      <button type="button" class="sticker-tab ${tab === "emoji" ? "is-on" : ""}" data-sticker-tab="emoji">${escapeHtml(t("chat.emoji"))}</button>
    </div>
    <div class="${tab === "emoji" ? "" : "sticker-grid"}" id="stickerGrid">${grid}</div>
    <p class="sticker-foot">${
      tab === "custom"
        ? escapeHtml(t("chat.customStickerLimit"))
        : tab === "builtin"
          ? escapeHtml(t("chat.builtinHint"))
          : escapeHtml(t("chat.emojiHint"))
    }</p>`, {
    onMount: (sheet) => {
      sheet.querySelectorAll("[data-sticker-tab]").forEach((button) => {
        button.addEventListener("click", () => openStickerSheet(button.dataset.stickerTab));
      });
      sheet.querySelectorAll("[data-sticker-pack]").forEach((button) => {
        button.addEventListener("click", () => {
          stickerPack = button.dataset.stickerPack;
          openStickerSheet("builtin");
        });
      });
      sheet.querySelectorAll("[data-sticker]").forEach((button) => {
        button.addEventListener("click", (event) => {
          if (event.target.closest("[data-remove-sticker]")) return;
          sendSticker(button.dataset.sticker);
        });
      });
      sheet.querySelectorAll("[data-remove-sticker]").forEach((button) => {
        button.addEventListener("click", (event) => {
          event.stopPropagation();
          const id = button.dataset.removeSticker;
          state.customStickers = state.customStickers.filter((sticker) => sticker.id !== id);
          persist();
          openStickerSheet("custom");
          toast(t("toast.deleted"));
        });
      });
      sheet.querySelector("#addSticker")?.addEventListener("click", () => {
        closeSheet();
        const input = $("#stickerInput");
        input.value = "";
        input.click();
      });
      sheet.querySelector("#aiMakeSticker")?.addEventListener("click", () => {
        closeSheet();
        openStudioSettings();
      });
      sheet.querySelectorAll("[data-emoji]").forEach((button) => {
        button.addEventListener("click", () => {
          insertEmoji(button.dataset.emoji);
          closeSheet();
        });
      });
    },
  });
}

/* =========================================================
   Report
   ========================================================= */

function openReportSheet() {
  if (!state) return;
  const estimate = estimateReportTokens(state.messages);
  const min = Math.max(220, Math.round(estimate * 0.72));
  const max = Math.max(min + 180, Math.round(estimate * 1.45));
  openSheet(`<div class="sheet-handle"></div>
    <div class="sheet-head">
      <div><h2 class="sheet-title">${escapeHtml(t("report.title"))}</h2><p class="sheet-sub">${escapeHtml(t("chat.reportBadge"))}</p></div>
      <button type="button" class="sheet-close" data-close-sheet aria-label="${escapeHtml(t("common.close"))}">${icon("close")}</button>
    </div>
    <div class="report-intro">
      <span class="report-symbol">${icon("doc")}</span>
      <p>${escapeHtml(t("report.lead"))}</p>
    </div>
    <div class="cost-strip">${icon("sparkle")}<span><b>${escapeHtml(t("report.costTitle"))}</b> · ${escapeHtml(t("report.cost", { min, max }))}</span></div>
    <p class="field-hint">${escapeHtml(t("report.sandbox"))}</p>
    <p class="field-hint" style="margin-top:7px">${escapeHtml(t("report.limit"))}</p>
    <div class="modal-actions">
      <button type="button" class="btn btn-primary" id="reportGenerate">${escapeHtml(t("report.generate"))}</button>
    </div>
    <p class="field-error" id="reportError" hidden></p>`, {
    onMount: (sheet) => {
      sheet.querySelector("#reportGenerate")?.addEventListener("click", (event) => generateReport(event.currentTarget));
    },
  });
}

async function generateReport(button) {
  if (reporting) return;
  if (!requireApi()) return;
  if (sending || studioGenerating) {
    toast(t("chat.busy"));
    return;
  }
  const context = threadContext();
  const originSettings = { ...state.settings };
  reporting = true;
  const error = $("#reportError");
  if (error) error.hidden = true;
  setLoading(button, true, t("common.generating"));
  try {
    const result = await chatCompletion({
      settings: originSettings,
      messages: buildReportMessages({ ...state, settings: originSettings }),
      model: originSettings.model,
      maxTokens: 2400,
      temperature: 0.86,
      json: true,
    });
    recordUsage(result.usage);
    /* Reports used to fall back to dumping the raw reply into the viewer when
       the JSON did not parse — on a phone that looked like `{"title":"…`.
       Salvage the readable fields instead, and never render the source. */
    let report = null;
    const reportState = { ...state, settings: originSettings };
    try {
      report = buildReportFromRaw(parseJsonReply(result.content), reportState);
    } catch {
      report = buildReportFromRaw(salvageReport(result.content), reportState);
    }
    const createdAt = Date.now();
    const message = {
      id: uid("m"),
      role: "assistant",
      kind: "report",
      text: "",
      ts: createdAt,
      report: { ...report, createdAt },
      usage: result.usage,
    };
    /* 报备属于发起生成的那条会话，切走了也不要塞进当前会话。 */
    const active = pushToThread(context, message);
    persist();
    if (active) {
      closeSheet();
      renderChat({ forceScroll: true, animateId: message.id });
      openReportViewer(message);
    } else {
      if (context.chatId) bumpUnread(context.chatId);
      if (document.body.dataset.screen === "list") renderChatList();
    }
    toast(t("chat.reportDone", { tokens: result.usage.total || "?" }));
  } catch (err) {
    if (error && threadStillActive(context)) {
      error.hidden = false;
      error.textContent = t("report.failed", { msg: errorText(err, t) });
    } else {
      toast(t("report.failed", { msg: errorText(err, t) }), { timeout: 5000 });
    }
  } finally {
    reporting = false;
    setLoading(button, false);
  }
}

function openReportViewer(message) {
  const report = message.report || {};
  const fallback = `<h2>${escapeHtml(report.title || t("report.titleFallback"))}</h2><p>${escapeHtml(report.summary || t("report.emptyBody"))}</p>`;
  // New reports are plain text + a local scene illustration; old saved reports
  // still fall back to the sanitised HTML fragment. The title/teaser used to be
  // dropped here, which made a salvaged report look like loose paragraphs.
  const blocksHtml = reportBlocksHtml(report.blocks);
  const lead = blocksHtml
    ? `${report.title ? `<h2>${escapeHtml(report.title)}</h2>` : ""}${report.summary ? `<p>${escapeHtml(report.summary)}</p>` : ""}`
    : "";
  const safeHtml = blocksHtml
    ? `${lead}${blocksHtml}`
    : sanitizeReportHtml(report.html || "") || fallback;
  const createdAt = report.createdAt || message.ts || Date.now();
  const modal = openModal(`<header class="report-cinema-head" id="reportHead">
      <div class="report-cinema-title">
        <span class="report-cinema-kicker">${icon("sparkle")}${escapeHtml(t("chat.reportBadge"))}</span>
        <b>${escapeHtml(t("report.title"))}</b>
      </div>
      <button type="button" class="sheet-close report-close" id="reportClose" aria-label="${escapeHtml(t("common.close"))}">${icon("close")}</button>
    </header>
    <div class="report-cinema-body">
      <div class="report-aurora" aria-hidden="true"><i></i><i></i><i></i></div>
      <div class="report-scroll" id="reportScroll">
        <p class="report-cinema-stamp">${escapeHtml(t("report.cinemaKicker", { name: state.settings.aiName || "Lian" }))}</p>
        <article class="report-direct" id="reportDirect">${safeHtml}</article>
        <div class="report-endline">${escapeHtml(t("report.saved"))}</div>
      </div>
      <div class="report-progress" id="reportProgress" aria-hidden="true"><i></i></div>
    </div>
    <footer class="report-cinema-foot">
      <time>${escapeHtml(timeLabel(createdAt))}</time>
      <div class="report-cinema-actions">
        <button type="button" class="report-ghost" id="reportReplay">${icon("sparkle")}${escapeHtml(t("report.replay"))}</button>
        <button type="button" class="report-solid" id="reportDone">${escapeHtml(t("common.done"))}</button>
      </div>
    </footer>`, {
    className: "report-modal report-cinema",
    onMount: (modalEl) => {
      const direct = modalEl.querySelector("#reportDirect");
      const scroll = modalEl.querySelector("#reportScroll");
      const progress = modalEl.querySelector("#reportProgress i");
      const blocks = [...(direct?.children || [])];
      blocks.forEach((block, index) => block.style.setProperty("--i", String(index)));
      const play = () => {
        if (!direct) return;
        direct.classList.remove("is-playing");
        if (progress) progress.style.animation = "none";
        void direct.offsetWidth;
        direct.classList.add("is-playing");
        if (progress) progress.style.animation = "";
        if (scroll) scroll.scrollTop = 0;
      };
      requestAnimationFrame(play);
      modalEl.querySelector("#reportReplay")?.addEventListener("click", play);
      modalEl.querySelector("#reportClose")?.addEventListener("click", closeModal);
      modalEl.querySelector("#reportDone")?.addEventListener("click", closeModal);
      modalEl.querySelector("#reportHead")?.addEventListener("dblclick", closeModal, { once: true });
    },
  });
  return modal;
}

/* =========================================================
   AI sticker studio + sandbox host
   ========================================================= */

async function generateStickerPack(button) {
  if (studioGenerating) return;
  if (!state.stickerStudio) state.stickerStudio = { packs: [], style: "auto", direction: "" };
  if (!Array.isArray(state.stickerStudio.packs)) state.stickerStudio.packs = [];
  if (sending || reporting) {
    toast(t("common.loading"));
    return;
  }
  if (!requireApi()) return;
  if ((state.stickerStudio?.packs || []).length >= 12) {
    toast(t("studio.limit"));
    return;
  }
  if ((state.customStickers || []).length + 6 > 120) {
    toast(t("studio.limit"));
    return;
  }
  studioGenerating = true;
  setLoading(button, true, t("studio.generating"));
  try {
    const style = state.stickerStudio?.style || "auto";
    const direction = String(state.stickerStudio?.direction || "").trim().slice(0, 180);
    const result = await chatCompletion({
      settings: state.settings,
      messages: buildStickerPackMessages(state, { style, direction }),
      model: state.settings.model,
      maxTokens: 1500,
      temperature: 0.95,
      json: true,
    });
    recordUsage(result.usage);
    const parsed = parseStickerPack(result.content, { style });
    const packId = uid("pack");
    const stickers = makeStickersFromSpecs(parsed.stickers, packId);
    const assetIds = [];
    await waitForSandboxHost(1200);
    for (const sticker of stickers) {
      try {
        const asset = await hostSticker(sticker.svg, `${parsed.name} · ${sticker.name}`, {
          source: "sticker-pack",
          packId,
          stickerId: sticker.id,
        });
        assetIds.push(asset.id);
      } catch {
        // Hosting is optional; the sticker still works from its data URL.
      }
    }
    const pack = {
      id: packId,
      name: parsed.name,
      theme: parsed.theme,
      style: parsed.style || "kaomoji",
      source: "ai",
      createdAt: Date.now(),
      stickerIds: stickers.map((sticker) => sticker.id),
      assetIds,
      equipped: true,
    };
    state.customStickers.push(...stickers);
    state.stickerStudio.packs.push(pack);
    state.stickerStudio.lastAt = Date.now();
    persist();
    if (document.body.dataset.screen === "settings") renderSettings(settingsCallbacks());
    toast(t("studio.done", { tokens: result.usage.total || "?" }));
    openStickerPackModal(pack, { tokens: result.usage.total || 0, justCreated: true });
  } catch (error) {
    toast(t("studio.failed", { msg: errorText(error, t) }));
  } finally {
    studioGenerating = false;
    setLoading(button, false);
  }
}

function openStickerPackModal(pack, { tokens = 0, justCreated = false } = {}) {
  const stickers = (pack.stickerIds || [])
    .map((id) => getSticker(id, state.customStickers))
    .filter(Boolean);
  openModal(`<div class="modal-head">
      <div class="modal-title"><h2>${escapeHtml(pack.name)}</h2><small>${escapeHtml(t("studio.packBadge"))}</small></div>
      <button type="button" class="sheet-close" data-close-studio aria-label="${escapeHtml(t("common.close"))}">${icon("close")}</button>
    </div>
    <div class="modal-body">
      <div class="studio-pack-banner">
        <span class="studio-mark">${icon("sparkle")}</span>
        <span>${escapeHtml(justCreated ? t("studio.autoEquipped") : pack.equipped ? t("studio.equipped") : t("studio.unequipped"))}</span>
      </div>
      <div class="pack-grid pack-grid-lg">${stickers
        .map(
          (sticker) => `<figure class="pack-cell"><img src="${escapeHtml(stickerSrc(sticker))}" alt="${escapeHtml(sticker.name)}"><figcaption>${escapeHtml(sticker.name)}</figcaption></figure>`,
        )
        .join("")}</div>
      ${pack.theme ? `<p class="field-hint" style="margin-top:12px">${escapeHtml(pack.theme)}</p>` : ""}
      ${tokens ? `<div class="token-line">${escapeHtml(t("studio.costActual", { tokens }))}</div>` : ""}
      <div class="modal-actions">
        <button type="button" class="btn btn-primary" data-pack-chat>${escapeHtml(t("studio.goChat"))}</button>
        <button type="button" class="btn btn-ghost" data-open-sandbox>${escapeHtml(t("sandbox.open"))}</button>
      </div>
    </div>`, {
    className: "studio-pack-modal",
    onMount: (modalEl) => {
      modalEl.querySelector("[data-close-studio]")?.addEventListener("click", closeModal);
      modalEl.querySelector("[data-pack-chat]")?.addEventListener("click", () => {
        closeModal();
        showScreen("chat");
        applyAppearance();
        renderHeader();
        renderChat({ forceScroll: true });
      });
      modalEl.querySelector("[data-open-sandbox]")?.addEventListener("click", () => {
        closeModal();
        openSandboxWorkbench();
      });
    },
  });
}

function toggleStickerPack(packId) {
  const pack = state.stickerStudio?.packs?.find((item) => item.id === packId);
  if (!pack) return;
  pack.equipped = !pack.equipped;
  persist();
  toast(pack.equipped ? t("studio.equipped") : t("studio.unequipped"));
  if (document.body.dataset.screen === "settings") renderSettings(settingsCallbacks());
}

async function copyPackHostUrl(packId) {
  const pack = state.stickerStudio?.packs?.find((item) => item.id === packId);
  const assetId = pack?.assetIds?.[0];
  if (!assetId) {
    toast(t("studio.noHostedAsset"));
    return;
  }
  const ready = await waitForSandboxHost(1200);
  if (!ready) {
    toast(t("sandbox.pendingHint"));
    return;
  }
  try {
    await navigator.clipboard.writeText(sandboxUrl(assetId));
    toast(t("studio.copied"));
  } catch {
    toast(t("settings.shareFail"));
  }
}

function openStudioSettings() {
  closeSheet();
  if (document.body.dataset.screen === "settings") {
    const details = document.querySelector('#settingsBody [data-group="studio"]');
    if (details) {
      details.open = true;
      details.scrollIntoView({ block: "start", behavior: "smooth" });
    }
    return;
  }
  openSettings("studio");
}

async function openSandboxWorkbench() {
  const ready = await waitForSandboxHost(1400);
  const assets = (await listSandbox()).sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
  const total = assets.reduce((sum, asset) => sum + assetBytes(asset), 0);
  const status = ready ? t("sandbox.ready") : sandboxHostStatus() === "unsupported" ? t("sandbox.unsupported") : t("sandbox.pending");
  const rows = assets
    .map((asset) => {
      const thumb = asset.kind === "svg"
        ? `<span class="asset-thumb">${icon("sticker")}</span>`
        : `<span class="asset-thumb">${icon("doc")}</span>`;
      return `<div class="asset-row">
        ${thumb}
        <div class="asset-copy">
          <b>${escapeHtml(asset.name)}</b>
          <small>${escapeHtml(assetTypeLabel(asset))} · ${formatBytes(assetBytes(asset))} · ${escapeHtml(timeLabel(asset.createdAt))}</small>
        </div>
        <div class="asset-actions">
          <button type="button" class="btn btn-ghost btn-small" data-asset-preview="${escapeHtml(asset.id)}">${escapeHtml(t("sandbox.preview"))}</button>
          <button type="button" class="btn btn-ghost btn-small" data-asset-copy="${escapeHtml(asset.id)}">${escapeHtml(t("sandbox.copy"))}</button>
          <button type="button" class="asset-del" data-asset-delete="${escapeHtml(asset.id)}" aria-label="${escapeHtml(t("common.delete"))}">${icon("trash")}</button>
        </div>
      </div>`;
    })
    .join("");
  openModal(`<div class="modal-head">
      <div class="modal-title"><h2>${escapeHtml(t("sandbox.title"))}</h2><small>${escapeHtml(t("sandbox.hostBadge"))}</small></div>
      <button type="button" class="sheet-close" data-close-sandbox aria-label="${escapeHtml(t("common.close"))}">${icon("close")}</button>
    </div>
    <div class="modal-body sandbox-body">
      <div class="sandbox-status ${ready ? "is-ready" : ""}">
        <span class="host-dot"></span>
        <span>${escapeHtml(status)}</span>
        <span class="host-meta">${assets.length} ${escapeHtml(t("sandbox.assets"))} · ${formatBytes(total)}</span>
      </div>
      <p class="field-hint">${escapeHtml(t("sandbox.lead"))}</p>
      ${ready ? "" : `<div class="warning-box">${icon("sparkle")}<span>${escapeHtml(t("sandbox.pendingHint"))}</span></div>`}
      <div class="asset-list">${rows || `<p class="empty-note">${escapeHtml(t("sandbox.empty"))}</p>`}</div>
      <p class="hint-inline" style="margin-top:12px">${escapeHtml(t("sandbox.note"))}</p>
    </div>`, {
    className: "sandbox-modal",
    onMount: (modalEl) => {
      modalEl.querySelector("[data-close-sandbox]")?.addEventListener("click", closeModal);
      modalEl.querySelectorAll("[data-asset-preview]").forEach((button) => {
        button.addEventListener("click", () => {
          const asset = assets.find((item) => item.id === button.dataset.assetPreview);
          if (asset) previewSandboxAsset(asset, ready);
        });
      });
      modalEl.querySelectorAll("[data-asset-copy]").forEach((button) => {
        button.addEventListener("click", () => copySandboxAsset(button.dataset.assetCopy, ready));
      });
      modalEl.querySelectorAll("[data-asset-delete]").forEach((button) => {
        button.addEventListener("click", () => deleteSandboxAssetFlow(button.dataset.assetDelete));
      });
    },
  });
}

function openDrawingViewer(message) {
  const drawing = message?.drawing;
  if (!drawing) return;
  const label = escapeHtml(t("chat.drawing"));
  const media =
    drawing.type === "html"
      ? `<iframe class="drawing-full is-html" sandbox="" referrerpolicy="no-referrer" scrolling="no" title="${label}" srcdoc="${escapeHtml(buildHtmlDocument(drawing.markup || ""))}"></iframe>`
      : `<img class="drawing-full" src="${escapeHtml(buildSvgDataUri(drawing.markup || ""))}" alt="${label}">`;
  openModal(
    `<div class="modal-head">
      <div class="modal-title"><h2>${label}</h2><small>${escapeHtml(drawingLabel(drawing))}</small></div>
      <button type="button" class="sheet-close" data-close-drawing aria-label="${escapeHtml(t("common.close"))}">${icon("close")}</button>
    </div>
    <div class="modal-body drawing-viewer">${media}</div>`,
    {
      className: "drawing-modal",
      onMount: (modalEl) => {
        modalEl.querySelector("[data-close-drawing]")?.addEventListener("click", closeModal);
      },
    },
  );
}

function previewSandboxAsset(asset, ready) {
  const isSvg = asset.kind === "svg";
  const media = isSvg
    ? `<img class="sandbox-preview-image" src="${ready ? escapeHtml(sandboxUrl(asset.id)) : escapeHtml(svgToDataUrl(asset.content))}" alt="${escapeHtml(asset.name)}">`
    : `<iframe class="sandbox-preview-frame" sandbox="allow-same-origin" title="${escapeHtml(asset.name)}"></iframe>`;
  openModal(`<div class="modal-head">
      <div class="modal-title"><h2>${escapeHtml(asset.name)}</h2><small>${escapeHtml(assetTypeLabel(asset))}</small></div>
      <button type="button" class="sheet-close" data-close-preview aria-label="${escapeHtml(t("common.close"))}">${icon("close")}</button>
    </div>
    <div class="modal-body sandbox-preview-body">${media}
      <div class="token-line">${escapeHtml(t("sandbox.previewNote"))}</div>
      <div class="modal-actions">
        <button type="button" class="btn btn-ghost" data-copy-current>${escapeHtml(t("sandbox.copy"))}</button>
        <button type="button" class="btn btn-primary" data-close-current>${escapeHtml(t("common.close"))}</button>
      </div>
    </div>`, {
    className: "sandbox-preview-modal",
    onMount: (modalEl) => {
      const frame = modalEl.querySelector("iframe");
      if (frame) {
        if (ready) frame.src = sandboxUrl(asset.id);
        else frame.srcdoc = asset.content;
      }
      modalEl.querySelector("[data-close-preview]")?.addEventListener("click", closeModal);
      modalEl.querySelector("[data-close-current]")?.addEventListener("click", closeModal);
      modalEl.querySelector("[data-copy-current]")?.addEventListener("click", () => copySandboxAsset(asset.id, ready));
    },
  });
}

async function copySandboxAsset(id, ready = null) {
  const isReady = ready ?? (await waitForSandboxHost(1200));
  if (!isReady) {
    toast(t("sandbox.pendingHint"));
    return;
  }
  try {
    await navigator.clipboard.writeText(sandboxUrl(id));
    toast(t("sandbox.copied"));
  } catch {
    toast(t("settings.shareFail"));
  }
}

async function deleteSandboxAssetFlow(id) {
  const ok = await confirmDialog({
    title: t("sandbox.deleteTitle"),
    body: t("sandbox.deleteBody"),
    confirm: t("common.delete"),
    danger: true,
  });
  if (!ok) {
    openSandboxWorkbench();
    return;
  }
  await removeSandboxAsset(id);
  for (const pack of state.stickerStudio?.packs || []) {
    if (Array.isArray(pack.assetIds)) pack.assetIds = pack.assetIds.filter((assetId) => assetId !== id);
  }
  persist();
  toast(t("toast.deleted"));
  openSandboxWorkbench();
}

/* =========================================================
   Proposal messages
   ========================================================= */

function startProactiveTimer() {
  clearInterval(proactiveTimer);
  if (!state || demoMode) return;
  proactiveTimer = window.setInterval(checkProactive, 45_000);
}

async function checkProactive() {
  if (!state || demoMode || !state.settings.proactive.enabled) return;
  /* 主动消息只属于陪伴：助理和剧本里「忽然想起你」很出戏。 */
  if (chatModeOf(state.settings) !== "companion") return;
  if (!state.settings.apiKey) return;
  if (document.visibilityState !== "visible" && !state.settings.notifications?.background) return;
  if (sending || reporting || studioGenerating || proactiveBusy || isBlocked()) return;
  if (!state.messages.some((m) => m.role === "user")) return;
  const interval = Math.max(15, Number(state.settings.proactive.interval) || 45) * 60_000;
  const last = Number(state.settings.proactive.lastAt || 0);
  if (Date.now() - last < interval) return;
  const lastMessage = state.messages.at(-1)?.ts || 0;
  if (Date.now() - lastMessage < interval) return;
  await sendProactive({ manual: false });
}

async function sendProactive({ manual = false } = {}) {
  if (!state || proactiveBusy || sending || reporting || studioGenerating || isBlocked()) return;
  if (demoMode) {
    toast(t("toast.demo"));
    return;
  }
  if (chatModeOf(state.settings) !== "companion") {
    toast(t("settings.proactiveCompanionOnly"));
    return;
  }
  if (!state.settings.apiKey) {
    requireApi();
    return;
  }
  if (!state.messages.some((m) => m.role === "user")) {
    toast(t("settings.proactiveNeedChat"));
    return;
  }
  proactiveBusy = true;
  state.settings.proactive.lastAt = Date.now();
  persist();
  try {
    await requestAssistant(null, { proactive: true, manual });
  } finally {
    proactiveBusy = false;
    if (state.settings.proactive.enabled) startProactiveTimer();
  }
}

/* =========================================================
   Media
   ========================================================= */

function pickAvatar(role) {
  pendingAvatarRole = role;
  const input = $("#avatarInput");
  input.value = "";
  input.click();
}

function pickBackground() {
  const input = $("#bgInput");
  input.value = "";
  input.click();
}

async function handleAvatarFile(file) {
  if (!file || !pendingAvatarRole) return;
  if (!file.type.startsWith("image/")) {
    toast(t("toast.imageOnly"));
    return;
  }
  try {
    const result = await compressImage(file, { max: 320, quality: 0.86, square: true });
    if (pendingAvatarRole === "ai") state.settings.aiAvatar = result.dataUrl;
    else state.settings.userAvatar = result.dataUrl;
    persist();
    renderHeader();
    if (document.body.dataset.screen === "settings") renderSettings(settingsCallbacks());
    else if (document.body.dataset.screen === "setup") renderSetup(setupCallbacks());
    toast(t("toast.avatarSet"));
  } catch {
    toast(t("toast.imageOnly"));
  } finally {
    pendingAvatarRole = null;
  }
}

async function handleBackgroundFile(file) {
  if (!file) return;
  if (!file.type.startsWith("image/")) {
    toast(t("toast.imageOnly"));
    return;
  }
  if (file.size > 12 * 1024 * 1024) {
    toast(t("toast.imageTooLarge"));
    return;
  }
  try {
    const result = await compressImage(file, { max: 1800, quality: 0.78 });
    state.settings.chatBg = result.dataUrl;
    persist();
    applyAppearance();
    if (document.body.dataset.screen === "settings") renderSettings(settingsCallbacks());
    toast(t("toast.bgSet"));
  } catch {
    toast(t("toast.imageOnly"));
  }
}

async function handleImageFile(file) {
  if (!file) return;
  if (!file.type.startsWith("image/")) {
    toast(t("toast.imageOnly"));
    return;
  }
  if (file.size > 12 * 1024 * 1024) {
    toast(t("toast.imageTooLarge"));
    return;
  }
  try {
    const result = await compressImage(file, { max: 1440, quality: 0.8 });
    activeAttachment = {
      kind: "image",
      ...result,
      name: file.name || "image.jpg",
      size: dataUrlBytes(result.dataUrl),
      mime: "image/jpeg",
    };
    renderAttachmentPreview();
    updateSendButton();
    $("#messageInput")?.focus();
  } catch {
    toast(t("toast.imageOnly"));
  }
}

async function handleFileAttachment(file) {
  if (!file) return;
  if (file.size > 8 * 1024 * 1024) {
    toast(t("toast.fileTooLarge"));
    return;
  }
  try {
    const dataUrl = await fileToDataUrl(file);
    let textPreview = "";
    const textLike =
      file.type.startsWith("text/") ||
      /\.(txt|md|markdown|json|csv|log|yml|yaml|js|ts|css|html)$/i.test(file.name || "");
    if (textLike && file.size <= 400_000) {
      try {
        textPreview = (await file.text()).slice(0, 12_000);
      } catch {
        textPreview = "";
      }
    }
    activeAttachment = {
      kind: "file",
      dataUrl,
      name: file.name || "file",
      size: file.size,
      mime: file.type || "application/octet-stream",
      textPreview,
    };
    renderAttachmentPreview();
    updateSendButton();
    $("#messageInput")?.focus();
  } catch {
    toast(t("common.failed"));
  }
}

async function compressSticker(file) {
  const dataUrl = await fileToDataUrl(file);
  const img = await loadImage(dataUrl);
  const size = 320;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  const srcW = img.naturalWidth || img.width;
  const srcH = img.naturalHeight || img.height;
  const ratio = Math.min(size / srcW, size / srcH);
  const w = Math.round(srcW * ratio);
  const h = Math.round(srcH * ratio);
  ctx.drawImage(img, (size - w) / 2, (size - h) / 2, w, h);
  return canvas.toDataURL("image/png");
}

async function handleStickerFiles(files) {
  const images = [...(files || [])].filter((file) => file?.type?.startsWith("image/"));
  if (!images.length) {
    toast(t("toast.imageOnly"));
    return;
  }
  const userStickerCount = state.customStickers.filter((sticker) => !sticker.ai).length;
  const room = Math.max(0, USER_STICKER_LIMIT - userStickerCount);
  if (!room || state.customStickers.length >= 120) {
    toast(t("toast.stickerLimit"));
    return;
  }
  const batch = images.slice(0, room);
  let saved = 0;
  for (const file of batch) {
    try {
      const dataUrl = await compressSticker(file);
      const rawName = (file.name || "sticker").replace(/\.[^.]+$/, "").replace(/^[\s_-]+|[\s_-]+$/g, "");
      const name = (rawName || "表情").slice(0, 12);
      state.customStickers.push({
        id: `custom_${uid("s")}`,
        name,
        dataUrl,
        mood: moodFromText(name) || "",
        createdAt: Date.now(),
      });
      saved += 1;
    } catch {
      // Skip an individual file that the browser cannot decode.
    }
  }
  if (!saved) {
    toast(t("toast.imageOnly"));
    return;
  }
  persist();
  renderChat();
  toast(t("toast.stickersSaved", { n: saved }));
  openStickerSheet("custom");
}

/* =========================================================
   Data / share
   ========================================================= */

function profilePayload() {
  const s = state.settings;
  return {
    app: "Lian",
    version: 1,
    exportedAt: new Date().toISOString(),
    profile: {
      aiName: s.aiName,
      userName: s.userName,
      aiAvatar: s.aiAvatar,
      userAvatar: s.userAvatar,
      relationship: s.relationship,
      persona: s.persona,
      greeting: s.greeting,
      aiLang: s.aiLang,
      theme: s.theme,
      accent: s.accent,
      font: s.font,
      chatBg: s.chatBg,
      chatBgOpacity: s.chatBgOpacity,
      optimize: { ...s.optimize },
      realism: { ...s.realism },
      blocking: { ...s.blocking },
      memory: { ...s.memory },
      notifications: { ...s.notifications },
      memories: state.memories,
      customStickers: state.customStickers,
      stickerStudio: state.stickerStudio,
    },
  };
}

function exportProfile() {
  const payload = profilePayload();
  const stamp = new Date().toISOString().slice(0, 10).replaceAll("-", "");
  downloadBlob(`lian-profile-${stamp}.json`, JSON.stringify(payload, null, 2));
  toast(t("toast.exported"));
}

async function importProfile(file) {
  if (!file) return;
  try {
    const text = await file.text();
    const data = JSON.parse(text);
    if (data?.app !== "Lian" || !data.profile) throw new Error("wrong format");
    const p = data.profile;
    const s = state.settings;
    for (const key of ["aiName", "userName", "relationship", "persona", "greeting", "aiLang", "theme", "accent", "font"]) {
      if (typeof p[key] === "string") s[key] = p[key].slice(0, key === "persona" ? 1200 : 300);
    }
    for (const key of ["aiAvatar", "userAvatar", "chatBg"]) {
      if (typeof p[key] === "string" && isRasterDataUrl(p[key])) s[key] = p[key];
    }
    if (p.optimize && typeof p.optimize === "object") {
      for (const key of ["noActions", "segments", "autoSticker", "emoji", "shortReplies", "quotes"]) {
        if (typeof p.optimize[key] === "boolean") s.optimize[key] = p.optimize[key];
      }
    }
    if (p.realism && typeof p.realism === "object") {
      for (const key of ["enabled", "typing", "autoDelay"]) {
        if (typeof p.realism[key] === "boolean") s.realism[key] = p.realism[key];
      }
      s.realism.minDelay = clamp(Number(p.realism.minDelay) || s.realism.minDelay, 0, 20);
      s.realism.maxDelay = clamp(Number(p.realism.maxDelay) || s.realism.maxDelay, s.realism.minDelay, 30);
      s.realism.segmentDelay = clamp(Number(p.realism.segmentDelay) || s.realism.segmentDelay, 0, 8);
    }
    if (p.blocking && typeof p.blocking === "object") {
      s.blocking.enabled = Boolean(p.blocking.enabled);
      s.blocking.minutes = clamp(Number(p.blocking.minutes) || 30, 1, 1440);
      s.blocking.mode = p.blocking.mode === "reject" ? "reject" : "silent";
    }
    if (p.memory && typeof p.memory === "object") {
      s.memory.auto = Boolean(p.memory.auto);
    }
    if (p.notifications && typeof p.notifications === "object") {
      s.notifications.enabled = Boolean(p.notifications.enabled);
      s.notifications.background = Boolean(p.notifications.background);
    }
    s.chatBgOpacity = clamp(Number(p.chatBgOpacity) || 0.24, 0.08, 0.65);
    if (Array.isArray(p.memories)) {
      state.memories = p.memories
        .filter((memory) => memory && typeof memory.text === "string")
        .slice(-60)
        .map((memory) => ({ id: uid("mem"), text: memory.text.slice(0, 180), createdAt: Date.now() }));
    }
    if (Array.isArray(p.customStickers)) {
      state.customStickers = p.customStickers
        .filter((sticker) => sticker?.dataUrl && sticker?.id && isImageDataUrl(sticker.dataUrl))
        .slice(-120)
        .map((sticker) => ({
          id: String(sticker.id).slice(0, 60),
          name: String(sticker.name || "sticker").slice(0, 12),
          dataUrl: sticker.dataUrl,
          packId: typeof sticker.packId === "string" ? sticker.packId.slice(0, 60) : "",
          ai: Boolean(sticker.ai),
          svg: typeof sticker.svg === "string" && sticker.svg.startsWith("<svg") ? sticker.svg.slice(0, 30_000) : "",
        }));
    }
    if (Array.isArray(p.stickerStudio?.packs)) {
      state.stickerStudio.packs = p.stickerStudio.packs
        .filter((pack) => pack?.id && Array.isArray(pack.stickerIds))
        .slice(-12)
        .map((pack) => ({
          id: String(pack.id).slice(0, 60),
          name: String(pack.name || t("studio.title")).slice(0, 24),
          theme: String(pack.theme || "").slice(0, 80),
          source: "ai",
          createdAt: Number(pack.createdAt) || Date.now(),
          stickerIds: pack.stickerIds.filter((id) => typeof id === "string").slice(0, 8),
          assetIds: [],
          equipped: Boolean(pack.equipped),
        }));
    }
    await waitForSandboxHost(1000);
    for (const pack of state.stickerStudio.packs) {
      const assetIds = [];
      for (const stickerId of pack.stickerIds) {
        const sticker = state.customStickers.find((item) => item.id === stickerId);
        if (!sticker?.svg) continue;
        try {
          const asset = await hostSticker(sticker.svg, `${pack.name} · ${sticker.name}`, {
            source: "sticker-pack",
            packId: pack.id,
            stickerId: sticker.id,
          });
          assetIds.push(asset.id);
        } catch {
          // ignore hosting failure
        }
      }
      pack.assetIds = assetIds;
    }
    persist();
    applyAppearance();
    applyStaticI18n();
    renderHeader();
    renderChat();
    renderSettings(settingsCallbacks());
    toast(t("settings.importOk"));
  } catch (error) {
    toast(t("settings.importFail", { msg: error.message || "invalid" }));
  } finally {
    const input = $("#importInput");
    if (input) input.value = "";
  }
}

async function shareApp() {
  const url = new URL(location.href);
  url.search = "";
  url.hash = "";
  const data = { title: "Lian", text: t("app.tagline"), url: url.toString() };
  try {
    if (navigator.share) {
      await navigator.share(data);
    } else if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(url.toString());
      toast(t("settings.shareCopied"));
    } else {
      toast(t("settings.shareFail"));
    }
  } catch (error) {
    if (error?.name !== "AbortError") {
      try {
        await navigator.clipboard.writeText(url.toString());
        toast(t("settings.shareCopied"));
      } catch {
        toast(t("settings.shareFail"));
      }
    }
  }
}

async function clearChat(withConfirm = false) {
  if (withConfirm) {
    const ok = await confirmDialog({
      title: t("menu.clear"),
      body: t("settings.clearChatConfirm"),
      confirm: t("common.delete"),
      danger: true,
    });
    if (!ok) return;
  }
  state.messages = [];
  state.block = null;
  activeQuote = null;
  state.memoryMeta.lastUserCount = 0;
  renderedIds = new Set();
  lastRenderedDay = "";
  lastFailed = null;
  state.settings.proactive.lastAt = Date.now();
  persist();
  renderQuotePreview();
  updateBlockUI();
  renderChat();
  hideError();
  closeAllOverlays();
  toast(t("settings.cleared"));
}

async function clearAllData() {
  await resetStorage();
  try {
    window.LianNative?.setBackgroundEnabled?.(false);
  } catch {
    // ignore
  }
  clearInterval(proactiveTimer);
  demoMode = false;
  state = defaultState();
  renderedIds = new Set();
  lastRenderedDay = "";
  activeAttachment = null;
  activeQuote = null;
  clearInterval(blockTicker);
  blockTicker = 0;
  closeAllOverlays();
  setLang(state.settings.uiLang);
  applyAppearance();
  applyStaticI18n();
  renderHeader();
  showSetup(0);
  toast(t("settings.cleared"));
}

/* =========================================================
   Event wiring
   ========================================================= */

function bindGlobalEvents() {
  $("#headsUp")?.addEventListener("click", (event) => {
    if (event.target.closest("#headsClose")) {
      event.stopPropagation();
      hideHeadsUp();
      return;
    }
    const messageId = $("#headsUp")?.dataset.message || "";
    hideHeadsUp();
    closeAllOverlays();
    showScreen("chat");
    applyAppearance();
    renderHeader();
    renderChat();
    if (messageId) {
      requestAnimationFrame(() => {
        const message = document.querySelector(`[data-message="${String(messageId).replace(/["\\]/g, "")}"]`);
        message?.scrollIntoView({ block: "center", behavior: "smooth" });
      });
    }
  });
  $("#composer")?.addEventListener("submit", (event) => {
    event.preventDefault();
    if (sending) {
      stopGeneration();
      return;
    }
    setComposerTray(false);
    handleSend();
  });
  /* 助理页输入栏上方的两个能力开关 */
  $("#assistantTools")?.addEventListener("click", (event) => {
    const button = event.target.closest("[data-assistant-tool]");
    if (!button || !state) return;
    const key = button.dataset.assistantTool;
    if (key !== "web" && key !== "thinking") return;
    if (!assistantCapabilities()[key]) {
      toast(t("assistant.capabilityUnsupported"));
      return;
    }
    if (!state.settings.assistant || typeof state.settings.assistant !== "object") {
      state.settings.assistant = { web: false, thinking: false };
    }
    state.settings.assistant[key] = !state.settings.assistant[key];
    syncAssistantTools();
    syncAssistantThinking();
    persist();
  });

  const input = $("#messageInput");
  input?.addEventListener("input", () => {
    autoResizeInput(input);
    updateSendButton();
    saveDraft(input.value);
  });
  input?.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault();
      if (!sending) handleSend();
    }
  });

  /* 「+」不再直接弹面板，先在输入栏里张开一层工具盘 */
  $("#btnAttach")?.addEventListener("click", () => {
    const tray = $("#composerTray");
    setComposerTray(Boolean(tray?.hidden));
  });
  $("#composerTray")?.addEventListener("click", (event) => {
    const emoji = event.target.closest("[data-emoji]");
    if (emoji) {
      insertEmoji(emoji.dataset.emoji);
      return;
    }
    const action = event.target.closest("[data-tray]");
    if (!action) return;
    const kind = action.dataset.tray;
    if (kind === "image" || kind === "file") {
      setComposerTray(false);
      const picker = kind === "image" ? $("#imageInput") : $("#fileInput");
      if (picker) {
        picker.value = "";
        picker.click();
      }
      return;
    }
    setComposerTray(false);
    if (kind === "sticker") openStickerSheet("builtin");
    else if (kind === "report") openReportSheet();
    else openAttachSheet();
  });
  $("#btnSticker")?.addEventListener("click", () => openStickerSheet(stickerTab));
  $("#btnChatBack")?.addEventListener("click", openChatList);
  $("#btnPeer")?.addEventListener("click", () => openSettings("persona", "chat"));
  $("#btnNewChat")?.addEventListener("click", openNewChatSheet);
  $("#btnNewContact")?.addEventListener("click", openNewChatSheet);
  $("#btnHomeNewChat")?.addEventListener("click", openNewChatSheet);
  $("#tabBar")?.addEventListener("click", (event) => {
    const tab = event.target.closest("[data-tab]");
    if (tab) openTab(tab.dataset.tab);
  });
  $("#chatList")?.addEventListener("click", (event) => {
    if (event.target.closest("[data-new-chat]")) {
      openNewChatSheet();
      return;
    }
    const row = event.target.closest("[data-chat-open]");
    if (row) switchChat(row.dataset.chatOpen);
  });
  $("#contactsList")?.addEventListener("click", (event) => {
    if (event.target.closest("[data-contacts-clear]")) {
      contactsQuery = "";
      renderContacts();
      return;
    }
    if (event.target.closest("[data-new-contact]")) {
      openNewChatSheet();
      return;
    }
    const row = event.target.closest("[data-chat-open]");
    if (row) switchChat(row.dataset.chatOpen);
  });
  $("#contactsSearchInput")?.addEventListener("input", (event) => {
    contactsQuery = String(event.target.value || "");
    renderContacts();
  });
  $("#contactsSearchInput")?.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      contactsQuery = "";
      renderContacts();
    }
  });
  $("#contactsSearchClear")?.addEventListener("click", () => {
    contactsQuery = "";
    renderContacts();
    $("#contactsSearchInput")?.focus();
  });
  $("#contactsSort")?.addEventListener("click", (event) => {
    const button = event.target.closest("[data-contacts-sort]");
    if (!button) return;
    contactsSort = button.dataset.contactsSort === "name" ? "name" : "recent";
    renderContacts();
  });
  $("#homeBody")?.addEventListener("click", (event) => {
    const shuffle = event.target.closest("[data-daily-shuffle]");
    if (shuffle) {
      dailyShift += 1;
      renderHome(true);
      return;
    }
    if (event.target.closest("[data-daily-ask]")) {
      askDailyQuestion();
      return;
    }
    const button = event.target.closest("[data-home-action]");
    if (!button) return;
    const action = button.dataset.homeAction;
    if (action === "report") {
      closeAllOverlays();
      showScreen("chat");
      applyAppearance();
      renderHeader();
      renderChat();
      openReportSheet();
      return;
    }
    if (action === "newChat") {
      openNewChatSheet();
      return;
    }
    if (action === "allChats") {
      openTab("list");
      return;
    }
    openSettings(action, "home");
  });
  $("#btnSettingsBack")?.addEventListener("click", closeSettings);
  $("#btnSettingsDone")?.addEventListener("click", closeSettings);
  $("#btnRetry")?.addEventListener("click", () => {
    const failed = lastFailed;
    if (!failed) {
      hideError();
      return;
    }
    hideError();
    if (failed.proactive && !failed.afterBlock) sendProactive({ manual: true });
    else requestAssistant(failed.userMessage, { retry: true, afterBlock: Boolean(failed.afterBlock) });
  });
  $("#btnErrorClose")?.addEventListener("click", hideError);
  $("#btnUnblock")?.addEventListener("click", () => clearBlock());
  $("#jumpLatest")?.addEventListener("click", () => scrollToBottom(true));

  $("#chatScroll")?.addEventListener("scroll", updateJumpButton, { passive: true });

  $("#imageInput")?.addEventListener("change", (event) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    handleImageFile(file);
  });
  $("#fileInput")?.addEventListener("change", (event) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    handleFileAttachment(file);
  });
  $("#avatarInput")?.addEventListener("change", (event) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    handleAvatarFile(file);
  });
  $("#bgInput")?.addEventListener("change", (event) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    handleBackgroundFile(file);
  });
  $("#stickerInput")?.addEventListener("change", (event) => {
    const files = [...(event.target.files || [])];
    event.target.value = "";
    handleStickerFiles(files);
  });
  $("#importInput")?.addEventListener("change", (event) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    importProfile(file);
  });

  $("#settingsBody")?.addEventListener("click", (event) => {
    const generate = event.target.closest("[data-generate-pack]");
    if (generate) {
      generateStickerPack(generate);
      return;
    }
    const equip = event.target.closest("[data-studio-equip]");
    if (equip) {
      toggleStickerPack(equip.dataset.studioEquip);
      return;
    }
    const preview = event.target.closest("[data-studio-preview]");
    if (preview) {
      const pack = state.stickerStudio.packs.find((item) => item.id === preview.dataset.studioPreview);
      if (pack) openStickerPackModal(pack);
      return;
    }
    const copy = event.target.closest("[data-studio-copy]");
    if (copy) {
      copyPackHostUrl(copy.dataset.studioCopy);
      return;
    }
    const sandbox = event.target.closest("[data-open-sandbox]");
    if (sandbox) {
      openSandboxWorkbench();
    }
  });

  $("#messageList")?.addEventListener("click", (event) => {
    if (event.target.closest("[data-load-earlier]")) {
      loadEarlierMessages();
      return;
    }
    const quoteButton = event.target.closest("[data-quote]");
    if (quoteButton) {
      event.preventDefault();
      startQuote(quoteButton.dataset.quote);
      return;
    }
    const image = event.target.closest("[data-image]");
    if (image) {
      const message = state.messages.find((m) => m.id === image.dataset.image);
      if (message?.image?.dataUrl) lightboxImage(message.image.dataUrl, message.text || t("chat.image"));
      return;
    }
    const report = event.target.closest("[data-report]");
    if (report) {
      const message = state.messages.find((m) => m.id === report.dataset.report);
      if (message?.report) openReportViewer(message);
      return;
    }
    const sticker = event.target.closest("[data-sticker-view]");
    if (sticker) {
      const message = state.messages.find((m) => m.id === sticker.dataset.stickerView);
      const item = getSticker(message?.stickerId, state.customStickers);
      if (item) lightboxImage(stickerSrc(item), item.name);
      return;
    }
    const drawing = event.target.closest("[data-drawing-view]");
    if (drawing) {
      const message = state.messages.find((m) => m.id === drawing.dataset.drawingView);
      if (message?.drawing) openDrawingViewer(message);
    }
  });

  // Long-press / right-click also starts a quote, matching mobile chat habits.
  $("#messageList")?.addEventListener("contextmenu", (event) => {
    const message = event.target.closest(".msg[data-message]");
    if (!message) return;
    event.preventDefault();
    startQuote(message.dataset.message);
  });

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
      saveNow(state);
      flushNativeSnapshot();
    } else {
      syncNativeRuntime();
      pullNativeMessages();
      reconcileNativeBlockFollowUp();
      updateBlockUI();
      startBlockTicker();
      checkProactive();
    }
  });
  window.addEventListener("pagehide", () => {
    saveNow(state);
    flushNativeSnapshot();
  });
  navigator.serviceWorker?.addEventListener("controllerchange", () => {
    if (document.body.dataset.screen === "settings") renderSettings(settingsCallbacks());
  });

  // Global escape closes the topmost UI layer.
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      if (!$("#modalLayer")?.hidden) closeModal();
      else if (!$("#sheetLayer")?.hidden) closeSheet();
    }
  });
}

/* =========================================================
   Start
   ========================================================= */

init().catch((error) => {
  console.error("Lian failed to start:", error);
  const boot = $("#boot");
  if (boot) {
    boot.classList.remove("is-done");
    boot.innerHTML = `<p style="padding:24px;color:#666;font-size:13px;line-height:1.7">Lian 启动失败：${escapeHtml(error.message || String(error))}<br>请刷新页面，或确认通过本地服务器打开。</p>`;
  }
});
