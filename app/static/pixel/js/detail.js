// Anime details: art, info, synopsis, the episodes (as a grid of numbers, or a
// list with titles and screenshots), the trailer, characters, related seasons
// and recommendations -- the app's detail screen.
import { h, sprite, pixelCover, drips, plainText, clear, fmtTime } from "./px.js";
import { api, history, titleOf, coverOf, airedEpisodes } from "./api.js";
import { watchlist } from "./watchlist.js";
import { sfx } from "./sfx.js";
import { initShell, sectionHead, emptyState, posterCard, shelf } from "./ui.js";

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

const VIEW = "av.epview";
const readView = () => { try { return localStorage.getItem(VIEW) || "grid"; } catch { return "grid"; } };
const saveView = (v) => { try { localStorage.setItem(VIEW, v); } catch { /* storage off */ } };
const RELATION = { PREQUEL: "Prequel", SEQUEL: "Sequel", SIDE_STORY: "Side story", SPIN_OFF: "Spin-off", ALTERNATIVE: "Alternative",
  PARENT: "Main story", SUMMARY: "Summary", COMPILATION: "Compilation", CHARACTER: "Shared cast", OTHER: "Related", CONTAINS: "Contains", SOURCE: "Source" };
const extra = api.extra(id);
const episodeInfo = api.episodes(id);

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
  const stats = h("div.stats");
  clear(top).append(h("div.detail-hero", null,
    h("div.backdrop", null, pixelCover(cover, 24)),
    h("div.shade"),
    dripCanvas,
    h("div.wrap", null, h("div.detail-top", null,
      h("div.poster-art.px-box.rivets", null, pixelCover(cover, 110, title)),
      h("div.detail-info", null,
        h("h1", null, title),
        romaji && romaji !== title ? h("div.alt", null, romaji) : null,
        h("div.chips", null, (a.genres || []).map((g) => h("a.chip.px-box", { href: `/genre/${encodeURIComponent(g)}` }, g))),
        stats,
        actions)))));
  stats.append(...[
    a.format ? h("span.chip.dark.px-box", null, String(a.format).replace("_", " ")) : null,
    a.episodes ? h("span.chip.dark.px-box", null, `${a.episodes} eps`) : null,
    a.status ? h("span.chip.dark.px-box", null, STATUS[a.status] || a.status) : null,
    a.averageScore ? h("span.chip.dark.px-box", { style: { color: "var(--gold)" } }, `${a.averageScore}%`) : null,
    a.duration ? h("span.chip.dark.px-box", null, `${a.duration}m`) : null,
  ].filter(Boolean));
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
    renderExtras(a, stats);
    return;
  }
  const RANGE = 100;
  const grid = h("div.eps");
  const ranges = h("div.range");
  let view = readView();
  let titles = null;
  const toggle = h("div.view-toggle", { role: "group", "aria-label": "Episode view" },
    ["grid", "list"].map((v) => h("button.px-btn.px-box.bevel.small", {
      type: "button", dataset: { view: v }, "aria-pressed": String(view === v),
      onclick: () => { view = v; saveView(v); sfx("select"); redraw(); },
    }, v === "grid" ? "Grid" : "List")));
  const head = h("div.eps-head", null, sectionHead("Episodes"), toggle, ranges);
  section.append(head, grid);
  let current = 1;
  const redraw = () => drawRange(current);

  const drawRange = (start) => {
    current = start;
    clear(grid);
    [...toggle.children].forEach((b) => { const on = b.dataset.view === view; b.classList.toggle("dark", !on); b.setAttribute("aria-pressed", String(on)); });
    [...ranges.children].forEach((b) => b.classList.toggle("dark", Number(b.dataset.start) !== start));
    const end = Math.min(total, start + RANGE - 1);
    const progress = new Map(history.forAnime(id).map((e) => [e.episode, e]));
    if (view === "list") {
      grid.className = "ep-list";
      if (!titles) {
        grid.append(h("div.skel", { style: { height: "220px" } }));
        episodeInfo.then((list) => { titles = new Map(list.map((e) => [e.number, e])); if (view === "list") redraw(); });
        return;
      }
      for (let n = start; n <= end; n++) grid.append(episodeRow(a, n, n > aired, titles.get(n), progress.get(n)));
      return;
    }
    grid.className = "eps";
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
  };
  const resume = resumePoint(a, aired);
  if (total > RANGE) {
    for (let s = 1; s <= total; s += RANGE) {
      ranges.append(h("button.px-btn.px-box.bevel.small", { type: "button", dataset: { start: String(s) }, onclick: () => drawRange(s) }, `${s}-${Math.min(total, s + RANGE - 1)}`));
    }
  }
  drawRange(Math.floor(((resume ? resume.ep : 1) - 1) / RANGE) * RANGE + 1);
  renderActions(actions, a, aired, resume);
  history.onChange(redraw);
  renderExtras(a, stats);
}

/** One episode in the list view: screenshot, number, title, air date, progress. */
function episodeRow(a, n, future, info, e) {
  const title = (info && info.title) || `Episode ${n}`;
  const done = e && history.finished(e);
  const frac = e && e.duration_ms ? Math.min(1, e.position_ms / e.duration_ms) : 0;
  const when = [
    info && info.airDate ? new Date(info.airDate).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" }) : "",
    info && info.runtime ? `${info.runtime}m` : "",
    future ? "Not aired yet" : done ? "Watched" : "",
  ].filter(Boolean).join(" · ");
  const shot = info && info.image ? pixelCover(info.image, 72, "") : pixelCover(coverOf(a), 40, "");
  const inner = [
    h("div.shot.px-box.flat", null, shot, h("span.num", null, `EP ${n}`), done ? h("span.mark", null, sprite("skullSmall", 2)) : null),
    h("div.info", null,
      h("b", null, title),
      when ? h("span.when", null, when) : null,
      info && info.overview ? h("p", null, info.overview) : null,
      e && !done && frac > 0.02 ? h("div.px-bar.bar", null, h("i", null, h("b", { style: { width: `${frac * 100}%` } }))) : null),
    future ? null : h("span.go.px-btn.px-box.bevel.small", null, sprite("play", 1.4), done ? "Again" : frac > 0.02 ? "Resume" : "Play"),
  ];
  return future
    ? h("div.ep-row.px-box.future", { "aria-label": `Episode ${n}, not aired yet` }, inner)
    : h(`a.ep-row.px-box${done ? ".watched" : ""}`, { href: `/watch/${a.id}/${n}`, "aria-label": `Episode ${n}: ${title}` }, inner);
}

/** Studio and season chips, the trailer, characters, related seasons, recommendations. */
async function renderExtras(a, stats) {
  const x = await extra;
  if (!x || !Object.keys(x).length) return;
  stats.append(...[
    x.season && x.seasonYear ? h("span.chip.dark.px-box", null, `${x.season[0]}${x.season.slice(1).toLowerCase()} ${x.seasonYear}`) : null,
    x.studio ? h("span.chip.dark.px-box", null, x.studio) : null,
  ].filter(Boolean));

  const t = x.trailer;
  const embed = t && t.id ? (t.site === "youtube" ? `https://www.youtube-nocookie.com/embed/${encodeURIComponent(t.id)}?autoplay=1&rel=0`
    : t.site === "dailymotion" ? `https://www.dailymotion.com/embed/video/${encodeURIComponent(t.id)}?autoplay=1` : null) : null;
  if (embed) {
    const box = h("div.trailer.px-box");
    // Nothing loads from the video site until you press play.
    box.append(h("button.poster-btn", {
      type: "button", "aria-label": "Play the trailer",
      onclick: () => {
        sfx("start");
        clear(box).append(h("iframe", { src: embed, title: `${titleOf(a)} trailer`, allow: "autoplay; encrypted-media; picture-in-picture; fullscreen", allowfullscreen: true, referrerpolicy: "strict-origin-when-cross-origin" }));
      },
    }, pixelCover(t.thumbnail || x.bannerImage || coverOf(a), 96, ""), h("span.big-play.px-box.bevel", null, sprite("play", 3))));
    body.append(h("section.section", null, sectionHead("Trailer"), box));
  }

  const chars = (x.characters || []).filter((c) => c.name);
  if (chars.length) {
    const grid = h("div.chars", null, chars.slice(0, 12).map((c) => h("div.char.px-box", null,
      h("div.face.px-box.flat", null, pixelCover(c.image, 40, c.name)),
      h("div", null, h("b", null, c.name), h("small", null, c.role === "MAIN" ? "Main" : "Supporting")),
      c.voiceActor ? h("div.va", null, h("b", null, c.voiceActor), h("small", null, "Japanese")) : h("div"),
      c.voiceActorImage ? h("div.face.px-box.flat", null, pixelCover(c.voiceActorImage, 40, c.voiceActor || "")) : h("div"))));
    body.append(h("section.section", null, sectionHead("Characters"), grid));
  }

  const related = (x.relations || []).filter((r) => r && r.id);
  if (related.length) {
    body.append(h("section.section", null, sectionHead("Related"), shelf(related.map((r) => {
      const card = posterCard(r);
      card.querySelector(".badge")?.remove();
      card.querySelector(".frame").append(h("span.badge", null, RELATION[r.relation] || "Related"));
      return card;
    }))));
  }
  const recs = (x.recommendations || []).filter((r) => r && r.id);
  if (recs.length) body.append(h("section.section", null, sectionHead("You might also like"), shelf(recs.map(posterCard))));
}

/** Where "continue" should land: the last episode touched, or the one after. */
function resumePoint(a, aired) {
  const last = history.forAnime(a.id)[0];
  if (!last) return null;
  if (history.finished(last)) return last.episode < aired ? { ep: last.episode + 1, next: true } : null;
  return { ep: last.episode, at: last.position_ms / 1000 };
}

function followButton(a, aired) {
  const btn = h("button.px-btn.dark.px-box.bevel", { type: "button" });
  const draw = () => {
    const on = watchlist.has(a.id);
    btn.setAttribute("aria-pressed", String(on));
    clear(btn).append(sprite(on ? "bookmark" : "bookmarkOff", 1.6), on ? "On My List" : "My List");
  };
  btn.addEventListener("click", () => {
    if (watchlist.has(a.id)) watchlist.unfollow(a.id);
    else { watchlist.follow(a, aired); sfx("achieve"); }
    draw();
  });
  draw();
  return btn;
}

function renderActions(el, a, aired, resume) {
  clear(el);
  if (!aired) {
    el.append(h("span.px-btn.px-box.bevel", { "aria-disabled": "true", style: { filter: "grayscale(1)" } }, "Not aired yet"), followButton(a, aired));
    return;
  }
  if (resume) {
    const label = resume.next ? `Next: EP ${resume.ep}` : `Resume EP ${resume.ep}${resume.at > 10 ? ` · ${fmtTime(resume.at)}` : ""}`;
    el.append(h("a.px-btn.px-box.bevel", { href: `/watch/${a.id}/${resume.ep}` }, sprite("play", 1.6), label));
    if (resume.ep !== 1) el.append(h("a.px-btn.dark.px-box.bevel", { href: `/watch/${a.id}/1` }, "From EP 1"));
  } else {
    el.append(h("a.px-btn.px-box.bevel", { href: `/watch/${a.id}/1` }, sprite("play", 1.6), "Watch EP 1"));
  }
  el.append(followButton(a, aired), h("a.px-btn.dark.px-box.bevel", { href: "#episodes" }, "Episodes"));
}
