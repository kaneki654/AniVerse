// Watch parties: everyone on the same episode, at the same moment, through the
// server's /ws/party/{code} room. Whoever plays, pauses, seeks or changes
// episode sends the new state; the others follow it. Times are worked out
// against the server's clock, never the devices', so a slow phone clock does
// not put anyone out of step. The same rooms serve the app.
import { h, sprite, toast } from "./px.js";
import { auth } from "./api.js";
import { sfx } from "./sfx.js";

const NAME = "av.party.name";
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O or 1/I to misread

export const newPartyCode = () => Array.from(crypto.getRandomValues(new Uint8Array(6)), (b) => CODE_CHARS[b % CODE_CHARS.length]).join("");
export const validCode = (c) => /^[A-Z0-9]{4,8}$/.test(String(c || "").toUpperCase());

function myName() {
  const u = auth.user;
  if (u && (u.display_name || u.username)) return u.display_name || u.username;
  try {
    let n = localStorage.getItem(NAME);
    if (!n) { n = `Guest-${newPartyCode().slice(0, 4)}`; localStorage.setItem(NAME, n); }
    return n;
  } catch { return "Guest"; }
}

/**
 * Joins room `code` and draws the party bar after `mount`.
 *   getState() -> {anime, ep, category, playing, t}   what this viewer is doing
 *   applyState(state, t)                               follow someone else; t is where playback should be now
 * Returns {send(), sendEpisode(ep), leave()}; send() after anything the viewer did.
 */
export function startParty({ code, mount, getState, applyState }) {
  code = code.toUpperCase();
  let ws = null, offset = 0, closed = false, retry = 0, pingTimer = 0, me = myName();
  let members = [];

  // --- the bar ----------------------------------------------------------------------
  const status = h("span.muted", null, "Connecting…");
  const who = h("span.members");
  const log = h("div.party-chat", { "aria-live": "polite" });
  const input = h("input.px-input", { type: "text", maxlength: "200", placeholder: "Say something", "aria-label": "Party chat message" });
  const invite = `${location.origin}${location.pathname}?party=${code}`;
  const bar = h("section.party-bar.px-box", { "aria-label": "Watch party" },
    sprite("party", 2),
    h("span.code", { title: "Party code" }, code),
    who,
    status,
    h("button.px-btn.px-box.bevel.small", {
      type: "button",
      onclick: async () => {
        try { await navigator.clipboard.writeText(invite); toast("Invite link copied. Anyone with it joins this party."); }
        catch { prompt("Copy this invite link:", invite); }
      },
    }, "Copy invite"),
    h("button.px-btn.dark.px-box.bevel.small", { type: "button", onclick: () => leave(true) }, "Leave"),
    log,
    h("form.party-send", {
      onsubmit: (e) => {
        e.preventDefault();
        const text = input.value.trim();
        if (!text || !ws || ws.readyState !== 1) return;
        ws.send(JSON.stringify({ type: "chat", text }));
        input.value = "";
      },
    }, input, h("button.px-btn.px-box.bevel.small", { type: "submit" }, "Send")));
  mount.after(bar);

  const line = (...parts) => {
    log.append(h("div", null, parts));
    while (log.children.length > 60) log.firstChild.remove();
    log.scrollTop = log.scrollHeight;
  };
  const sys = (text) => line(h("span.sys", null, text));
  const drawMembers = () => {
    who.textContent = members.length ? `${members.length} watching: ${members.join(", ")}` : "";
  };

  // --- the connection ---------------------------------------------------------------------
  const serverNow = () => Date.now() / 1000 + offset;
  const where = (s) => s.t + (s.playing ? Math.max(0, serverNow() - s.at) : 0);

  function connect() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    ws = new WebSocket(`${proto}://${location.host}/ws/party/${code}?name=${encodeURIComponent(me)}`);
    ws.onopen = () => {
      retry = 0;
      status.textContent = "";
      clearInterval(pingTimer);
      // Tunnels drop quiet sockets; a ping now and then keeps the room open.
      pingTimer = setInterval(() => { if (ws.readyState === 1) ws.send('{"type":"ping"}'); }, 25000);
    };
    ws.onmessage = (ev) => {
      let m;
      try { m = JSON.parse(ev.data); } catch { return; }
      if (typeof m.now === "number") offset = m.now - Date.now() / 1000;
      if (m.type === "hello") {
        me = m.you || me;
        members = m.members || [];
        drawMembers();
        sys(`You joined party ${code} as ${me}.`);
        if (m.state) applyState(m.state, where(m.state));
        else send(); // first in: what you are watching is the party's episode
      } else if (m.type === "members") {
        members = m.members || [];
        drawMembers();
        if (m.joined) {
          sys(`${m.joined} joined.`);
          sfx("select");
          // Bring the newcomer to the exact spot; a paused room's saved state is already exact.
          const s = getState();
          if (s && s.playing) send(s);
        }
        if (m.left) sys(`${m.left} left.`);
      } else if (m.type === "state" && m.state) {
        applyState(m.state, where(m.state));
      } else if (m.type === "chat") {
        line(h("b", null, `${m.name}: `), m.text);
        if (m.name !== me) sfx("click");
      }
    };
    ws.onclose = (ev) => {
      clearInterval(pingTimer);
      if (closed) return;
      if (ev.code === 4413) { status.textContent = "This party is full."; return; }
      if (ev.code === 4400 || ev.code === 4429) { status.textContent = "Can't join this party."; return; }
      status.textContent = "Reconnecting…";
      setTimeout(connect, Math.min(15000, 1000 * 2 ** retry++));
    };
  }

  function send(state = getState()) {
    if (!state || !ws || ws.readyState !== 1) return;
    ws.send(JSON.stringify({ type: "state", ...state }));
  }

  function leave(reload) {
    closed = true;
    clearInterval(pingTimer);
    ws?.close();
    bar.remove();
    if (reload) location.href = location.pathname;
  }

  connect();
  return {
    /** After anything the viewer did; `patch` overrides parts of getState(). */
    send: (patch) => send(patch ? { ...getState(), ...patch } : getState()),
    /**
     * Moving to another episode: tell the room, then go quiet. Without the
     * silence this page could answer someone joining the new episode with the
     * old one, and the whole room would bounce back.
     */
    sendEpisode(ep) {
      send({ ...getState(), ep, t: 0, playing: true });
      leave(false); // anything sent before close() still goes out first
    },
    leave,
    get code() { return code; },
  };
}
