/* =========================================================
   insights — 列表 / 主页要用的小统计
   ---------------------------------------------------------
   纯函数，不碰 DOM、不读全局状态，方便单测：
     · 连续聊天天数（今天或昨天有消息才算在连着）
     · 今天聊了多少条
     · 认识第几天
     · 按小时给出问候时段
   ========================================================= */

const DAY = 86400000;

/** Local calendar day, as a comparable integer (not a string, avoids TZ drift). */
export function dayNumber(ts) {
  const date = new Date(Number(ts) || 0);
  return Math.floor((date.getTime() - date.getTimezoneOffset() * 60000) / DAY);
}

/** Every message timestamp in every chat, flattened. */
export function allTimestamps(chats = []) {
  const out = [];
  for (const chat of chats) {
    for (const message of chat?.messages || []) {
      const ts = Number(message?.ts);
      if (Number.isFinite(ts) && ts > 0) out.push(ts);
    }
  }
  return out;
}

/**
 * How many days in a row (ending today, or yesterday when today is still empty)
 * have at least one message.
 */
export function streakDays(timestamps = [], now = Date.now()) {
  const days = new Set(timestamps.map(dayNumber));
  if (!days.size) return 0;
  const today = dayNumber(now);
  let cursor = days.has(today) ? today : today - 1;
  if (!days.has(cursor)) return 0;
  let streak = 0;
  while (days.has(cursor)) {
    streak += 1;
    cursor -= 1;
  }
  return streak;
}

export function todayCount(timestamps = [], now = Date.now()) {
  const today = dayNumber(now);
  return timestamps.filter((ts) => dayNumber(ts) === today).length;
}

/** Days since the first chat was created, inclusive (day one is 1). */
export function togetherDays(chats = [], now = Date.now()) {
  const created = chats
    .map((chat) => Number(chat?.createdAt))
    .filter((value) => Number.isFinite(value) && value > 0);
  if (!created.length) return 0;
  return Math.max(1, dayNumber(now) - dayNumber(Math.min(...created)) + 1);
}

export function chatStats(chats = [], now = Date.now()) {
  const timestamps = allTimestamps(chats);
  const unread = chats.reduce((sum, chat) => sum + Math.max(0, Number(chat?.unread) || 0), 0);
  return {
    chats: chats.length,
    unread,
    today: todayCount(timestamps, now),
    streak: streakDays(timestamps, now),
    together: togetherDays(chats, now),
    total: timestamps.length,
  };
}

/** morning / afternoon / evening / night, from the local hour. */
export function greetingPeriod(hour) {
  const h = Number(hour);
  if (!Number.isFinite(h)) return "evening";
  if (h >= 5 && h < 11) return "morning";
  if (h >= 11 && h < 14) return "noon";
  if (h >= 14 && h < 18) return "afternoon";
  if (h >= 18 && h < 23) return "evening";
  return "night";
}

/**
 * Which daily prompt to show. Stable for a whole day, then moves on; `shift`
 * lets the shuffle button page through the list without touching storage.
 */
export function dailyQuestionIndex(now = Date.now(), shift = 0, total = 8) {
  const day = Math.floor(Number(now) / DAY);
  const count = Math.max(1, Math.trunc(Number(total) || 8));
  return (((day + Math.trunc(Number(shift) || 0)) % count) + count) % count;
}
