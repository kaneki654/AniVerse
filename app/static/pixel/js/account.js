// Sign in, create an account, or see the one signed in -- the app's account
// screen. Accounts are shared with the app, so history follows you between them.
import { h, sprite, clear } from "./px.js";
import { auth, history } from "./api.js";
import { initShell } from "./ui.js";

initShell();
const root = document.getElementById("account");
let mode = "login";

function render() {
  clear(root);
  const user = auth.user;
  if (user) return profile(user);
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

  const form = h("form.card.px-box", { novalidate: true },
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
  root.append(h("h1.page-title", null, mode === "login" ? "Sign in" : "Create account"), form);
  username.focus();
}

function profile(user) {
  const name = user.display_name || user.username || "Player";
  const count = history.latestPerAnime().length;
  root.append(h("h1.page-title", null, "Account"),
    h("div.card.px-box", null,
      h("div.profile", null,
        h("div.avatar-big.px-box", null, name.trim().charAt(0).toUpperCase()),
        h("div.who", null, h("b", null, name), user.username ? h("span.muted", null, `@${user.username}`) : null)),
      h("p.muted", { style: { margin: "0 0 18px" } }, `${count} anime in your history, synced with the app.`),
      h("div.actions", null,
        h("a.px-btn.dark.px-box.bevel", { href: "/history" }, sprite("clock", 1.6), "History"),
        h("button.px-btn.px-box.bevel", { type: "button", onclick: async () => { await history.sync(); await auth.logout(); render(); } }, sprite("logout", 1.6), "Sign out"))));
}

auth.onChange(() => render());
render();
