// AniVerse Pixel service worker: makes the website installable and keeps its
// look (fonts, styles, scripts, sprites) and an offline page on the device.
// Streams, the API and watch-party sockets always go to the network.

const SHELL = "av-shell-v1";
const OFFLINE = "/offline";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(SHELL).then((c) => c.addAll([
      OFFLINE,
      "/static/pixel/pixel.css",
      "/static/pixel/fonts/PressStart2P-latin.woff2",
      "/static/pixel/fonts/DotGothic16-latin.woff2",
      "/static/pixel/img/logo.png",
    ])).then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== SHELL).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

const NETWORK_ONLY = /^\/(api|proxy|ws|app)\//;

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== location.origin || NETWORK_ONLY.test(url.pathname)) return;

  // Fonts and images never change under the same name: cache first.
  if (/^\/static\/pixel\/(fonts|img)\//.test(url.pathname)) {
    event.respondWith(caches.match(req).then((hit) => hit || fetch(req).then((res) => {
      if (res.ok) caches.open(SHELL).then((c) => c.put(req, res.clone()));
      return res;
    })));
    return;
  }

  // Scripts, styles and pages: network first so updates arrive at once,
  // the cached copy when offline, and the offline page for a page never seen.
  event.respondWith(fetch(req).then((res) => {
    if (res.ok && (url.pathname.startsWith("/static/pixel/") || req.mode === "navigate")) {
      const copy = res.clone();
      caches.open(SHELL).then((c) => c.put(req, copy));
    }
    return res;
  }).catch(async () => (await caches.match(req)) || (req.mode === "navigate" ? caches.match(OFFLINE) : Response.error())));
});
