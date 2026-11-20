import test from "node:test";
import assert from "node:assert/strict";
import { chatStats, dailyQuestionIndex, dayNumber, greetingPeriod, streakDays, todayCount, togetherDays } from "../js/insights.js";

const DAY = 86400000;
/* Work in whole days so the local-calendar arithmetic is the only variable. */
const at = (daysAgo, hour = 12) => {
  const d = new Date();
  d.setDate(d.getDate() - daysAgo);
  d.setHours(hour, 0, 0, 0);
  return d.getTime();
};

test("streak: counts consecutive days ending today", () => {
  const now = at(0);
  assert.equal(streakDays([at(0), at(1), at(1), at(2)], now), 3);
  assert.equal(streakDays([at(0)], now), 1);
  assert.equal(streakDays([], now), 0);
  /* today empty but yesterday talked: the streak is still alive */
  assert.equal(streakDays([at(1), at(2)], now), 2);
  /* a gap kills it */
  assert.equal(streakDays([at(2), at(3)], now), 0);
});

test("streak: same day repeated only counts once", () => {
  assert.equal(streakDays([at(0, 9), at(0, 20), at(0, 23)], at(0)), 1);
});

test("today: only today's messages", () => {
  assert.equal(todayCount([at(0, 1), at(0, 23), at(1)], at(0, 23)), 2);
});

test("together: day one is 1, not 0", () => {
  assert.equal(togetherDays([{ createdAt: at(0) }], at(0)), 1);
  assert.equal(togetherDays([{ createdAt: at(6) }], at(0)), 7);
  assert.equal(togetherDays([], at(0)), 0);
  assert.equal(togetherDays([{ createdAt: at(9) }, { createdAt: at(3) }], at(0)), 10);
});

test("chatStats: adds up chats, unread, today and streak", () => {
  const chats = [
    { createdAt: at(4), unread: 2, messages: [{ ts: at(0) }, { ts: at(1) }] },
    { createdAt: at(9), unread: 0, messages: [{ ts: at(1) }, { ts: at(2) }] },
  ];
  const stats = chatStats(chats, at(0));
  assert.equal(stats.chats, 2);
  assert.equal(stats.unread, 2);
  assert.equal(stats.today, 1);
  assert.equal(stats.streak, 3);
  assert.equal(stats.together, 10);
  assert.equal(stats.total, 4);
});

test("dayNumber: a fixed timestamp maps to one local day", () => {
  const ts = at(0, 0);
  assert.equal(dayNumber(ts), dayNumber(ts + 60000));
  assert.equal(dayNumber(ts) - dayNumber(at(1)), 1);
});

test("daily question: stable within a day, shifts with the shuffle button", () => {
  const noon = at(0, 12);
  const late = at(0, 23);
  assert.equal(dailyQuestionIndex(noon, 0), dailyQuestionIndex(late, 0));
  assert.equal(dailyQuestionIndex(noon, 0), dailyQuestionIndex(noon + 86400000, 7));
  assert.equal(dailyQuestionIndex(noon, 1), (dailyQuestionIndex(noon, 0) + 1) % 8);
  assert.equal(dailyQuestionIndex(noon, -1), (dailyQuestionIndex(noon, 0) + 7) % 8);
  assert.ok(dailyQuestionIndex(noon, -99) >= 0 && dailyQuestionIndex(noon, -99) < 8);
});

test("greeting: hour bands", () => {
  assert.equal(greetingPeriod(7), "morning");
  assert.equal(greetingPeriod(12), "noon");
  assert.equal(greetingPeriod(16), "afternoon");
  assert.equal(greetingPeriod(20), "evening");
  assert.equal(greetingPeriod(2), "night");
  assert.equal(greetingPeriod("x"), "evening");
});
