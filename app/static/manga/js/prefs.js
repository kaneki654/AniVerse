// Settings: palette, sound, data saver, subtitle style and alerts. Kept in this
// browser; the app has the same choices in its own Settings screen.
import { h, clear, sprite } from "./px.js";
import { settings } from "./settings.js";
import { playIntro } from "./intro.js";
import { push } from "./push.js";
import { toast } from "./px.js";
import { sfx } from "./sfx.js";
import { initShell } from "./ui.js";

initShell();
const root = document.getElementById("page-root");

/** Manga or pixel: the server sends the pages in the look this cookie names. */
function lookSetting(current) {
  const sel = h("select.px-select", {
    "aria-label": "Look",
    onchange: () => {
      document.cookie = `av_look=${sel.value}; path=/; max-age=31536000; samesite=lax`;
      location.reload();
    },
  }, h("option", { value: "manga", selected: current === "manga" }, "Manga"), h("option", { value: "pixel", selected: current === "pixel" }, "Pixel art"));
  return h("div.setting.px-box", null,
    h("div", null, h("b", null, "Look"), h("span", null, "Manga: ink, paper and panels. Pixel art: the pixel look, with its palettes.")), sel);
}

function toggle(key, label, text, onChange) {
  const s = settings.get();
  return h("div.setting.px-box", null,
    h("div", null, h("b", null, label), h("span", null, text)),
    h("button.px-switch", {
      type: "button", role: "switch", "aria-checked": String(!!s[key]), "aria-label": label,
      onclick: async (e) => {
        const btn = e.currentTarget;
        const next = !settings.get()[key];
        if (onChange && !(await onChange(next))) return;
        settings.set({ [key]: next });
        btn.setAttribute("aria-checked", String(next));
        sfx("select");
      },
    }));
}

/** A dropdown; `parse` turns the option text back into the stored value. */
function choice(key, label, text, options, parse = (v) => v) {
  const current = String(settings.get()[key]);
  const sel = h("select.px-select", {
    "aria-label": label,
    onchange: () => { settings.set({ [key]: parse(sel.value) }); sfx("select"); },
  }, Object.entries(options).map(([v, t]) => h("option", { value: v, selected: current === v }, t)));
  return h("div.setting.px-box", null, h("div", null, h("b", null, label), h("span", null, text)), sel);
}

function render() {
  const s = settings.get();
  clear(root).append(
    h("section.setting-group", null,
      lookSetting("manga"),
      toggle("intro", "Intro", "The manga opening on your first page of a visit: panels inking in, the logo landing. Click it to skip."),
      h("button.px-btn.dark.px-box.small", {
        type: "button", style: { marginTop: "12px" },
        onclick: () => { try { sessionStorage.removeItem("av.intro"); } catch { /* storage off */ } playIntro(); },
      }, sprite("play", 1.4), "Replay intro")),
    h("section.setting-group", null,
      choice("effects", "Effects", "The animation in the background, on clicks and on buttons. Lite is lighter on the battery; Off keeps the page still.",
        { full: "Full", lite: "Lite", off: "Off" }, (v) => { setTimeout(() => location.reload(), 150); return v; }),
      toggle("contrast", "High contrast", "Brighter secondary text on any palette, for low vision. Your browser's zoom makes text bigger.")),
    h("section.setting-group", null,
      toggle("sfx", "Sound effects", "Paper, ink and impact sounds: clicks, page turns, hits and achievements."),
      choice("volume", "Effects volume", "How loud the sound effects are.", { "0.15": "Quiet", "0.35": "Normal", "0.7": "Loud" }, Number)),
    h("section.setting-group", null,
      toggle("dataSaver", "Data saver", "Always play the lowest quality to save mobile data."),
      choice("subSize", "Subtitle size", "How big subtitles are drawn.", { s: "Small", m: "Medium", l: "Large", xl: "Extra large" }),
      toggle("subBg", "Subtitle background", "A dark box behind subtitles, for bright scenes."),
      choice("subLang", "Subtitle language", "Used when a stream has more than one.", {
        "": "Source default", English: "English", Spanish: "Spanish", Portuguese: "Portuguese", French: "French",
        German: "German", Italian: "Italian", Arabic: "Arabic", Russian: "Russian", Indonesian: "Indonesian",
      })),
    h("section.setting-group", null,
      toggle("alerts", "New-episode alerts", "Notify me when a show on My List airs a new episode, even with AniVerse closed.", async (on) => {
        if (!on) { await push.disable(); return true; }
        if (!("Notification" in window)) return false;
        if ((await Notification.requestPermission()) !== "granted") return false;
        // Push needs a secure address; without it, alerts still come while a tab is open.
        if (push.supported() && !(await push.enable())) toast("Alerts will show while AniVerse is open (push isn't available here).");
        return true;
      }),
      push.supported() ? h("button.px-btn.dark.px-box.bevel.small", {
        type: "button", style: { marginTop: "12px" },
        onclick: async () => toast((await push.test()) ? "Test alert sent." : "Turn alerts on first, then try again."),
      }, "Send a test alert") : null),
    h("p.muted", null, sprite("gear", 1.6), " The app has these too, under its gear icon."),
  );
}
render();
