import { escapeHtml } from "./utils.js";

const $ = (selector, root = document) => root.querySelector(selector);

const USER_SILHOUETTE = `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="3.4"/><path d="M4.5 21c.4-4.2 3.2-6.8 7.5-6.8s7.1 2.6 7.5 6.8Z"/></svg>`;

export function icon(name, className = "icon") {
  return `<svg class="${className}" aria-hidden="true"><use href="#i-${name}"></use></svg>`;
}

export function avatarMarkup({ src = "", role = "ai", name = "Lian", size = 40, extra = "" } = {}) {
  const cls = `avatar avatar-${role} avatar-${size} ${extra}`.trim();
  const presence = role === "ai" ? '<span class="presence"></span>' : "";
  if (src) {
    return `<span class="${cls}"><img src="${escapeHtml(src)}" alt="">${presence}</span>`;
  }
  const fallback = role === "user" ? USER_SILHOUETTE : escapeHtml(String(name || "L").slice(0, 1));
  return `<span class="${cls}"><span class="avatar-fallback">${fallback}</span>${presence}</span>`;
}

export function paintAvatar(el, { src = "", role = "ai", name = "Lian" } = {}) {
  if (!el) return;
  el.classList.toggle("avatar-user", role === "user");
  el.classList.toggle("avatar-ai", role !== "user");
  el.innerHTML = src
    ? `<img src="${escapeHtml(src)}" alt="">${role === "ai" ? '<i class="presence"></i>' : ""}`
    : `<span class="avatar-fallback">${role === "user" ? USER_SILHOUETTE : escapeHtml(String(name || "L").slice(0, 1))}</span>${role === "ai" ? '<i class="presence"></i>' : ""}`;
}

let toastTimer = 0;
let toastAction = null;

export function hideToast() {
  const el = $("#toast");
  if (!el) return;
  el.hidden = true;
  toastAction = null;
  clearTimeout(toastTimer);
}

export function toast(message, { action = "", onAction = null, timeout = 3200 } = {}) {
  const el = $("#toast");
  const text = $("#toastText");
  const actionBtn = $("#toastAction");
  if (!el || !text || !actionBtn) return;
  clearTimeout(toastTimer);
  text.textContent = message;
  toastAction = onAction;
  actionBtn.hidden = !action;
  actionBtn.textContent = action;
  actionBtn.onclick = () => {
    const fn = toastAction;
    hideToast();
    fn?.();
  };
  el.hidden = false;
  toastTimer = window.setTimeout(hideToast, timeout);
}

let sheetCleanup = null;
let modalCleanup = null;

export function openSheet(html, { onMount = null, className = "", lock = true } = {}) {
  const layer = $("#sheetLayer");
  const sheet = $("#sheet");
  if (!layer || !sheet) return null;
  sheet.className = `sheet ${className}`.trim();
  sheet.innerHTML = html;
  layer.hidden = false;
  if (lock) document.documentElement.classList.add("is-locked");
  // Bind synchronously: every sheet's onMount only wires listeners, and a tap
  // that lands in the same frame as the render used to be swallowed.
  onMount?.(sheet);
  requestAnimationFrame(() => {
    sheet.scrollTop = 0;
    const first = sheet.querySelector("input:not([type=hidden]), textarea, button");
    // Do not steal focus for menu-like sheets; only when the caller asks.
    if (first && sheet.dataset.autofocus === "true") first.focus();
  });
  return sheet;
}

export function closeSheet() {
  const layer = $("#sheetLayer");
  if (!layer || layer.hidden) return;
  layer.hidden = true;
  $("#sheet").innerHTML = "";
  document.documentElement.classList.remove("is-locked");
  sheetCleanup?.();
  sheetCleanup = null;
}

export function onSheetCleanup(fn) {
  sheetCleanup = fn;
}

export function openModal(html, { className = "", onMount = null, onClose = null } = {}) {
  const layer = $("#modalLayer");
  const modal = $("#modal");
  if (!layer || !modal) return null;
  modal.className = `modal ${className}`.trim();
  modal.innerHTML = html;
  layer.hidden = false;
  document.documentElement.classList.add("is-locked");
  modalCleanup = onClose;
  onMount?.(modal);
  return modal;
}

export function closeModal() {
  const layer = $("#modalLayer");
  if (!layer || layer.hidden) return;
  layer.hidden = true;
  $("#modal").innerHTML = "";
  document.documentElement.classList.remove("is-locked");
  modalCleanup?.();
  modalCleanup = null;
}

export function closeAllOverlays() {
  closeSheet();
  closeModal();
}

export function confirmDialog({ title, body = "", confirm = "确认", cancel = "取消", danger = false }) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      closeModal();
      resolve(value);
    };
    const modal = openModal(
      `<div class="confirm-modal">
        <h2>${escapeHtml(title)}</h2>
        ${body ? `<p>${escapeHtml(body)}</p>` : ""}
        <div class="confirm-actions">
          <button type="button" class="btn btn-ghost" data-cancel>${escapeHtml(cancel)}</button>
          <button type="button" class="btn ${danger ? "btn-danger" : "btn-primary"}" data-confirm>${escapeHtml(confirm)}</button>
        </div>
      </div>`,
      {
        onClose: () => finish(false),
      },
    );
    modal.querySelector("[data-cancel]").addEventListener("click", () => finish(false));
    modal.querySelector("[data-confirm]").addEventListener("click", () => finish(true));
  });
}

export function lightboxImage(src, alt = "") {
  const el = document.createElement("div");
  el.className = "lightbox";
  el.innerHTML = `<button type="button" class="lightbox-close" aria-label="关闭">${icon("close")}</button><img src="${escapeHtml(src)}" alt="${escapeHtml(alt)}">`;
  document.body.appendChild(el);
  const close = () => el.remove();
  el.addEventListener("click", (event) => {
    if (event.target === el || event.target.closest(".lightbox-close")) close();
  });
  const onKey = (event) => {
    if (event.key === "Escape") {
      close();
      document.removeEventListener("keydown", onKey);
    }
  };
  document.addEventListener("keydown", onKey);
  return el;
}

export function setLoading(button, loading, label = "") {
  if (!button) return;
  if (loading) {
    button.dataset.original = button.innerHTML;
    button.disabled = true;
    button.innerHTML = `<span class="spinner"></span>${label ? `<span>${escapeHtml(label)}</span>` : ""}`;
  } else if (button.dataset.original) {
    button.innerHTML = button.dataset.original;
    delete button.dataset.original;
    button.disabled = false;
  }
}

export function showScreen(name) {
  const map = {
    setup: "#setupScreen",
    list: "#chatListScreen",
    contacts: "#contactsScreen",
    home: "#homeScreen",
    chat: "#chatScreen",
    settings: "#settingsScreen",
  };
  for (const [key, selector] of Object.entries(map)) {
    const el = $(selector);
    if (el) el.hidden = key !== name;
  }
  document.body.dataset.screen = name;
  for (const tab of document.querySelectorAll("#tabBar [data-tab]")) {
    const active = tab.dataset.tab === name;
    tab.classList.toggle("is-on", active);
    if (active) tab.setAttribute("aria-current", "page");
    else tab.removeAttribute("aria-current");
  }
}

export function closeTopLayer() {
  if (!$("#modalLayer").hidden) {
    closeModal();
    return true;
  }
  if (!$("#sheetLayer").hidden) {
    closeSheet();
    return true;
  }
  return false;
}

export function bindLayerScaffolding() {
  const sheetLayer = $("#sheetLayer");
  sheetLayer?.addEventListener("click", (event) => {
    if (event.target.closest("[data-close-sheet]")) closeSheet();
  });
  const modalLayer = $("#modalLayer");
  modalLayer?.addEventListener("click", (event) => {
    if (event.target === modalLayer) closeModal();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeTopLayer();
  });
}
