import os
import json
import html as html_lib
import tempfile
import webbrowser
HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AniVerse — __TITLE_ESC__ · Ep __EP_NUM__</title>
<script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
<script src="https://unpkg.com/lucide@latest"></script>
<style>
/* ── Reset & Variables ── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
:root {
  --bg: #0a0a0a;
  --surface: #141414;
  --surface2: #1f1f1f;
  --accent: #e50914;
  --text: #ffffff;
  --text-dim: #999;
  --border: #2a2a2a;
  --radius: 8px;
}
html, body { height: 100%; background: var(--bg); color: var(--text);
             font-family: 'Segoe UI', system-ui, sans-serif; overflow-x: hidden; }
 
/* ── Layout ── */
.watch-container { max-width: 1400px; margin: 0 auto; padding-bottom: 48px; }
 
/* ── Player wrapper & container ── */
.video-player-wrapper { width: 100%; background: #000; }
.player-container {
  position: relative; width: 100%; aspect-ratio: 16/9;
  background: #000; cursor: none; outline: none;
  user-select: none; overflow: hidden;
}
.player-container.controls-visible { cursor: default; }
video { width: 100%; height: 100%; display: block; object-fit: contain; }
 
/* ── Gradients ── */
.top-gradient-overlay {
  position: absolute; top: 0; left: 0; right: 0; height: 80px;
  background: linear-gradient(to bottom, rgba(0,0,0,.7) 0%, transparent 100%);
  pointer-events: none; z-index: 2;
}
 
/* ── Loading Spinner ── */
.loading-spinner {
  position: absolute; top: 50%; left: 50%; transform: translate(-50%,-50%);
  z-index: 10; display: none; align-items: center; justify-content: center;
}
.loading-spinner.visible { display: flex; }
.loading-spinner svg { width: 48px; height: 48px; color: var(--accent); animation: spin 1s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
 
/* ── Feedback Icons ── */
.feedback-overlay {
  position: absolute; top: 50%; left: 50%; transform: translate(-50%,-50%);
  z-index: 8; pointer-events: none; display: flex; align-items: center; justify-content: center;
}
.feedback-icon {
  display: none; width: 64px; height: 64px; color: white;
  filter: drop-shadow(0 0 8px rgba(0,0,0,.8));
}
.feedback-icon.show { display: block; animation: feedback-pop .45s ease-out forwards; }
.speed-overlay {
  display: none; font-size: 1.4rem; font-weight: 700; color: white;
  background: rgba(0,0,0,.65); padding: 8px 18px; border-radius: 6px;
}
.speed-overlay.show { display: block; animation: feedback-pop .45s ease-out forwards; }
@keyframes feedback-pop {
  0%   { opacity: 1; transform: scale(.8); }
  70%  { opacity: 1; transform: scale(1.1); }
  100% { opacity: 0; transform: scale(1); }
}
 
/* ── Ripple Seek Overlays ── */
.ripple-overlay {
  position: absolute; top: 0; bottom: 0; width: 25%;
  display: flex; align-items: center; justify-content: center;
  opacity: 0; pointer-events: none; z-index: 7; transition: opacity .15s ease;
}
.ripple-overlay.left  { left: 0;  background: radial-gradient(ellipse at left,  rgba(255,255,255,.12) 0%, transparent 70%); }
.ripple-overlay.right { right: 0; background: radial-gradient(ellipse at right, rgba(255,255,255,.12) 0%, transparent 70%); }
.ripple-overlay.show  { opacity: 1; }
.ripple-content { display: flex; flex-direction: column; align-items: center; color: white; font-size: .85rem; gap: 4px; }
.ripple-content svg { width: 28px; height: 28px; }
 
/* ── Toast ── */
.toast-container { position: absolute; top: 16px; right: 16px; z-index: 20; display: flex; flex-direction: column; gap: 8px; }
.toast {
  background: rgba(0,0,0,.88); border: 1px solid var(--border); color: white;
  padding: 8px 16px; border-radius: 6px; font-size: .85rem;
  animation: toast-in .25s ease forwards;
}
.toast.error { border-color: var(--accent); }
@keyframes toast-in { from { opacity: 0; transform: translateX(16px); } to { opacity: 1; transform: none; } }
 
/* ── Skip Buttons ── */
.skip-btn {
  position: absolute; bottom: 80px; right: 16px;
  display: none; align-items: center; gap: 6px;
  background: rgba(0,0,0,.8); border: 1px solid rgba(255,255,255,.3);
  color: white; padding: 8px 16px; border-radius: 4px; cursor: pointer;
  font-size: .9rem; font-weight: 500; z-index: 6; transition: background .2s, border-color .2s;
}
.skip-btn:hover { background: rgba(229,9,20,.8); border-color: var(--accent); }
.skip-btn.visible { display: flex; }
 
/* ── Controls Overlay ── */
.controls-overlay {
  position: absolute; bottom: 0; left: 0; right: 0;
  background: linear-gradient(to top, rgba(0,0,0,.88) 0%, rgba(0,0,0,.4) 60%, transparent 100%);
  padding: 12px 16px 16px;
  opacity: 0; transform: translateY(8px);
  transition: opacity .3s ease, transform .3s ease;
  z-index: 5;
}
.player-container.controls-visible .controls-overlay,
.player-container.paused .controls-overlay { opacity: 1 !important; transform: translateY(0) !important; }
 
/* ── Progress Bar ── */
.progress-container { padding: 8px 0; cursor: pointer; }
.progress-bar {
  position: relative; height: 4px; background: rgba(255,255,255,.25);
  border-radius: 2px; transition: height .2s ease;
}
.progress-container:hover .progress-bar { height: 6px; }
.progress-buffer, .progress-fill {
  position: absolute; top: 0; left: 0; height: 100%; border-radius: 2px; pointer-events: none;
}
.progress-buffer { background: rgba(255,255,255,.18); width: 0%; }
.progress-fill   { background: var(--accent); width: 0%; }
.progress-handle {
  position: absolute; top: 50%; left: 0%; transform: translate(-50%, -50%);
  width: 14px; height: 14px; background: white; border-radius: 50%;
  opacity: 0; transition: opacity .2s ease; box-shadow: 0 0 4px rgba(0,0,0,.5);
}
.progress-container:hover .progress-handle { opacity: 1; }
 
/* ── Controls Row ── */
.controls-row { display: flex; align-items: center; gap: 4px; margin-top: 4px; }
.controls-left, .controls-right { display: flex; align-items: center; gap: 4px; }
.spacer { flex: 1; }
.control-btn {
  background: none; border: none; color: white; cursor: pointer; padding: 6px;
  border-radius: 4px; display: flex; align-items: center; justify-content: center;
  transition: background .15s; flex-shrink: 0;
}
.control-btn:hover { background: rgba(255,255,255,.15); }
.control-btn svg { width: 20px; height: 20px; }
 
/* play/pause icon toggling */
.player-container         .icon-pause { display: none; }
.player-container.playing .icon-play  { display: none; }
.player-container.playing .icon-pause { display: block; }
 
/* volume icon toggling */
.control-btn .icon-vol-low,
.control-btn .icon-vol-mute { display: none; }
.player-container[data-vol="low"]  .icon-vol-high { display: none; }
.player-container[data-vol="low"]  .icon-vol-low  { display: block; }
.player-container[data-vol="mute"] .icon-vol-high,
.player-container[data-vol="mute"] .icon-vol-low  { display: none; }
.player-container[data-vol="mute"] .icon-vol-mute  { display: block; }
 
/* volume slider */
#volume-slider {
  -webkit-appearance: none; width: 80px; height: 4px;
  background: linear-gradient(to right, white 0%, white var(--vol-pct, 100%), rgba(255,255,255,.25) var(--vol-pct, 100%));
  border-radius: 2px; cursor: pointer; outline: none;
}
#volume-slider::-webkit-slider-thumb {
  -webkit-appearance: none; width: 12px; height: 12px;
  background: white; border-radius: 50%; cursor: pointer;
}
.volume-container { display: flex; align-items: center; gap: 4px; }
 
/* fullscreen icon toggling */
.player-container          .icon-min { display: none; }
.player-container.fullscreen .icon-max { display: none; }
.player-container.fullscreen .icon-min { display: block; }
 
/* time display */
.time-display {
  font-size: .8rem; color: rgba(255,255,255,.85); white-space: nowrap;
  margin-left: 4px; font-variant-numeric: tabular-nums;
}
 
/* ── Settings Menu ── */
.settings-menu {
  position: absolute; bottom: 70px; right: 16px;
  background: rgba(18,18,18,.97); backdrop-filter: blur(12px);
  border: 1px solid var(--border); border-radius: var(--radius);
  width: 280px; overflow: hidden; z-index: 20;
  opacity: 0; transform: scale(.95) translateY(8px);
  transform-origin: bottom right;
  transition: opacity .2s ease, transform .2s ease;
  pointer-events: none;
}
.settings-menu.open { opacity: 1; transform: scale(1) translateY(0); pointer-events: all; }
.settings-main, .settings-submenu { padding: 8px 0; }
.settings-submenu { display: none; }
.settings-submenu.active { display: block; }
.settings-item {
  display: flex; align-items: center; justify-content: space-between;
  padding: 10px 16px; cursor: pointer; transition: background .15s; font-size: .9rem;
}
.settings-item:hover { background: rgba(255,255,255,.07); }
.settings-item .label { display: flex; align-items: center; gap: 10px; color: var(--text-dim); }
.settings-item .label svg { width: 16px; height: 16px; }
.settings-item .value { display: flex; align-items: center; gap: 6px; color: white; font-size: .85rem; }
.settings-item .value svg { width: 14px; height: 14px; opacity: .6; }
.settings-header {
  display: flex; align-items: center; gap: 10px;
  padding: 10px 16px; cursor: pointer; font-weight: 600;
  border-bottom: 1px solid var(--border); margin-bottom: 4px;
}
.settings-header:hover { background: rgba(255,255,255,.05); }
.settings-header svg { width: 16px; height: 16px; }
.settings-option {
  padding: 9px 16px 9px 44px; cursor: pointer; font-size: .875rem;
  transition: background .15s; display: flex; align-items: center; justify-content: space-between;
}
.settings-option:hover { background: rgba(255,255,255,.07); }
.settings-option.active { color: var(--accent); }
.settings-option .check-icon { display: none; width: 14px; height: 14px; }
.settings-option.active .check-icon { display: block; }
 
/* ── Shortcut Overlay ── */
.shortcut-overlay {
  position: absolute; inset: 0; background: rgba(0,0,0,.78); backdrop-filter: blur(4px);
  z-index: 30; display: none; align-items: center; justify-content: center;
}
.shortcut-overlay.open { display: flex; }
.shortcut-modal {
  background: var(--surface); border: 1px solid var(--border); border-radius: 12px;
  padding: 24px; max-width: 480px; width: 90%; position: relative;
}
.shortcut-modal h3 { font-size: 1.1rem; margin-bottom: 16px; }
.shortcut-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
.sc-item { font-size: .85rem; color: var(--text-dim); }
.key {
  display: inline-block; background: var(--surface2); border: 1px solid var(--border);
  border-radius: 4px; padding: 2px 6px; font-family: monospace; font-size: .8rem; color: white;
}
.close-shortcuts {
  position: absolute; top: 12px; right: 12px;
  background: none; border: none; color: var(--text-dim); cursor: pointer; padding: 4px;
}
.close-shortcuts:hover { color: white; }
.close-shortcuts svg { width: 18px; height: 18px; }
 
/* ── Player Notice ── */
.player-notice {
  display: flex; align-items: center; justify-content: space-between;
  background: rgba(229,9,20,.1); border: 1px solid rgba(229,9,20,.3);
  border-top: none; padding: 10px 16px; font-size: .85rem;
}
.player-notice p { display: flex; align-items: center; gap: 8px; }
.notice-icon { width: 16px; height: 16px; color: var(--accent); flex-shrink: 0; }
.dismiss-btn { background: none; border: none; color: var(--text-dim); cursor: pointer; font-size: 1.2rem; }
 
/* ── Episode / Source Info ── */
.episode-info { padding: 16px 20px 8px; }
.episode-info h2 { font-size: 1.3rem; font-weight: 700; margin-bottom: 4px; }
.episode-info h3 { font-size: 1rem; color: var(--text-dim); font-weight: 400; }
 
/* ── Sources List ── */
.episode-list-container {
  margin: 12px 20px; background: var(--surface);
  border-radius: var(--radius); border: 1px solid var(--border); overflow: hidden;
}
.episode-list-header {
  display: flex; align-items: center; justify-content: space-between;
  padding: 12px 16px; font-weight: 600; cursor: pointer; border-bottom: 1px solid var(--border);
}
.episode-list-header:hover { background: rgba(255,255,255,.04); }
.episode-list-header svg { width: 16px; height: 16px; }
.episode-scroll-area {
  display: flex; flex-wrap: wrap; gap: 8px; padding: 12px 16px;
  max-height: 160px; overflow-y: auto;
}
.episode-scroll-area.hidden { display: none; }
.ep-btn {
  min-width: 52px; height: 36px; display: flex; align-items: center; justify-content: center;
  background: var(--surface2); border: 1px solid var(--border); border-radius: 4px;
  color: var(--text-dim); font-size: .85rem; cursor: pointer; text-decoration: none;
  padding: 0 8px; transition: all .15s ease;
}
.ep-btn:hover { background: rgba(255,255,255,.12); color: white; border-color: rgba(255,255,255,.3); }
.ep-btn.active { background: var(--accent); border-color: var(--accent); color: white; }
 
/* Scrollbar */
::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
</style>
</head>
<body>
<div class="watch-container">
 
  <!-- ── Player ── -->
  <div class="video-player-wrapper" id="player-wrapper">
    <div class="player-container" id="player-container" tabindex="0">
      <video id="video" playsinline crossorigin="anonymous"></video>
 
      <!-- Loading -->
      <div class="loading-spinner" id="loading-spinner">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83
                   M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/>
        </svg>
      </div>
 
      <div class="top-gradient-overlay"></div>
 
      <!-- Visual Feedback -->
      <div class="feedback-overlay" id="feedback-overlay">
        <i data-lucide="play"     class="feedback-icon" id="fb-play"></i>
        <i data-lucide="pause"    class="feedback-icon" id="fb-pause"></i>
        <i data-lucide="volume-2" class="feedback-icon" id="fb-vol-up"></i>
        <i data-lucide="volume-x" class="feedback-icon" id="fb-vol-mute"></i>
        <div class="speed-overlay" id="fb-speed">1x</div>
      </div>
 
      <!-- Ripple Seek -->
      <div class="ripple-overlay left" id="ripple-left">
        <div class="ripple-content">
          <i data-lucide="rewind"></i><span>-10s</span>
        </div>
      </div>
      <div class="ripple-overlay right" id="ripple-right">
        <div class="ripple-content">
          <i data-lucide="fast-forward"></i><span>+10s</span>
        </div>
      </div>
 
      <div class="toast-container" id="toast-container"></div>
 
      <!-- Skip Buttons -->
      <button id="skip-intro" class="skip-btn">
        <span>Skip Intro</span> <i data-lucide="chevrons-right"></i>
      </button>
      <button id="skip-outro" class="skip-btn">
        <span>Skip Outro</span> <i data-lucide="chevrons-right"></i>
      </button>
 
      <!-- Controls Overlay -->
      <div class="controls-overlay" id="controls-overlay">
        <div class="progress-container" id="progress-container">
          <div class="progress-bar" id="progress-bar">
            <div class="progress-buffer" id="progress-buffer"></div>
            <div class="progress-fill"   id="progress-fill"></div>
            <div class="progress-handle" id="progress-handle"></div>
          </div>
        </div>
        <div class="controls-row">
          <div class="controls-left">
            <button id="prev-10s-btn" class="control-btn" title="Rewind 10s (J)">
              <i data-lucide="rotate-ccw"></i>
            </button>
            <button id="play-btn" class="control-btn" title="Play/Pause (Space)">
              <i data-lucide="play"  class="icon-play"></i>
              <i data-lucide="pause" class="icon-pause"></i>
            </button>
            <button id="next-10s-btn" class="control-btn" title="Forward 10s (L)">
              <i data-lucide="rotate-cw"></i>
            </button>
            <button id="next-ep-btn" class="control-btn" title="Next Episode (N)" style="display:none">
              <i data-lucide="skip-forward"></i>
            </button>
            <div class="volume-container">
              <button id="mute-btn" class="control-btn" title="Mute (M)">
                <i data-lucide="volume-2" class="icon-vol-high"></i>
                <i data-lucide="volume-1" class="icon-vol-low"></i>
                <i data-lucide="volume-x" class="icon-vol-mute"></i>
              </button>
              <input type="range" id="volume-slider" min="0" max="1" step="0.05" value="1">
            </div>
            <span class="time-display" id="time-display">0:00 / 0:00</span>
          </div>
          <div class="spacer"></div>
          <div class="controls-right">
            <button id="subs-btn"      class="control-btn" title="Subtitles (C)"><i data-lucide="subtitles"></i></button>
            <button id="settings-btn"  class="control-btn" title="Settings (S)"><i data-lucide="settings"></i></button>
            <button id="fullscreen-btn" class="control-btn" title="Fullscreen (F)">
              <i data-lucide="maximize" class="icon-max"></i>
              <i data-lucide="minimize" class="icon-min"></i>
            </button>
          </div>
        </div>
      </div>
 
      <!-- Settings Menu -->
      <div class="settings-menu" id="settings-menu">
        <div class="settings-main" id="settings-main">
          <div class="settings-item" data-target="audio">
            <div class="label"><i data-lucide="headphones"></i> Audio</div>
            <div class="value"><span id="current-audio">__CATEGORY_UPPER__</span> <i data-lucide="chevron-right"></i></div>
          </div>
          <div class="settings-item" data-target="source">
            <div class="label"><i data-lucide="server"></i> Source</div>
            <div class="value"><span id="current-source">—</span> <i data-lucide="chevron-right"></i></div>
          </div>
          <div class="settings-item" data-target="quality">
            <div class="label"><i data-lucide="monitor"></i> Quality</div>
            <div class="value"><span id="current-quality">Auto</span> <i data-lucide="chevron-right"></i></div>
          </div>
          <div class="settings-item" data-target="speed">
            <div class="label"><i data-lucide="gauge"></i> Speed</div>
            <div class="value"><span id="current-speed">Normal</span> <i data-lucide="chevron-right"></i></div>
          </div>
          <div class="settings-item" data-target="subs">
            <div class="label"><i data-lucide="subtitles"></i> Subtitles</div>
            <div class="value"><span id="current-subs">Off</span> <i data-lucide="chevron-right"></i></div>
          </div>
        </div>
        <!-- Sub-menus -->
        <div class="settings-submenu" id="submenu-audio">
          <div class="settings-header" id="back-audio"><i data-lucide="chevron-left"></i> Audio</div>
          <div id="settings-audio-options"></div>
        </div>
        <div class="settings-submenu" id="submenu-source">
          <div class="settings-header" id="back-source"><i data-lucide="chevron-left"></i> Source</div>
          <div id="settings-source-options"></div>
        </div>
        <div class="settings-submenu" id="submenu-quality">
          <div class="settings-header" id="back-quality"><i data-lucide="chevron-left"></i> Quality</div>
          <div id="settings-quality-options"></div>
        </div>
        <div class="settings-submenu" id="submenu-speed">
          <div class="settings-header" id="back-speed"><i data-lucide="chevron-left"></i> Speed</div>
          <div id="settings-speed-options"></div>
        </div>
        <div class="settings-submenu" id="submenu-subs">
          <div class="settings-header" id="back-subs"><i data-lucide="chevron-left"></i> Subtitles</div>
          <div id="settings-subs-options"></div>
        </div>
      </div>
 
      <!-- Shortcut Help -->
      <div class="shortcut-overlay" id="shortcut-overlay">
        <div class="shortcut-modal">
          <h3>Keyboard Shortcuts</h3>
          <div class="shortcut-grid">
            <div class="sc-item"><span class="key">SPACE</span> / <span class="key">K</span> Play/Pause</div>
            <div class="sc-item"><span class="key">J</span> / <span class="key">←</span> Rewind 10s</div>
            <div class="sc-item"><span class="key">L</span> / <span class="key">→</span> Forward 10s</div>
            <div class="sc-item"><span class="key">F</span> Fullscreen</div>
            <div class="sc-item"><span class="key">M</span> Mute</div>
            <div class="sc-item"><span class="key">↑</span> / <span class="key">↓</span> Volume</div>
            <div class="sc-item"><span class="key">N</span> Next Ep</div>
            <div class="sc-item"><span class="key">?</span> Toggle Help</div>
          </div>
          <button class="close-shortcuts" id="close-shortcuts"><i data-lucide="x"></i></button>
        </div>
      </div>
    </div><!-- /.player-container -->
  </div><!-- /.video-player-wrapper -->
 
  <!-- Notice -->
  <div class="player-notice" id="player-notice">
    <p>
      <i data-lucide="info" class="notice-icon"></i>
      <span>If video fails, try changing <strong>Source</strong> or <strong>Audio</strong> in settings.</span>
    </p>
    <button class="dismiss-btn" onclick="document.getElementById('player-notice').style.display='none'">×</button>
  </div>
 
  <!-- Episode Info -->
  <div class="episode-info">
    <h2>__TITLE_ESC__</h2>
    <h3>Episode __EP_NUM__ &nbsp;·&nbsp; __CATEGORY_UPPER__</h3>
  </div>
 
  <!-- Sources Panel -->
  <div class="episode-list-container">
    <div class="episode-list-header" onclick="this.nextElementSibling.classList.toggle('hidden')">
      <span>Sources</span>
      <i data-lucide="chevron-down"></i>
    </div>
    <div class="episode-scroll-area" id="sources-list"></div>
  </div>
 
</div><!-- /.watch-container -->
 
<script>
// ─── Embedded stream data ───────────────────────────────────────────────────
const STREAMS   = __STREAMS__;
const SUBTITLES = __SUBTITLES__;
const CATEGORY  = __CATEGORY_JSON__;
const TITLE     = __TITLE_JSON__;
const EP_NUM    = __EP_NUM__;
 
// ─── Player ────────────────────────────────────────────────────────────────
class AniVersePlayer {
  constructor() {
    this.video      = document.getElementById('video');
    this.container  = document.getElementById('player-container');
    this.hls        = null;
    this.streams    = STREAMS;
    this.subtitles  = SUBTITLES;
    this.curStream  = 0;
    this.curSub     = -1;
    this.qualities  = [];
    this.prevVol    = 1;
    this.hideTimer  = null;
    this.dragging   = false;
    this.speeds     = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
    this.speedLabels= ['0.25x','0.5x','0.75x','Normal','1.25x','1.5x','1.75x','2x'];
  }
 
  // ── Initialise ────────────────────────────────────────────────────────────
  init() {
    this.bindEvents();
    this.buildSettings();
    if (this.streams.length) this.loadStream(0);
    lucide.createIcons();
  }
 
  // ── Settings builder ─────────────────────────────────────────────────────
  buildSettings() {
    // Audio
    document.getElementById('settings-audio-options').innerHTML =
      ['Sub','Dub'].map(a => `
        <div class="settings-option ${CATEGORY.toLowerCase()===a.toLowerCase()?'active':''}"
             data-audio="${a.toLowerCase()}">
          ${a}<i data-lucide="check" class="check-icon"></i>
        </div>`).join('');
 
    // Sources
    this._rebuildSources();
 
    // Speed
    document.getElementById('settings-speed-options').innerHTML =
      this.speeds.map((s,i) => `
        <div class="settings-option ${s===1?'active':''}" data-speed="${s}">
          ${this.speedLabels[i]}<i data-lucide="check" class="check-icon"></i>
        </div>`).join('');
 
    // Subs
    this._rebuildSubs();
 
    // Sources list panel at bottom
    document.getElementById('sources-list').innerHTML =
      this.streams.map((s,i) => `
        <a class="ep-btn ${i===0?'active':''}" href="#"
           onclick="player.loadStream(${i});return false;">
          ${s.server||('S'+(i+1))}
        </a>`).join('');
  }
 
  _rebuildSources() {
    document.getElementById('settings-source-options').innerHTML =
      this.streams.map((s,i) => `
        <div class="settings-option ${i===0?'active':''}" data-source="${i}">
          ${s.server||('Server '+(i+1))}<i data-lucide="check" class="check-icon"></i>
        </div>`).join('');
    if (this.streams[0])
      document.getElementById('current-source').textContent =
        this.streams[0].server || 'Server 1';
  }
 
  _rebuildSubs() {
    const off = `<div class="settings-option active" data-sub="-1">
                   Off<i data-lucide="check" class="check-icon"></i></div>`;
    const tracks = this.subtitles.map((s,i) => `
      <div class="settings-option" data-sub="${i}">
        ${s.label||('Track '+(i+1))}<i data-lucide="check" class="check-icon"></i>
      </div>`).join('');
    document.getElementById('settings-subs-options').innerHTML = off + tracks;
  }
 
  // ── Stream loading ───────────────────────────────────────────────────────
  loadStream(idx) {
    this.curStream = idx;
    const stream = this.streams[idx];
    if (!stream) return;
 
    this.showSpinner(true);
 
    // Update active source highlights
    document.querySelectorAll('[data-source]').forEach(el =>
      el.classList.toggle('active', +el.dataset.source === idx));
    document.querySelectorAll('#sources-list .ep-btn').forEach((el,i) =>
      el.classList.toggle('active', i === idx));
    document.getElementById('current-source').textContent =
      stream.server || `Server ${idx+1}`;
 
    // Tear down previous HLS instance
    if (this.hls) { this.hls.destroy(); this.hls = null; }
 
    const url = stream.url;
    const isHLS = /\.m3u8|m3u8/i.test(url);
 
    if (isHLS && Hls.isSupported()) {
      this.hls = new Hls({ startLevel: -1, maxBufferLength: 30 });
      this.hls.loadSource(url);
      this.hls.attachMedia(this.video);
      this.hls.on(Hls.Events.MANIFEST_PARSED, (_e, data) => {
        this._buildQuality(data.levels);
        this.video.play().catch(()=>{});
        this.showSpinner(false);
      });
      this.hls.on(Hls.Events.ERROR, (_e, data) => {
        if (data.fatal) { this.toast('Stream error — try another source.','error'); this.showSpinner(false); }
      });
    } else {
      // Native (MP4 / native HLS on Safari)
      this.video.src = url;
      this.video.play().catch(()=>{});
      this.showSpinner(false);
    }
 
    this._applySubtitles();
  }
 
  _buildQuality(levels) {
    this.qualities = levels;
    const opts = document.getElementById('settings-quality-options');
    opts.innerHTML =
      `<div class="settings-option active" data-quality="-1">Auto<i data-lucide="check" class="check-icon"></i></div>` +
      levels.map((l,i) => `
        <div class="settings-option" data-quality="${i}">
          ${l.height ? l.height+'p' : 'Level '+(i+1)}
          <i data-lucide="check" class="check-icon"></i>
        </div>`).join('');
    document.getElementById('current-quality').textContent = 'Auto';
    lucide.createIcons();
  }
 
  // ── Subtitle tracks ───────────────────────────────────────────────────────
  _applySubtitles() {
    // Remove old tracks
    Array.from(this.video.querySelectorAll('track')).forEach(t => t.remove());
    this.curSub = -1;
    document.getElementById('current-subs').textContent = 'Off';
 
    this.subtitles.forEach((sub, i) => {
      const t = document.createElement('track');
      t.kind    = 'subtitles';
      t.label   = sub.label || `Track ${i+1}`;
      t.src     = sub.file  || sub.url || '';
      t.default = false;
      this.video.appendChild(t);
    });
  }
 
  setSub(idx) {
    this.curSub = idx;
    const tracks = this.video.textTracks;
    for (let i = 0; i < tracks.length; i++) tracks[i].mode = 'disabled';
    if (idx >= 0 && tracks[idx]) {
      tracks[idx].mode = 'showing';
      document.getElementById('current-subs').textContent =
        this.subtitles[idx]?.label || `Track ${idx+1}`;
    } else {
      document.getElementById('current-subs').textContent = 'Off';
    }
    document.querySelectorAll('[data-sub]').forEach(el =>
      el.classList.toggle('active', +el.dataset.sub === idx));
    lucide.createIcons();
  }
 
  // ── Event binding ─────────────────────────────────────────────────────────
  bindEvents() {
    const v  = this.video;
    const c  = this.container;
 
    // Play / Pause
    document.getElementById('play-btn').addEventListener('click', () => this.togglePlay());
    v.addEventListener('click', () => this.togglePlay());
 
    // Video state
    v.addEventListener('waiting', ()  => this.showSpinner(true));
    v.addEventListener('canplay', ()  => this.showSpinner(false));
    v.addEventListener('playing', ()  => { this.showSpinner(false); c.classList.add('playing'); });
    v.addEventListener('pause',   ()  => { c.classList.remove('playing'); c.classList.add('paused'); this.showControls(); });
    v.addEventListener('play',    ()  => c.classList.remove('paused'));
    v.addEventListener('ended',   ()  => c.classList.remove('playing'));
    v.addEventListener('timeupdate',  () => this.updateProgress());
    v.addEventListener('progress',    () => this.updateBuffer());
 
    // Volume
    const slider = document.getElementById('volume-slider');
    slider.addEventListener('input', () => { v.volume = +slider.value; this.updateVolumeUI(); });
    document.getElementById('mute-btn').addEventListener('click', () => this.toggleMute());
 
    // Seek
    const pc = document.getElementById('progress-container');
    pc.addEventListener('mousedown', e => { this.dragging = true; this._seek(e); });
    document.addEventListener('mousemove', e => { if (this.dragging) this._seek(e); });
    document.addEventListener('mouseup',   () => { this.dragging = false; });
    pc.addEventListener('touchstart', e => { this.dragging = true; this._seek(e.touches[0]); }, { passive: true });
    document.addEventListener('touchmove', e => { if (this.dragging) this._seek(e.touches[0]); }, { passive: true });
    document.addEventListener('touchend',  () => { this.dragging = false; });
 
    // Skip 10s
    document.getElementById('prev-10s-btn').addEventListener('click', () =>
      { v.currentTime = Math.max(0, v.currentTime - 10); this.ripple('left'); });
    document.getElementById('next-10s-btn').addEventListener('click', () =>
      { v.currentTime = Math.min(v.duration||0, v.currentTime + 10); this.ripple('right'); });
 
    // Fullscreen
    document.getElementById('fullscreen-btn').addEventListener('click', () => this.toggleFullscreen());
    document.addEventListener('fullscreenchange', () => {
      c.classList.toggle('fullscreen', !!document.fullscreenElement);
      lucide.createIcons();
    });
 
    // Settings open / close
    document.getElementById('settings-btn').addEventListener('click', e => {
      e.stopPropagation(); this.toggleSettings();
    });
    document.getElementById('subs-btn').addEventListener('click', () =>
      this.openSub('subs'));
 
    // Settings items
    document.querySelectorAll('.settings-item').forEach(item =>
      item.addEventListener('click', () => this.openSub(item.dataset.target)));
 
    // Back headers
    ['audio','source','quality','speed','subs'].forEach(name => {
      document.getElementById(`back-${name}`).addEventListener('click', () => this.closeSub());
    });
 
    // Settings option clicks (delegated)
    document.getElementById('settings-menu').addEventListener('click', e => {
      const opt = e.target.closest('.settings-option');
      if (!opt) return;
 
      if (opt.dataset.source !== undefined) {
        this.loadStream(+opt.dataset.source);
        this.closeSettings();
 
      } else if (opt.dataset.quality !== undefined) {
        const lvl = +opt.dataset.quality;
        if (this.hls) this.hls.currentLevel = lvl;
        document.getElementById('current-quality').textContent =
          lvl === -1 ? 'Auto' : (this.qualities[lvl]?.height + 'p' || `Level ${lvl}`);
        document.querySelectorAll('[data-quality]').forEach(el =>
          el.classList.toggle('active', +el.dataset.quality === lvl));
        lucide.createIcons();
        this.closeSettings();
 
      } else if (opt.dataset.speed !== undefined) {
        const spd = +opt.dataset.speed;
        v.playbackRate = spd;
        const lbl = spd === 1 ? 'Normal' : spd + 'x';
        document.getElementById('current-speed').textContent = lbl;
        document.querySelectorAll('[data-speed]').forEach(el =>
          el.classList.toggle('active', +el.dataset.speed === spd));
        lucide.createIcons();
        this.feedback('speed', lbl + ' Speed');
        this.closeSettings();
 
      } else if (opt.dataset.sub !== undefined) {
        this.setSub(+opt.dataset.sub);
        this.closeSettings();
 
      } else if (opt.dataset.audio !== undefined) {
        document.getElementById('current-audio').textContent =
          opt.dataset.audio.charAt(0).toUpperCase() + opt.dataset.audio.slice(1);
        document.querySelectorAll('[data-audio]').forEach(el =>
          el.classList.toggle('active', el.dataset.audio === opt.dataset.audio));
        lucide.createIcons();
        this.toast('Audio preference updated. Reload streams to apply.', 'info');
        this.closeSettings();
      }
    });
 
    // Click outside settings to close
    c.addEventListener('click', e => {
      if (!e.target.closest('#settings-menu') && !e.target.closest('#settings-btn'))
        this.closeSettings();
    });
 
    // Mouse controls visibility
    c.addEventListener('mousemove', () => this.showControls());
    c.addEventListener('mouseleave', () => { if (!v.paused) this.startHideTimer(); });
 
    // Keyboard shortcuts
    document.addEventListener('keydown', e => {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
      switch (e.key) {
        case ' ': case 'k': case 'K':
          e.preventDefault(); this.togglePlay(); break;
        case 'j': case 'J': case 'ArrowLeft':
          e.preventDefault(); v.currentTime -= 10; this.ripple('left'); break;
        case 'l': case 'L': case 'ArrowRight':
          e.preventDefault(); v.currentTime += 10; this.ripple('right'); break;
        case 'ArrowUp':
          e.preventDefault();
          v.volume = Math.min(1, v.volume + 0.1); this.updateVolumeUI(); this.feedback('vol-up'); break;
        case 'ArrowDown':
          e.preventDefault();
          v.volume = Math.max(0, v.volume - 0.1); this.updateVolumeUI(); break;
        case 'f': case 'F': this.toggleFullscreen(); break;
        case 'm': case 'M': this.toggleMute(); break;
        case 's': case 'S': this.toggleSettings(); break;
        case 'c': case 'C': this.openSub('subs'); break;
        case '?':
          document.getElementById('shortcut-overlay').classList.toggle('open'); break;
        case 'Escape':
          document.getElementById('shortcut-overlay').classList.remove('open');
          this.closeSettings(); break;
      }
    });
 
    // Close shortcut modal
    document.getElementById('close-shortcuts').addEventListener('click', () =>
      document.getElementById('shortcut-overlay').classList.remove('open'));
 
    // Double-tap seek (mobile)
    let lastTap = 0, lastZone = '';
    c.addEventListener('touchend', e => {
      const x = e.changedTouches[0].clientX;
      const rect = c.getBoundingClientRect();
      const zone = x < rect.left + rect.width / 2 ? 'left' : 'right';
      const now = Date.now();
      if (now - lastTap < 300 && zone === lastZone) {
        v.currentTime += zone === 'left' ? -10 : 10;
        this.ripple(zone);
      }
      lastTap = now; lastZone = zone;
    });
  }
 
  // ── Helpers ───────────────────────────────────────────────────────────────
  togglePlay() {
    if (this.video.paused) { this.video.play(); this.feedback('play'); }
    else                   { this.video.pause(); this.feedback('pause'); }
  }
 
  toggleMute() {
    const v = this.video;
    if (v.muted || v.volume === 0) {
      v.muted = false; v.volume = this.prevVol || 0.5; this.feedback('vol-up');
    } else {
      this.prevVol = v.volume; v.muted = true; this.feedback('vol-mute');
    }
    this.updateVolumeUI();
  }
 
  updateVolumeUI() {
    const v = this.video;
    const vol = v.muted ? 0 : v.volume;
    const slider = document.getElementById('volume-slider');
    slider.value = v.volume;
    slider.style.setProperty('--vol-pct', (v.volume * 100) + '%');
    const c = this.container;
    if (vol === 0 || v.muted)  c.dataset.vol = 'mute';
    else if (vol < 0.5)        c.dataset.vol = 'low';
    else                       delete c.dataset.vol;
    lucide.createIcons();
  }
 
  _seek(e) {
    const bar  = document.getElementById('progress-container');
    const rect = bar.getBoundingClientRect();
    const pct  = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    this.video.currentTime = pct * (this.video.duration || 0);
  }
 
  updateProgress() {
    const v = this.video;
    if (!v.duration) return;
    const pct = (v.currentTime / v.duration) * 100;
    document.getElementById('progress-fill').style.width   = pct + '%';
    document.getElementById('progress-handle').style.left  = `calc(${pct}% - 6px)`;
    document.getElementById('time-display').textContent    =
      `${this.fmt(v.currentTime)} / ${this.fmt(v.duration)}`;
  }
 
  updateBuffer() {
    const v = this.video;
    if (!v.duration || !v.buffered.length) return;
    const pct = (v.buffered.end(v.buffered.length - 1) / v.duration) * 100;
    document.getElementById('progress-buffer').style.width = pct + '%';
  }
 
  fmt(s) {
    if (!s || isNaN(s)) return '0:00';
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = String(Math.floor(s % 60)).padStart(2, '0');
    return h > 0 ? `${h}:${String(m).padStart(2,'0')}:${sec}` : `${m}:${sec}`;
  }
 
  toggleFullscreen() {
    if (!document.fullscreenElement) this.container.requestFullscreen().catch(()=>{});
    else document.exitFullscreen().catch(()=>{});
  }
 
  showSpinner(on) {
    document.getElementById('loading-spinner').classList.toggle('visible', on);
  }
 
  showControls() {
    this.container.classList.add('controls-visible');
    clearTimeout(this.hideTimer);
    this.startHideTimer();
  }
 
  startHideTimer() {
    this.hideTimer = setTimeout(() => {
      if (!this.video.paused) this.container.classList.remove('controls-visible');
    }, 3000);
  }
 
  toggleSettings() {
    const m = document.getElementById('settings-menu');
    if (m.classList.contains('open')) { this.closeSettings(); }
    else { m.classList.add('open'); this.closeSub(); }
  }
 
  closeSettings() {
    document.getElementById('settings-menu').classList.remove('open');
    this.closeSub();
  }
 
  openSub(name) {
    document.getElementById('settings-menu').classList.add('open');
    document.getElementById('settings-main').style.display = 'none';
    document.querySelectorAll('.settings-submenu').forEach(s => s.classList.remove('active'));
    document.getElementById(`submenu-${name}`).classList.add('active');
    lucide.createIcons();
  }
 
  closeSub() {
    document.getElementById('settings-main').style.display = '';
    document.querySelectorAll('.settings-submenu').forEach(s => s.classList.remove('active'));
  }
 
  feedback(type, text) {
    const map = { play:'fb-play', pause:'fb-pause', 'vol-up':'fb-vol-up', 'vol-mute':'fb-vol-mute', speed:'fb-speed' };
    const el = document.getElementById(map[type]);
    if (!el) return;
    if (type === 'speed') el.textContent = text;
    el.classList.remove('show');
    void el.offsetWidth;            // force reflow for re-animation
    el.classList.add('show');
    setTimeout(() => el.classList.remove('show'), 450);
    lucide.createIcons();
  }
 
  ripple(side) {
    const el = document.getElementById(`ripple-${side}`);
    el.classList.add('show');
    setTimeout(() => el.classList.remove('show'), 450);
  }
 
  toast(msg, type = 'info') {
    const tc = document.getElementById('toast-container');
    const t  = document.createElement('div');
    t.className = 'toast' + (type === 'error' ? ' error' : '');
    t.textContent = msg;
    tc.appendChild(t);
    setTimeout(() => t.remove(), 3500);
  }
}
 
const player = new AniVersePlayer();
player.init();
</script>
</body>
</html>
"""
def get_player(title: str, ep_num: int, category: str, streams_data: dict) -> str:
    streams     = streams_data.get("streams", [])
    subtitles   = streams_data.get("subtitles", [])
    return (
        HTML_TEMPLATE
        .replace("__STREAMS__",         json.dumps(streams))
        .replace("__SUBTITLES__",       json.dumps(subtitles))
        .replace("__TITLE_ESC__",       html_lib.escape(title))
        .replace("__TITLE_JSON__",      json.dumps(title))
        .replace("__EP_NUM__",          str(ep_num))
        .replace("__CATEGORY_JSON__",   json.dumps(category))
        .replace("__CATEGORY__UPPER__", category.upper())
    )
def open_browser_player(title: str, ep_num: int, category: str, streams_data: dict) -> None:
    html_content = get_player_html(title, ep_num, category, streams_data)
    fd, path = tempfile.mkstemp(suffix=".html", prefix="aniverse_vid_player_")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(html_content)
    webbrowser.open(f"file://{path}")