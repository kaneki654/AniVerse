// Watching an episode: find streams, open the first that plays, keep it
// playing through bad connections, and remember how far you got -- the app's
// watch_screen.dart, for the web. player.js draws; this decides. Also here:
// quality and speed, subtitle choice, reporting a bad stream, fetching the
// next episode's streams early, and watch parties.
import { h, sprite, clear, toast, fmtTime } from "./px.js";
import { api, history, titleOf, coverOf, airedEpisodes } from "./api.js";
import { settings } from "./settings.js";
import { sfx } from "./sfx.js";
import { initShell, reportError } from "./ui.js";
import { createPlayer, pref } from "./player.js";
import { startParty, newPartyCode, validCode } from "./party.js";
import { castReady, castDevice, startCast, stopCast, castLoad, castPlayPause, castSeek, onCastChange, onCastProgress, onCastFinished } from "./cast.js";

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
let cues = [], currentTrack = null;

// A watch party is on when the address carries ?party=CODE.
const partyParam = new URLSearchParams(location.search).get("party");
let partyCode = validCode(partyParam) ? partyParam.toUpperCase() : null;
let party = null;
const epHref = (n) => `/watch/${animeId}/${n}${partyCode ? `?party=${partyCode}` : ""}`;
/** Another episode; in a party the room is told first so everyone comes along. */
function goEpisode(n) {
  if (!party) { location.href = epHref(n); return; }
  if (!party.canControl()) { party.toldLocked(); return; }
  party.sendEpisode(n);
  setTimeout(() => { location.href = epHref(n); }, 150);
}

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
    const at = video.currentTime;
    category = category === "sub" ? "dub" : "sub";
    captionsChoice = null;
    party?.send({ category, t: at, playing: true });
    resolve();
  },
  onToggleCaptions: () => {
    if (!cues.length) return;
    captionsChoice = !captionsOn();
    syncCaptions();
  },
  onNext: () => goEpisode(ep + 1),
  menu: () => buildMenu(),
});
const video = player.video;
const styleCaptions = (s) => player.captionStyle({ size: s.subSize, bg: s.subBg });
styleCaptions(settings.get());
settings.onChange(styleCaptions);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// --- Chromecast (cast.js): the episode goes to the TV from where it is, the page becomes the remote.
let canCast = false;
castReady().then((ok) => { canCast = ok; });
onCastChange(({ device, position }) => {
  if (!device) {
    castStage = null;
    player.hideStage();
    if (position > 0) video.currentTime = position;
    if (phase === "playing") video.play().catch(() => {});
    return;
  }
  castHere(device);
});

/** Sends this episode to the TV; before a stream is found, as soon as one is. */
let castWaiting = false;
function castHere(device) {
  const src = sources[sourceIndex];
  if (!src || phase !== "playing") { castWaiting = true; return; }
  castWaiting = false;
  video.pause();
  const abs = (u) => new URL(u, location.href).href;
  castLoad({
    url: abs(src.url),
    title: info ? titleOf(info) : "AniVerse",
    subtitle: `Episode ${ep}${category === "dub" ? " (dub)" : ""}`,
    position: video.currentTime || 0,
    subtitles: captionsOn() && currentTrack ? abs(currentTrack.url) : null,
    hls: src.isM3U8 === true || /m3u8/.test(src.url),
  }).then((ok) => { if (!ok) toast("The TV wouldn't take this stream. Try another server."); });
  castStage = player.casting(device, { onPlayPause: castPlayPause, onStop: stopCast });
  sfx("select");
}

// While casting: the TV's position, a skip button inside a marked range, and
// the next episode when one ends there (the session carries over to the page).
let castStage = null;
onCastProgress(({ time, duration }) => {
  if (!castStage || !castDevice()) return;
  castStage.update({ time, duration });
  const inRange = (r) => r && time >= r.start && time < r.end - 1;
  const hit = [["Skip recap", skipMarks.recap], ["Skip intro", skipMarks.intro], ["Skip outro", skipMarks.outro]].find(([, r]) => inRange(r));
  castStage.setSkip(hit ? hit[0] : null, () => hit && castSeek(hit[1].end));
});
onCastFinished(() => {
  if (castDevice() && aired && ep < aired) { toast(`Episode ${ep + 1} is next on ${castDevice()}.`); goEpisode(ep + 1); }
});

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
  currentTrack = null;
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
      hls.on(Hls.Events.MANIFEST_PARSED, applyQuality);
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

let startedOnce = false;
function attached() {
  phase = "playing";
  if (castWaiting && castDevice()) setTimeout(() => castHere(castDevice()), 0);
  reconnectTries = 0;
  mediaRecovered = false;
  player.hideStage();
  player.hideBuffering();
  loadCaptions(sources[sourceIndex]);
  loadSkipTimes(sources[sourceIndex]);
  renderActions();
  mediaSession();
  video.defaultPlaybackRate = video.playbackRate = pref.get("rate", 1);
  if (!startedOnce) { startedOnce = true; sfx("start"); }
  remoteUntil = performance.now() + 1500; // opening is not something to tell the party
  video.play().catch(() => player.poke()); // Autoplay refused: the play button waits.
  if (pendingParty) {
    const p = pendingParty;
    pendingParty = null;
    applyPartyState(p.s, p.t + (p.s.playing ? (performance.now() - p.at) / 1000 : 0));
  }
}

function fail(reason) {
  phase = "failed";
  teardown();
  sfx("error");
  const other = category === "sub" ? "DUB" : "SUB";
  const offerSwitch = category === "dub" || hasDub !== false;
  reportError({ kind: "playback", message: `EP ${ep} (${category}): ${reason}`, where: `watch/${animeId}` });
  player.failed("Couldn't play this episode", reason, [
    { label: "Retry", run: () => resolve() },
    offerSwitch ? { label: `Try ${other}`, kind: "dark", run: () => { category = category === "sub" ? "dub" : "sub"; captionsChoice = null; resolve(); } } : null,
    { label: "Details", kind: "dark", href: backHref },
  ].filter(Boolean), { boss: () => resolve() });
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

// --- skip intro / outro ---------------------------------------------------------------
// The playing source's own markers when its provider has them; otherwise the
// server's, which come from AniSkip or from matching this episode's audio with
// its neighbour's. That last can take a couple of minutes the first time, so a
// "pending" answer is asked again, and better times replace earlier ones.

let skipMarks = { intro: null, outro: null, recap: null };
let skipTimer = 0;

function loadSkipTimes(src) {
  clearTimeout(skipTimer);
  const g = gen;
  skipMarks = { intro: src?.intro || null, outro: src?.outro || null, recap: null };
  player.setMarkers(skipMarks.intro, skipMarks.outro);
  // Recaps only come from the server (AniSkip), and only from episode 2 on.
  if (skipMarks.intro && skipMarks.outro && ep <= 1) return;
  const ask = async (attempt) => {
    if (g !== gen) return;
    const d = video.duration;
    if (!Number.isFinite(d) || d <= 0) { skipTimer = setTimeout(() => ask(attempt), 1000); return; }
    const r = await api.skipTimes(animeId, ep, d, src?.serverName, category);
    if (g !== gen || !r) return;
    // The source's own markers are exact for it; fill only what it lacks.
    skipMarks = { intro: src?.intro || r.intro || skipMarks.intro, outro: src?.outro || r.outro || skipMarks.outro,
      recap: r.recap || skipMarks.recap };
    player.setMarkers(skipMarks.intro, skipMarks.outro, skipMarks.recap);
    if (r.pending && attempt < 4) skipTimer = setTimeout(() => ask(attempt + 1), [60, 90, 150, 300][attempt] * 1000);
  };
  ask(0);
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

const tracksOf = (src) => ((src && src.subtitles) || []).filter((t) => t && t.url);
const trackName = (t) => t.label || t.lang || "Subtitles";

/** The language picked in Settings when the stream has it, else its default, else English. */
function pickTrack(tracks) {
  const lang = settings.get().subLang;
  const named = (re) => tracks.find((t) => re.test(trackName(t)));
  return (lang && named(new RegExp(`^${lang}`, "i"))) || tracks.find((t) => t.default) || named(/^english/i) || tracks[0];
}

function loadCaptions(src) {
  const tracks = tracksOf(src);
  if (tracks.length) loadTrack(pickTrack(tracks));
}

async function loadTrack(track) {
  const g = gen;
  currentTrack = track;
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
  if (aired && ep < aired) player.upNext(ep + 1, 8, () => goEpisode(ep + 1), () => {});
  else toast("That was the latest episode.");
});

// The next episode's streams are looked up near the end of this one, so the
// server has them ready when "up next" fires.
let prefetched = false;
video.addEventListener("timeupdate", () => {
  if (prefetched || phase !== "playing" || !aired || ep >= aired) return;
  const d = video.duration;
  if (Number.isFinite(d) && d > 60 && video.currentTime / d > 0.85) {
    prefetched = true;
    api.sources(animeId, ep + 1, category);
  }
});

// --- quality, speed, the settings menu, reports ---------------------------------------------

const levelName = (l) => (l.height ? `${l.height}p` : `${Math.round((l.bitrate || 0) / 1000)} kbps`);
function lowestLevel() {
  let best = 0;
  hls.levels.forEach((l, i) => { if ((l.bitrate || 0) < (hls.levels[best].bitrate || 0)) best = i; });
  return best;
}
/** The quality to start on: the lowest with data saver, else the one picked last time. */
function applyQuality() {
  if (!hls || hls.levels.length < 2) return;
  if (settings.get().dataSaver) {
    const low = lowestLevel();
    hls.autoLevelCapping = low;
    hls.currentLevel = low;
    return;
  }
  hls.autoLevelCapping = -1;
  const want = pref.get("quality", "auto");
  const i = want === "auto" ? -1 : hls.levels.findIndex((l) => l.height === want);
  if (i >= 0) hls.currentLevel = i;
}
function setQuality(i) {
  if (!hls) return;
  pref.set("quality", i < 0 ? "auto" : hls.levels[i].height || "auto");
  hls.autoLevelCapping = -1; // a quality picked by hand beats data saver for this episode
  hls.currentLevel = i;      // -1: automatic
}

function buildMenu() {
  const s = settings.get();
  const items = [];
  if (hls && hls.levels && hls.levels.length > 1) {
    const cur = hls.levels[hls.currentLevel];
    items.push({ label: "Quality", value: hls.autoLevelEnabled ? `Auto${cur ? ` (${levelName(cur)})` : ""}` : cur ? levelName(cur) : "Auto", sub: qualityPage });
  }
  items.push({ label: "Speed", value: `${video.playbackRate}x`, sub: speedPage });
  const tracks = tracksOf(sources[sourceIndex]);
  if (tracks.length && phase === "playing") items.push({ label: "Subtitles", value: captionsOn() && currentTrack ? trackName(currentTrack) : "Off", sub: subtitlePage });
  items.push({ label: "Subtitle style", sub: stylePage });
  items.push({
    label: "Data saver", value: s.dataSaver ? "On" : "Off", stay: true,
    run: () => {
      const on = !settings.get().dataSaver;
      settings.set({ dataSaver: on });
      if (on) applyQuality();
      else if (hls) { hls.autoLevelCapping = -1; hls.currentLevel = -1; }
    },
  });
  if (canCast && sources.length && phase === "playing") {
    items.push({ label: castDevice() ? "Stop casting" : "Cast to TV", value: castDevice() || "", run: () => (castDevice() ? stopCast() : startCast()) });
  }
  if (sources.length && phase === "playing") items.push("-", { label: "Report a problem", sub: reportPage });
  return { title: "Settings", items, refresh: buildMenu };
}

function qualityPage() {
  if (!hls) return { title: "Quality", items: [] };
  const auto = hls.autoLevelEnabled;
  return {
    title: settings.get().dataSaver ? "Quality · data saver on" : "Quality",
    items: [
      { label: "Auto", checked: auto, run: () => setQuality(-1) },
      ...hls.levels.map((l, i) => ({ l, i }))
        .sort((a, b) => (b.l.height || 0) - (a.l.height || 0) || (b.l.bitrate || 0) - (a.l.bitrate || 0))
        .map(({ l, i }) => ({ label: levelName(l), checked: !auto && hls.currentLevel === i, run: () => setQuality(i) })),
    ],
  };
}

function speedPage() {
  return {
    title: "Speed",
    items: [0.5, 0.75, 1, 1.25, 1.5, 2].map((r) => ({
      label: r === 1 ? "Normal" : `${r}x`, checked: video.playbackRate === r,
      run: () => { video.defaultPlaybackRate = video.playbackRate = r; pref.set("rate", r); },
    })),
  };
}

function subtitlePage() {
  return {
    title: "Subtitles",
    items: [
      { label: "Off", checked: !captionsOn(), run: () => { captionsChoice = false; syncCaptions(); } },
      ...tracksOf(sources[sourceIndex]).map((t) => ({
        label: trackName(t), checked: captionsOn() && currentTrack === t,
        run: () => { captionsChoice = true; if (currentTrack === t) syncCaptions(); else loadTrack(t); },
      })),
    ],
  };
}

function stylePage() {
  const s = settings.get();
  return {
    title: "Subtitle style", refresh: stylePage,
    items: [
      ...[["s", "Small"], ["m", "Medium"], ["l", "Large"], ["xl", "Extra large"]].map(([v, label]) => ({
        label, checked: s.subSize === v, stay: true, run: () => settings.set({ subSize: v }),
      })),
      "-",
      { label: "Dark box behind text", value: s.subBg ? "On" : "Off", stay: true, run: () => settings.set({ subBg: !settings.get().subBg }) },
    ],
  };
}

const REASONS = ["Video won't play", "Wrong episode", "Audio and video out of sync", "Subtitles missing or wrong", "Keeps buffering", "Very bad quality"];
function reportPage() {
  return { title: "What's wrong?", items: REASONS.map((r) => ({ label: r, run: () => report(r) })) };
}

/** Tells the server this stream is bad (it is left out for a few hours) and moves on to another. */
async function report(reason) {
  const src = sources[sourceIndex];
  if (!src) return;
  api.report(animeId, ep, category, src.url, reason);
  sfx("slash");
  toast("Thanks for reporting. That stream is set aside for everyone; trying another.");
  const g = ++gen;
  const at = video.currentTime;
  sources = sources.filter((_, i) => i !== sourceIndex);
  if (sources.length && await openFrom(sourceIndex % sources.length, at, g)) return;
  if (g !== gen) return;
  player.loading("Finding another stream");
  const next = await api.sources(animeId, ep, category);
  if (g !== gen) return;
  apply(next);
  if (sources.length && await openFrom(0, at, g)) return;
  if (g === gen) fail("Every stream found for this episode has been reported. Try again later, or switch between SUB and DUB.");
}

// --- lock screen and media keys ----------------------------------------------------------------

function mediaSession() {
  const ms = navigator.mediaSession;
  if (!ms || !info) return;
  try {
    ms.metadata = new MediaMetadata({ title: `Episode ${ep}`, artist: titleOf(info), album: "AniVerse", artwork: coverOf(info) ? [{ src: coverOf(info) }] : [] });
    ms.setActionHandler("play", () => video.play().catch(() => {}));
    ms.setActionHandler("pause", () => video.pause());
    ms.setActionHandler("seekbackward", () => { video.currentTime = Math.max(0, video.currentTime - 10); });
    ms.setActionHandler("seekforward", () => { video.currentTime += 10; });
    ms.setActionHandler("previoustrack", ep > 1 ? () => goEpisode(ep - 1) : null);
    ms.setActionHandler("nexttrack", aired && ep < aired ? () => goEpisode(ep + 1) : null);
  } catch { /* an older browser without some of these actions */ }
}

// --- watch party -----------------------------------------------------------------------------------

let remoteUntil = 0;   // events before this are the party's doing, not the viewer's
let pendingParty = null;

const partyState = () => ({
  anime: animeId, ep, category,
  playing: phase === "playing" && !video.paused && !video.ended,
  t: phase === "playing" ? video.currentTime : resumeAt(),
});

/** Someone in the party played, paused, seeked or changed episode: follow. */
function applyPartyState(s, t) {
  if (String(s.anime) !== String(animeId) || s.ep !== ep) {
    toast(`${s.by || "The party"} moved to episode ${s.ep}`);
    party?.leave(false);
    location.href = `/watch/${encodeURIComponent(s.anime)}/${s.ep}?party=${partyCode}`;
    return;
  }
  if (s.category !== category && (s.category === "sub" || hasDub !== false)) {
    category = s.category;
    captionsChoice = null;
    pendingParty = { s, t, at: performance.now() };
    resolve();
    return;
  }
  if (phase !== "playing") { pendingParty = { s, t, at: performance.now() }; return; }
  remoteUntil = performance.now() + 1200;
  if (Math.abs(video.currentTime - t) > 1.5) video.currentTime = t;
  if (s.playing && video.paused) video.play().catch(() => player.poke());
  if (!s.playing && !video.paused) video.pause();
}

const viewerDid = () => { if (party && phase === "playing" && performance.now() > remoteUntil) party.send(); };
video.addEventListener("play", viewerDid);
video.addEventListener("pause", () => { if (!video.ended) viewerDid(); });
video.addEventListener("seeked", viewerDid);

function joinParty() {
  party = startParty({ code: partyCode, mount: actionsEl, stage: document.getElementById("player"),
    getState: partyState, applyState: applyPartyState });
}

// In a party, episode links move the whole room (before the page-change effect sees the click).
document.addEventListener("click", (e) => {
  if (!party || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey) return;
  const a = e.target instanceof Element ? e.target.closest("a[href]") : null;
  const m = a && new URL(a.href, location.href).pathname.match(/^\/watch\/([^/]+)\/(\d+)$/);
  if (!m || m[1] !== String(animeId)) return;
  e.preventDefault();
  goEpisode(Number(m[2]));
}, true);

// --- the page around the player --------------------------------------------------------------

const titleEl = document.getElementById("watch-title");
const metaEl = document.getElementById("watch-meta");
const actionsEl = document.getElementById("watch-actions");
const epsEl = document.getElementById("watch-eps");
const rangeNav = h("div", { style: { display: "flex", flexWrap: "wrap", gap: "8px", marginTop: "12px" } });
epsEl.after(rangeNav);

function renderActions() {
  clear(actionsEl);
  if (ep > 1) actionsEl.append(h("a.px-btn.dark.px-box.bevel.small", { href: epHref(ep - 1) }, h("span", { style: { transform: "scaleX(-1)", display: "grid" } }, sprite("skipNext", 1.4)), `EP ${ep - 1}`));
  if (aired && ep < aired) actionsEl.append(h("a.px-btn.px-box.bevel.small", { href: epHref(ep + 1) }, `EP ${ep + 1}`, sprite("skipNext", 1.4)));
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
  if (!party) {
    actionsEl.append(h("button.px-btn.dark.px-box.bevel.small", {
      type: "button", title: "Watch together: everyone with the link plays, pauses and seeks together",
      onclick: () => {
        partyCode = newPartyCode();
        window.history.replaceState(null, "", epHref(ep));
        joinParty();
        renderActions();
        renderEpisodes();
      },
    }, sprite("party", 1.4), "Watch party"));
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
    epsEl.append(h(`a.ep-btn.px-box${cls}`, { href: epHref(n), "aria-current": n === ep ? "page" : null },
      String(n), done && n !== ep ? h("span.mark", null, sprite("skullSmall", 2)) : null));
  }
  clear(rangeNav);
  if (start > 1) rangeNav.append(h("a.px-btn.dark.px-box.bevel.small", { href: epHref(start - RANGE) }, `${start - RANGE}-${start - 1}`));
  if (end < aired) rangeNav.append(h("a.px-btn.dark.px-box.bevel.small", { href: epHref(end + 1) }, `${end + 1}+`));
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
  mediaSession();
  history.onChange(renderEpisodes);
  if (a.status === "NOT_YET_RELEASED") {
    ++gen;
    teardown();
    player.failed("Not aired yet", `${title} has not started airing. Episodes appear once they air.`, [{ label: "Details", href: backHref }]);
  }
}).catch(() => { player.setTitle(`Episode ${ep}`); });

player.setTitle(`Episode ${ep}`);
renderActions();
if (partyCode) joinParty();
resolve();
