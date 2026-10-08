// Status: how each stream provider has done over the last day, how many
// episode lookups found something to play, and the latest failures.
import { h, clear, fmtTime } from "./px.js";
import { api } from "./api.js";
import { initShell, sectionHead, emptyState } from "./ui.js";

initShell();
const root = document.getElementById("page-root");
const NAMES = { ZokoAnimeProvider: "ZokoAnime", GogoAnimeProvider: "GogoAnime", VidSrcProvider: "VidSrc",
  AniWatchProvider: "AniWatch (HD-1)", AniWatchOneProvider: "AniWatchOne (Byse)" };

const ago = (t, now) => {
  const s = Math.max(0, now - t);
  return s < 90 ? "just now" : s < 5400 ? `${Math.round(s / 60)} min ago` : `${Math.round(s / 3600)} h ago`;
};

/** This server: disk space, how much of what is trending plays, and error reports from clients. */
function serverSection(o, now) {
  if (!o) return null;
  const dk = o.disk, sw = o.sweep, ce = o.clientErrors;
  return h("section.section", null, sectionHead("This server"),
    h("div.stat-row", null,
      h(`div.stat.px-box${dk.low ? ".warn" : ""}`, null, h("b", null, `${dk.freeGb} GB`),
        h("small", null, dk.low ? `Disk nearly full (${dk.freePercent}% free)` : `Disk free (${dk.freePercent}%)`)),
      h("div.stat.px-box", null, h("b", null, sw && sw.total ? `${sw.ok}/${sw.total}` : "--"),
        h("small", null, sw && sw.at ? `Trending anime playable · ${ago(sw.at, now)}` : "Trending sweep: not run yet")),
      h("div.stat.px-box", null, h("b", null, String(ce.last24h)), h("small", null, "Error reports (24h)"))),
    ...[
      sw && sw.failing.length ? h("div.list", null, sw.failing.map((f) => h("a.list-item.px-box", { href: `/watch/${f.id}/${f.ep}` },
        h("div.body", null, h("span.name", null, `${f.title} · EP ${f.ep}`), h("span.sub", null, f.error || "no stream found"))))) : null,
      ce.latest.length ? h("div.list", null, ce.latest.map((e) => h("div.list-item.px-box", null,
        h("div.body", null, h("span.name", null, `${e.source} ${e.version} · ${e.kind}${e.where ? ` · ${e.where}` : ""}`),
          h("span.sub", null, `${ago(e.at, now)} · ${e.message}`))))) : null,
    ].filter(Boolean));
}

async function render() {
  let d;
  const ops = api.ops();
  try { d = await api.status(); } catch {
    clear(root).append(emptyState("Can't reach the server", "The status comes from the AniVerse server, which didn't answer."));
    return;
  }
  const cov = d.coverage;
  const rate = cov.total ? Math.round((100 * cov.playable) / cov.total) : null;
  const top = Math.max(1, ...d.hours.map((x) => x.total));
  const server = serverSection(await ops, d.now);
  // DOM append() prints null as "null": optional parts are filtered out.
  clear(root).append(...[
    server,
    h("div.stat-row", null,
      h("div.stat.px-box", null, h("b", null, rate === null ? "--" : `${rate}%`), h("small", null, "Episodes playable (24h)")),
      h("div.stat.px-box", null, h("b", null, String(cov.total)), h("small", null, "Episode lookups")),
      h("div.stat.px-box", null, h("b", null, cov.avgSeconds ? `${cov.avgSeconds}s` : "--"), h("small", null, "Average time to a stream"))),
    sectionHead("Lookups per hour"),
    h("div.hours.px-box", { role: "img", "aria-label": "Playable lookups per hour over the last day" },
      d.hours.map((hr) => h("i", {
        title: `${new Date(hr.start * 1000).toLocaleTimeString(undefined, { hour: "2-digit" })}: ${hr.playable}/${hr.total} playable`,
        style: { height: `${(100 * hr.total) / top}%` },
      }, h("b", { style: { height: hr.total ? `${(100 * hr.playable) / hr.total}%` : "0" } })))),
    h("section.section", null, sectionHead("Providers"),
      d.providers.length ? d.providers.map((p) => h("div.prov.px-box", null,
        h("div", null, h("b", null, NAMES[p.name] || p.name),
          h("small", null, p.lastError && (!p.lastOk || p.lastError.at > p.lastOk) ? ` · last error ${ago(p.lastError.at, d.now)}` : p.lastOk ? ` · last stream ${ago(p.lastOk, d.now)}` : "")),
        h("div.px-bar", null, h("i", null, h("b", { style: { width: `${p.successRate || 0}%` } }))),
        h("span", null, p.successRate === null ? "--" : `${p.successRate}%`),
        h("span.avg.muted", null, p.avgSeconds ? (p.avgSeconds < 60 ? `${Number(p.avgSeconds).toFixed(1)}s` : fmtTime(p.avgSeconds)) : "--")))
        : emptyState("No lookups yet", "Numbers appear once someone plays an episode.")),
    d.recentFailures.length ? h("section.section", null, sectionHead("Recent failures"),
      h("div.list", null, d.recentFailures.map((f) => h("a.list-item.px-box", { href: `/watch/${f.anilistId}/${f.episode}` },
        h("div.body", null, h("span.name", null, `Anime ${f.anilistId} · EP ${f.episode} · ${f.category.toUpperCase()}`),
          h("span.sub", null, `${ago(f.at, d.now)} · ${f.error || "nothing played"}`)))))) : null,
  ].filter(Boolean));
}
render();
setInterval(render, 60000);
