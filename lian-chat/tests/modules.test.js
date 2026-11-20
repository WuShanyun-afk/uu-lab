/* Guards against the "PROVIDERS is not defined" class of boot crash.
 *
 * The 1.9.0 APK shipped with js/app.js using PROVIDERS without importing it.
 * Every unit test still passed, because none of them loads app.js. This test
 * statically checks every module for:
 *   - named imports that the target module does not export
 *   - ALL_CAPS / PascalCase constants used but never imported or declared
 * and fails the suite when the browser would throw at boot.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const JS_DIR = path.join(ROOT, "js");
const MODULES = fs.readdirSync(JS_DIR).filter((f) => f.endsWith(".js")).sort();

test("module graph has no missing imports or undeclared constants", () => {
  const result = spawnSync(process.execPath, [path.join(ROOT, "scripts", "check-modules.mjs")], {
    encoding: "utf8",
    cwd: ROOT,
  });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});

test("every module parses as an ES module", () => {
  for (const file of MODULES) {
    const result = spawnSync(process.execPath, ["--check", path.join(JS_DIR, file)], {
      encoding: "utf8",
    });
    assert.equal(result.status, 0, `${file}: ${result.stderr}`);
  }
});

test("app.js imports every constant it references", () => {
  const source = fs.readFileSync(path.join(JS_DIR, "app.js"), "utf8");
  for (const name of ["PROVIDERS", "DEFAULT_GREETING", "THEMES", "EMOJIS"]) {
    if (!new RegExp(`\\b${name}\\b`).test(source)) continue;
    assert.match(
      source,
      new RegExp(`import\\s*\\{[^}]*\\b${name}\\b[^}]*\\}\\s*from\\s*"\\./config\\.js"`),
      `${name} is used in app.js but not imported from ./config.js`,
    );
  }
});
