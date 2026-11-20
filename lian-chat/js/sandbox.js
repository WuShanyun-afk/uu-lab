import { deleteSandboxAsset, getSandboxAsset, listSandboxAssets, putSandboxAsset } from "./store.js";
import { uid } from "./utils.js";

export const SANDBOX_SEGMENT = "__sandbox__/asset/";

export function sandboxUrl(id) {
  if (!id) return "";
  return new URL(`__sandbox__/asset/${encodeURIComponent(id)}`, location.href).href;
}

export function sandboxBase() {
  return `${location.origin}${new URL("./", location.href).pathname}${SANDBOX_SEGMENT}`;
}

export function sandboxHostStatus() {
  if (!("serviceWorker" in navigator)) return "unsupported";
  if (navigator.serviceWorker.controller) return "ready";
  return "pending";
}

export async function waitForSandboxHost(timeout = 1800) {
  if (!("serviceWorker" in navigator)) return false;
  if (navigator.serviceWorker.controller) return true;
  const deadline = Date.now() + timeout;
  await Promise.race([
    navigator.serviceWorker.ready.catch(() => null),
    new Promise((resolve) => setTimeout(resolve, timeout)),
  ]);
  if (navigator.serviceWorker.controller) return true;
  const remaining = Math.max(0, deadline - Date.now());
  if (!remaining) return false;
  return new Promise((resolve) => {
    let done = false;
    const finish = (value) => {
      if (done) return;
      done = true;
      navigator.serviceWorker.removeEventListener("controllerchange", onChange);
      clearTimeout(timer);
      resolve(value);
    };
    const onChange = () => finish(Boolean(navigator.serviceWorker.controller));
    const timer = setTimeout(() => finish(Boolean(navigator.serviceWorker.controller)), remaining);
    navigator.serviceWorker.addEventListener("controllerchange", onChange, { once: true });
  });
}

export async function hostSandboxAsset({ kind, mime, name, content, meta = {} }) {
  const asset = {
    id: uid("sbx"),
    kind,
    mime,
    name: String(name || "untitled").slice(0, 80),
    content: String(content || ""),
    createdAt: Date.now(),
    meta,
  };
  await putSandboxAsset(asset);
  return asset;
}

export async function hostSticker(svg, name, meta = {}) {
  return hostSandboxAsset({
    kind: "svg",
    mime: "image/svg+xml",
    name,
    content: svg,
    meta,
  });
}

export async function hostHtml(html, name, meta = {}) {
  return hostSandboxAsset({
    kind: "html",
    mime: "text/html; charset=utf-8",
    name,
    content: html,
    meta,
  });
}

export async function listSandbox() {
  try {
    return await listSandboxAssets();
  } catch {
    return [];
  }
}

export async function removeSandboxAsset(id) {
  try {
    await deleteSandboxAsset(id);
    return true;
  } catch {
    return false;
  }
}

export async function readSandboxAsset(id) {
  try {
    return await getSandboxAsset(id);
  } catch {
    return null;
  }
}

export function assetTypeLabel(asset) {
  if (!asset) return "";
  if (asset.kind === "svg") return "SVG";
  if (asset.kind === "html") return "HTML";
  return String(asset.mime || "ASSET").split(";")[0].toUpperCase();
}

export function assetBytes(asset) {
  return new Blob([String(asset?.content || "")]).size;
}
