import { AI_LANGS, CHAT_LAYOUTS, FONTS, PROVIDERS, THEMES, UI_LANGS, estimateReportTokens, estimateStickerPackTokens, getSticker, stickerSrc, themeLabel } from "./config.js";
import { t } from "./i18n.js";
import { testConnection, errorText } from "./api.js";
import { sandboxHostStatus } from "./sandbox.js";
import { avatarMarkup, confirmDialog, icon, setLoading, toast } from "./ui.js";
import { escapeHtml, uid } from "./utils.js";
import { STICKER_STYLE_OPTIONS } from "./studio.js";
import { normaliseAccent } from "./palette.js";

function group(id, title, hint, iconName, body, open = false) {
  return `<details class="settings-group" data-group="${id}" ${open ? "open" : ""}>
    <summary>
      <span class="group-icon">${icon(iconName)}</span>
      <span class="group-copy"><b>${escapeHtml(title)}</b><small>${escapeHtml(hint)}</small></span>
      <svg class="group-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="m6 9 6 6 6-6"/></svg>
    </summary>
    <div class="group-body">${body}</div>
  </details>`;
}

function switchRow(label, hint, checked, attrs = "", disabled = false) {
  return `<label class="setting-row" ${attrs}>
    <span class="setting-copy"><b>${escapeHtml(label)}</b><small>${escapeHtml(hint)}</small></span>
    <span class="switch"><input type="checkbox" ${checked ? "checked" : ""} ${disabled ? "disabled" : ""}><span></span></span>
  </label>`;
}

export function refreshNativeBackgroundUI(root = document.querySelector("#settingsBody")) {
  const card = root?.querySelector("#bgPermission");
  if (!card || !window.LianNative?.getBackgroundStatus) return;
  let status = null;
  try {
    status = JSON.parse(window.LianNative.getBackgroundStatus() || "{}");
  } catch {
    return;
  }
  const setState = (name, text, good) => {
    const node = card.querySelector(`[data-bg-${name}]`);
    if (!node) return;
    node.textContent = text;
    node.classList.toggle("is-good", Boolean(good));
    node.classList.toggle("is-warn", !good);
  };
  const enabled = Boolean(status.backgroundEnabled);
  const serviceGood = Boolean(status.serviceRunning) || (enabled && status.appVisible);
  const serviceText = !enabled
    ? t("settings.bgServiceOff")
    : status.serviceRunning
      ? t("settings.bgServiceOn")
      : t("settings.bgServiceEnabled");
  setState("service", serviceText, serviceGood);
  setState(
    "battery",
    status.batteryOptimized ? t("settings.bgBatteryOff") : t("settings.bgBatteryOn"),
    !status.batteryOptimized,
  );
  setState(
    "notify",
    status.notifications ? t("settings.bgNotifyOn") : t("settings.bgNotifyOff"),
    Boolean(status.notifications),
  );
  const error = card.querySelector("[data-bg-error]");
  if (error) {
    error.hidden = !status.lastError;
    error.textContent = status.lastError ? t("settings.bgError", { msg: status.lastError }) : "";
  }
  const ready = enabled && !status.batteryOptimized && Boolean(status.notifications);
  const overall = card.querySelector("[data-bg-overall]");
  if (overall) {
    overall.textContent = !enabled
      ? t("settings.bgOff")
      : ready
        ? t("settings.bgReady")
        : t("settings.bgNeedBattery");
    overall.classList.toggle("is-ready", ready);
  }
  card.classList.toggle("is-ready", ready);
}

function selectSettingsKey(state, key) {
  if (!state || !key) return;
  const s = state.settings;
  state.activeKeyId = key.id;
  s.provider = key.provider || s.provider;
  s.apiKey = String(key.apiKey || "");
  s.baseUrl = String(key.baseUrl || "");
  s.model = String(key.model || "");
  s.visionModel = String(key.visionModel || "");
  const chat = state.chats?.find((item) => item.id === state.activeChatId);
  if (chat) chat.keyId = key.id;
}

function chips(options, active, dataAttr, { dot = false, labels = true } = {}) {
  return `<div class="chip-row">${options
    .map(
      (option) => `<button type="button" class="chip ${option.id === active ? "is-on" : ""}" ${dataAttr}="${escapeHtml(option.id)}">
        ${dot ? `<i class="dot" style="background:${escapeHtml(option.color || "#ccc")}"></i>` : ""}
        ${labels ? escapeHtml(option.label) : ""}
      </button>`,
    )
    .join("")}</div>`;
}

function memoryItems(state) {
  if (!state.memories.length) return `<p class="empty-note">${escapeHtml(t("settings.memoryEmpty"))}</p>`;
  return `<div class="memory-list">${state.memories
    .map(
      (memory) => `<div class="memory-item" data-memory="${escapeHtml(memory.id)}">
        <span>${escapeHtml(memory.text)}</span>
        <button type="button" class="memory-del" data-del-memory="${escapeHtml(memory.id)}" aria-label="${escapeHtml(t("settings.memoryDelete"))}">${icon("close")}</button>
      </div>`,
    )
    .join("")}</div>`;
}

export function renderSettings({
  state,
  onChange,
  onAppearance,
  onMode,
  onUiLanguage,
  onPickAvatar,
  onPickBackground,
  onRemoveBackground,
  onExport,
  onImport,
  onShare,
  onClearChat,
  onClearAll,
  onOpenContext,
  onOrganizeMemory,
  onUnblock,
  onOpenReport,
  onProactiveNow,
  onRestartSetup,
}) {
  const deps = {
    state, onChange, onAppearance, onMode, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
    onOpenContext, onOrganizeMemory, onUnblock,
    onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
  };
  const rerender = () => renderSettings(deps);
  const root = document.querySelector("#settingsBody");
  if (!root) return;
  const s = state.settings;
  if (!Array.isArray(state.keys)) state.keys = [];
  if (!Array.isArray(state.chats)) state.chats = [];
  const scroll = document.querySelector(".settings-scroll");
  const previousScroll = scroll?.scrollTop || 0;
  const previousOpen = new Set(
    [...root.querySelectorAll(".settings-group[open]")].map((details) => details.dataset.group).filter(Boolean),
  );
  const keyLast = s.apiKey ? s.apiKey.slice(-4) : "";
  const connectedNote = s.apiKey ? t("settings.keyMasked", { last: keyLast }) : t("settings.keyMissing");
  const reportEstimate = estimateReportTokens(state.messages);
  const hasUserMessages = state.messages.some((m) => m.role === "user");
  const proactiveReady = Boolean(s.apiKey) && hasUserMessages;
  const proactiveHint = !s.apiKey
    ? t("settings.proactiveNoKey")
    : !hasUserMessages
      ? t("settings.proactiveNeedChat")
      : s.proactive.enabled
        ? t("settings.proactiveEnabled")
        : t("settings.proactiveReady");
  const reportMin = Math.max(220, Math.round(reportEstimate * 0.72));
  const reportMax = Math.max(reportMin + 180, Math.round(reportEstimate * 1.45));
  const studioEstimate = estimateStickerPackTokens();
  const studioPacks = state.stickerStudio?.packs || [];
  const hostStatus = sandboxHostStatus();
  const hostLabel = hostStatus === "ready" ? t("sandbox.ready") : hostStatus === "unsupported" ? t("sandbox.unsupported") : t("sandbox.pending");
  const activeTheme = THEMES.find((item) => item.id === s.theme);
  const immersiveTheme = Boolean(activeTheme?.immersive);
  const backgroundPreview = s.chatBg || (activeTheme?.defaultBg ? new URL(activeTheme.defaultBg, document.baseURI).href : "");
  const contextMessages = state.messages.filter((m) => (m.role === "user" || m.role === "assistant") && m.kind !== "error").slice(-28);
  const contextChars = contextMessages.reduce((sum, m) => sum + String(m.text || "").length + 24, 0);
  const blockedActive = Boolean(state.block && Number(state.block.until) > Date.now());
  const blockedRemaining = blockedActive ? Math.max(0, Math.ceil((state.block.until - Date.now()) / 1000)) : 0;
  const blockedHours = Math.floor(blockedRemaining / 3600);
  const blockedLabel =
    blockedHours > 0
      ? `${blockedHours}:${String(Math.floor((blockedRemaining % 3600) / 60)).padStart(2, "0")}:${String(blockedRemaining % 60).padStart(2, "0")}`
      : `${Math.floor(blockedRemaining / 60)}:${String(blockedRemaining % 60).padStart(2, "0")}`;

  const personaBody = `
    <p class="field-label">${escapeHtml(t("settings.mode"))}</p>
    <div class="mode-picker" id="modePicker">
      ${["companion", "roleplay", "assistant"]
        .map((id) => {
          const on = (["companion", "roleplay", "assistant"].includes(s.mode) ? s.mode : "companion") === id;
          return `<button type="button" class="mode-card${on ? " is-on" : ""}" data-mode="${id}" aria-pressed="${on}">
            <b>${escapeHtml(t(`settings.mode.${id}`))}</b>
            <small>${escapeHtml(t(`settings.modeHint.${id}`))}</small>
          </button>`;
        })
        .join("")}
    </div>
    <p class="field-hint">${escapeHtml(s.mode === "assistant" ? t("settings.modeThreadAssistant") : t("settings.modeThreadHint"))}</p>
    ${s.mode === "assistant" ? `<p class="field-hint">${escapeHtml(t("settings.assistantCapHint"))}</p>` : ""}
    <div class="two-col avatar-cards">
      <div class="avatar-card">
        ${avatarMarkup({ src: s.aiAvatar, role: "ai", name: s.aiName, size: 50 })}
        <div class="avatar-card-copy"><b>${escapeHtml(t("settings.aiAvatar"))}</b><small>${escapeHtml(s.aiName || "Lian")}</small></div>
        <button type="button" class="icon-btn" data-pick-avatar="ai" aria-label="${escapeHtml(t("settings.changeAvatar"))}">${icon("upload")}</button>
      </div>
      <div class="avatar-card">
        ${avatarMarkup({ src: s.userAvatar, role: "user", name: s.userName || "你", size: 50 })}
        <div class="avatar-card-copy"><b>${escapeHtml(t("settings.userAvatar"))}</b><small>${escapeHtml(s.userName || "你")}</small></div>
        <button type="button" class="icon-btn" data-pick-avatar="user" aria-label="${escapeHtml(t("settings.changeAvatar"))}">${icon("upload")}</button>
      </div>
    </div>
    <div class="settings-actions">
      ${s.aiAvatar ? `<button type="button" class="btn btn-ghost btn-small" data-remove-avatar="ai">${escapeHtml(t("settings.removeAvatar"))}</button>` : ""}
      ${s.userAvatar ? `<button type="button" class="btn btn-ghost btn-small" data-remove-avatar="user">${escapeHtml(t("settings.removeAvatar"))}</button>` : ""}
    </div>
    <div class="settings-field">
      <label class="field-label" for="setAiName">${escapeHtml(t("settings.aiName"))}</label>
      <input class="input" id="setAiName" data-setting="aiName" maxlength="20" value="${escapeHtml(s.aiName)}">
    </div>
    <div class="settings-field">
      <label class="field-label" for="setUserName">${escapeHtml(t("settings.userName"))}</label>
      <input class="input" id="setUserName" data-setting="userName" maxlength="20" value="${escapeHtml(s.userName)}">
    </div>
    <div class="settings-field">
      <label class="field-label" for="setRelation">${escapeHtml(t("settings.relationship"))}</label>
      <input class="input" id="setRelation" data-setting="relationship" maxlength="40" value="${escapeHtml(s.relationship)}" placeholder="${escapeHtml(t("settings.relationshipPh"))}">
    </div>
    <div class="settings-field">
      <label class="field-label" for="setPersona">${escapeHtml(t("settings.personaField"))}</label>
      <textarea class="textarea" id="setPersona" data-setting="persona" maxlength="1200" placeholder="${escapeHtml(t("settings.personaPh"))}">${escapeHtml(s.persona)}</textarea>
    </div>
    <div class="settings-field">
      <label class="field-label" for="setGreeting">${escapeHtml(t("settings.greeting"))}</label>
      <textarea class="textarea" id="setGreeting" data-setting="greeting" maxlength="240" style="min-height:60px">${escapeHtml(s.greeting)}</textarea>
    </div>
    <div class="settings-actions">
      <button type="button" class="btn btn-primary btn-small" data-save-persona>${escapeHtml(t("settings.savePersona"))}</button>
      <span class="hint-inline">${escapeHtml(t("settings.personaHint"))}</span>
    </div>`;

  const memoryBody = `
    <div class="memory-context-card">
      <div class="memory-context-stats">
        <span><b>${state.memories.length}</b> ${escapeHtml(t("settings.memoryCountLabel"))}</span>
        <span><b>${contextMessages.length}</b> ${escapeHtml(t("settings.memoryContextMessages"))}</span>
        <span><b>${contextChars}</b> ${escapeHtml(t("settings.memoryContextChars"))}</span>
      </div>
      <p>${escapeHtml(t("settings.memoryContextHint"))}</p>
      <div class="settings-actions">
        <button type="button" class="btn btn-ghost btn-small" data-context-view>${escapeHtml(t("settings.memoryViewContext"))}</button>
        <button type="button" class="btn btn-primary btn-small" data-organize-memory>${escapeHtml(t("settings.memoryOrganize"))}</button>
      </div>
    </div>
    ${switchRow(t("settings.memoryAuto"), t("settings.memoryAutoHint"), Boolean(s.memory?.auto), 'data-toggle="memoryAuto"')}
    <p class="sticker-group-label" style="margin-top:14px">${escapeHtml(t("settings.memoryLongTerm"))}</p>
    ${memoryItems(state)}
    <div class="memory-add">
      <input class="input" id="memoryInput" maxlength="180" placeholder="${escapeHtml(t("settings.memoryAddPh"))}">
      <button type="button" class="btn btn-primary" id="memoryAdd">${escapeHtml(t("settings.memoryAdd"))}</button>
    </div>
    <p class="field-hint" style="margin-top:8px">${escapeHtml(t("settings.memoryNote"))}</p>`;

  const opt = s.optimize;
  const experienceBody = `
    ${switchRow(t("settings.optNoActions"), t("settings.optNoActionsHint"), opt.noActions, 'data-toggle="noActions"')}
    ${switchRow(t("settings.optSegments"), t("settings.optSegmentsHint"), opt.segments, 'data-toggle="segments"')}
    ${switchRow(t("settings.optStreaming"), t("settings.optStreamingHint"), opt.streaming !== false, 'data-toggle="streaming"')}
${switchRow(t("settings.optDrawings"), t("settings.optDrawingsHint"), Boolean(opt.drawings), 'data-toggle="drawings"')}
    ${switchRow(t("settings.optAutoSticker"), t("settings.optAutoStickerHint"), opt.autoSticker, 'data-toggle="autoSticker"')}
    ${switchRow(t("settings.optEmoji"), t("settings.optEmojiHint"), opt.emoji, 'data-toggle="emoji"')}
    ${switchRow(t("settings.optShort"), t("settings.optShortHint"), opt.shortReplies, 'data-toggle="shortReplies"')}
    ${switchRow(t("settings.quoteReplies"), t("settings.quoteRepliesHint"), opt.quotes !== false, 'data-toggle="quotes"')}
    <p class="field-hint" style="margin-top:9px">${escapeHtml(t("settings.aboutProactive"))}</p>`;

  const realism = s.realism || {};
  const realismSummary =
    Number(realism.minDelay) === Number(realism.maxDelay)
      ? t("settings.realismSummarySame", { sec: realism.minDelay })
      : t("settings.realismSummary", { min: realism.minDelay, max: realism.maxDelay });
  const maxDelayOptions = [1, 1.5, 2, 2.5, 3, 4, 4.5, 5, 6, 10, 15];
  const delayOptions = (values, active) => {
    const all = [...new Set([...values, Number(active)].filter((value) => Number.isFinite(value)))].sort((a, b) => a - b);
    return all
      .map((value) => `<option value="${value}" ${Number(active) === value ? "selected" : ""}>${value} s</option>`)
      .join("");
  };
  const realismBody = `
    ${switchRow(t("settings.realismToggle"), t("settings.realismToggleHint"), realism.enabled !== false, 'data-toggle="realismEnabled"')}
    ${switchRow(t("settings.realismTyping"), t("settings.realismTypingHint"), realism.typing !== false, 'data-toggle="realismTyping"')}
    ${switchRow(t("settings.realismAuto"), t("settings.realismAutoHint"), realism.autoDelay !== false, 'data-toggle="realismAuto"')}
    <p class="field-hint">${escapeHtml(realismSummary)}</p>
    <div class="two-col">
      <div class="settings-field">
        <label class="field-label" for="realismMin">${escapeHtml(t("settings.realismMin"))}</label>
        <select class="select" id="realismMin">${delayOptions([0.5, 0.8, 1.2, 2, 3, 5], realism.minDelay)}</select>
      </div>
      <div class="settings-field">
        <label class="field-label" for="realismMax">${escapeHtml(t("settings.realismMax"))}</label>
        <select class="select" id="realismMax">${delayOptions(maxDelayOptions, realism.maxDelay)}</select>
      </div>
    </div>
    <div class="settings-field">
      <label class="field-label" for="realismSegment">${escapeHtml(t("settings.realismSegment"))}</label>
      <select class="select" id="realismSegment">
        ${delayOptions([0, 0.3, 0.6, 0.85, 1.2, 2, 3], realism.segmentDelay)}
      </select>
      <p class="field-hint">${escapeHtml(t("settings.realismSegmentHint"))}</p>
    </div>
    <p class="field-hint">${escapeHtml(t("settings.realismNote"))}</p>`;

  const blockMinuteOptions = [
    ...new Set([1, 5, 10, 30, 45, 60, 90, 180, 360, 720, Number(s.blocking?.minutes) || 30]),
  ]
    .filter((value) => Number.isFinite(value) && value >= 1 && value <= 1440)
    .sort((a, b) => a - b);
  const blockDurationLabel = (minutes) =>
    minutes >= 60 && minutes % 60 === 0 ? `${minutes / 60} h` : `${minutes} min`;
  const blockingBody = `
    <div class="warning-box">${icon("moon")}<span>${escapeHtml(t("settings.blockingWarning"))}</span></div>
    ${switchRow(t("settings.blockingToggle"), t("settings.blockingToggleHint"), Boolean(s.blocking?.enabled), 'data-toggle="aiBlock"')}
    <div class="settings-field">
      <div class="field-label">${escapeHtml(t("settings.blockingMode"))}</div>
      <div class="coldwar-grid" role="group" aria-label="${escapeHtml(t("settings.blockingMode"))}">
        <button type="button" class="coldwar-card ${(s.blocking?.mode || "silent") === "silent" ? "is-on" : ""}" data-block-mode="silent">
          <span class="coldwar-icon">${icon("moon")}</span>
          <b>${escapeHtml(t("settings.coldWarSilent"))}</b>
          <small>${escapeHtml(t("settings.coldWarSilentHint"))}</small>
        </button>
        <button type="button" class="coldwar-card ${s.blocking?.mode === "reject" ? "is-on" : ""}" data-block-mode="reject">
          <span class="coldwar-icon">${icon("close")}</span>
          <b>${escapeHtml(t("settings.coldWarReject"))}</b>
          <small>${escapeHtml(t("settings.coldWarRejectHint"))}</small>
        </button>
      </div>
      <p class="field-hint">${escapeHtml(t("settings.blockingModeHint"))}</p>
    </div>
    <div class="settings-field">
      <label class="field-label" for="blockMinutes">${escapeHtml(t("settings.blockingMinutes"))}</label>
      <select class="select" id="blockMinutes">
        ${blockMinuteOptions
          .map((value) => `<option value="${value}" ${Number(s.blocking?.minutes) === value ? "selected" : ""}>${blockDurationLabel(value)}</option>`)
          .join("")}
      </select>
      <p class="field-hint">${escapeHtml(t("settings.blockingMinutesHint"))}</p>
    </div>
    ${
      blockedActive
        ? `<div class="blocked-settings-row" data-blocked-row>
            <span>${icon("moon")}<b data-blocked-label>${escapeHtml(t("settings.blockingActive", { time: blockedLabel }))}</b></span>
            <button type="button" class="btn btn-ghost btn-small" data-unblock>${escapeHtml(t("settings.blockingRelease"))}</button>
          </div>`
        : ""
    }`;

  const nativeBackground = Boolean(window.LianNative?.getBackgroundStatus);
  const backgroundPermission = nativeBackground
    ? `<div class="bg-permission" id="bgPermission">
        <div class="bg-permission-head">
          <span class="bg-dot"></span>
          <b>${escapeHtml(t("settings.bgTitle"))}</b>
          <span class="bg-pill" data-bg-overall>—</span>
        </div>
        <div class="bg-status-grid">
          <div class="bg-status"><span>${escapeHtml(t("settings.bgService"))}</span><b data-bg-service>—</b></div>
          <div class="bg-status"><span>${escapeHtml(t("settings.bgBattery"))}</span><b data-bg-battery>—</b></div>
          <div class="bg-status"><span>${escapeHtml(t("settings.bgNotify"))}</span><b data-bg-notify>—</b></div>
        </div>
        <div class="settings-actions">
          <button type="button" class="btn btn-ghost btn-small" data-bg-action="battery">${escapeHtml(t("settings.bgAllowBattery"))}</button>
          <button type="button" class="btn btn-ghost btn-small" data-bg-action="autostart">${escapeHtml(t("settings.bgAutoStart"))}</button>
          <button type="button" class="btn btn-ghost btn-small" data-bg-action="notify">${escapeHtml(t("settings.bgNotifySettings"))}</button>
          <button type="button" class="btn btn-ghost btn-small" data-bg-action="test">${escapeHtml(t("settings.bgTestNotify"))}</button>
        </div>
        <p class="field-hint">${escapeHtml(t("settings.bgHint"))}</p>
        <p class="field-hint bg-error" data-bg-error hidden></p>
      </div>`
    : `<p class="field-hint">${escapeHtml(t("settings.bgWebOnly"))}</p>`;
  const notificationBody = `
    <div class="warning-box">${icon("moon")}<span>${escapeHtml(t("settings.notificationsHint"))}</span></div>
    ${switchRow(t("settings.notificationsToggle"), t("settings.notificationsToggleHint"), Boolean(s.notifications?.enabled), 'data-toggle="notificationsEnabled"')}
    ${switchRow(t("settings.backgroundToggle"), t("settings.backgroundToggleHint"), Boolean(s.notifications?.background), 'data-toggle="backgroundRun"', !s.notifications?.enabled)}
    ${s.notifications?.background && !s.proactive?.enabled ? `<div class="warning-box">${icon("sparkle")}<span>${escapeHtml(t("settings.bgNeedProactive"))}</span></div>` : ""}
    ${backgroundPermission}
    <p class="field-hint">${escapeHtml(t("settings.notificationsLimit"))}</p>`;

  const packCards = studioPacks
    .map((pack) => {
      const previews = (pack.stickerIds || [])
        .map((id) => getSticker(id, state.customStickers))
        .filter(Boolean)
        .map((sticker) => `<img src="${escapeHtml(stickerSrc(sticker))}" alt="${escapeHtml(sticker.name)}" title="${escapeHtml(sticker.name)}">`)
        .join("");
      const hasHosted = Array.isArray(pack.assetIds) && pack.assetIds.length > 0;
      return `<div class="studio-pack">
        <div class="studio-pack-head">
          <div><b>${escapeHtml(pack.name)}</b><small>${escapeHtml(pack.theme || "")}</small></div>
          <span class="pack-state ${pack.equipped ? "is-on" : ""}">${escapeHtml(pack.equipped ? t("studio.equippedShort") : t("studio.unequippedShort"))}</span>
        </div>
        <div class="studio-pack-gallery">${previews}</div>
        <div class="studio-pack-actions">
          <button type="button" class="chip ${pack.equipped ? "is-on" : ""}" data-studio-equip="${escapeHtml(pack.id)}">${escapeHtml(pack.equipped ? t("studio.unequip") : t("studio.equip"))}</button>
          <button type="button" class="chip" data-studio-preview="${escapeHtml(pack.id)}">${escapeHtml(t("studio.preview"))}</button>
          <button type="button" class="chip" data-studio-copy="${escapeHtml(pack.id)}" ${hasHosted ? "" : "disabled"}>${escapeHtml(t("studio.copyHost"))}</button>
        </div>
      </div>`;
    })
    .join("");

  const studioBody = `
    <div class="warning-box">${icon("sparkle")}<span>${escapeHtml(t("studio.cost", { min: studioEstimate.min, max: studioEstimate.max }))}</span></div>
    <p class="field-hint">${escapeHtml(t("studio.lead"))}</p>
    <div class="studio-compose">
      <div class="settings-field">
        <label class="field-label" for="studioStyle">${escapeHtml(t("studio.styleLabel"))}</label>
        <select class="select" id="studioStyle">
          ${STICKER_STYLE_OPTIONS.map((option) => `<option value="${option.id}" ${(state.stickerStudio?.style || "auto") === option.id ? "selected" : ""}>${escapeHtml(t(option.labelKey))}</option>`).join("")}
        </select>
        <p class="field-hint" id="studioStyleHint">${escapeHtml(t((STICKER_STYLE_OPTIONS.find((option) => option.id === (state.stickerStudio?.style || "auto")) || STICKER_STYLE_OPTIONS[0]).hintKey))}</p>
      </div>
      <div class="settings-field">
        <label class="field-label" for="studioDirection">${escapeHtml(t("studio.directionLabel"))} <small>${escapeHtml(t("common.optional"))}</small></label>
        <textarea class="textarea studio-direction" id="studioDirection" maxlength="180" rows="2" placeholder="${escapeHtml(t("studio.directionPh"))}">${escapeHtml(state.stickerStudio?.direction || "")}</textarea>
        <p class="field-hint">${escapeHtml(t("studio.directionHint"))}</p>
      </div>
    </div>
    <button type="button" class="btn btn-primary btn-block" data-generate-pack>${escapeHtml(t("studio.generate"))}</button>
    <p class="field-hint" style="margin-top:8px">${escapeHtml(t("studio.autoEquipHint"))}</p>
    <div class="studio-pack-list">
      ${packCards || `<p class="empty-note">${escapeHtml(t("studio.empty"))}</p>`}
    </div>
    <p class="hint-inline" style="margin-top:10px">${escapeHtml(t("studio.recipeNote"))}</p>`;

  const sandboxBody = `
    <div class="sandbox-status ${hostStatus === "ready" ? "is-ready" : ""}">
      <span class="host-dot"></span>
      <span>${escapeHtml(hostLabel)}</span>
      <span class="host-meta">${escapeHtml(t("sandbox.localOnly"))}</span>
    </div>
    <p class="field-hint">${escapeHtml(t("sandbox.lead"))}</p>
    <div class="settings-actions">
      <button type="button" class="btn btn-ghost btn-small" data-open-sandbox>${escapeHtml(t("sandbox.open"))}</button>
    </div>
    <p class="hint-inline" style="margin-top:9px">${escapeHtml(t("sandbox.note"))}</p>`;

  const proactiveBody = `
    <div class="warning-box">${icon("sparkle")}<span>${escapeHtml(t("settings.proactiveWarning"))}</span></div>
    ${switchRow(
      t("settings.proactiveToggle"),
      proactiveHint,
      Boolean(s.proactive.enabled && proactiveReady),
      'data-toggle="proactive"',
      !proactiveReady,
    )}
    <div class="settings-field">
      <label class="field-label" for="proactiveInterval">${escapeHtml(t("settings.proactiveInterval"))}</label>
      <select class="select" id="proactiveInterval">
        ${[
          [15, "15 min"],
          [30, "30 min"],
          [45, "45 min"],
          [60, "1 h"],
          [120, "2 h"],
          [240, "4 h"],
        ]
          .map(([value, label]) => `<option value="${value}" ${Number(s.proactive.interval) === value ? "selected" : ""}>${label}</option>`)
          .join("")}
      </select>
      <p class="field-hint">${escapeHtml(t("settings.proactiveIntervalHint"))}</p>
    </div>
    <div class="settings-actions">
      <button type="button" class="btn btn-ghost btn-small" id="proactiveNow" ${proactiveReady ? "" : "disabled"}>${escapeHtml(t("settings.proactiveTest"))}</button>
      <span class="hint-inline">${escapeHtml(t("settings.proactiveTestHint"))}</span>
    </div>
    <div class="danger-row" style="margin-top:12px">
      <div class="danger-row-copy">
        <b>${escapeHtml(t("settings.report"))}</b>
        <small>${escapeHtml(t("settings.reportHint"))} · ${escapeHtml(t("settings.reportCost", { min: reportMin, max: reportMax }))}</small>
      </div>
      <button type="button" class="btn btn-ghost" id="openReportFromSettings">${escapeHtml(t("settings.reportButton"))}</button>
    </div>
    <p class="hint-inline" style="margin-top:7px">${escapeHtml(t("report.limit"))}</p>`;

  const appearanceBody = `
    <div class="settings-field">
      <div class="field-label">${escapeHtml(t("settings.theme"))} <small>${escapeHtml(t("settings.themeHint"))}</small></div>
      <div class="theme-wrap">
        ${THEMES.filter((theme) => theme.id !== "assistant").map(
          (theme) => `<button type="button" class="theme-swatch ${s.theme === theme.id ? "is-on" : ""}" data-theme="${theme.id}" title="${escapeHtml(themeLabel(theme, s.uiLang))}">
            <i style="background:${theme.swatch || theme.accent}"></i><span class="swatch-label">${escapeHtml(themeLabel(theme, s.uiLang))}</span>
          </button>`,
        ).join("")}
      </div>
      ${s.theme === "assistant" ? `<p class="field-hint">${escapeHtml(t("settings.assistantThemeAuto"))}</p>` : ""}
      <div class="accent-editor">
        <span class="accent-chip" id="accentChip" style="background:${escapeHtml(s.accent)}"></span>
        <input class="input accent-hex" id="accentHex" maxlength="7" spellcheck="false" autocomplete="off"
          value="${escapeHtml(String(s.accent || "").toUpperCase())}" placeholder="#06C755"
          aria-label="${escapeHtml(t("settings.customAccent"))}">
        <span class="accent-hint">${escapeHtml(t("settings.customAccentHint"))}</span>
      </div>
      ${immersiveTheme ? `<p class="field-hint">${escapeHtml(t("settings.immersiveThemeHint"))}</p>` : ""}
    </div>
    <div class="settings-field">
      <div class="field-label">${escapeHtml(t("settings.layout"))} <small>${escapeHtml(t("settings.layoutHint"))}</small></div>
      ${chips(CHAT_LAYOUTS, s.layout || "line", "data-layout")}
    </div>
    <div class="settings-field">
      <div class="field-label">${escapeHtml(t("settings.font"))}</div>
      ${chips(FONTS, s.font, "data-font")}
    </div>
    <div class="two-col">
      <div class="settings-field">
        <label class="field-label" for="uiLang">${escapeHtml(t("settings.uiLang"))}</label>
        <select class="select" id="uiLang">
          ${UI_LANGS.map((lang) => `<option value="${lang.id}" ${lang.id === s.uiLang ? "selected" : ""}>${escapeHtml(lang.label)}</option>`).join("")}
        </select>
      </div>
      <div class="settings-field">
        <label class="field-label" for="aiLang">${escapeHtml(t("settings.aiLang"))}</label>
        <select class="select" id="aiLang">
          ${AI_LANGS.map((lang) => `<option value="${lang.id}" ${lang.id === s.aiLang ? "selected" : ""}>${escapeHtml(lang.label)}</option>`).join("")}
        </select>
      </div>
    </div>
    <div class="settings-field">
      <div class="field-label">${escapeHtml(t("settings.background"))} <small>${escapeHtml(t("settings.backgroundHint"))}</small></div>
      <div class="bg-preview" style="${backgroundPreview ? `background-image:url('${escapeHtml(backgroundPreview)}')` : ""}">
        <span class="bg-label">${s.chatBg ? t("settings.background") : immersiveTheme ? t("settings.backgroundBuiltin") : t("settings.backgroundUpload")}</span>
      </div>
      <div class="settings-actions">
        <button type="button" class="btn btn-ghost btn-small" id="pickBg">${escapeHtml(t("settings.backgroundUpload"))}</button>
        ${s.chatBg ? `<button type="button" class="btn btn-ghost btn-small" id="removeBg">${escapeHtml(t("settings.backgroundRemove"))}</button>` : ""}
      </div>
      ${s.chatBg && !immersiveTheme ? `<div class="range-row" style="margin-top:10px">
        <input type="range" id="bgOpacity" min="8" max="65" value="${Math.round(Number(s.chatBgOpacity || 0.24) * 100)}">
        <output>${Math.round(Number(s.chatBgOpacity || 0.24) * 100)}%</output>
      </div>
      <p class="field-hint">${escapeHtml(t("settings.backgroundOpacity"))}</p>` : ""}
      ${immersiveTheme ? `<p class="field-hint" style="margin-top:8px">${escapeHtml(t("settings.immersiveBgHint"))}</p>` : ""}
    </div>`;

  const connectionBody = `
    <div class="key-display"><i class="key-dot"></i><span>${escapeHtml(connectedNote)}</span></div>
    ${state.keys.length ? `<div class="settings-field">
      <label class="field-label" for="keySelect">${escapeHtml(t("settings.keyCurrent"))}</label>
      <select class="select" id="keySelect">
        ${state.keys.map((key) => `<option value="${escapeHtml(key.id)}" ${key.id === state.activeKeyId ? "selected" : ""}>${escapeHtml(key.name)} · ${escapeHtml((key.apiKey || "").slice(-4) || "…")}</option>`).join("")}
      </select>
    </div>` : ""}
    <p class="field-hint">${escapeHtml(t("settings.keyHint"))}</p>
    <div class="settings-actions">
      <button type="button" class="btn btn-ghost btn-small" id="editKey">${escapeHtml(t("settings.replaceKey"))}</button>
      <button type="button" class="btn btn-ghost btn-small" id="addKey">${escapeHtml(t("settings.addKey"))}</button>
      ${state.keys.length > 1 ? `<button type="button" class="btn btn-ghost btn-small" id="deleteKey">${escapeHtml(t("settings.deleteKey"))}</button>` : ""}
      <button type="button" class="btn btn-ghost btn-small" id="testConn">${escapeHtml(t("common.test"))}</button>
      <span class="hint-inline" id="testConnStatus"></span>
    </div>
    <div id="newKeyPanel" hidden style="margin-top:10px">
      <div class="new-key-form">
        <input class="input" id="newKeyName" maxlength="40" placeholder="${escapeHtml(t("settings.keyNamePh"))}">
        <input class="input" id="newKeyValue" type="password" autocomplete="off" spellcheck="false" placeholder="${escapeHtml(t("setup.keyPh"))}">
        <select class="select" id="newKeyProvider">
          ${Object.values(PROVIDERS).map((p) => `<option value="${p.id}" ${p.id === s.provider ? "selected" : ""}>${escapeHtml(p.label)}</option>`).join("")}
        </select>
        <button type="button" class="btn btn-primary btn-small" id="createKey">${escapeHtml(t("settings.saveKey"))}</button>
      </div>
    </div>
    <div id="keyEditor" hidden style="margin-top:10px">
      <div class="memory-add">
        <input class="input" id="newKey" type="password" autocomplete="off" spellcheck="false" placeholder="${escapeHtml(t("setup.keyPh"))}">
        <button type="button" class="btn btn-primary" id="saveKey">${escapeHtml(t("common.save"))}</button>
      </div>
    </div>
    <div class="settings-field">
      <label class="field-label" for="connProvider">${escapeHtml(t("settings.provider"))}</label>
      <select class="select" id="connProvider">
        ${Object.values(PROVIDERS).map((p) => `<option value="${p.id}" ${p.id === s.provider ? "selected" : ""}>${escapeHtml(p.label)}</option>`).join("")}
      </select>
    </div>
    <div class="settings-field">
      <label class="field-label" for="connBase">${escapeHtml(t("settings.baseUrl"))}</label>
      <input class="input" id="connBase" data-conn="baseUrl" type="url" spellcheck="false" value="${escapeHtml(s.baseUrl)}">
    </div>
    <div class="settings-field">
      <label class="field-label" for="connModel">${escapeHtml(t("settings.model"))}</label>
      <input class="input" id="connModel" data-conn="model" spellcheck="false" value="${escapeHtml(s.model)}">
    </div>
    <div class="settings-field">
      <label class="field-label" for="connVision">${escapeHtml(t("settings.visionModel"))} <small>${escapeHtml(t("common.optional"))}</small></label>
      <input class="input" id="connVision" data-conn="visionModel" spellcheck="false" value="${escapeHtml(s.visionModel)}" placeholder="${escapeHtml(t("settings.visionHint"))}">
    </div>
    <p class="token-line">${escapeHtml(t("settings.tokenUsage", { n: state.meta.totalTokens.toLocaleString(), calls: state.meta.totalCalls }))}</p>`;

  const dataBody = `
    <div class="danger-row">
      <div class="danger-row-copy"><b>${escapeHtml(t("settings.export"))}</b><small>${escapeHtml(t("settings.exportHint"))}</small></div>
      <button type="button" class="btn btn-ghost" id="exportProfile">${escapeHtml(t("settings.export"))}</button>
    </div>
    <div class="danger-row">
      <div class="danger-row-copy"><b>${escapeHtml(t("settings.import"))}</b><small>${escapeHtml(t("settings.importHint"))}</small></div>
      <button type="button" class="btn btn-ghost" id="importProfile">${escapeHtml(t("settings.import"))}</button>
    </div>
    <div class="danger-row">
      <div class="danger-row-copy"><b>${escapeHtml(t("settings.share"))}</b><small>${escapeHtml(t("settings.shareHint"))}</small></div>
      <button type="button" class="btn btn-ghost" id="shareApp">${escapeHtml(t("settings.share"))}</button>
    </div>
    <div class="danger-row">
      <div class="danger-row-copy"><b>${escapeHtml(t("settings.clearChat"))}</b><small>${escapeHtml(t("settings.clearChatHint"))}</small></div>
      <button type="button" class="btn btn-ghost" id="clearChat">${escapeHtml(t("common.delete"))}</button>
    </div>
    <div class="danger-row">
      <div class="danger-row-copy"><b>${escapeHtml(t("settings.clearAll"))}</b><small>${escapeHtml(t("settings.clearAllHint"))}</small></div>
      <button type="button" class="btn btn-danger" id="clearAll">${escapeHtml(t("common.delete"))}</button>
    </div>
    <p class="token-line">${escapeHtml(t("settings.version", { v: "1.9.26" }))}</p>`;

  const aboutBody = `
    <div class="about-box">
      <h3>${escapeHtml(t("settings.aboutTitle"))}</h3>
      <p>${escapeHtml(t("settings.aboutText"))}</p>
      <p>${escapeHtml(t("settings.aboutPrivacy"))}</p>
      <p>${escapeHtml(t("settings.aboutProactive"))}</p>
      <p>${escapeHtml(t("settings.aboutLicense"))}</p>
    </div>
    <div class="settings-actions">
      <button type="button" class="btn btn-ghost btn-small" id="restartSetup">${escapeHtml(t("settings.setupAgain"))}</button>
    </div>`;

  root.innerHTML = `
    <div class="profile-hero">
      ${avatarMarkup({ src: s.aiAvatar, role: "ai", name: s.aiName, size: 56 })}
      <div class="profile-hero-copy">
        <h2>${escapeHtml(s.aiName || "Lian")}</h2>
        <p>${escapeHtml(s.relationship || t("app.tagline"))}</p>
      </div>
      <button type="button" class="profile-edit" id="heroEdit">${icon("settings")}${escapeHtml(t("settings.editPersona"))}</button>
    </div>

    ${group("persona", t("settings.persona"), t("settings.personaHint"), "heart", personaBody, previousOpen.has("persona"))}
    ${group("memory", t("settings.memory"), t("settings.memoryHint", { n: state.memories.length }), "sparkle", memoryBody, true)}
    ${group("experience", t("settings.experience"), t("settings.experienceHint"), "sticker", experienceBody, previousOpen.has("experience"))}
    ${group("realism", t("settings.realism"), t("settings.realismHint"), "moon", realismBody, previousOpen.has("realism"))}
    ${group("blocking", t("settings.blocking"), t("settings.blockingHint"), "heart", blockingBody, previousOpen.has("blocking"))}
    ${group("notifications", t("settings.notifications"), t("settings.notificationsHintShort"), "moon", notificationBody, previousOpen.has("notifications"))}
    ${group("studio", t("studio.title"), t("studio.hint"), "sparkle", studioBody, previousOpen.has("studio"))}
    ${group("sandbox", t("sandbox.title"), t("sandbox.hint"), "doc", sandboxBody, previousOpen.has("sandbox"))}
    ${group("proactive", t("settings.proactive"), t("settings.proactiveHint"), "moon", proactiveBody, previousOpen.has("proactive"))}
    ${group("appearance", t("settings.appearance"), t("settings.appearanceHint"), "image", appearanceBody, previousOpen.has("appearance"))}
    ${group("connection", t("settings.connection"), t("settings.connectionHint"), "settings", connectionBody, previousOpen.has("connection"))}
    ${group("data", t("settings.data"), t("settings.dataHint"), "share", dataBody, previousOpen.has("data"))}
    ${group("about", t("settings.about"), t("settings.aboutHint"), "doc", aboutBody, previousOpen.has("about"))}
  `;

  if (scroll) scroll.scrollTop = previousScroll;

  root.querySelectorAll("[data-setting]").forEach((el) => {
    el.addEventListener("input", () => {
      s[el.dataset.setting] = el.value;
      onChange();
    });
  });

  root.querySelector("[data-save-persona]")?.addEventListener("click", () => {
    if (!s.aiName.trim()) s.aiName = "Lian";
    if (!s.userName.trim()) s.userName = "你";
    onChange();
    toast(t("toast.saved"));
    renderSettings({
      state, onChange, onAppearance, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
      onOpenContext, onOrganizeMemory, onUnblock,
      onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
    });
  });

  root.querySelectorAll("[data-pick-avatar]").forEach((el) => {
    el.addEventListener("click", () => onPickAvatar(el.dataset.pickAvatar));
  });
  root.querySelectorAll("[data-remove-avatar]").forEach((el) => {
    el.addEventListener("click", () => {
      s[el.dataset.removeAvatar === "ai" ? "aiAvatar" : "userAvatar"] = "";
      onChange();
      toast(t("toast.avatarReset"));
      renderSettings({
        state, onChange, onAppearance, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
        onOpenContext, onOrganizeMemory, onUnblock,
        onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
      });
    });
  });

  root.querySelectorAll("[data-toggle]").forEach((row) => {
    const checkbox = row.matches('input[type="checkbox"]') ? row : row.querySelector('input[type="checkbox"]');
    if (!checkbox) return;
    checkbox.addEventListener("change", async () => {
      const key = row.dataset.toggle;
      const checked = Boolean(checkbox.checked);
      if (key === "proactive") {
        s.proactive.enabled = checked;
        s.proactive.lastAt = checked ? Date.now() : 0;
        const hint = row.querySelector(".setting-copy small");
        if (hint) hint.textContent = checked ? t("settings.proactiveEnabled") : t("settings.proactiveReady");
      } else if (key === "memoryAuto") {
        s.memory.auto = checked;
      } else if (key === "realismEnabled") {
        s.realism.enabled = checked;
      } else if (key === "realismTyping") {
        s.realism.typing = checked;
      } else if (key === "realismAuto") {
        s.realism.autoDelay = checked;
      } else if (key === "aiBlock") {
        s.blocking.enabled = checked;
      } else if (key === "notificationsEnabled") {
        s.notifications.enabled = checked;
        if (!checked) s.notifications.background = false;
        const bg = root.querySelector('[data-toggle="backgroundRun"] input');
        if (bg) {
          bg.checked = Boolean(s.notifications.background);
          bg.disabled = !checked;
        }
      } else if (key === "backgroundRun") {
        s.notifications.background = checked;
      } else if (s.optimize[key] !== undefined) {
        // Drawing costs tokens on almost every reply once enabled, so ask first.
        if (key === "drawings" && checked) {
          const ok = await confirmDialog({
            title: t("settings.drawingsWarnTitle"),
            body: t("settings.drawingsWarnBody"),
            confirm: t("settings.drawingsWarnConfirm"),
            cancel: t("common.cancel"),
          });
          if (!ok) {
            checkbox.checked = false;
            return;
          }
        }
        s.optimize[key] = checked;
      }
      onChange();
      if (key === "notificationsEnabled" || key === "backgroundRun") {
        window.setTimeout(() => refreshNativeBackgroundUI(root), 450);
      }
      toast(t("toast.saved"));
    });
  });

  root.querySelector("#memoryAdd")?.addEventListener("click", addMemory);
  root.querySelector("#memoryInput")?.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      addMemory();
    }
  });
  function addMemory() {
    const input = root.querySelector("#memoryInput");
    const text = input?.value.trim();
    if (!text) return;
    if (state.memories.length >= 60) {
      toast(t("settings.memoryFull"));
      return;
    }
    state.memories.push({ id: uid("mem"), text, createdAt: Date.now() });
    input.value = "";
    onChange();
    renderSettings({
      state, onChange, onAppearance, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
      onOpenContext, onOrganizeMemory, onUnblock,
      onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
    });
  }
  root.querySelectorAll("[data-del-memory]").forEach((el) => {
    el.addEventListener("click", () => {
      state.memories = state.memories.filter((memory) => memory.id !== el.dataset.delMemory);
      onChange();
      renderSettings({
        state, onChange, onAppearance, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
        onOpenContext, onOrganizeMemory, onUnblock,
        onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
      });
    });
  });

  root.querySelector("[data-context-view]")?.addEventListener("click", () => onOpenContext());
  root.querySelector("[data-organize-memory]")?.addEventListener("click", (event) => onOrganizeMemory(event.currentTarget));
  root.querySelector("[data-unblock]")?.addEventListener("click", () => onUnblock());
  root.querySelectorAll("[data-block-mode]").forEach((button) => {
    button.addEventListener("click", () => {
      s.blocking.mode = button.dataset.blockMode === "reject" ? "reject" : "silent";
      onChange();
      toast(t("toast.saved"));
      renderSettings({
        state, onChange, onAppearance, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
        onOpenContext, onOrganizeMemory, onUnblock,
        onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
      });
    });
  });
  root.querySelector("#blockMinutes")?.addEventListener("change", (event) => {
    s.blocking.minutes = Number(event.target.value) || 30;
    onChange();
    toast(t("toast.saved"));
  });
  root.querySelector("#realismMin")?.addEventListener("change", (event) => {
    const min = Number(event.target.value) || 0;
    s.realism.minDelay = min;
    if (Number(s.realism.maxDelay) < min) {
      s.realism.maxDelay = maxDelayOptions.find((value) => value >= min) || 15;
    }
    const maxSelect = root.querySelector("#realismMax");
    if (maxSelect && maxDelayOptions.includes(Number(s.realism.maxDelay))) {
      maxSelect.value = String(s.realism.maxDelay);
    }
    onChange();
    toast(t("toast.saved"));
  });
  root.querySelector("#realismMax")?.addEventListener("change", (event) => {
    const min = Number(s.realism.minDelay) || 0;
    const requested = Number(event.target.value) || 0;
    s.realism.maxDelay = requested >= min ? requested : maxDelayOptions.find((value) => value >= min) || 15;
    event.target.value = String(s.realism.maxDelay);
    onChange();
    toast(t("toast.saved"));
  });
  root.querySelector("#realismSegment")?.addEventListener("change", (event) => {
    s.realism.segmentDelay = Number(event.target.value) || 0;
    onChange();
    toast(t("toast.saved"));
  });

  root.querySelector("#proactiveInterval")?.addEventListener("change", (event) => {
    s.proactive.interval = Number(event.target.value) || 45;
    s.proactive.lastAt = Date.now();
    onChange();
    toast(t("toast.saved"));
  });
  root.querySelector("#proactiveNow")?.addEventListener("click", () => onProactiveNow());
  root.querySelector("#openReportFromSettings")?.addEventListener("click", () => onOpenReport());

  root.querySelectorAll("[data-theme]").forEach((el) => {
    el.addEventListener("click", () => {
      const theme = THEMES.find((item) => item.id === el.dataset.theme);
      if (!theme) return;
      s.theme = theme.id;
      s.accent = theme.accent;
      onChange();
      onAppearance();
      renderSettings({
        state, onChange, onAppearance, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
        onOpenContext, onOrganizeMemory, onUnblock,
        onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
      });
    });
  });
  /* 色号模式：直接输入 #RRGGBB，边打边预览；格式不对就标红，不改状态 */
  const accentHex = root.querySelector("#accentHex");
  const accentChip = root.querySelector("#accentChip");
  const applyAccent = (value, commit = false) => {
    const hex = normaliseAccent(value);
    if (!hex) {
      accentHex?.classList.add("is-invalid");
      if (accentChip) accentChip.classList.add("is-invalid");
      return false;
    }
    accentHex?.classList.remove("is-invalid");
    accentChip?.classList.remove("is-invalid");
    if (accentChip) accentChip.style.background = hex;
    if (hex !== s.accent || s.theme !== "custom") {
      s.accent = hex;
      s.theme = "custom";
      onChange();
      onAppearance();
    }
    if (commit) {
      if (accentHex) accentHex.value = hex;
      toast(t("toast.saved"));
    }
    return true;
  };
  accentHex?.addEventListener("input", () => applyAccent(accentHex.value));
  accentHex?.addEventListener("change", () => {
    if (applyAccent(accentHex.value, true) && s.theme === "custom") rerender();
  });
  accentHex?.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      accentHex.blur();
    }
  });
  root.querySelectorAll("[data-font]").forEach((el) => {
    el.addEventListener("click", () => {
      s.font = el.dataset.font;
      onChange();
      onAppearance();
    });
  });
  root.querySelectorAll("[data-layout]").forEach((el) => {
    el.addEventListener("click", () => {
      s.layout = el.dataset.layout;
      onChange();
      onAppearance();
      rerender();
    });
  });
  root.querySelectorAll("[data-mode]").forEach((el) => {
    el.addEventListener("click", () => {
      if (deps.onMode) deps.onMode(el.dataset.mode);
    });
  });
  root.querySelector("#uiLang")?.addEventListener("change", (event) => {
    s.uiLang = event.target.value;
    onChange();
    onUiLanguage();
  });
  root.querySelector("#aiLang")?.addEventListener("change", (event) => {
    s.aiLang = event.target.value;
    onChange();
    toast(t("toast.saved"));
  });
  root.querySelector("#pickBg")?.addEventListener("click", onPickBackground);
  root.querySelector("#removeBg")?.addEventListener("click", onRemoveBackground);
  root.querySelector("#bgOpacity")?.addEventListener("input", (event) => {
    s.chatBgOpacity = Number(event.target.value) / 100;
    const output = event.target.parentElement.querySelector("output");
    if (output) output.textContent = `${event.target.value}%`;
    onChange();
    onAppearance({ settingsOnly: true });
  });

  root.querySelector("#editKey")?.addEventListener("click", () => {
    const editor = root.querySelector("#keyEditor");
    editor.hidden = !editor.hidden;
    if (!editor.hidden) editor.querySelector("input")?.focus();
  });
  root.querySelector("#saveKey")?.addEventListener("click", () => {
    const value = root.querySelector("#newKey").value.trim();
    if (!value) return;
    s.apiKey = value;
    onChange();
    toast(t("toast.saved"));
    renderSettings({
      state, onChange, onAppearance, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
      onOpenContext, onOrganizeMemory, onUnblock,
      onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
    });
  });
  root.querySelector("#keySelect")?.addEventListener("change", (event) => {
    const key = state.keys.find((item) => item.id === event.target.value);
    if (!key) return;
    selectSettingsKey(state, key);
    onChange();
    toast(t("settings.keySwitched", { name: key.name }));
    renderSettings({
      state, onChange, onAppearance, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
      onOpenContext, onOrganizeMemory, onUnblock,
      onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
    });
  });
  root.querySelector("#addKey")?.addEventListener("click", () => {
    const panel = root.querySelector("#newKeyPanel");
    if (!panel) return;
    panel.hidden = !panel.hidden;
    if (!panel.hidden) panel.querySelector("#newKeyName")?.focus();
  });
  root.querySelector("#createKey")?.addEventListener("click", () => {
    const value = root.querySelector("#newKeyValue")?.value.trim();
    if (!value) {
      root.querySelector("#newKeyValue")?.focus();
      return;
    }
    const providerId = root.querySelector("#newKeyProvider")?.value || "custom";
    const provider = PROVIDERS[providerId] || PROVIDERS.custom;
    const name = root.querySelector("#newKeyName")?.value.trim()
      || `${provider.short || provider.label || "Key"} ${state.keys.length + 1}`;
    const key = {
      id: uid("key"),
      name: name.slice(0, 40),
      provider: provider.id,
      apiKey: value,
      baseUrl: provider.baseUrl,
      model: provider.model,
      visionModel: provider.visionModel || "",
      createdAt: Date.now(),
    };
    state.keys.push(key);
    selectSettingsKey(state, key);
    onChange();
    toast(t("settings.keyAdded", { name: key.name }));
    renderSettings({
      state, onChange, onAppearance, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
      onOpenContext, onOrganizeMemory, onUnblock,
      onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
    });
  });
  root.querySelector("#deleteKey")?.addEventListener("click", async () => {
    if (state.keys.length <= 1) return;
    const key = state.keys.find((item) => item.id === state.activeKeyId) || state.keys[0];
    const ok = await confirmDialog({
      title: t("settings.deleteKey"),
      body: t("settings.deleteKeyConfirm", { name: key.name }),
      confirm: t("common.delete"),
      danger: true,
    });
    if (!ok) return;
    state.keys = state.keys.filter((item) => item.id !== key.id);
    const next = state.keys[0];
    for (const chat of state.chats) {
      if (chat.keyId === key.id) chat.keyId = next?.id || "";
    }
    if (next) selectSettingsKey(state, next);
    else {
      state.activeKeyId = "";
      s.apiKey = "";
    }
    onChange();
    toast(t("settings.keyDeleted"));
    renderSettings({
      state, onChange, onAppearance, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
      onOpenContext, onOrganizeMemory, onUnblock,
      onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
    });
  });
  root.querySelector("#connProvider")?.addEventListener("change", (event) => {
    const provider = PROVIDERS[event.target.value];
    if (!provider) return;
    s.provider = provider.id;
    if (provider.id !== "custom") {
      s.baseUrl = provider.baseUrl;
      s.model = provider.model;
      s.visionModel = provider.visionModel || "";
    }
    onChange();
    renderSettings({
      state, onChange, onAppearance, onUiLanguage, onPickAvatar, onPickBackground, onRemoveBackground,
      onOpenContext, onOrganizeMemory, onUnblock,
      onExport, onImport, onShare, onClearChat, onClearAll, onOpenReport, onProactiveNow, onRestartSetup,
    });
  });
  root.querySelectorAll("[data-conn]").forEach((el) => {
    el.addEventListener("input", () => {
      s[el.dataset.conn] = el.value;
      onChange();
    });
  });
  root.querySelector("#testConn")?.addEventListener("click", async (event) => {
    const btn = event.currentTarget;
    const status = root.querySelector("#testConnStatus");
    if (!s.apiKey) {
      status.textContent = t("setup.fillKey");
      status.className = "hint-inline status-bad";
      return;
    }
    setLoading(btn, true, "");
    status.textContent = "";
    try {
      const result = await testConnection(s);
      status.textContent = result.count ? t("setup.connected", { count: result.count }) : t("settings.connectionOk");
      status.className = "hint-inline status-good";
    } catch (error) {
      status.textContent = t("settings.connectionFail", { msg: errorText(error, t) });
      status.className = "hint-inline status-bad";
    } finally {
      setLoading(btn, false);
    }
  });

  root.querySelector("#exportProfile")?.addEventListener("click", onExport);
  root.querySelector("#importProfile")?.addEventListener("click", onImport);
  root.querySelector("#shareApp")?.addEventListener("click", onShare);
  root.querySelector("#clearChat")?.addEventListener("click", async () => {
    const ok = await confirmDialog({
      title: t("settings.clearChat"),
      body: t("settings.clearChatConfirm"),
      confirm: t("common.delete"),
      danger: true,
    });
    if (ok) onClearChat();
  });
  root.querySelector("#clearAll")?.addEventListener("click", async () => {
    const ok = await confirmDialog({
      title: t("settings.clearAll"),
      body: t("settings.clearAllConfirm"),
      confirm: t("common.delete"),
      danger: true,
    });
    if (ok) onClearAll();
  });
  root.querySelector("#restartSetup")?.addEventListener("click", onRestartSetup);
  root.querySelector("#heroEdit")?.addEventListener("click", () => {
    const details = root.querySelector('[data-group="persona"]');
    if (details) {
      details.open = true;
      details.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  });

  root.querySelector("#studioStyle")?.addEventListener("change", (event) => {
    if (!state.stickerStudio) state.stickerStudio = { packs: [] };
    state.stickerStudio.style = STICKER_STYLE_OPTIONS.some((option) => option.id === event.target.value)
      ? event.target.value
      : "auto";
    const option = STICKER_STYLE_OPTIONS.find((item) => item.id === state.stickerStudio.style);
    const hint = root.querySelector("#studioStyleHint");
    if (hint && option) hint.textContent = t(option.hintKey);
    onChange();
  });
  root.querySelector("#studioDirection")?.addEventListener("input", (event) => {
    if (!state.stickerStudio) state.stickerStudio = { packs: [] };
    state.stickerStudio.direction = event.target.value.slice(0, 180);
    onChange();
  });

  root.querySelectorAll("[data-bg-action]").forEach((button) => {
    button.addEventListener("click", () => {
      const action = button.dataset.bgAction;
      try {
        if (action === "battery") {
          toast(t("settings.bgPermissionToast"), { timeout: 4200 });
          window.LianNative?.requestIgnoreBatteryOptimizations?.();
        } else if (action === "autostart") {
          toast(t("settings.bgAutoStartToast"), { timeout: 4200 });
          window.LianNative?.openAutoStartSettings?.();
        } else if (action === "notify") {
          toast(t("settings.bgNotifyToast"), { timeout: 4200 });
          window.LianNative?.openNotificationSettings?.();
        } else if (action === "test") {
          let sent = false;
          try {
            sent = Boolean(window.LianNative?.notify?.("Lian", t("settings.bgTestNotifyBody")));
          } catch {
            // The bridge is optional.
          }
          toast(sent ? t("settings.bgTestNotifyToast") : t("settings.bgNotifyOff"), { timeout: 4200 });
        }
      } catch {
        // Older APKs may not expose the newer bridge methods.
      }
      window.setTimeout(() => refreshNativeBackgroundUI(root), 700);
    });
  });

  refreshNativeBackgroundUI(root);
}
