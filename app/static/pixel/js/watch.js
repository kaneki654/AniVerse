// Watching an episode: find streams, open the first that plays, keep it
// playing through bad connections, and remember how far you got -- the app's
// watch_screen.dart, for the web. player.js draws; this decides.
import { h, sprite, clear, toast, fmtTime } from "./px.js";
import { api, history, titleOf, coverOf, airedEpisodes } from "./api.js";
import { initShell } from "./ui.js";
import { createPlayer } from "./player.js";

initShell();
const root = document.getElementById("watch");
const animeId = root.dataset.id;
const ep = Number(root.dataset.ep);
const backHref = `/anime/${animeId}`;

let info = null, aired = null;
let category = "sub";
let sources = [], sourceIndex = 0, hasDub = null;
let gen = 0;               // bumped when earlier async work must stop mattering
let hls = null;
let phase = "resolving";   // resolving | opening | playing | reconnecting | failed
let captionsChoice = null; // null: on for SUB, off for DUB, as in the app
let cues = [];

const player = createPlayer(document.getElementById("player"), {
  backHref,
  onTogglePlay: () => {
    if (phase !== "playing") return;
    if (video.paused || video.ended) video.play().catch(() => {});
    else video.pause();
  },
  onToggleCategory: () => {
    if (category === "sub" && hasDub === false) return;
    saveProgress();
    category = category === "sub" ? "dub" : "sub";
    captionsChoice = null;
    resolve();
  },
  onToggleCaptions: () => {
    if (!cues.length) return;
    captionsChoice = !captionsOn();
    syncCaptions();
  },
  onNext: () => { location.href = `/watch/${animeId}/${ep + 1}`; },
});
const video = player.video;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// --- link speed ---------------------------------------------------------------------
// Each finished segment's own download rate, smoothed: the link's real speed,
// shown in the orb. Bytes are also what the loading orb fills from.
const speed = {
  mbps: null, bytes: 0, last: 0,
  frag(stats) {
    const loaded = stats.loaded || stats.total || 0;
    this.bytes += loaded;
    this.last = performance.now();
    const ms = (stats.loading?.end || 0) - (stats.loading?.start || 0);
    if (loaded > 50000 && ms > 0) {
      const m = (loaded * 8) / (ms * 1000);
      this.mbps = this.mbps == null ? m : this.mbps * 0.6 + m * 0.4;
    }
  },
};
let bytesPerMediaSecond = 150000;

// --- finding and opening a stream -----------------------------------------------------

function explain(data) {
  if (data.offline) return "Can't reach the AniVerse server. Check your connection.";
  if (category === "dub" && hasDub === false) return "This episode has no English dub yet.";
  const err = data.error || "";
  if (!err || err.includes("sources available")) {
    return `No working ${category.toUpperCase()} stream was found for this episode right now. Streams come and go, so trying again in a minute often works.`;
  }
  return err;
}

function apply(data) {
  sources = data.sources.filter((s) => s && s.url);
  hasDub = data.hasDub ?? null;
  player.setMarkers(data.intro || null, data.outro || null);
  player.setCategory(category, category === "dub" || hasDub !== false);
}

function resumeAt() {
  const e = history.progressFor(animeId, ep);
  if (!e || history.finished(e) || e.position_ms < 10000) return 0;
  return e.position_ms / 1000;
}

async function resolve() {
  const g = ++gen;
  phase = "resolving";
  teardown();
  player.setCategory(category, category === "dub" || hasDub !== false);
  renderActions();
  player.loading("Finding sources");
  let data = await api.sources(animeId, ep, category);
  if (g !== gen) return;
  // Providers time out now and then; one more look often finds what the
  // first one missed.
  if (!data.sources.length && !data.offline) {
    player.loading("Still looking");
    await sleep(2000);
    if (g !== gen) return;
    data = await api.sources(animeId, ep, category);
    if (g !== gen) return;
  }
  apply(data);
  if (!sources.length) {
    // No subbed copy anywhere, but the server found a dub: play that rather
    // than an error screen, and say why.
    if (category === "sub" && hasDub === true && !data.offline) {
      category = "dub";
      captionsChoice = null;
      toast("No subbed version was found, so this is the English dub.");
      return resolve();
    }
    return fail(explain(data));
  }

  const start = resumeAt();
  let ok = await openFrom(0, start, g);
  if (g !== gen) return;
  if (!ok) {
    // Links carry tokens that can die before the server's cache entry does.
    const tried = sources.length;
    player.loading("Getting fresh links");
    const fresh = await api.sources(animeId, ep, category, true);
    if (g !== gen) return;
    if (!fresh.sources.length) {
      return fail(fresh.offline ? explain(fresh) : `The server found ${tried} stream${tried === 1 ? "" : "s"}, but none of them would play, and a fresh search found nothing new. Try again in a moment.`);
    }
    apply(fresh);
    ok = await openFrom(0, start, g);
    if (g !== gen) return;
  }
  if (!ok) return fail(`The server found ${sources.length} stream${sources.length === 1 ? "" : "s"}, but none of them would play, even with fresh links. Try again in a moment.`);
  if (start > 0) toast(`Resumed from ${fmtTime(start)}`, { action: { label: "Start over", run: () => { video.currentTime = 0; } } });
}

/** Opens sources starting at `first` (wrapping round), attaching the first that plays. */
async function openFrom(first, start, g) {
  for (let n = 0; n < sources.length; n++) {
    const i = (first + n) % sources.length;
    const ok = await openSource(sources[i], start, g);
    if (g !== gen) return false;
    if (ok) {
      sourceIndex = i;
      attached();
      return true;
    }
  }
  return false;
}

function teardown() {
  if (hls) { hls.destroy(); hls = null; }
  video.pause();
  video.removeAttribute("src");
  video.load();
  cues = [];
  player.setCaptions(false, false);
  player.hideBuffering();
}

function openSource(src, start, g) {
  return new Promise((done) => {
    teardown();
    phase = "opening";
    const url = src.url;
    const isHls = src.isM3U8 === true || url.includes("m3u8");
    const ui = player.opening("Loading video 3%");
    const began = performance.now();
    const bytes0 = speed.bytes;
    let settled = false;

    const finish = (ok) => {
      if (settled) return;
      settled = true;
      clearInterval(tick);
      clearTimeout(timer);
      video.removeEventListener("canplay", ready);
      video.removeEventListener("error", failed);
      if (!ok) teardown();
      done(ok && g === gen);
    };
    const ready = () => finish(true);
    const failed = () => finish(false);
    // The orb fills from what is really arriving: bytes since the attempt
    // began, then the buffer where playback will start.
    const tick = setInterval(() => {
      if (g !== gen) return finish(false);
      const expected = bytesPerMediaSecond * 6 * (start > 0 ? 1.4 : 1);
      const byBytes = 1 - Math.exp(-Math.max(0, speed.bytes - bytes0) / expected);
      let ahead = 0;
      for (let i = 0; i < video.buffered.length; i++) {
        if (video.buffered.start(i) <= video.currentTime + 1) ahead = Math.max(ahead, video.buffered.end(i) - video.currentTime);
      }
      const byBuffer = Math.min(1, ahead / 2.5);
      const byTime = 0.5 * (1 - Math.exp(-(performance.now() - began) / 15000));
      const p = Math.min(0.95, 0.03 + 0.92 * Math.max(byBytes, byBuffer, byTime));
      ui.set({ progress: p, mbps: speed.mbps, text: `Loading video ${Math.round(p * 100)}%` });
    }, 250);
    // A dead connection can hang forever; the bound gives the next source a turn.
    const timer = setTimeout(() => finish(false), 45000);
    video.addEventListener("canplay", ready);
    video.addEventListener("error", failed);

    const Hls = window.Hls;
    if (isHls && Hls && Hls.isSupported()) {
      hls = new Hls({
        startPosition: start > 1 ? start : -1,
        maxBufferLength: 40,
        backBufferLength: 60,
        manifestLoadingMaxRetry: 2,
        fragLoadingMaxRetry: 4,
      });
      hls.on(Hls.Events.FRAG_LOADED, (_, d) => speed.frag(d.frag.stats));
      hls.on(Hls.Events.ERROR, (_, d) => {
        if (!d.fatal) return;
        if (!settled) finish(false);
        else onFatal(d);
      });
      hls.loadSource(url);
      hls.attachMedia(video);
    } else if (isHls && !video.canPlayType("application/vnd.apple.mpegurl")) {
      finish(false);
    } else {
      // Safari plays HLS itself; MP4 sources play anywhere.
      if (start > 1) video.addEventListener("loadedmetadata", () => { video.currentTime = start; }, { once: true });
      video.src = url;
    }
  });
}

function attached() {
  phase = "playing";
  reconnectTries = 0;
  mediaRecovered = false;
  player.hideStage();
  player.hideBuffering();
  loadCaptions(sources[sourceIndex]);
  renderActions();
  video.play().catch(() => player.poke()); // Autoplay refused: the play button waits.
}

function fail(reason) {
  phase = "failed";
  teardown();
  const other = category === "sub" ? "DUB" : "SUB";
  const offerSwitch = category === "dub" || hasDub !== false;
  player.failed("Couldn't play this episode", reason, [
    { label: "Retry", run: () => resolve() },
    offerSwitch ? { label: `Try ${other}`, kind: "dark", run: () => { category = category === "sub" ? "dub" : "sub"; captionsChoice = null; resolve(); } } : null,
    { label: "Details", kind: "dark", href: backHref },
  ].filter(Boolean));
}

// --- keeping it playing ---------------------------------------------------------------

let bufferingSince = 0, bufUi = null, bufTick = 0, lastBufEnd = 0, lastProgressAt = 0;
let reconnectTries = 0, mediaRecovered = false, reconnecting = false;

function bufferedAhead() {
  for (let i = 0; i < video.buffered.length; i++) {
    if (video.buffered.start(i) <= video.currentTime + 0.5 && video.buffered.end(i) > video.currentTime) return video.buffered.end(i) - video.currentTime;
  }
  return 0;
}

function showBuffering(label, opts) {
  bufUi = player.buffering(label, opts);
  clearInterval(bufTick);
  bufTick = setInterval(() => {
    if (!bufUi) return clearInterval(bufTick);
    // ExoPlayer and browsers resume after a stall with ~5s in hand, so the
    // orb is full exactly when playback comes back.
    bufUi.set({ progress: navigator.onLine ? Math.min(1, bufferedAhead() / 5) : null, mbps: speed.mbps });
  }, 250);
}
function hideBuffering() {
  if (!bufUi) return;
  bufUi.set({ progress: 1 });
  const ui = bufUi;
  bufUi = null;
  clearInterval(bufTick);
  setTimeout(() => { if (!bufUi && ui.el.isConnected) player.hideBuffering(); }, 250);
}

video.addEventListener("waiting", () => {
  if (phase !== "playing") return;
  bufferingSince = performance.now();
  setTimeout(() => {
    if (phase === "playing" && bufferingSince && !bufUi && video.readyState < 3) showBuffering(navigator.onLine ? "Buffering" : "Offline");
  }, 450);
});
const unstall = () => { bufferingSince = 0; if (phase === "playing" && !reconnecting) hideBuffering(); };
video.addEventListener("playing", unstall);
video.addEventListener("canplay", () => { if (!video.paused) unstall(); });
video.addEventListener("seeked", () => { if (video.readyState >= 3) unstall(); });

// A hung connection: buffering for 20s with nothing new arriving.
setInterval(() => {
  if (phase !== "playing" || !bufferingSince) return;
  let end = 0;
  for (let i = 0; i < video.buffered.length; i++) end = Math.max(end, video.buffered.end(i));
  const now = performance.now();
  if (end > lastBufEnd + 0.05 || now - speed.last < 2000) { lastBufEnd = end; lastProgressAt = now; return; }
  if (now - Math.max(lastProgressAt, bufferingSince) > 20000) reconnect();
}, 1000);

video.addEventListener("error", () => { if (phase === "playing" && !hls) reconnect(); });

function onFatal(d) {
  if (phase !== "playing") return;
  const Hls = window.Hls;
  if (d.type === Hls.ErrorTypes.MEDIA_ERROR && !mediaRecovered) {
    mediaRecovered = true;
    hls.recoverMediaError();
    return;
  }
  if (d.type === Hls.ErrorTypes.NETWORK_ERROR && reconnectTries < 3) {
    const delay = [1, 2, 4][reconnectTries++] * 1000;
    showBuffering("Reconnecting");
    setTimeout(() => { if (hls && navigator.onLine) hls.startLoad(); }, delay);
    return;
  }
  reconnect();
}

addEventListener("offline", () => { if (phase === "playing") showBuffering("Offline", { detail: "Waiting for the connection to come back." }); });
addEventListener("online", () => {
  if (phase !== "playing") return;
  if (hls) hls.startLoad();
  if (video.readyState >= 3) hideBuffering(); else showBuffering("Reconnecting");
});

/** The stream died mid-episode: get new links and carry on from the same spot. */
async function reconnect() {
  if (reconnecting) return;
  reconnecting = true;
  const g = gen;
  const at = video.currentTime;
  saveProgress();
  phase = "reconnecting";
  for (const delay of [0, 2, 5, 10]) {
    if (delay) await sleep(delay * 1000);
    if (g !== gen) { reconnecting = false; return; }
    const fresh = await api.sources(animeId, ep, category, true);
    if (g !== gen) { reconnecting = false; return; }
    if (fresh.sources.length) {
      apply(fresh);
      if (await openFrom(sourceIndex % sources.length, at, g)) { reconnecting = false; return; }
      if (g !== gen) { reconnecting = false; return; }
    }
  }
  reconnecting = false;
  fail("The stream dropped and could not be brought back. Check your connection and retry.");
}

// --- subtitles -------------------------------------------------------------------------
// Most "sub" streams are the raw episode with the text in a separate VTT file,
// so the subtitles are drawn here, in the pixel style, from that file.

const captionsOn = () => captionsChoice ?? category === "sub";

function syncCaptions() {
  player.setCaptions(cues.length > 0, captionsOn());
  paintCue();
}

function paintCue() {
  if (!cues.length || !captionsOn()) return player.showCaption("");
  const t = video.currentTime;
  const lines = [];
  for (const c of cues) if (t >= c.start && t < c.end) lines.push(c.text);
  player.showCaption(lines.join("\n"));
}
video.addEventListener("timeupdate", paintCue);
setInterval(() => { if (!video.paused && cues.length) paintCue(); }, 200);

async function loadCaptions(src) {
  const g = gen;
  const tracks = (src && src.subtitles) || [];
  if (!tracks.length) return;
  const track = tracks.find((t) => t.default) || tracks.find((t) => /^english/i.test(t.label || "")) || tracks[0];
  try {
    const r = await fetch(track.url);
    if (!r.ok || g !== gen) return;
    const text = await r.text();
    if (g !== gen || !/^﻿?\s*WEBVTT/.test(text)) return;
    cues = parseVtt(text);
    syncCaptions();
  } catch { /* no subtitles is not a reason to stop the episode */ }
}

function parseVtt(text) {
  const ts = (s) => {
    const m = /^(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{1,3})$/.exec(s);
    return m ? Number(m[1] || 0) * 3600 + Number(m[2]) * 60 + Number(m[3]) + Number(m[4].padEnd(3, "0")) / 1000 : null;
  };
  const decode = (s) => s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&");
  const out = [];
  for (const block of text.replace(/\r/g, "").split(/\n{2,}/)) {
    const lines = block.split("\n");
    const i = lines.findIndex((l) => l.includes("-->"));
    if (i < 0) continue;
    const [a, z] = lines[i].split("-->").map((s) => s.trim().split(/\s+/)[0]);
    const start = ts(a), end = ts(z);
    if (start === null || end === null) continue;
    const body = decode(lines.slice(i + 1).join("\n").replace(/<[^>]*>/g, "")).trim();
    if (body) out.push({ start, end, text: body });
  }
  return out;
}

// --- progress ------------------------------------------------------------------------------

function saveProgress(final = false) {
  if (!info || phase !== "playing" && phase !== "reconnecting") return;
  const d = video.duration;
  if (!Number.isFinite(d) || d <= 0) return;
  const pos = final ? d : video.currentTime;
  if (pos < 1) return;
  history.save({
    anime_id: animeId, episode: ep, title: titleOf(info), cover: coverOf(info),
    position_ms: Math.round(pos * 1000), duration_ms: Math.round(d * 1000),
  });
  // Learned from real playback: bytes per second of video, for the loading orb.
  if (speed.bytes > 2e6 && video.currentTime > 30) bytesPerMediaSecond = Math.max(40000, speed.bytes / Math.max(30, video.currentTime));
}
setInterval(() => { if (!video.paused && phase === "playing") saveProgress(); }, 10000);
video.addEventListener("pause", () => saveProgress());
addEventListener("pagehide", () => saveProgress());
video.addEventListener("ended", () => {
  saveProgress(true);
  if (aired && ep < aired) player.upNext(ep + 1, 8, () => { location.href = `/watch/${animeId}/${ep + 1}`; }, () => {});
  else toast("That was the latest episode.");
});

// --- the page around the player --------------------------------------------------------------

const titleEl = document.getElementById("watch-title");
const metaEl = document.getElementById("watch-meta");
const actionsEl = document.getElementById("watch-actions");
const epsEl = document.getElementById("watch-eps");
const rangeNav = h("div", { style: { display: "flex", flexWrap: "wrap", gap: "8px", marginTop: "12px" } });
epsEl.after(rangeNav);

function renderActions() {
  clear(actionsEl);
  if (ep > 1) actionsEl.append(h("a.px-btn.dark.px-box.bevel.small", { href: `/watch/${animeId}/${ep - 1}` }, h("span", { style: { transform: "scaleX(-1)", display: "grid" } }, sprite("skipNext", 1.4)), `EP ${ep - 1}`));
  if (aired && ep < aired) actionsEl.append(h("a.px-btn.px-box.bevel.small", { href: `/watch/${animeId}/${ep + 1}` }, `EP ${ep + 1}`, sprite("skipNext", 1.4)));
  if (sources.length > 1 && phase === "playing") {
    actionsEl.append(h("button.px-btn.dark.px-box.bevel.small", {
      type: "button",
      title: "Use a different stream for this episode",
      onclick: async () => {
        const g = ++gen;
        const at = video.currentTime;
        if (!(await openFrom((sourceIndex + 1) % sources.length, at, g)) && g === gen) fail("None of the other streams would play.");
      },
    }, sprite("refresh", 1.4), `Source ${sourceIndex + 1}/${sources.length}`));
  }
  actionsEl.append(h("a.px-btn.dark.px-box.bevel.small", { href: backHref }, "Details"));
  const src = sources[sourceIndex];
  metaEl.textContent = [`EP ${ep}`, category.toUpperCase(), src && phase === "playing" ? `Server: ${src.serverName || "Auto"}` : null].filter(Boolean).join(" · ");
}

function renderEpisodes() {
  if (!aired) return;
  clear(epsEl);
  const total = Math.max(aired, info.episodes || 0);
  const RANGE = 100;
  const start = Math.floor((ep - 1) / RANGE) * RANGE + 1;
  const end = Math.min(total, start + RANGE - 1);
  const progress = new Map(history.forAnime(animeId).map((e) => [e.episode, e]));
  for (let n = start; n <= end; n++) {
    if (n > aired) { epsEl.append(h("span.ep-btn.future.px-box", { title: "Not aired yet" }, String(n))); continue; }
    const e = progress.get(n);
    const done = e && history.finished(e);
    const cls = n === ep ? ".current" : done ? ".watched" : "";
    epsEl.append(h(`a.ep-btn.px-box${cls}`, { href: `/watch/${animeId}/${n}`, "aria-current": n === ep ? "page" : null },
      String(n), done && n !== ep ? h("span.mark", null, sprite("skullSmall", 2)) : null));
  }
  clear(rangeNav);
  if (start > 1) rangeNav.append(h("a.px-btn.dark.px-box.bevel.small", { href: `/watch/${animeId}/${start - RANGE}` }, `${start - RANGE}-${start - 1}`));
  if (end < aired) rangeNav.append(h("a.px-btn.dark.px-box.bevel.small", { href: `/watch/${animeId}/${end + 1}` }, `${end + 1}+`));
  epsEl.querySelector(".current")?.scrollIntoView({ block: "nearest" });
}

api.info(animeId).then((a) => {
  info = a;
  aired = airedEpisodes(a);
  const title = titleOf(a);
  document.title = `${title} · EP ${ep} · AniVerse`;
  clear(titleEl).append(h("a", { href: backHref }, title));
  player.setTitle(`${title} · EP ${ep}`);
  player.setNext(ep < aired);
  renderActions();
  renderEpisodes();
  history.onChange(renderEpisodes);
  if (a.status === "NOT_YET_RELEASED") {
    ++gen;
    teardown();
    player.failed("Not aired yet", `${title} has not started airing. Episodes appear once they air.`, [{ label: "Details", href: backHref }]);
  }
}).catch(() => { player.setTitle(`Episode ${ep}`); });

player.setTitle(`Episode ${ep}`);
renderActions();
resolve();
