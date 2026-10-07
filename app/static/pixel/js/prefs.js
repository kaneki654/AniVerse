// Settings: palette, sound, data saver, subtitle style and alerts. Kept in this
// browser; the app has the same choices in its own Settings screen.
import { h, clear, sprite, paletteSwitch } from "./px.js";
import { settings, THEMES } from "./settings.js";
import { sfx } from "./sfx.js";
import { initShell } from "./ui.js";

initShell();
const root = document.getElementById("page-root");

const SWATCH = { blood: "#d10a1a", neon: "#00d9ff", sakura: "#ff5fa2" };

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
      h("div.setting.px-box", null,
        h("div", null, h("b", null, "Palette"), h("span", null, "The colour of blood, glows and effects. Everything stays pixel art.")),
        h("div.theme-swatches", null, Object.entries(THEMES).map(([id, name]) =>
          h("button.theme-swatch.px-box", {
            type: "button", "aria-pressed": String(s.theme === id),
            // Each palette arrives with its own transition: covered in its style,
            // reloaded in its colours, uncovered on arrival.
            onclick: async () => {
              if (id === settings.get().theme) return;
              sfx({ neon: "hit", sakura: "skip" }[id] || "slash");
              await paletteSwitch(id, "cover");
              settings.set({ theme: id });
              try { sessionStorage.setItem("av.palette", id); } catch { /* storage off */ }
              location.reload();
            },
          }, h("i", { style: { background: SWATCH[id] } }), name))))),
    h("section.setting-group", null,
      toggle("sfx", "Sound effects", "8-bit blips for buttons, hits and achievements."),
      choice("volume", "Effects volume", "How loud the blips are.", { "0.15": "Quiet", "0.35": "Normal", "0.7": "Loud" }, Number)),
    h("section.setting-group", null,
      toggle("dataSaver", "Data saver", "Always play the lowest quality to save mobile data."),
      choice("subSize", "Subtitle size", "How big subtitles are drawn.", { s: "Small", m: "Medium", l: "Large", xl: "Extra large" }),
      toggle("subBg", "Subtitle background", "A dark box behind subtitles, for bright scenes."),
      choice("subLang", "Subtitle language", "Used when a stream has more than one.", {
        "": "Source default", English: "English", Spanish: "Spanish", Portuguese: "Portuguese", French: "French",
        German: "German", Italian: "Italian", Arabic: "Arabic", Russian: "Russian", Indonesian: "Indonesian",
      })),
    h("section.setting-group", null,
      toggle("alerts", "New-episode alerts", "Notify me when a show on My List airs a new episode.", async (on) => {
        if (!on) return true;
        if (!("Notification" in window)) return false;
        return (await Notification.requestPermission()) === "granted";
      })),
    h("p.muted", null, sprite("gear", 1.6), " The app has these too, under its gear icon."),
  );
}
render();
