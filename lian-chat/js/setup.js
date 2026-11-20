import { DEFAULT_GREETING, PROVIDERS } from "./config.js";
import { t } from "./i18n.js";
import { testConnection, errorText } from "./api.js";
import { avatarMarkup, icon, setLoading } from "./ui.js";
import { escapeHtml } from "./utils.js";

export function renderSetup({ state, onChange, onStart, onPickAvatar, onDemo }) {
  const s = state.settings;
  const step = state.setupStep === 1 ? 1 : 0;
  const body = document.querySelector("#setupBody");
  const footer = document.querySelector("#setupFooter");
  const progress = document.querySelectorAll("#setupProgress span");
  if (!body || !footer) return;

  progress.forEach((el, index) => el.classList.toggle("is-on", index <= step));
  progress[0]?.setAttribute("aria-label", t("setup.step", { n: 1 }));

  if (step === 0) {
    body.innerHTML = `
      <p class="setup-kicker">${escapeHtml(t("setup.kickerConnect"))}</p>
      <h1 class="setup-title">${escapeHtml(t("setup.step1Title"))}</h1>
      <p class="setup-lead">${escapeHtml(t("setup.step1Lead"))}</p>

      <div class="field">
        <div class="field-label">${escapeHtml(t("setup.provider"))}</div>
        <div class="provider-grid" role="group">
          ${Object.values(PROVIDERS)
            .map(
              (provider) => `
            <button type="button" class="provider-chip ${provider.id === s.provider ? "is-on" : ""}" data-provider="${provider.id}">
              <b>${escapeHtml(provider.label)}</b>
              <small>${escapeHtml(provider.note)}</small>
            </button>`,
            )
            .join("")}
        </div>
      </div>

      <div class="field">
        <label class="field-label" for="setupKey">${escapeHtml(t("setup.key"))}</label>
        <div class="input-wrap">
          <input class="input" id="setupKey" type="password" autocomplete="off" spellcheck="false"
                 placeholder="${escapeHtml(t("setup.keyPh"))}" value="${escapeHtml(s.apiKey)}">
        </div>
        <p class="field-hint">${escapeHtml(t("setup.keyHint"))}</p>
        <p class="field-hint" id="setupKeyStatus"></p>
        <div class="settings-actions">
          <button type="button" class="btn btn-ghost btn-small" id="setupTest">${escapeHtml(t("common.test"))}</button>
          <span class="hint-inline" id="setupTestStatus"></span>
        </div>
      </div>

      <details class="advanced" ${s.provider === "custom" ? "open" : ""}>
        <summary>${escapeHtml(t("setup.advanced"))}</summary>
        <div class="advanced-body">
          <div class="field">
            <label class="field-label" for="setupBase">${escapeHtml(t("setup.baseUrl"))}</label>
            <input class="input" id="setupBase" type="url" inputmode="url" spellcheck="false"
                   placeholder="https://api.example.com/v1" value="${escapeHtml(s.baseUrl)}">
          </div>
          <div class="field">
            <label class="field-label" for="setupModel">${escapeHtml(t("setup.model"))}</label>
            <input class="input" id="setupModel" type="text" spellcheck="false"
                   placeholder="model-name" value="${escapeHtml(s.model)}">
          </div>
          <div class="field">
            <label class="field-label" for="setupVision">${escapeHtml(t("setup.visionModel"))} <small>${escapeHtml(t("common.optional"))}</small></label>
            <input class="input" id="setupVision" type="text" spellcheck="false"
                   placeholder="model-name" value="${escapeHtml(s.visionModel)}">
            <p class="field-hint">${escapeHtml(t("setup.visionHint"))}</p>
          </div>
        </div>
      </details>

      <div class="welcome-note">
        ${icon("heart")}
        <span>${escapeHtml(t("setup.privacyNote"))}</span>
      </div>
      <div class="setup-step" style="margin-top:18px">${escapeHtml(t("setup.step", { n: 1 }))}</div>
    `;
    footer.innerHTML = `
      <button type="button" class="btn btn-primary" id="setupNext">${escapeHtml(t("setup.next"))}</button>
      <p class="footer-note">${escapeHtml(t("setup.footerNote"))}</p>
    `;
  } else {
    body.innerHTML = `
      <p class="setup-kicker">${escapeHtml(t("settings.persona"))}</p>
      <h1 class="setup-title">${escapeHtml(t("setup.personaTitle"))}</h1>
      <p class="setup-lead">${escapeHtml(t("setup.personaLead"))}</p>

      <div class="avatar-pick" style="margin-bottom:18px">
        ${avatarMarkup({ src: s.aiAvatar, role: "ai", name: s.aiName, size: 50, extra: "avatar-50" })}
        <div class="avatar-pick-copy">
          <b>${escapeHtml(t("setup.avatar"))}</b>
          <small>${escapeHtml(t("common.optional"))} · ${escapeHtml(t("setup.changeAvatar"))}</small>
        </div>
        <button type="button" class="btn btn-ghost btn-small" data-pick-avatar="ai">${escapeHtml(t("setup.changeAvatar"))}</button>
      </div>

      <div class="field">
        <label class="field-label" for="setupAiName">${escapeHtml(t("setup.aiName"))}</label>
        <input class="input" id="setupAiName" type="text" maxlength="20" value="${escapeHtml(s.aiName)}" placeholder="Lian">
      </div>
      <div class="field">
        <label class="field-label" for="setupUserName">${escapeHtml(t("setup.userName"))}</label>
        <input class="input" id="setupUserName" type="text" maxlength="20" value="${escapeHtml(s.userName)}" placeholder="你">
      </div>
      <div class="field">
        <label class="field-label" for="setupRelation">${escapeHtml(t("setup.relationship"))} <small>${escapeHtml(t("common.optional"))}</small></label>
        <input class="input" id="setupRelation" type="text" maxlength="40" value="${escapeHtml(s.relationship)}" placeholder="${escapeHtml(t("setup.relationshipPh"))}">
      </div>
      <div class="field">
        <label class="field-label" for="setupPersona">${escapeHtml(t("setup.persona"))} <small>${escapeHtml(t("common.optional"))}</small></label>
        <textarea class="textarea" id="setupPersona" maxlength="1200" placeholder="${escapeHtml(t("setup.personaPh"))}">${escapeHtml(s.persona)}</textarea>
      </div>
      <div class="field">
        <label class="field-label" for="setupGreeting">${escapeHtml(t("setup.greeting"))}</label>
        <textarea class="textarea" id="setupGreeting" maxlength="240" style="min-height:64px" placeholder="${escapeHtml(t("setup.greetingPh"))}">${escapeHtml(s.greeting)}</textarea>
      </div>

      <div class="welcome-note">
        ${icon("sparkle")}
        <span>${escapeHtml(t("setup.privacyNote"))}</span>
      </div>
      <div class="setup-step" style="margin-top:18px">${escapeHtml(t("setup.step", { n: 2 }))}</div>
    `;
    footer.innerHTML = `
      <button type="button" class="btn btn-primary" id="setupStart">${escapeHtml(t("setup.start"))}</button>
      <button type="button" class="btn btn-text" id="setupBack">${escapeHtml(t("common.back"))}</button>
    `;
  }

  const bindField = (selector, key, { trim = false } = {}) => {
    const el = body.querySelector(selector);
    if (!el) return;
    el.addEventListener("input", () => {
      s[key] = trim ? el.value.trimStart() : el.value;
      onChange();
      if (key === "aiName" && !s.aiAvatar) {
        const av = body.querySelector(".avatar-pick .avatar");
        if (av) av.innerHTML = `<span class="avatar-fallback">${escapeHtml(String(s.aiName || "L").slice(0, 1))}</span>`;
      }
    });
  };

  if (step === 0) {
    body.querySelector("#setupKey")?.addEventListener("input", (event) => {
      s.apiKey = event.target.value.trim();
      onChange();
    });
    bindField("#setupBase", "baseUrl");
    bindField("#setupModel", "model");
    bindField("#setupVision", "visionModel");

    body.querySelectorAll("[data-provider]").forEach((button) => {
      button.addEventListener("click", () => {
        const provider = PROVIDERS[button.dataset.provider];
        if (!provider) return;
        s.provider = provider.id;
        if (provider.id !== "custom") {
          s.baseUrl = provider.baseUrl;
          s.model = provider.model;
          s.visionModel = provider.visionModel || "";
        }
        onChange();
        renderSetup({ state, onChange, onStart, onPickAvatar, onDemo });
      });
    });

    body.querySelector("#setupTest")?.addEventListener("click", async (event) => {
      const btn = event.currentTarget;
      const status = body.querySelector("#setupTestStatus");
      if (!s.apiKey) {
        status.textContent = t("setup.fillKey");
        status.className = "hint-inline status-bad";
        return;
      }
      setLoading(btn, true, t("setup.testing"));
      status.textContent = "";
      try {
        const result = await testConnection(s);
        status.textContent = result.count ? t("setup.connected", { count: result.count }) : t("setup.connectedNoList");
        status.className = "hint-inline status-good";
        s.lastTest = { ok: true, at: Date.now(), count: result.count };
        onChange();
      } catch (error) {
        status.textContent = t("setup.badKey", { msg: errorText(error, t) });
        status.className = "hint-inline status-bad";
      } finally {
        setLoading(btn, false);
        if (btn.dataset.original) btn.textContent = t("common.test");
      }
    });

    requestAnimationFrame(() => {
      const key = body.querySelector("#setupKey");
      if (key && key.value) key.setSelectionRange(key.value.length, key.value.length);
    });
  } else {
    bindField("#setupAiName", "aiName");
    bindField("#setupUserName", "userName");
    bindField("#setupRelation", "relationship");
    bindField("#setupPersona", "persona");
    bindField("#setupGreeting", "greeting");
    body.querySelector("[data-pick-avatar]")?.addEventListener("click", () => onPickAvatar("ai"));
  }

  footer.querySelector("#setupNext")?.addEventListener("click", () => {
    if (!s.apiKey) {
      const status = body.querySelector("#setupKeyStatus");
      status.textContent = t("setup.fillKey");
      status.className = "field-error";
      body.querySelector("#setupKey")?.focus();
      return;
    }
    if (s.provider === "custom" && (!s.baseUrl.trim() || !s.model.trim())) {
      const details = body.querySelector("details.advanced");
      if (details) details.open = true;
      const status = body.querySelector("#setupTestStatus") || body.querySelector("#setupKeyStatus");
      status.textContent = t("setup.customRequired");
      status.className = "field-error";
      return;
    }
    state.setupStep = 1;
    onChange();
    renderSetup({ state, onChange, onStart, onPickAvatar, onDemo });
  });
  footer.querySelector("#setupBack")?.addEventListener("click", () => {
    state.setupStep = 0;
    onChange();
    renderSetup({ state, onChange, onStart, onPickAvatar, onDemo });
  });
  footer.querySelector("#setupStart")?.addEventListener("click", () => {
    if (!s.aiName.trim()) s.aiName = "Lian";
    if (!s.userName.trim()) s.userName = "你";
    if (!s.greeting.trim()) s.greeting = DEFAULT_GREETING;
    state.onboarded = true;
    state.setupStep = 1;
    onChange();
    onStart();
  });
}
