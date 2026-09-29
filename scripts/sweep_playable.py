"""Measure how many anime actually resolve to a playable stream.

Resolves one episode for every title in a list and reports which returned at
least one stream, which did not, and why. Used to find where coverage breaks,
not just whether the popular handful still work.

    python scripts/sweep_playable.py titles.json [--base URL] [--jobs N]

The title list is JSON: [{"id": <anilist id>, "ep": <episode>, "title": ...}].
"""
import argparse
import asyncio
import json
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


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("titles")
    ap.add_argument("--base", default="http://127.0.0.1:8001")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--fresh", action="store_true", help="bypass the resolve cache")
    ap.add_argument("--out", default="sweep_results.json")
    args = ap.parse_args()

    items = json.load(open(args.titles, encoding="utf-8"))
    sem = asyncio.Semaphore(args.jobs)
    async with httpx.AsyncClient(timeout=240) as client:
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
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
