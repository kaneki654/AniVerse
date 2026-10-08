// Settings: palette, sound, data saver, subtitle style and alerts. Kept in this
// browser; the app has the same choices in its own Settings screen.
import { h, clear, sprite, paletteSwitch, retheme } from "./px.js";
import { settings, THEMES } from "./settings.js";
import { push } from "./push.js";
import { toast } from "./px.js";
import { sfx } from "./sfx.js";
import { initShell } from "./ui.js";

initShell();
const root = document.getElementById("page-root");

const SWATCH = { blood: "#d10a1a", neon: "#00d9ff", sakura: "#ff5fa2", gameboy: "#8bac0f", samurai: "#d4a537" };

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
            // Each palette arrives with its own transition: covered in its
            // style, switched underneath without a reload, then uncovered.
            onclick: async () => {
              if (id === settings.get().theme || document.querySelector("canvas.palette-fx")) return;
              sfx({ neon: "hit", sakura: "skip", gameboy: "select", samurai: "boss" }[id] || "slash");
              await paletteSwitch(id, "cover");
              settings.set({ theme: id });
              retheme();
              render();
              document.querySelectorAll("canvas.palette-fx, .palette-fx-label").forEach((el) => el.remove());
              await paletteSwitch(id, "reveal");
            },
          }, h("i", { style: { background: SWATCH[id] } }), name))))),
    h("section.setting-group", null,
      choice("effects", "Effects", "The animation in the background, on clicks and on buttons. Lite is lighter on the battery; Off keeps the page still.",
        { full: "Full", lite: "Lite", off: "Off" }, (v) => { setTimeout(() => location.reload(), 150); return v; })),
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
