import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MODULES = path.join(ROOT, "css", "modules");

function sheets() {
  const list = [path.join(ROOT, "css", "app.css")];
  for (const name of fs.readdirSync(MODULES)) {
    if (name.endsWith(".css")) list.push(path.join(MODULES, name));
  }
  return list;
}

test("no stylesheet declares a font size below 10px", () => {
  const offenders = [];
  for (const file of sheets()) {
    const text = fs.readFileSync(file, "utf8");
    for (const match of text.matchAll(/font-size:\s*([0-9.]+)px/g)) {
      const size = Number(match[1]);
      if (size < 10) offenders.push(`${path.relative(ROOT, file)}: ${size}px`);
    }
  }
  assert.deepEqual(offenders, []);
});

test("the type scale starts at the readable floor and includes a 15px body", () => {
  const tokens = fs.readFileSync(path.join(MODULES, "01-tokens.css"), "utf8");
  const sizes = [...tokens.matchAll(/--fs-[a-z0-9]+:\s*([0-9.]+)px/g)].map((m) => Number(m[1]));
  assert.ok(sizes.length >= 6, "expected a full type scale");
  assert.ok(Math.min(...sizes) >= 10, `smallest token is ${Math.min(...sizes)}px`);
  assert.ok(sizes.includes(15), "body size missing");
});

test("body text and timestamps use the scale instead of magic numbers", () => {
  const type = fs.readFileSync(path.join(MODULES, "02-type.css"), "utf8");
  assert.ok(/\.bubble\s*\{[^}]*var\(--fs-body\)/.test(type));
  assert.ok(/\.msg-time\s*\{[^}]*var\(--fs-xs\)/.test(type));
  assert.ok(/tabular-nums/.test(type));
});
