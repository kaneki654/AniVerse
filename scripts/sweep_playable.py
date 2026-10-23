"""Measure how many anime actually resolve to a playable stream.

Resolves one episode for every title in a list and reports which returned at
least one stream, which did not, and why. Used to find where coverage breaks,
not just whether the popular handful still work.

    python scripts/sweep_playable.py titles.json [--base URL] [--jobs N]
    python scripts/sweep_playable.py --trending 40 --summary data/sweep.json

The title list is JSON: [{"id": <anilist id>, "ep": <episode>, "title": ...}].
With --trending N the list is what is popular on AniList right now, each at its
latest aired episode. --summary writes the totals, which servers answered, and
what failed, for the status page (app/ops.py); start_all.sh runs this daily.
"""
import argparse
import asyncio
import json
import os
import sys
import time

import httpx


async def resolve_one(client, base, item, sem, fresh):
    async with sem:
        started = time.time()
        url = f"{base}/anime/resolve/{item['id']}/{item['ep']}?category=sub"
        if fresh:
            url += "&fresh=true"
        try:
            resp = await client.get(url)
            data = resp.json()
            streams = data.get("streams", []) if isinstance(data, dict) else []
            error = (data.get("error") or data.get("detail") or "") if isinstance(data, dict) else ""
        except Exception as e:  # noqa: BLE001 - a sweep reports, it does not stop
            streams, error = [], f"{type(e).__name__}: {e}"
        return {
            **item,
            "ok": bool(streams),
            "servers": [s.get("server", "?") for s in streams],
            "error": str(error)[:160],
            "seconds": round(time.time() - started, 1),
        }


TRENDING_QUERY = """
query ($n: Int) { Page(perPage: $n) {
  media(type: ANIME, sort: TRENDING_DESC, status_in: [RELEASING, FINISHED]) {
    id episodes status nextAiringEpisode { episode } title { english romaji }
  }
} }"""


def latest_aired(m: dict) -> int:
    nxt = (m.get("nextAiringEpisode") or {}).get("episode")
    if nxt:
        return max(1, nxt - 1)
    return max(1, m.get("episodes") or 1)


async def trending(client, n: int) -> list:
    resp = await client.post("https://graphql.anilist.co", json={"query": TRENDING_QUERY, "variables": {"n": n}})
    resp.raise_for_status()
    media = resp.json()["data"]["Page"]["media"]
    return [{"id": m["id"], "ep": latest_aired(m),
             "title": (m.get("title") or {}).get("english") or (m.get("title") or {}).get("romaji") or str(m["id"])}
            for m in media]


def summarize(results: list) -> dict:
    servers: dict = {}
    for r in results:
        for name in set(r["servers"]):
            servers[name] = servers.get(name, 0) + 1
    return {
        "at": int(time.time()),
        "total": len(results),
        "ok": sum(r["ok"] for r in results),
        "servers": dict(sorted(servers.items(), key=lambda kv: -kv[1])),
        "failing": [{"id": r["id"], "ep": r["ep"], "title": r["title"], "error": r["error"]}
                    for r in results if not r["ok"]],
    }


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("titles", nargs="?", help="JSON title list (or use --trending)")
    ap.add_argument("--trending", type=int, metavar="N", help="sweep the N anime trending on AniList")
    ap.add_argument("--summary", metavar="PATH", help="also write totals for the status page here")
    ap.add_argument("--base", default="http://127.0.0.1:8001")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--fresh", action="store_true", help="bypass the resolve cache")
    ap.add_argument("--out", default="sweep_results.json")
    args = ap.parse_args()

    if not args.titles and not args.trending:
        ap.error("give a title list or --trending N")
    sem = asyncio.Semaphore(args.jobs)
    async with httpx.AsyncClient(timeout=240) as client:
        if args.trending:
            items = await trending(client, args.trending)
        else:
            items = json.load(open(args.titles, encoding="utf-8"))
        tasks = [resolve_one(client, args.base, it, sem, args.fresh) for it in items]
        results = []
        for fut in asyncio.as_completed(tasks):
            r = await fut
            results.append(r)
            mark = "OK  " if r["ok"] else "FAIL"
            print(f"{mark} {r['seconds']:6.1f}s  {r['id']:>7} ep{r['ep']:<4} "
                  f"{r['title'][:38]:<38} {', '.join(r['servers'][:3]) or r['error'][:60]}",
                  flush=True)

    ok = sum(r["ok"] for r in results)
    print(f"\n==== {ok}/{len(results)} playable ({ok * 100 // max(1, len(results))}%) ====")
    json.dump(results, open(args.out, "w", encoding="utf-8"), indent=1)
    if args.summary:
        tmp = args.summary + ".tmp"
        json.dump(summarize(results), open(tmp, "w", encoding="utf-8"), indent=1)
        os.replace(tmp, args.summary)  # never a half-written file for the status page
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
