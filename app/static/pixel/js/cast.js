// Chromecast from the website, through Google's Cast sender library -- Chrome
// on https only; anywhere else castReady() is false and the option never shows.
// The TV fetches the stream and subtitles from the AniVerse proxy itself (the
// proxy answers cross-origin for it), so the page only hands over the URLs and
// then acts as the remote. The app does the same in CastBridge.kt.
const SDK = "https://www.gstatic.com/cv/js/sender/v1/cast_sender.js?loadCastFramework=1";

let ready = null;
let ctx = null, remote = null, control = null;
let device = null, lastTime = 0;
const listeners = new Set();

/** Resolves true once this browser can cast (the SDK loads on first call). */
export function castReady() {
  if (ready) return ready;
  ready = new Promise((resolve) => {
    if (!window.chrome || !window.isSecureContext) return resolve(false);
    const give = setTimeout(() => resolve(false), 10000);
    window.__onGCastApiAvailable = (ok) => {
      clearTimeout(give);
      if (!ok) return resolve(false);
      try { setUp(); resolve(true); } catch { resolve(false); }
    };
    const s = document.createElement("script");
    s.src = SDK;
    s.async = true;
    s.onerror = () => { clearTimeout(give); resolve(false); };
    document.head.append(s);
  });
  return ready;
}

function setUp() {
  const fw = window.cast.framework;
  ctx = fw.CastContext.getInstance();
  ctx.setOptions({
    receiverApplicationId: window.chrome.cast.media.DEFAULT_MEDIA_RECEIVER_APP_ID,
    autoJoinPolicy: window.chrome.cast.AutoJoinPolicy.ORIGIN_SCOPED,
  });
  remote = new fw.RemotePlayer();
  control = new fw.RemotePlayerController(remote);
  control.addEventListener(fw.RemotePlayerEventType.CURRENT_TIME_CHANGED, () => {
    if (remote.currentTime > 0) lastTime = remote.currentTime;
  });
  ctx.addEventListener(fw.CastContextEventType.SESSION_STATE_CHANGED, (e) => {
    const S = fw.SessionState;
    if (e.sessionState === S.SESSION_STARTED || e.sessionState === S.SESSION_RESUMED) {
      device = ctx.getCurrentSession()?.getCastDevice()?.friendlyName || "TV";
      lastTime = 0;
      listeners.forEach((fn) => fn({ device, position: 0 }));
    } else if (e.sessionState === S.SESSION_ENDED && device) {
      device = null;
      listeners.forEach((fn) => fn({ device: null, position: lastTime }));
    }
  });
}

/** The TV being cast to, by name, or null. */
export const castDevice = () => device;

/** fn({device, position}) when a cast starts (device set) or ends (position: where the TV got to, seconds). */
export function onCastChange(fn) { listeners.add(fn); }

/** Chrome's device picker. */
export function startCast() { ctx?.requestSession().catch(() => {}); }

export function stopCast() { ctx?.endCurrentSession(true); }

export function castPlayPause() { control?.playOrPause(); }

/** Hands the episode over: absolute URLs the TV can reach, from `position` seconds. */
export async function castLoad({ url, title, subtitle, position = 0, subtitles = null, hls = true }) {
  const session = ctx?.getCurrentSession();
  if (!session) return false;
  const m = window.chrome.cast.media;
  const info = new m.MediaInfo(url, hls ? "application/x-mpegURL" : "video/mp4");
  info.streamType = m.StreamType.BUFFERED;
  info.metadata = new m.GenericMediaMetadata();
  info.metadata.title = title;
  info.metadata.subtitle = subtitle;
  if (subtitles) {
    const t = new m.Track(1, m.TrackType.TEXT);
    t.trackContentId = subtitles;
    t.trackContentType = "text/vtt";
    t.subtype = m.TextTrackType.SUBTITLES;
    t.name = "Subtitles";
    info.tracks = [t];
  }
  const req = new m.LoadRequest(info);
  req.autoplay = true;
  req.currentTime = position;
  if (subtitles) req.activeTrackIds = [1];
  try { await session.loadMedia(req); return true; } catch { return false; }
}
