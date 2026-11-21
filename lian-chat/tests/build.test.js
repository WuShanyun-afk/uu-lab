import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("HTML build, app build and package version agree", () => {
  const html = read("index.html");
  const app = read("js/app.js");
  const version = JSON.parse(read("package.json")).version;
  const htmlBuild = html.match(/__LIAN_HTML_BUILD__\s*=\s*"([^"]+)"/)?.[1];
  const appBuild = app.match(/__LIAN_APP_BUILD__\s*=\s*"([^"]+)"/)?.[1];
  assert.equal(htmlBuild, version, "index.html build must match package.json");
  assert.equal(appBuild, version, "app.js build must match package.json");
  assert.ok(html.includes(`js/app.js?v=${version}`), "the entry script should carry the build query");
});

test("a missing translation never prints its key", () => {
  const app = read("js/app.js");
  assert.ok(
    app.includes("if (value && value !== key) el.textContent = value;"),
    "data-i18n must fall back to the baked-in Chinese instead of the key",
  );
  assert.ok(app.includes("if (value && value !== el.dataset.i18nPh) el.placeholder = value;"));
  assert.ok(app.includes("if (value && value !== el.dataset.i18nAria) el.setAttribute(\"aria-label\", value);"));
});

test("the service worker serves scripts and styles network-first", () => {
  const sw = read("sw.js");
  assert.ok(sw.includes('url.pathname.includes("/js/")'), "js must bypass the stale cache");
  assert.ok(sw.includes('url.pathname.includes("/css/")'), "css must bypass the stale cache");
  assert.ok(sw.includes("fetch(request)"), "network-first needs a fetch");
});
