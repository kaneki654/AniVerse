// Sign in, create an account, or see the one signed in -- the app's account
// screen. Accounts are shared with the app, so history follows you between them.
// Also here: your level, rank and achievements (from watch history, so they
// count without an account too) and the AniList / MyAnimeList connections.
import { h, sprite, clear, toast, SPRITES } from "./px.js";
import { api, auth, history } from "./api.js";
import { BADGES, stats, level, unlocked } from "./achievements.js";
import { sfx } from "./sfx.js";
import { initShell, sectionHead } from "./ui.js";
import { push } from "./push.js";

initShell();
const root = document.getElementById("account");
root.classList.remove("auth");
let mode = "login";

function render() {
  clear(root);
  const user = auth.user;
  if (user) return profile(user);
  const narrow = h("div.auth");
  root.append(narrow, progress(null));
  signInForm(narrow);
}

function signInForm(root) {
  const err = h("p.form-error.px-box", { role: "alert", hidden: true });
  const username = h("input.px-input.px-box.flat#u", { name: "username", autocomplete: "username", required: true, minlength: 3, maxlength: 24 });
  const display = h("input.px-input.px-box.flat#d", { name: "display", autocomplete: "nickname", maxlength: 40 });
  const password = h("input.px-input.px-box.flat#p", { name: "password", type: "password", required: true, minlength: 6, autocomplete: mode === "login" ? "current-password" : "new-password" });
  const eye = h("button.icon-btn", { type: "button", "aria-label": "Show password", onclick: () => {
    const show = password.type === "password";
    password.type = show ? "text" : "password";
    clear(eye).append(sprite(show ? "eyeOff" : "eye", 2));
    eye.setAttribute("aria-label", show ? "Hide password" : "Show password");
  } }, sprite("eye", 2));
  const submit = h("button.px-btn.px-box.bevel.wide", { type: "submit" }, sprite(mode === "login" ? "lock" : "check", 1.6), mode === "login" ? "Sign in" : "Create account");

  const form = h("form.card.px-box.rivets", { novalidate: true },
    h("div.tabs", null,
      h(`button.px-btn.px-box.bevel.small${mode === "login" ? "" : ".dark"}`, { type: "button", onclick: () => { mode = "login"; render(); } }, "Sign in"),
      h(`button.px-btn.px-box.bevel.small${mode === "register" ? "" : ".dark"}`, { type: "button", onclick: () => { mode = "register"; render(); } }, "New account")),
    err,
    h("div.field", null, h("label", { for: "u" }, "Username"), username),
    mode === "register" ? h("div.field", null, h("label", { for: "d" }, "Display name (optional)"), display) : null,
    h("div.field", null, h("label", { for: "p" }, "Password"), h("div.pw", null, password, eye)),
    submit,
    h("p.muted", { style: { margin: "16px 0 0", fontSize: "14px" } },
      "The same account works in the AniVerse Pixel app, and your watch history syncs between them."));

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    err.hidden = true;
    const u = username.value.trim();
    if (u.length < 3) return fail("Username must be at least 3 characters.");
    if (password.value.length < 6) return fail("Password must be at least 6 characters.");
    submit.disabled = true;
    try {
      if (mode === "login") await auth.login(u, password.value);
      else await auth.register(u, password.value, display.value.trim());
      const back = new URLSearchParams(location.search).get("next");
      if (back && back.startsWith("/") && !back.startsWith("//")) location.href = back;
      else render();
    } catch (ex) {
      fail(ex.message);
      submit.disabled = false;
    }
  });
  function fail(msg) { err.textContent = msg; err.hidden = false; }
  const google = h("div.google-signin");
  root.append(h("h1.page-title", null, mode === "login" ? "Sign in" : "Create account"), form, google);
  googleButton(google);
  username.focus();
}

/** "Sign in with Google", when the server has a Google client ID set up. */
async function googleButton(el) {
  const cfg = await api.authConfig();
  const clientId = cfg.google && cfg.google.enabled && cfg.google.server_client_id;
  if (!clientId || !el.isConnected) return;
  await new Promise((ok, no) => {
    if (window.google?.accounts?.id) return ok();
    const s = h("script", { src: "https://accounts.google.com/gsi/client", async: true });
    s.onload = ok;
    s.onerror = no;
    document.head.append(s);
  }).catch(() => null);
  const gid = window.google?.accounts?.id;
  if (!gid || !el.isConnected) return;
  gid.initialize({
    client_id: clientId,
    callback: async (resp) => {
      try { await auth.google(resp.credential); render(); } catch (ex) { toast(ex.message); }
    },
  });
  el.append(h("p.muted.or", null, "or"));
  const slot = h("div");
  el.append(slot);
  gid.renderButton(slot, { theme: "filled_black", size: "large", shape: "rectangular", text: "signin_with", width: 300 });
}

// --- level, stats, achievements -------------------------------------------------------------

function progress(user) {
  const s = stats();
  const lv = level(s);
  const got = new Set(unlocked(s));
  const name = (user && (user.display_name || user.username)) || "Player";
  const toNext = lv.level >= 99 ? 0 : Math.max(0, 40 * lv.level ** 2 - lv.xp);
  return h("section.section", null,
    h("div.level-card.px-box.rivets", null,
      h("div.avatar-frame", { dataset: { frame: lv.frame }, title: `${lv.frame[0].toUpperCase()}${lv.frame.slice(1)} frame` },
        name.trim().charAt(0).toUpperCase(), h("span.lv", null, `LV ${lv.level}`)),
      h("div.who", null,
        h("b", null, name),
        h("span.rank", null, lv.rank),
        h("div.px-bar", { role: "progressbar", "aria-label": "Progress to the next level", "aria-valuemin": "0", "aria-valuemax": "100", "aria-valuenow": String(Math.round(lv.progress * 100)) },
          h("i", null, h("b", { style: { width: `${lv.progress * 100}%` } }))),
        h("span.muted", null, lv.level >= 99 ? `${lv.xp} XP · max level` : `${lv.xp} XP · ${toNext} to level ${lv.level + 1}`))),
    h("div.stat-row", null,
      stat(s.finished, "Episodes finished"), stat(s.anime, "Anime"), stat(s.streak, "Day streak"), stat(`${Math.floor(s.hours)}h`, "Watched")),
    h("button.px-btn.dark.px-box.bevel.small", { type: "button", style: { marginBottom: "18px" }, onclick: () => shareCard(name) },
      sprite("trophy", 1.4), "Share card"),
    sectionHead(`Achievements · ${got.size}/${BADGES.length}`),
    h("div.badges", null, BADGES.map((b) => h(`div.badge.px-box${got.has(b.id) ? "" : ".locked"}`, { title: got.has(b.id) ? "Unlocked" : "Locked" },
      sprite(b.sprite, 3), h("b", null, b.name), h("span", null, b.text)))),
    user ? null : h("p.muted", { style: { marginTop: "14px" } }, "Progress counts on this browser. Sign in to keep it with your account and the app."));
}
const stat = (value, label) => h("div.stat.px-box", null, h("b", null, String(value)), h("small", null, label));

// --- the share card: the profile as a picture, drawn in the palette's colours --------------
// The same frame colours as the app's Achievements.frameColor.
const FRAME = { bronze: "#b06a2c", silver: "#c9d2de", gold: null, blood: null, legend: "#b48cff" };

async function shareCard(name) {
  const s = stats(), lv = level(s), got = BADGES.filter((b) => unlocked(s).includes(b.id));
  const css = getComputedStyle(document.documentElement);
  const v = (k, d) => css.getPropertyValue(k).trim() || d;
  const W = 600, H = 380, cv = document.createElement("canvas");
  cv.width = W * 2; cv.height = H * 2;
  const g = cv.getContext("2d");
  g.scale(2, 2);
  g.imageSmoothingEnabled = false;
  await document.fonts.load('16px "PressStart2P"').catch(() => {});
  const font = (px) => `${px}px "PressStart2P", monospace`;
  const frame = FRAME[lv.frame] || (lv.frame === "gold" ? v("--gold", "#e8b23a") : v("--blood-light", "#ff4d57"));
  g.fillStyle = v("--ink", "#0d0709"); g.fillRect(0, 0, W, H);
  g.fillStyle = frame; [[0, 0, W, 8], [0, H - 8, W, 8], [0, 0, 8, H], [W - 8, 0, 8, H]].forEach((r) => g.fillRect(...r));
  g.textAlign = "center";
  g.fillStyle = v("--blood", "#d10a1a"); g.font = font(22); g.fillText("ANIVERSE", W / 2, 56);
  g.fillStyle = v("--bone", "#f2e8d5"); g.font = font(16); g.fillText(name.toUpperCase().slice(0, 22), W / 2, 100);
  g.fillStyle = v("--gold", "#e8b23a"); g.font = font(12); g.fillText(`LV ${lv.level} · ${lv.rank.toUpperCase()}`, W / 2, 130);
  g.fillStyle = v("--panel", "#1b1114"); g.fillRect(150, 146, 300, 12);
  g.fillStyle = v("--blood", "#d10a1a"); g.fillRect(150, 146, 300 * lv.progress, 12);
  [[s.finished, "EPISODES"], [s.anime, "ANIME"], [`${Math.floor(s.hours)}H`, "WATCHED"], [s.streak, "STREAK"]].forEach(([n, label], i) => {
    const x = 90 + i * 140;
    g.fillStyle = v("--bone", "#f2e8d5"); g.font = font(16); g.fillText(String(n), x, 200);
    g.fillStyle = v("--ash", "#8a7f7a"); g.font = font(8); g.fillText(label, x, 220);
  });
  // The badges earned, as their sprites, centred in a row (two rows if many).
  const cell = 3, per = Math.min(got.length, 9);
  got.forEach((b, i) => {
    const rows = SPRITES[b.sprite] || [], row = Math.floor(i / 9), col = i % 9, inRow = row ? got.length - 9 : per;
    const x0 = W / 2 - (inRow * 48) / 2 + col * 48 + 8, y0 = 250 + row * 44;
    g.fillStyle = v("--gold", "#e8b23a");
    rows.forEach((line, y) => [...line].forEach((ch, x) => { if (ch !== ".") g.fillRect(x0 + x * cell, y0 + y * cell, cell, cell); }));
  });
  g.fillStyle = v("--ash", "#8a7f7a"); g.font = font(8); g.fillText(`${got.length}/${BADGES.length} BADGES`, W / 2, H - 22);

  const blob = await new Promise((r) => cv.toBlob(r, "image/png"));
  if (!blob) return;
  const file = new File([blob], "aniverse-card.png", { type: "image/png" });
  const text = `Level ${lv.level} ${lv.rank} on AniVerse`;
  if (navigator.canShare?.({ files: [file] })) {
    navigator.share({ files: [file], text }).catch(() => {});
  } else {
    const a = h("a", { href: URL.createObjectURL(blob), download: file.name });
    document.body.append(a); a.click(); a.remove();
    toast("Card saved as aniverse-card.png.");
  }
}

// --- AniList / MyAnimeList ---------------------------------------------------------------------

async function tracking(el) {
  const [cfg, status] = await Promise.all([
    api.trackingConfig(),
    auth.call("GET", "/api/tracking").catch(() => ({})),
  ]);
  if (!el.isConnected) return;
  clear(el).append(sectionHead("Tracking"),
    h("p.muted", { style: { margin: "0 0 14px" } }, "Episodes you finish here or in the app update your list there. Progress only ever moves forward."),
    service("anilist", "AniList", cfg.anilist, status.anilist, el),
    service("mal", "MyAnimeList", cfg.mal, status.mal, el));
}

function service(id, name, cfg, st, el) {
  const row = h("div.setting.px-box");
  const info = h("div", null, h("b", null, name),
    h("span", null, st && st.connected ? `Connected${st.account ? ` as ${st.account}` : ""}.` : cfg && cfg.enabled ? "Not connected." : "Not set up on this server yet."));
  const buttons = h("div.row", { style: { display: "flex", gap: "8px", flexWrap: "wrap" } });
  row.append(info, buttons);
  if (st && st.connected) {
    buttons.append(h("button.px-btn.dark.px-box.bevel.small", {
      type: "button",
      onclick: async () => { await auth.call("DELETE", `/api/tracking/${id}`).catch(() => null); tracking(el); },
    }, "Disconnect"));
  } else if (cfg && cfg.enabled) {
    buttons.append(h("button.px-btn.px-box.bevel.small", {
      type: "button",
      onclick: async () => {
        if (id === "mal") {
          try { location.href = (await auth.call("POST", "/api/tracking/mal/start")).url; } catch (ex) { toast(ex.message); }
          return;
        }
        // AniList shows a token on its own page; it is pasted back here.
        window.open(cfg.authorize_url, "_blank", "noopener");
        const input = h("input.px-input.px-box.flat", { type: "text", placeholder: "Paste the token AniList shows", "aria-label": "AniList token", autocomplete: "off" });
        const err = h("p.form-error.px-box", { role: "alert", hidden: true });
        const save = h("button.px-btn.px-box.bevel.small", { type: "submit" }, "Connect");
        row.after(h("form.card.px-box", {
          style: { marginTop: "10px" },
          onsubmit: async (e) => {
            e.preventDefault();
            save.disabled = true;
            try {
              await auth.call("POST", "/api/tracking/anilist", { token: input.value.trim() });
              sfx("achieve");
              tracking(el);
            } catch (ex) { err.textContent = ex.message; err.hidden = false; save.disabled = false; }
          },
        }, h("p.muted", { style: { margin: "0 0 10px", fontSize: "14px" } }, "Sign in on the AniList page that just opened, approve AniVerse, then copy the long token it shows into this box."),
        err, h("div", { style: { display: "flex", gap: "8px" } }, input, save)));
        input.focus();
      },
    }, "Connect"));
  }
  return row;
}

function profile(user) {
  const count = history.latestPerAnime().length;
  const track = h("section.section");
  root.append(h("h1.page-title", null, "Account"),
    progress(user),
    track,
    h("section.section", null,
      h("p.muted", { style: { margin: "0 0 14px" } }, `${user.username ? `@${user.username} · ` : ""}${count} anime in your history, synced with the app.`),
      h("div.actions", null,
        h("a.px-btn.dark.px-box.bevel", { href: "/history" }, sprite("clock", 1.6), "History"),
        h("a.px-btn.dark.px-box.bevel", { href: "/settings" }, sprite("gear", 1.6), "Settings"),
        h("button.px-btn.px-box.bevel", { type: "button", onclick: async () => { await history.sync(); await auth.logout(); push.sync(); render(); } }, sprite("logout", 1.6), "Sign out"))));
  tracking(track);
}

auth.onChange(() => render());
render();
