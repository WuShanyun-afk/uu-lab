import test from "node:test";
import assert from "node:assert/strict";
import { extractSources } from "../js/api.js";

test("MiMo url citations become deduplicated web sources", () => {
  const sources = extractSources({
    annotations: [
      { type: "url_citation", url: "https://example.com/a", title: "A", site_name: "Example" },
      { type: "url_citation", url: "https://example.com/a", title: "A again" },
      { type: "url_citation", url: "https://example.com/b", title: "B" },
      { type: "something_else", url: "https://example.com/c" },
      { type: "url_citation" },
    ],
  });
  assert.equal(sources.length, 2);
  assert.equal(sources[0].url, "https://example.com/a");
  assert.equal(sources[0].siteName, "Example");
  assert.equal(sources[1].url, "https://example.com/b");
  assert.deepEqual(extractSources({}), []);
  assert.deepEqual(extractSources({ annotations: "nope" }), []);
});
