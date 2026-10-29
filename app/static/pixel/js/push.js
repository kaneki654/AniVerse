// New-episode alerts that arrive with the website closed: a push subscription
// through the service worker (sw.js shows them), sent to the server with My
// List, which it checks every few hours (app/webpush.py). Signed in, the server
// uses the account's list; otherwise the list is sent along whenever it changes.
import { auth } from "./api.js";
import { watchlist } from "./watchlist.js";

const supported = () => "serviceWorker" in navigator && "PushManager" in window && "Notification" in window && isSecureContext;

function keyBytes(b64) {
  const raw = atob((b64 + "=".repeat((4 - (b64.length % 4)) % 4)).replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

async function registration() {
  const reg = await navigator.serviceWorker.register("/sw.js");
  await navigator.serviceWorker.ready;
  return reg;
}

const watchBody = () => watchlist.all().map((e) => ({ anime_id: e.anime_id, seen_episode: e.seen_episode || 0 }));

async function post(path, body) {
  const headers = { "Content-Type": "application/json" };
  if (auth.token) headers.Authorization = `Bearer ${auth.token}`;
  const r = await fetch(path, { method: "POST", headers, body: JSON.stringify(body) });
  return r.ok ? r.json().catch(() => ({})) : null;
}

export const push = {
  supported,

  /** Subscribe (asking for notification permission first). Resolves true when on. */
  async enable() {
    if (!supported()) return false;
    if ((await Notification.requestPermission()) !== "granted") return false;
    try {
      const reg = await registration();
      const { publicKey } = await (await fetch("/api/push/key")).json();
      const sub = (await reg.pushManager.getSubscription())
        || (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(publicKey) }));
      return !!(await post("/api/push/subscribe", { subscription: sub.toJSON(), watch: watchBody() }));
    } catch {
      return false; // push service unreachable, or the browser said no
    }
  },

  async disable() {
    if (!supported()) return;
    try {
      const reg = await navigator.serviceWorker.getRegistration();
      const sub = await reg?.pushManager.getSubscription();
      if (sub) {
        await post("/api/push/unsubscribe", { endpoint: sub.endpoint });
        await sub.unsubscribe();
      }
    } catch { /* nothing to undo */ }
  },

  /** Keep the server's copy of My List current (signed out only needs it). */
  async sync() {
    if (!supported() || Notification.permission !== "granted") return;
    try {
      const reg = await navigator.serviceWorker.getRegistration();
      const sub = await reg?.pushManager.getSubscription();
      if (sub) await post("/api/push/subscribe", { subscription: sub.toJSON(), watch: watchBody() });
    } catch { /* next change tries again */ }
  },

  /** A test notification to this browser. */
  async test() {
    try {
      const reg = await navigator.serviceWorker.getRegistration();
      const sub = await reg?.pushManager.getSubscription();
      if (!sub) return false;
      const r = await post("/api/push/test", { endpoint: sub.endpoint });
      return !!(r && r.ok);
    } catch {
      return false;
    }
  },
};

let syncTimer = 0;
watchlist.onChange(() => {
  clearTimeout(syncTimer);
  syncTimer = setTimeout(() => push.sync(), 4000);
});
