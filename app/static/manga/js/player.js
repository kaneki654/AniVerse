// The pixel video player's face: HUD, seek bar, captions, the settings menu and
// the overlays (katana loader, blood-orb buffering, the boss fight when nothing
// plays). Playback logic lives in watch.js; this only draws and reports what
// the viewer does -- the app's player_controls.dart and buffer_overlay.dart.
import { h, sprite, clear, katana, orb, fmtTime, pxRand, splat, shake } from "./px.js";
import { sfx } from "./sfx.js";

export const pref = {
  get: (k, d) => { try { const v = localStorage.getItem(`av.player.${k}`); return v === null ? d : JSON.parse(v); } catch { return d; } },
  set: (k, v) => { try { localStorage.setItem(`av.player.${k}`, JSON.stringify(v)); } catch { /* storage off */ } },
};

export function createPlayer(host, handlers) {
  const video = h("video", { playsinline: true, preload: "auto" });
  video.volume = pref.get("volume", 1);
  video.muted = pref.get("muted", false);

  const capText = h("span");
  const captions = h("div.captions", { "aria-live": "off" }, capText);
  captions.hidden = true;

  // --- HUD -----------------------------------------------------------------------
  const titleEl = h("div.t");
  const ccBtn = h("button.toggle.px-box", { type: "button", hidden: true, onclick: () => handlers.onToggleCaptions() }, "CC");
  const audioBtn = h("button.toggle.px-box", { type: "button", onclick: () => handlers.onToggleCategory() }, sprite("swap", 1.3), h("span", null, "SUB"));
  const top = h("div.hud-top", null,
    h("a.icon-btn", { href: handlers.backHref, "aria-label": "Back to details", title: "Back" }, sprite("back", 2.2)),
    titleEl, ccBtn, audioBtn);

  const playIcon = h("span", { style: { display: "grid" } }, sprite("play", 2.8));
  const bigPlay = h("button.big-play.px-box", { type: "button", "aria-label": "Play", onclick: () => handlers.onTogglePlay() }, playIcon);
  const center = h("div.hud-center", null,
    h("button.skip10.px-box", { type: "button", "aria-label": "Back 10 seconds", onclick: () => seekBy(-10) }, sprite("rewind", 2), "10"),
    bigPlay,
    h("button.skip10.px-box", { type: "button", "aria-label": "Forward 10 seconds", onclick: () => seekBy(10) }, sprite("forward", 2), "10"));

  const buf = h("i.buf"), done = h("i.done"), marks = h("div.marks");
  const handle = h("span.handle"); // a brush dab, in manga.css
  const tip = h("span.tip", { hidden: true });
  const seek = h("div.seek", { role: "slider", tabindex: "0", "aria-label": "Seek", "aria-valuemin": "0" },
    h("div.track", null, buf, marks, done), handle, tip);
  const timeEl = h("span.time");
  const volIcon = h("span", { style: { display: "grid" } });
  const volRange = h("input", { type: "range", min: "0", max: "1", step: "0.05", "aria-label": "Volume" });
  const nextBtn = h("button.icon-btn", { type: "button", hidden: true, "aria-label": "Next episode", title: "Next episode (N)", onclick: () => handlers.onNext() }, sprite("skipNext", 2));
  const fsIcon = h("span", { style: { display: "grid" } }, sprite("fullscreen", 2));
  const menuBtn = h("button.icon-btn", { type: "button", "aria-label": "Settings", title: "Quality, speed, subtitles", "aria-haspopup": "menu", "aria-expanded": "false", onclick: () => toggleMenu() }, sprite("gear", 2));
  const pipBtn = document.pictureInPictureEnabled
    ? h("button.icon-btn", { type: "button", "aria-label": "Picture in picture", title: "Picture in picture (P)", onclick: () => togglePip() }, sprite("pip", 2))
    : null;
  const bottom = h("div.hud-bottom", null, seek,
    h("div.hud-row", null,
      timeEl,
      h("span.grow"),
      h("span.vol", null,
        h("button.icon-btn", { type: "button", "aria-label": "Mute", title: "Mute (M)", onclick: () => setMuted(!video.muted) }, volIcon),
        volRange),
      nextBtn,
      handlers.menu ? menuBtn : null,
      pipBtn,
      h("button.icon-btn", { type: "button", "aria-label": "Fullscreen", title: "Fullscreen (F)", onclick: toggleFullscreen }, fsIcon)));
  const hud = h("div.hud", null, top, center, bottom);
  const skipFloat = h("div.skip-float", { hidden: true });
  const stage = h("div.stage", { hidden: true });
  const bufStage = h("div.stage.clear", { hidden: true });

  clear(host).append(video, captions, hud, skipFloat, bufStage, stage);

  // --- state shown -----------------------------------------------------------------
  let duration = 0, intro = null, outro = null, recap = null, dragging = null;

  const syncVolume = () => {
    clear(volIcon).append(sprite(video.muted || video.volume === 0 ? "mute" : "volume", 2));
    volRange.value = String(video.muted ? 0 : video.volume);
  };
  const setMuted = (m) => { video.muted = m; if (!m && video.volume === 0) video.volume = 0.5; pref.set("muted", m); syncVolume(); };
  volRange.addEventListener("input", () => {
    video.volume = Number(volRange.value);
    video.muted = video.volume === 0;
    pref.set("volume", video.volume);
    pref.set("muted", video.muted);
    syncVolume();
  });
  syncVolume();

  const syncPlay = () => {
    const playing = !video.paused && !video.ended;
    clear(playIcon).append(sprite(playing ? "pause" : "play", 2.8));
    bigPlay.setAttribute("aria-label", playing ? "Pause" : "Play");
  };
  video.addEventListener("play", syncPlay);
  video.addEventListener("pause", syncPlay);
  video.addEventListener("ended", syncPlay);

  function seekBy(s) {
    if (!Number.isFinite(video.duration)) return;
    video.currentTime = Math.min(Math.max(0, video.currentTime + s), Math.max(0, video.duration - 0.5));
    poke();
  }

  function paintTime() {
    duration = Number.isFinite(video.duration) ? video.duration : 0;
    const t = dragging ?? video.currentTime;
    const f = duration ? Math.min(1, t / duration) : 0;
    let end = 0;
    for (let i = 0; i < video.buffered.length; i++) {
      if (video.buffered.start(i) <= video.currentTime + 1) end = Math.max(end, video.buffered.end(i));
    }
    done.style.width = `calc(${f * 100}% - ${f * 4}px)`;
    buf.style.width = `calc(${(duration ? Math.min(1, end / duration) : 0) * 100}% - 4px)`;
    handle.style.left = `${f * 100}%`;
    clear(timeEl).append(fmtTime(t), h("span.muted", null, ` / ${fmtTime(duration)}`));
    seek.setAttribute("aria-valuenow", String(Math.floor(t)));
    seek.setAttribute("aria-valuemax", String(Math.floor(duration)));
    seek.setAttribute("aria-valuetext", `${fmtTime(t)} of ${fmtTime(duration)}`);
    // Skip intro / outro while inside either range.
    const inRange = (r) => r && t >= r.start && t < r.end - 1;
    const range = inRange(recap) ? ["Skip recap", recap] : inRange(intro) ? ["Skip intro", intro] : inRange(outro) ? ["Skip outro", outro] : null;
    if (range) {
      if (skipFloat._for !== range[0]) {
        skipFloat._for = range[0];
        clear(skipFloat).append(h("button.px-btn.bone.px-box.bevel.small", { type: "button", onclick: () => { sfx("skip"); video.currentTime = range[1].end; poke(); } }, sprite("forward", 1.4), range[0]));
      }
      skipFloat.hidden = false;
    } else {
      skipFloat.hidden = true;
      skipFloat._for = null;
    }
  }
  video.addEventListener("timeupdate", paintTime);
  video.addEventListener("durationchange", () => { paintTime(); paintMarks(); });
  video.addEventListener("progress", paintTime);

  function paintMarks() {
    clear(marks);
    if (!duration) return;
    for (const r of [intro, outro]) {
      if (!r) continue;
      const i = h("i");
      i.style.left = `calc(${(r.start / duration) * 100}% + 2px)`;
      i.style.width = `${((r.end - r.start) / duration) * 100}%`;
      marks.append(i);
    }
  }

  // Seeking by drag or tap anywhere on the bar.
  const fracAt = (x) => { const r = seek.getBoundingClientRect(); return Math.min(1, Math.max(0, (x - r.left) / r.width)); };
  seek.addEventListener("pointerdown", (e) => {
    if (!duration) return;
    seek.setPointerCapture(e.pointerId);
    dragging = fracAt(e.clientX) * duration;
    paintTime();
  });
  seek.addEventListener("pointermove", (e) => {
    if (!duration) return;
    const f = fracAt(e.clientX);
    tip.hidden = false;
    tip.textContent = fmtTime(f * duration);
    tip.style.left = `${f * 100}%`;
    if (dragging !== null) { dragging = f * duration; paintTime(); }
    poke();
  });
  const endDrag = () => {
    if (dragging !== null) { video.currentTime = dragging; dragging = null; paintTime(); }
  };
  seek.addEventListener("pointerup", endDrag);
  seek.addEventListener("pointercancel", () => { dragging = null; });
  seek.addEventListener("pointerleave", () => { tip.hidden = true; });
  seek.addEventListener("keydown", (e) => {
    if (e.key === "ArrowLeft") { seekBy(-5); e.preventDefault(); e.stopPropagation(); }
    if (e.key === "ArrowRight") { seekBy(5); e.preventDefault(); e.stopPropagation(); }
  });

  // --- HUD visibility: shown on activity, hidden 3s later while playing --------------
  let hideTimer = 0, hudOn = true;
  const setHud = (on) => {
    hudOn = on;
    hud.classList.toggle("off", !on);
    host.classList.toggle("hide-cursor", !on);
    captions.classList.toggle("lifted", on);
    skipFloat.style.bottom = on ? "" : "20px";
  };
  function poke() {
    setHud(true);
    clearTimeout(hideTimer);
    hideTimer = setTimeout(function hide() {
      // A seek usually lands mid-buffer, when the video reports paused-ish
      // states; still buffering is not paused, so look again shortly.
      if (video.readyState < 3 && !video.paused) { hideTimer = setTimeout(hide, 1000); return; }
      const busy = top.matches(":hover") || bottom.matches(":hover") || bottom.contains(document.activeElement) || !!menuEl;
      if (!video.paused && !busy) setHud(false);
      else hideTimer = setTimeout(hide, 2000);
    }, 3000);
  }
  host.addEventListener("pointermove", (e) => { if (e.pointerType === "mouse") poke(); });
  host.addEventListener("pointerleave", () => { if (!video.paused) { clearTimeout(hideTimer); hideTimer = setTimeout(() => setHud(false), 800); } });
  video.addEventListener("play", poke);
  video.addEventListener("pause", () => { clearTimeout(hideTimer); setHud(true); });

  // Mouse: click plays/pauses, double-click goes fullscreen. Touch: a tap shows
  // or hides the HUD, as in the app.
  let lastTouch = 0;
  hud.addEventListener("pointerup", (e) => {
    if (e.target !== hud && e.target !== center) return;
    if (e.pointerType === "touch") {
      lastTouch = Date.now();
      if (hudOn && !video.paused) { clearTimeout(hideTimer); setHud(false); } else poke();
      return;
    }
    if (Date.now() - lastTouch < 600) return;
    handlers.onTogglePlay();
  });
  hud.addEventListener("dblclick", (e) => { if (e.target === hud || e.target === center) toggleFullscreen(); });

  // --- the settings menu: pages of rows, a row either acts or opens another page ---------
  // handlers.menu() -> {title, items: [{label, value, checked, run, sub, stay} | "-"]}
  let menuEl = null;
  function closeMenu() {
    menuEl?.remove();
    menuEl = null;
    menuBtn.setAttribute("aria-expanded", "false");
  }
  function showMenu(page, stack = []) {
    closeMenu();
    const rows = page.items.map((it) => it === "-" ? h("hr") : h("button", {
      type: "button",
      role: it.checked === undefined ? "menuitem" : "menuitemradio",
      "aria-checked": it.checked === undefined ? null : String(!!it.checked),
      onclick: () => {
        sfx("select");
        if (it.sub) return showMenu(it.sub(), [...stack, page]);
        it.run?.();
        if (it.stay) showMenu(page.refresh ? page.refresh() : page, stack);
        else closeMenu();
      },
    }, h("span", null, it.label), it.value ? h("span.muted", null, it.value, it.sub ? " ›" : "") : it.sub ? h("span.muted", null, "›") : null));
    menuEl = h("div.pmenu", { role: "menu", "aria-label": page.title || "Settings" },
      stack.length ? h("button", { type: "button", onclick: () => showMenu(stack[stack.length - 1].refresh?.() || stack[stack.length - 1], stack.slice(0, -1)) },
        h("span", null, sprite("back", 1.2), " Back")) : null,
      page.title ? h("h4", null, page.title) : null,
      rows);
    host.append(menuEl);
    menuBtn.setAttribute("aria-expanded", "true");
    menuEl.querySelector("button")?.focus({ preventScroll: true });
  }
  function toggleMenu() {
    if (menuEl) closeMenu();
    else { sfx("click"); showMenu(handlers.menu()); }
    poke();
  }
  document.addEventListener("pointerdown", (e) => {
    if (menuEl && !menuEl.contains(e.target) && !menuBtn.contains(e.target)) closeMenu();
  });

  function togglePip() {
    if (document.pictureInPictureElement) document.exitPictureInPicture().catch(() => {});
    else video.requestPictureInPicture?.().catch(() => {});
  }

  // --- fullscreen ------------------------------------------------------------------------
  const fsElement = () => document.fullscreenElement || document.webkitFullscreenElement;
  function toggleFullscreen() {
    if (fsElement()) (document.exitFullscreen || document.webkitExitFullscreen)?.call(document);
    else {
      const req = host.requestFullscreen || host.webkitRequestFullscreen;
      if (req) {
        Promise.resolve(req.call(host)).then(() => screen.orientation?.lock?.("landscape").catch(() => {})).catch(() => {});
      } else if (video.webkitEnterFullscreen) {
        video.webkitEnterFullscreen(); // iPhone: only the video element can go fullscreen.
      }
    }
  }
  const syncFs = () => {
    const on = fsElement() === host;
    host.classList.toggle("fs", on);
    clear(fsIcon).append(sprite(on ? "fullscreenExit" : "fullscreen", 2));
  };
  document.addEventListener("fullscreenchange", syncFs);
  document.addEventListener("webkitfullscreenchange", syncFs);

  // --- keyboard ---------------------------------------------------------------------------
  document.addEventListener("keydown", (e) => {
    if (e.target instanceof HTMLElement && e.target.closest("input, textarea, select, [contenteditable]")) return;
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    const k = e.key.toLowerCase();
    if (k === "escape" && menuEl) { closeMenu(); menuBtn.focus(); return; }
    const map = {
      " ": () => handlers.onTogglePlay(), k: () => handlers.onTogglePlay(),
      arrowleft: () => seekBy(-10), j: () => seekBy(-10),
      arrowright: () => seekBy(10), l: () => seekBy(10),
      arrowup: () => { video.volume = Math.min(1, video.volume + 0.1); setMuted(false); pref.set("volume", video.volume); },
      arrowdown: () => { video.volume = Math.max(0, video.volume - 0.1); pref.set("volume", video.volume); syncVolume(); },
      m: () => setMuted(!video.muted), f: toggleFullscreen,
      c: () => handlers.onToggleCaptions(), n: () => { if (!nextBtn.hidden) handlers.onNext(); },
      p: () => { if (pipBtn) togglePip(); },
    };
    if (map[k] && !(k === " " && e.target instanceof HTMLButtonElement)) { map[k](); e.preventDefault(); poke(); }
  });

  // --- overlays ---------------------------------------------------------------------------------
  let currentOrb = null;
  const api = {
    video,
    setTitle: (t) => { titleEl.textContent = t; },
    setCategory(cat, canSwitch) {
      const name = cat === "tl" ? "TAGALOG" : cat.toUpperCase();
      audioBtn.querySelector("span").textContent = name;
      audioBtn.disabled = !canSwitch;
      audioBtn.classList.toggle("off", !canSwitch);
      audioBtn.title = canSwitch ? `Audio: ${name}. Switch to ${cat === "sub" ? "DUB" : "SUB"}` : "No dub for this episode";
    },
    setCaptions(available, on) {
      ccBtn.hidden = !available;
      ccBtn.classList.toggle("off", !on);
      ccBtn.setAttribute("aria-pressed", String(on));
      ccBtn.title = on ? "Subtitles on (C)" : "Subtitles off (C)";
      if (!available || !on) captions.hidden = true;
    },
    showCaption(text) {
      if (!text) { captions.hidden = true; return; }
      if (capText.textContent !== text) capText.textContent = text;
      captions.hidden = false;
    },
    setMarkers(i, o, r = null) { intro = i; outro = o; recap = r; paintMarks(); },
    /** Subtitle look: size s|m|l|xl, and the dark box behind the text or not. */
    captionStyle({ size = "m", bg = true } = {}) {
      captions.classList.remove("sz-s", "sz-l", "sz-xl");
      if (size !== "m") captions.classList.add(`sz-${size}`);
      captions.classList.toggle("nobg", !bg);
    },
    closeMenu,
    setNext(available) { nextBtn.hidden = !available; },
    poke,

    /** Full-cover stage: the katana while resolving. */
    loading(label) {
      currentOrb = null;
      const lab = h("div.label", null, label);
      clear(stage).append(h("a.icon-btn.back", { href: handlers.backHref, "aria-label": "Back" }, sprite("back", 2.2)), katana(170), lab);
      stage.hidden = false;
      let dots = 0;
      const t = setInterval(() => { if (!lab.isConnected) return clearInterval(t); dots = (dots + 1) % 4; lab.textContent = label + ".".repeat(dots); }, 330);
    },
    /** Full-cover stage: the orb while a stream opens. Returns {set}. */
    opening(label, level) {
      const o = orb(Math.min(150, host.clientWidth * 0.3), level ?? 0.03);
      const lab = h("div.label", null, label);
      clear(stage).append(h("a.icon-btn.back", { href: handlers.backHref, "aria-label": "Back" }, sprite("back", 2.2)), o.el, lab);
      stage.hidden = false;
      currentOrb = o;
      return { set: ({ progress, mbps, text }) => { o.set({ progress, mbps }); if (text) lab.textContent = text; }, level: o.level };
    },
    /** The orb over the playing video while it buffers. */
    buffering(label, { onRetry, detail } = {}) {
      const o = orb(Math.min(136, host.clientWidth * 0.26), currentOrb?.level?.() ?? 0.08);
      const lab = h("div.label", null, label);
      // DOM append() prints null as "null"; leave the absent parts out.
      clear(bufStage).append(...[o.el, lab, detail ? h("div.detail", null, detail) : null,
        onRetry ? h("button.px-btn.px-box.bevel.small", { type: "button", onclick: onRetry }, sprite("refresh", 1.4), "Retry now") : null].filter(Boolean));
      bufStage.hidden = false;
      center.style.visibility = "hidden";
      return { set: ({ progress, mbps, text }) => { o.set({ progress, mbps }); if (text) lab.textContent = text; }, el: bufStage };
    },
    hideBuffering() { bufStage.hidden = true; clear(bufStage); center.style.visibility = ""; },
    hideStage() { stage.hidden = true; clear(stage); },
    /** Full-cover stage while the episode plays on a Chromecast: this page is the remote. */
    /** Returns {update({time, duration}), setSkip(label | null, run)} for the TV's progress. */
    casting(device, { onPlayPause, onStop }) {
      currentOrb = null;
      closeMenu();
      const where = h("div.label.muted");
      const skipSlot = h("span");
      clear(stage).append(
        h("a.icon-btn.back", { href: handlers.backHref, "aria-label": "Back" }, sprite("back", 2.2)),
        h("div.label", null, `Casting to ${device}`),
        where,
        h("div.row", null,
          h("button.px-btn.px-box.bevel.small", { type: "button", onclick: onPlayPause }, sprite("play", 1.4), "Play / pause"),
          skipSlot,
          h("button.px-btn.dark.px-box.bevel.small", { type: "button", onclick: onStop }, "Stop casting")));
      stage.hidden = false;
      let shown = null;
      return {
        update({ time, duration }) { where.textContent = duration > 0 ? `${fmtTime(time)} / ${fmtTime(duration)}` : ""; },
        setSkip(label, run) {
          if (label === shown) return;
          shown = label;
          clear(skipSlot).append(...(label ? [h("button.px-btn.bone.px-box.bevel.small", { type: "button", onclick: () => { sfx("skip"); run(); } }, sprite("forward", 1.4), label)] : []));
        },
      };
    },
    /**
     * Failure screen with actions [{label, kind, run}]. With `boss`, the skull
     * is a boss to fight instead: knock its HP to zero and boss() runs (a retry).
     */
    failed(title, reason, actions, { boss } = {}) {
      currentOrb = null;
      closeMenu();
      clear(stage).append(
        h("a.icon-btn.back", { href: handlers.backHref, "aria-label": "Back" }, sprite("back", 2.2)),
        h("div.fail", { style: { display: "flex", flexDirection: "column", alignItems: "center", gap: "14px" } },
          boss ? bossFight(boss) : sprite("skull", 5), h("h3", null, title), h("p", null, reason),
          h("div.row", null, actions.map((a) => a.href
            ? h(`a.px-btn.px-box.bevel.small${a.kind ? "." + a.kind : ""}`, { href: a.href }, a.label)
            : h(`button.px-btn.px-box.bevel.small${a.kind ? "." + a.kind : ""}`, { type: "button", onclick: a.run }, a.label)))));
      stage.hidden = false;
    },
    /** End card: next episode with a countdown. */
    upNext(ep, seconds, onPlay, onCancel) {
      let left = seconds;
      const count = h("div.label", null, `Up next: EP ${ep} in ${left}`);
      const play = h("button.px-btn.px-box.bevel", { type: "button", onclick: () => { clearInterval(t); onPlay(); } }, sprite("play", 1.6), "Play now");
      clear(stage).append(count, h("div.row", null, play,
        h("button.px-btn.dark.px-box.bevel", { type: "button", onclick: () => { clearInterval(t); api.hideStage(); onCancel(); } }, "Cancel")));
      stage.hidden = false;
      const t = setInterval(() => {
        left--;
        if (!count.isConnected) return clearInterval(t);
        count.textContent = `Up next: EP ${ep} in ${left}`;
        if (left <= 0) { clearInterval(t); onPlay(); }
      }, 1000);
      play.focus();
    },
  };
  paintTime();
  return api;
}

// --- the shock panel ------------------------------------------------------------------------
// When no stream plays, the failure is a ガーン! panel (the manga sound of a
// shock). Every tap cracks it and jolts the page; the third smashes it and
// retries. The buttons below still work for anyone not in the mood.

const SHOCK_TAPS = 3;

function bossFight(onDefeat) {
  let left = SHOCK_TAPS;
  const word = h("span.word", null, "ガーン!");
  const cracks = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  cracks.setAttribute("class", "cracks");
  cracks.setAttribute("viewBox", "0 0 200 120");
  cracks.setAttribute("preserveAspectRatio", "none");
  const panel = h("button.shock", { type: "button", "aria-label": `Tap the panel (${left} taps left) to retry` }, word, cracks);
  const hint = h("div.hint", null, "Tap the panel to retry");
  const wrap = h("div.boss", null, panel, hint);
  panel.addEventListener("click", (e) => {
    if (left <= 0) return;
    left--;
    sfx(left ? "hit" : "don");
    // Cracks spreading from where it was hit.
    const r = panel.getBoundingClientRect();
    const x = r.width ? ((e.clientX - r.left) / r.width) * 200 : 100, y = r.height ? ((e.clientY - r.top) / r.height) * 120 : 60;
    const arms = left ? 5 : 9;
    for (let a = 0; a < arms; a++) {
      let ang = (a / arms) * Math.PI * 2 + pxRand(left * 31 + a) * 0.6, px = x, py = y, d = `M${px.toFixed(1)} ${py.toFixed(1)}`;
      for (let k = 0; k < 4; k++) {
        ang += (pxRand(left * 97 + a * 7 + k) - 0.5) * 0.9;
        const step = (left ? 16 : 34) * (0.7 + pxRand(a * 13 + k));
        px += Math.cos(ang) * step; py += Math.sin(ang) * step;
        d += ` L${px.toFixed(1)} ${py.toFixed(1)}`;
      }
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", d);
      cracks.appendChild(path);
    }
    wrap.classList.remove("hit");
    void wrap.offsetWidth;
    wrap.classList.add("hit");
    panel.setAttribute("aria-label", `Tap the panel (${left} taps left) to retry`);
    if (left > 0) { hint.textContent = `${left} more tap${left === 1 ? "" : "s"}`; return; }
    word.textContent = "ドン!";
    panel.classList.add("smashed");
    shake();
    hint.textContent = "Smashed. Retrying…";
    setTimeout(onDefeat, 800);
  });
  return wrap;
}
