/* Lian service worker — cache the shell so the app opens instantly.
   API calls are never cached. */
const VERSION = "lian-v1.9.23-1";
const SANDBOX_MARK = "/__sandbox__/asset/";
const ASSETS = [
  "./",
  "index.html",
  "css/app.css",
  "css/modules/01-tokens.css",
  "css/modules/02-type.css",
  "css/modules/03-contrast.css",
  "css/modules/04-bubbles.css",
  "css/modules/05-surfaces.css",
  "css/modules/06-home.css",
  "css/modules/07-theme-paper.css",
  "css/modules/08-motion.css",
  "css/modules/09-dark.css",
  "css/modules/10-live.css",
  "css/modules/11-actions.css",
  "css/modules/12-search.css",
  "css/modules/13-inbox.css",
  "css/modules/14-drawings.css",
"css/modules/15-themes.css",
  "css/modules/16-layouts.css",
  "css/modules/17-screens.css",
  "css/modules/18-composer.css",
  "css/modules/19-modes.css",
  "js/app.js",
  "js/api.js",
  "js/config.js",
  "js/drawing.js",
  "js/i18n.js",
  "js/insights.js",
  "js/memory.js",
  "js/palette.js",
  "js/roleplay.js",
  "js/prompt.js",
  "js/report.js",
  "js/search.js",
  "js/sandbox.js",
  "js/settings.js",
  "js/setup.js",
  "js/store.js",
  "js/studio.js",
  "js/ui.js",
  "js/utils.js",
  "manifest.webmanifest",
  "assets/backgrounds/snow-station.svg",
  "assets/stickers/mj_adore.webp",
  "assets/stickers/mj_agree.webp",
  "assets/stickers/mj_angry.webp",
  "assets/stickers/mj_cry.webp",
  "assets/stickers/mj_fault.webp",
  "assets/stickers/mj_goodnight.webp",
  "assets/stickers/mj_happy.webp",
  "assets/stickers/mj_hello.webp",
  "assets/stickers/mj_hmph.webp",
  "assets/stickers/mj_huh.webp",
  "assets/stickers/mj_like.webp",
  "assets/stickers/mj_love.webp",
  "assets/stickers/mj_meow.webp",
  "assets/stickers/mj_morning.webp",
  "assets/stickers/mj_ng.webp",
  "assets/stickers/mj_ok.webp",
  "assets/stickers/mj_pat.webp",
  "assets/stickers/mj_peace.webp",
  "assets/stickers/mj_peek.webp",
  "assets/stickers/mj_plead.webp",
  "assets/stickers/mj_promise.webp",
  "assets/stickers/mj_sleepy.webp",
  "assets/stickers/mj_sorry.webp",
  "assets/stickers/mj_stay.webp",
  "assets/stickers/mj_wail.webp",
  "assets/stickers/mk_adopt.webp",
  "assets/stickers/mk_bleh.webp",
  "assets/stickers/mk_bored.webp",
  "assets/stickers/mk_box.webp",
  "assets/stickers/mk_bye.webp",
  "assets/stickers/mk_cat.webp",
  "assets/stickers/mk_cheer.webp",
  "assets/stickers/mk_chuckle.webp",
  "assets/stickers/mk_clap.webp",
  "assets/stickers/mk_cry.webp",
  "assets/stickers/mk_drowsy.webp",
  "assets/stickers/mk_expect.webp",
  "assets/stickers/mk_goodnight.webp",
  "assets/stickers/mk_hello.webp",
  "assets/stickers/mk_hello-shy.webp",
  "assets/stickers/mk_hide.webp",
  "assets/stickers/mk_hiss.webp",
  "assets/stickers/mk_lie.webp",
  "assets/stickers/mk_like.webp",
  "assets/stickers/mk_meow.webp",
  "assets/stickers/mk_morning.webp",
  "assets/stickers/mk_nope.webp",
  "assets/stickers/mk_ok.webp",
  "assets/stickers/mk_peek.webp",
  "assets/stickers/mk_phone.webp",
  "assets/stickers/mk_plead.webp",
  "assets/stickers/mk_sad.webp",
  "assets/stickers/mk_scheme.webp",
  "assets/stickers/mk_shock.webp",
  "assets/stickers/mk_shutdown.webp",
  "assets/stickers/mk_shy.webp",
  "assets/stickers/mk_silly.webp",
  "assets/stickers/mk_sleep.webp",
  "assets/stickers/mk_sleepy.webp",
  "assets/stickers/mk_spy.webp",
  "assets/stickers/mk_stare.webp",
  "assets/stickers/mk_sulk.webp",
  "assets/stickers/mk_surprised.webp",
  "assets/stickers/mk_think.webp",
  "assets/stickers/mk_watch.webp",
  "assets/stickers/mk_what.webp",
  "assets/stickers/mk_wow.webp",
  "assets/stickers/mk_wronged.webp",
  "assets/stickers/mk_yay.webp",
  "assets/icons/icon.svg",
  "assets/icons/icon-180.png",
  "assets/icons/icon-192.png",
  "assets/icons/icon-512.png",
  "assets/icons/favicon.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(VERSION).then((cache) => cache.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== VERSION).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

function openAssetDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open("lian-chat", 2);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains("state")) db.createObjectStore("state");
      if (!db.objectStoreNames.contains("assets")) db.createObjectStore("assets");
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
    req.onblocked = () => reject(new Error("sandbox db blocked"));
  });
}

async function readAsset(id) {
  const db = await openAssetDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction("assets", "readonly");
    const req = tx.objectStore("assets").get(id);
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => reject(req.error);
  });
}

async function serveSandboxAsset(url) {
  const marker = url.pathname.lastIndexOf(SANDBOX_MARK);
  const id = marker >= 0 ? decodeURIComponent(url.pathname.slice(marker + SANDBOX_MARK.length)) : "";
  if (!id) return new Response("Missing asset id", { status: 400 });
  try {
    const asset = await readAsset(id);
    if (!asset) return new Response("Sandbox asset not found", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } });
    const headers = new Headers({
      "Content-Type": asset.mime || "application/octet-stream",
      "Content-Security-Policy":
        "default-src 'none'; style-src 'unsafe-inline'; img-src data:; script-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'self'",
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "no-store",
      "Content-Disposition": "inline",
    });
    return new Response(asset.content, { status: 200, headers });
  } catch {
    return new Response("Sandbox unavailable", { status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }
}

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((windows) => {
      for (const client of windows) {
        if ("focus" in client) return client.focus();
      }
      return self.clients.openWindow("./");
    }),
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== location.origin) return;

  if (url.pathname.includes(SANDBOX_MARK)) {
    event.respondWith(serveSandboxAsset(url));
    return;
  }

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(VERSION).then((cache) => cache.put("index.html", copy)).catch(() => {});
          return response;
        })
        .catch(() => caches.match("index.html").then((hit) => hit || caches.match("./"))),
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((hit) => {
      if (hit) {
        fetch(request)
          .then((response) => {
            if (response.ok) caches.open(VERSION).then((cache) => cache.put(request, response)).catch(() => {});
          })
          .catch(() => {});
        return hit;
      }
      return fetch(request).then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(VERSION).then((cache) => cache.put(request, copy)).catch(() => {});
        }
        return response;
      });
    }),
  );
});
