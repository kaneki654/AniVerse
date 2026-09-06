# Running AniVerse on another PC

Two servers make up the web app:

| process | port | started from | what it does |
| --- | --- | --- | --- |
| backend | 8001 | `AniVerseApiUrl/` | metadata, provider scraping, stream resolution |
| frontend | 8000 | repo root | web player, and proxies the backend under `/api/anime/*` |

The frontend is the only one that needs to be reachable from outside: it
passes API calls through to the backend, so a single tunnel covers both.

## Windows

### 1. Clone

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

### 2. Install Python dependencies

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

### 3. Run

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

## Linux / macOS

Same two servers, same ports, same logic — `run.sh` is the mirror of `run.bat`.

```bash
git clone https://github.com/kaneki654/AniVerse.git ~/AniVerse
cd ~/AniVerse
python3 -m pip install -r AniVerseApiUrl/requirements.txt -r requirements.txt
./start_all.sh
```

`start_all.sh` is the one that does everything: frees the ports, starts the
backend and waits for it, starts the frontend, opens the tunnel, and publishes
the tunnel's address so the phone app can find it. Ctrl+C stops all of it.

| command | what it does |
| --- | --- |
| `./start_all.sh` | servers + tunnel + publish the address |
| `./start_all.sh --no-publish` | servers + tunnel, just print the URL |
| `./start_all.sh --no-tunnel` | servers only |
| `./run.sh` | same as `--no-tunnel` |
| `./run_tunnel.sh` | tunnel only — assumes the servers are already up |

Then open <http://localhost:8000>.

**If the app cannot reach the server, this is nearly always why:** every
cloudflared start gets a fresh random URL, and the app looks the current one up
from the install site. Running `run_tunnel.sh` on its own starts a tunnel but
tells nobody about it, so the app keeps trying the previous, now-dead address.
`start_all.sh` publishes it for you. That step needs the Vercel CLI (`npm i -g
vercel`); without it the script prints the exact commands to run elsewhere.

`run.sh` frees ports 8000 and 8001 before starting (via `lsof`, `fuser` or `ss`,
whichever is installed), starts the backend, waits for its health check, then
starts the frontend — restarting either if it exits. Logs go to `logs/`.

Override the interpreter if `python3` is not the one you want:

```bash
PYTHON=/usr/bin/python3.12 ./run.sh
```

> **Do not put `libs/` on `PYTHONPATH`.** Older versions of `run.sh` did. That
> folder only ever contained the frontend's packages — it is missing numpy,
> rapidfuzz, selectolax, pycryptodome, mini-racer, m3u8 and APScheduler — so the
> backend cannot import with it. Install the requirements normally instead.

For the tunnel:

```bash
./run_tunnel.sh
```

It looks for `cloudflared` on PATH, then the usual install locations, and prints
install hints if it finds none.

## Reaching it from a phone (optional)

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

**`ModuleNotFoundError: No module named 'Crypto'`** (or numpy, rapidfuzz,
selectolax, m3u8, apscheduler, py_mini_racer) — only the root
`requirements.txt` was installed. It covers the frontend; the backend's packages
are in `AniVerseApiUrl/requirements.txt`. Install both, with the same
interpreter that runs the scripts:

```bash
python3 -m pip install -r AniVerseApiUrl/requirements.txt -r requirements.txt
```

`Crypto` comes from `pycryptodome`. Use `python3 -m pip` rather than a bare
`pip`, which can belong to a different interpreter. `start_all.sh` checks for all
of these before starting anything and names whatever is missing.

**Nothing plays** — check `logs\backend.log`. A cold resolve fans out across
every provider and can include a proof-of-work solve, so the first request for
an episode legitimately takes tens of seconds. Subsequent ones are cached for
10 minutes.
