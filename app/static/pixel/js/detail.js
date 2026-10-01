// Anime details: art, info, synopsis, and the episode grid with what has been
// watched -- the app's detail screen.
import { h, sprite, pixelCover, drips, plainText, clear, fmtTime } from "./px.js";
import { api, history, titleOf, coverOf, airedEpisodes } from "./api.js";
import { initShell, sectionHead, emptyState } from "./ui.js";

initShell();
const top = document.getElementById("detail");
const body = document.getElementById("detail-body");
const id = top.dataset.id;

top.append(h("div.detail-hero", null, h("div.wrap", null,
  h("div.detail-top", null,
    h("div.poster-art.px-box.skel"),
    h("div.detail-info", { style: { flex: "1" } },
      h("div.skel", { style: { height: "22px", width: "60%" } }),
      h("div.skel", { style: { height: "14px", width: "40%" } }))))));

const STATUS = { RELEASING: "Airing", FINISHED: "Finished", NOT_YET_RELEASED: "Not aired yet", CANCELLED: "Cancelled", HIATUS: "On hiatus" };

api.info(id).then(render).catch(() => {
  clear(top);
  body.append(emptyState("Anime not found", "It may have been removed, or the server could not reach AniList.",
    h("a.px-btn.px-box.bevel", { href: "/" }, "Go home")));
});

function render(a) {
  const title = titleOf(a);
  const romaji = a.title && a.title.romaji;
  const cover = coverOf(a);
  const aired = airedEpisodes(a);
  document.title = `${title} · AniVerse`;

  const dripCanvas = h("canvas.drips");
  const actions = h("div.actions");
  clear(top).append(h("div.detail-hero", null,
    h("div.backdrop", null, pixelCover(cover, 24)),
    h("div.shade"),
    dripCanvas,
    h("div.wrap", null, h("div.detail-top", null,
      h("div.poster-art.px-box", null, pixelCover(cover, 110, title)),
      h("div.detail-info", null,
        h("h1", null, title),
        romaji && romaji !== title ? h("div.alt", null, romaji) : null,
        h("div.chips", null, (a.genres || []).map((g) => h("a.chip.px-box", { href: `/genre/${encodeURIComponent(g)}` }, g))),
        h("div.stats", null,
          a.format ? h("span.chip.dark.px-box", null, String(a.format).replace("_", " ")) : null,
          a.episodes ? h("span.chip.dark.px-box", null, `${a.episodes} eps`) : null,
          a.status ? h("span.chip.dark.px-box", null, STATUS[a.status] || a.status) : null,
          a.averageScore ? h("span.chip.dark.px-box", { style: { color: "#e8b23a" } }, `${a.averageScore}%`) : null,
          a.duration ? h("span.chip.dark.px-box", null, `${a.duration}m`) : null),
        actions)))));
  drips(dripCanvas, { count: 9, seed: title.length + 3, cell: 3 });

  // Synopsis.
  const text = plainText(a.description);
  if (text) {
    const p = h("p.synopsis.clamp", null, text);
    const more = h("button.read-more", { type: "button", onclick: () => { p.classList.toggle("clamp"); more.textContent = p.classList.contains("clamp") ? "Read more" : "Show less"; } }, "Read more");
    body.append(p, more);
    requestAnimationFrame(() => { if (p.scrollHeight <= p.clientHeight + 2) more.remove(); });
  }

  // Episodes.
  const section = h("section.section#episodes", { style: { marginTop: "30px" } });
  body.append(section);
  const total = Math.max(aired, a.episodes || 0);
  if (!aired) {
    section.append(sectionHead("Episodes"), emptyState("Not aired yet", "Episodes will appear here once they air."));
    renderActions(actions, a, 0);
    return;
  }
  const RANGE = 100;
  const grid = h("div.eps");
  const ranges = h("div.range");
  const head = h("div.eps-head", null, sectionHead("Episodes"), ranges);
  section.append(head, grid);

  const drawRange = (start) => {
    clear(grid);
    const end = Math.min(total, start + RANGE - 1);
    const progress = new Map(history.forAnime(id).map((e) => [e.episode, e]));
    for (let n = start; n <= end; n++) {
      if (n > aired) { grid.append(h("span.ep-btn.future.px-box", { title: "Not aired yet" }, String(n))); continue; }
      const e = progress.get(n);
      const done = e && history.finished(e);
      const frac = e && e.duration_ms ? Math.min(1, e.position_ms / e.duration_ms) : 0;
      grid.append(h(`a.ep-btn.px-box${done ? ".watched" : ""}`, { href: `/watch/${id}/${n}`, "aria-label": `Episode ${n}${done ? ", watched" : ""}` },
        String(n),
        done ? h("span.mark", null, sprite("skullSmall", 2)) : null,
        e && !done && frac > 0.02 ? h("span.part", null, h("b", { style: { width: `${frac * 100}%` } })) : null));
    }
    [...ranges.children].forEach((b) => b.classList.toggle("dark", Number(b.dataset.start) !== start));
  };
  const resume = resumePoint(a, aired);
  if (total > RANGE) {
    for (let s = 1; s <= total; s += RANGE) {
      ranges.append(h("button.px-btn.px-box.bevel.small", { type: "button", dataset: { start: String(s) }, onclick: () => drawRange(s) }, `${s}-${Math.min(total, s + RANGE - 1)}`));
    }
  }
  drawRange(Math.floor(((resume ? resume.ep : 1) - 1) / RANGE) * RANGE + 1);
  renderActions(actions, a, aired, resume);
  history.onChange(() => drawRange(Number([...ranges.children].find((b) => !b.classList.contains("dark"))?.dataset.start || 1)));
}

/** Where "continue" should land: the last episode touched, or the one after. */
function resumePoint(a, aired) {
  const last = history.forAnime(a.id)[0];
  if (!last) return null;
  if (history.finished(last)) return last.episode < aired ? { ep: last.episode + 1, next: true } : null;
  return { ep: last.episode, at: last.position_ms / 1000 };
}

function renderActions(el, a, aired, resume) {
  clear(el);
  if (!aired) {
    el.append(h("span.px-btn.px-box.bevel", { "aria-disabled": "true", style: { filter: "grayscale(1)" } }, "Not aired yet"));
    return;
  }
  if (resume) {
    const label = resume.next ? `Next: EP ${resume.ep}` : `Resume EP ${resume.ep}${resume.at > 10 ? ` · ${fmtTime(resume.at)}` : ""}`;
    el.append(h("a.px-btn.px-box.bevel", { href: `/watch/${a.id}/${resume.ep}` }, sprite("play", 1.6), label));
    if (resume.ep !== 1) el.append(h("a.px-btn.dark.px-box.bevel", { href: `/watch/${a.id}/1` }, "From EP 1"));
  } else {
    el.append(h("a.px-btn.px-box.bevel", { href: `/watch/${a.id}/1` }, sprite("play", 1.6), "Watch EP 1"));
  }
  el.append(h("a.px-btn.dark.px-box.bevel", { href: "#episodes" }, "Episodes"));
}
