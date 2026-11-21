import { defaultState } from "./config.js";

const DB_NAME = "lian-chat";
const DB_VERSION = 2;
const STORE = "state";
const ASSET_STORE = "assets";
const KEY = "main";
const LS_FALLBACK = "lian.state.fallback.v1";

let dbPromise = null;
let saveTimer = 0;
let pendingState = null;

function openDB() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    if (!("indexedDB" in window)) {
      reject(new Error("IndexedDB unavailable"));
      return;
    }
    let settled = false;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (fn === reject) dbPromise = null;
      fn(value);
    };
    const timer = setTimeout(() => {
      dbPromise = null;
      finish(reject, new Error("IndexedDB open timed out"));
    }, 1600);
    let req;
    try {
      req = indexedDB.open(DB_NAME, DB_VERSION);
    } catch (error) {
      finish(reject, error);
      return;
    }
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE);
      if (!db.objectStoreNames.contains(ASSET_STORE)) db.createObjectStore(ASSET_STORE);
    };
    req.onsuccess = () => finish(resolve, req.result);
    req.onerror = () => finish(reject, req.error || new Error("IndexedDB open failed"));
    req.onblocked = () => finish(reject, new Error("IndexedDB blocked"));
  });
  return dbPromise;
}

function idbGet(key, storeName = STORE) {
  return openDB().then(
    (db) =>
      new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, "readonly");
        const req = tx.objectStore(storeName).get(key);
        req.onsuccess = () => resolve(req.result ?? null);
        req.onerror = () => reject(req.error);
      }),
  );
}

function idbPut(key, value, storeName = STORE) {
  return openDB().then(
    (db) =>
      new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, "readwrite");
        tx.objectStore(storeName).put(value, key);
        tx.oncomplete = () => resolve(true);
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error || new Error("IndexedDB write aborted"));
      }),
  );
}

function idbDelete(key, storeName = STORE) {
  return openDB().then(
    (db) =>
      new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, "readwrite");
        tx.objectStore(storeName).delete(key);
        tx.oncomplete = () => resolve(true);
        tx.onerror = () => reject(tx.error);
      }),
  );
}

export function putSandboxAsset(asset) {
  if (!asset?.id) return Promise.reject(new Error("asset id required"));
  return idbPut(asset.id, asset, ASSET_STORE);
}

export function getSandboxAsset(id) {
  return idbGet(id, ASSET_STORE);
}

export function deleteSandboxAsset(id) {
  return idbDelete(id, ASSET_STORE);
}

export function listSandboxAssets() {
  return openDB().then(
    (db) =>
      new Promise((resolve, reject) => {
        const tx = db.transaction(ASSET_STORE, "readonly");
        const req = tx.objectStore(ASSET_STORE).getAll();
        req.onsuccess = () => resolve(req.result || []);
        req.onerror = () => reject(req.error);
      }),
  );
}

function clearAssetStore() {
  return openDB().then(
    (db) =>
      new Promise((resolve, reject) => {
        const tx = db.transaction(ASSET_STORE, "readwrite");
        tx.objectStore(ASSET_STORE).clear();
        tx.oncomplete = () => resolve(true);
        tx.onerror = () => reject(tx.error);
      }),
  );
}

function deepMerge(base, extra) {
  if (!extra || typeof extra !== "object" || Array.isArray(extra)) return base;
  const out = Array.isArray(base) ? [...base] : { ...base };
  for (const [key, value] of Object.entries(extra)) {
    if (value && typeof value === "object" && !Array.isArray(value) && base?.[key] && typeof base[key] === "object" && !Array.isArray(base[key])) {
      out[key] = deepMerge(base[key], value);
    } else if (value !== undefined) {
      out[key] = value;
    }
  }
  return out;
}

export function normaliseState(raw) {
  const base = defaultState();
  if (!raw || typeof raw !== "object") return base;
  const merged = deepMerge(base, raw);
  if (!merged.settings || typeof merged.settings !== "object") merged.settings = base.settings;
  if (!merged.settings.optimize || typeof merged.settings.optimize !== "object") merged.settings.optimize = { ...base.settings.optimize };
  merged.messages = Array.isArray(merged.messages) ? merged.messages.filter(Boolean).slice(-400) : [];
  merged.memories = Array.isArray(merged.memories) ? merged.memories.filter(Boolean).slice(-60) : [];
  merged.activeChatId = typeof merged.activeChatId === "string" ? merged.activeChatId : "";
  merged.activeKeyId = typeof merged.activeKeyId === "string" ? merged.activeKeyId : "";
  merged.activeByMode = {
    companion: typeof merged.activeByMode?.companion === "string" ? merged.activeByMode.companion : "",
    roleplay: typeof merged.activeByMode?.roleplay === "string" ? merged.activeByMode.roleplay : "",
    assistant: typeof merged.activeByMode?.assistant === "string" ? merged.activeByMode.assistant : "",
  };
  merged.keys = Array.isArray(merged.keys)
    ? merged.keys
        .filter((key) => key && typeof key === "object" && key.id)
        .map((key) => ({
          id: String(key.id).slice(0, 80),
          name: String(key.name || key.provider || "Key").slice(0, 40),
          provider: String(key.provider || "custom").slice(0, 30),
          apiKey: String(key.apiKey || "").slice(0, 500),
          baseUrl: String(key.baseUrl || "").slice(0, 500),
          model: String(key.model || "").slice(0, 120),
          visionModel: String(key.visionModel || "").slice(0, 120),
          createdAt: Number(key.createdAt) || Date.now(),
        }))
        .slice(-20)
    : [];
  merged.chats = Array.isArray(merged.chats)
    ? merged.chats
        .filter((chat) => chat && typeof chat === "object" && chat.id)
        .map((chat) => ({
          ...chat,
          id: String(chat.id).slice(0, 80),
          name: String(chat.name || "Lian").slice(0, 120),
          /* 1.9.18：会话按模块分开。旧数据没有 mode，那些历史都是陪伴模式的。 */
          mode: ["companion", "roleplay", "assistant"].includes(chat.mode) ? chat.mode : "companion",
          kind: chat.kind === "module" ? "module" : "",
          avatar: typeof chat.avatar === "string" ? chat.avatar : "",
          relationship: String(chat.relationship || "").slice(0, 300),
          persona: String(chat.persona || "").slice(0, 1200),
          greeting: String(chat.greeting || "").slice(0, 500),
          keyId: String(chat.keyId || "").slice(0, 80),
          messages: Array.isArray(chat.messages) ? chat.messages.filter(Boolean).slice(-400) : [],
          memories: Array.isArray(chat.memories) ? chat.memories.filter(Boolean).slice(-60) : [],
          memoryMeta: chat.memoryMeta && typeof chat.memoryMeta === "object" ? chat.memoryMeta : { lastUserCount: 0, lastAttemptAt: 0, lastAt: 0 },
          block: chat.block && typeof chat.block === "object" ? chat.block : null,
          blockFollowUp: chat.blockFollowUp && typeof chat.blockFollowUp === "object" ? chat.blockFollowUp : null,
          createdAt: Number(chat.createdAt) || Date.now(),
          updatedAt: Number(chat.updatedAt) || Date.now(),
        }))
        .slice(-30)
    : [];
  merged.customStickers = Array.isArray(merged.customStickers)
    ? merged.customStickers
        .filter((s) => s?.id && s?.dataUrl)
        .map((s) => ({
          ...s,
          caption: typeof s.caption === "string" ? s.caption : "",
          aliases: Array.isArray(s.aliases) ? s.aliases.filter((alias) => typeof alias === "string").slice(0, 8) : [],
        }))
        .slice(-120)
    : [];
  const seenEmoji = new Set();
  merged.emojiUsage = Array.isArray(merged.emojiUsage)
    ? merged.emojiUsage
        .filter((item) => item && typeof item.e === "string" && item.e)
        .map((item) => ({
          e: item.e.slice(0, 16),
          n: Math.min(999, Math.max(1, Number(item.n) || 1)),
          at: Math.max(0, Number(item.at) || 0),
        }))
        .sort((a, b) => b.at - a.at)
        .filter((item) => !seenEmoji.has(item.e) && seenEmoji.add(item.e))
        .slice(0, 12)
    : [];
  merged.stickerStudio = merged.stickerStudio && typeof merged.stickerStudio === "object" ? merged.stickerStudio : { packs: [], lastAt: 0 };
  merged.stickerStudio.style = ["auto", "kaomoji", "plush", "emoji"].includes(merged.stickerStudio.style)
    ? merged.stickerStudio.style
    : "auto";
  merged.stickerStudio.direction = typeof merged.stickerStudio.direction === "string"
    ? merged.stickerStudio.direction.slice(0, 180)
    : "";
  merged.stickerStudio.packs = Array.isArray(merged.stickerStudio.packs)
    ? merged.stickerStudio.packs
        .filter((p) => p?.id && Array.isArray(p.stickerIds))
        .map((pack) => ({ ...pack, equipped: pack.equipped !== false }))
        .slice(-12)
    : [];
  merged.settings.apiKey = typeof merged.settings.apiKey === "string" ? merged.settings.apiKey.trim() : "";
  const realism = merged.settings.realism || {};
  realism.enabled = realism.enabled !== false;
  realism.typing = realism.typing !== false;
  realism.autoDelay = realism.autoDelay !== false;
  realism.minDelay = Math.min(20, Math.max(0, Number(realism.minDelay) || 1.2));
  realism.maxDelay = Math.min(30, Math.max(realism.minDelay, Number(realism.maxDelay) || 4.5));
  realism.segmentDelay = Math.min(8, Math.max(0, Number(realism.segmentDelay) || 0.85));
  merged.settings.realism = realism;
  merged.settings.blocking = {
    enabled: Boolean(merged.settings.blocking?.enabled),
    minutes: Math.min(1440, Math.max(1, Number(merged.settings.blocking?.minutes) || 30)),
    mode: merged.settings.blocking?.mode === "reject" ? "reject" : "silent",
  };
  merged.settings.memory = { auto: Boolean(merged.settings.memory?.auto) };
  merged.settings.notifications = {
    enabled: Boolean(merged.settings.notifications?.enabled),
    background: Boolean(merged.settings.notifications?.background),
  };
  if (!merged.settings.notifications.enabled) merged.settings.notifications.background = false;
  merged.settings.optimize.quotes = merged.settings.optimize.quotes !== false;
  merged.settings.optimize.drawings = merged.settings.optimize.drawings === true;
  merged.settings.mode = ["companion", "roleplay", "assistant"].includes(merged.settings.mode)
    ? merged.settings.mode
    : "companion";
  merged.settings.modeTheme =
    typeof merged.settings.modeTheme === "string" && merged.settings.modeTheme
      ? merged.settings.modeTheme.slice(0, 30)
      : "paper";
  /* 1.9.19：自定义色号（theme=custom）也要能原样带回来。 */
  merged.settings.modeAccent =
    typeof merged.settings.modeAccent === "string" ? merged.settings.modeAccent.slice(0, 30) : "";
  /* 1.9.21：助理页的联网 / 深度思考开关 */
  merged.settings.assistant = {
    web: Boolean(merged.settings.assistant?.web),
    thinking: Boolean(merged.settings.assistant?.thinking),
  };
  merged.settings.layout = ["line", "imessage", "letter", "bubble", "plain", "journal", "timeline", "comic"].includes(merged.settings.layout)
    ? merged.settings.layout
    : "line";
  merged.memoryMeta = {
    lastUserCount: Math.max(0, Number(merged.memoryMeta?.lastUserCount) || 0),
    lastAttemptAt: Math.max(0, Number(merged.memoryMeta?.lastAttemptAt) || 0),
    lastAt: Math.max(0, Number(merged.memoryMeta?.lastAt) || 0),
  };
  if (merged.block && !(Number(merged.block.until) > Date.now())) {
    // If the app was closed when a block ended, remember that the AI still
    // owes the user a short follow-up message.
    merged.blockFollowUp = { pending: true, endedAt: Number(merged.block.until) || Date.now() };
    merged.block = null;
  }
  if (!merged.block && !merged.blockFollowUp) merged.blockFollowUp = null;
  merged.version = 1;
  return merged;
}

export async function loadState() {
  try {
    const value = await idbGet(KEY);
    if (value) return normaliseState(value);
  } catch {
    // Private modes and locked-down browsers can reject IndexedDB.
  }
  try {
    const raw = localStorage.getItem(LS_FALLBACK);
    if (raw) return normaliseState(JSON.parse(raw));
  } catch {
    // Ignore malformed or unavailable fallback storage.
  }
  return null;
}

function trimForFallback(state) {
  const clone = JSON.parse(JSON.stringify(state));
  clone.settings.chatBg = "";
  const trim = (list) => (Array.isArray(list) ? list.slice(-60) : []).map((m) => {
    if (m.image?.dataUrl && m.image.dataUrl.length > 300_000) {
      delete m.image.dataUrl;
      m.image.missing = true;
    }
    if (m.file?.dataUrl && m.file.dataUrl.length > 200_000) {
      delete m.file.dataUrl;
      m.file.missing = true;
    }
    /* 思考过程可能很长：降级存储只留开头，答案本身不丢。 */
    if (typeof m.reasoning === "string" && m.reasoning.length > 4000) {
      m.reasoning = `${m.reasoning.slice(0, 4000)}…`;
    }
    if (Array.isArray(m.sources) && m.sources.length > 5) m.sources = m.sources.slice(0, 5);
    return m;
  });
  clone.messages = trim(clone.messages);
  /* 每个模块的会话也存了消息：只裁当前那条会让其它模块在降级存储里整段消失。 */
  clone.chats = (clone.chats || []).map((chat) => ({ ...chat, messages: trim(chat.messages) }));
  clone.customStickers = clone.customStickers.map((s) => (s.dataUrl.length > 120_000 ? { ...s, dataUrl: "" } : s)).filter((s) => s.dataUrl);
  return clone;
}

export function scheduleSave(state) {
  pendingState = state;
  clearTimeout(saveTimer);
  saveTimer = window.setTimeout(() => {
    saveNow(pendingState);
  }, 220);
}

export async function saveNow(state = pendingState) {
  if (!state) return;
  clearTimeout(saveTimer);
  saveTimer = 0;
  try {
    await idbPut(KEY, state);
  } catch {
    try {
      localStorage.setItem(LS_FALLBACK, JSON.stringify(trimForFallback(state)));
    } catch {
      // Last resort: keep running in memory.
    }
  }
}

export async function resetStorage() {
  clearTimeout(saveTimer);
  pendingState = null;
  try {
    await idbDelete(KEY);
  } catch {
    // ignore
  }
  try {
    await clearAssetStore();
  } catch {
    // ignore
  }
  try {
    localStorage.removeItem(LS_FALLBACK);
  } catch {
    // ignore
  }
}
