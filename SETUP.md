# Running AniVerse on another PC

Two servers make up the web app:

| process | port | started from | what it does |
| --- | --- | --- | --- |
| backend | 8001 | `AniVerseApiUrl/` | metadata, provider scraping, stream resolution |
| frontend | 8000 | repo root | web player, and proxies the backend under `/api/anime/*` |

The frontend is the only one that needs to be reachable from outside: it
passes API calls through to the backend, so a single tunnel covers both.

## 1. Clone

```bat
git clone https://github.com/kaneki654/AniVerse.git C:\AniVerse
cd C:\AniVerse
git checkout feat/pow-optimization-and-install-site
```

Clone somewhere **shallow**, like `C:\AniVerse`. Paths inside the repo reach 89
characters, and Windows' 260-character limit will break the clone from a deep
parent folder. If it does fail with `Filename too long`:

```bat
git config --global core.longpaths true
```

## 2. Install Python dependencies

Python 3.9 or newer, on PATH.

```bat
pip install -r AniVerseApiUrl\requirements.txt -r requirements.txt
```

Both files are needed: the first is the backend (provider scraping, the
proof-of-work solver, HTML/JS parsing), the second is the frontend (templates
and form handling).

> The `libs/` folder in this repo is **Linux-only** `.so` binaries left over
> from an earlier deployment. Ignore it on Windows, and do not put it on
> `PYTHONPATH` — `run.bat` deliberately does not.

## 3. Run

```bat
run.bat
```

That frees ports 8000 and 8001, starts both servers in their own restart-loop
windows, and waits for the backend's health check before starting the frontend.
Logs land in `logs\`.

Open <http://localhost:8000>.

To run them by hand instead, in two terminals:

```bat
cd AniVerseApiUrl && python -m uvicorn app.main:app --host 0.0.0.0 --port 8001
```

```bat
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The frontend finds the backend at `http://localhost:8001` unless
`ANIVERSE_API_BASE` says otherwise, so a different backend port only needs:

```bat
set ANIVERSE_API_BASE=http://127.0.0.1:8011
```

## 4. Reaching it from a phone (optional)

Only needed for the Android app, or for watching away from this machine.

Install [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)
and either put `cloudflared.exe` on your PATH or drop it at `C:\Tools\cloudflared.exe`,
then:

```bat
run_tunnel.bat
```

It prints a `https://<random>.trycloudflare.com` URL that maps to port 8000.

**That URL changes every time the tunnel restarts.** The Android app handles
this by itself from build 8 onward: it reads the current address from
`https://aniversesite.vercel.app/version.json`, so after a restart you only
republish that file — no rebuild, no reinstall:

```bat
python aniverse_site\build_site.py --host https://<new-url>.trycloudflare.com
cd aniverse_site && vercel deploy --prod
```

An address typed into the app under the gear icon always wins, but only while it
still answers; once it stops responding the app falls back to the published one.

## Troubleshooting

**Ports already in use** — `run.bat` clears 8000/8001 before starting, including
any leftover restart-loop windows. If a server still will not bind, check for a
stray `python.exe` holding the port.

**Genre screens say "nothing found"** — AniList rate limits at roughly 30
queries a minute. Successful genre pages are cached for 30 minutes and throttled
requests are retried, so this should recover on its own; it is not a
misconfiguration.

**Nothing plays** — check `logs\backend.log`. A cold resolve fans out across
every provider and can include a proof-of-work solve, so the first request for
an episode legitimately takes tens of seconds. Subsequent ones are cached for
10 minutes.
