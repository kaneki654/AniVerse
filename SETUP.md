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

## Shipping a new app build

Bump `version:` in `aniverse_mobile/pubspec.yaml` **and** `kAppBuildNumber` in
`aniverse_mobile/lib/app_version.dart` (they must match), then:

```bash
(cd aniverse_mobile && flutter build apk --release)
python scripts/publish_apk.py aniverse_mobile/build/app/outputs/flutter-apk/app-release.apk
```

The publish command verifies the APK signature and reads its actual package and
version using the Android SDK. It copies the finished APK into ignored
`data/releases/`, then atomically switches `current.json` to the new release.
It refuses a different signing key, a lower build number, or changed APK bytes
under the same build number. Keep this directory alongside your signing-key
backup. SDK tools are discovered automatically; use `--aapt` and `--apksigner`
to supply their paths if necessary.

The web app serves the published APK at `/app/aniverse.apk` and its version at
`/app/version.json`. Installed apps with a lower build number offer the update
on their next launch after publication. Editing the version or starting a build
does not advertise an update. If no valid release is published, the endpoint
reports `available: false`. No server restart is needed after publishing.

**Signing.** Android only installs an update over an existing app when both are
signed with the same key. Release builds now stop if
`aniverse_mobile/android/key.properties` or its keystore is missing, instead of
silently signing with the building machine's debug key. Debug builds remain
available without that file.

To keep updating the copies already on phones, recover the keystore that signed
them. For earlier AniVerse builds this is the original build computer's debug
keystore: `%USERPROFILE%\.android\debug.keystore` on Windows, or
`~/.android/debug.keystore` on Linux/macOS. Copy that existing file to
`aniverse_mobile/android/app/aniverse-release.keystore`, then create
`aniverse_mobile/android/key.properties`:

```properties
storeFile=aniverse-release.keystore
storePassword=android
keyAlias=androiddebugkey
keyPassword=android
```

These are the standard debug-key passwords and alias; use the original values
if the app was signed with a custom key. `storeFile` is relative to
`aniverse_mobile/android/app/`, or it can be an absolute path. Both files are
gitignored; keep a private backup and never commit them.

For "App not installed as package conflicts with an existing package", compare
the old and new APKs using Android SDK Build Tools:

```bash
apksigner verify --print-certs old-aniverse.apk
apksigner verify --print-certs aniverse_mobile/build/app/outputs/flutter-apk/app-release.apk
```

The signer SHA-256 fingerprints must match for these builds. A new keystore,
renamed APK, or higher version number cannot repair a different signing key.
Rebuild with the original key to preserve the installed app and its data. If
that key is permanently lost, a fresh installation requires uninstalling the
old app first, which deletes its local data; this is not an in-place update.

## Accounts and Google sign-in (optional)

Username/password accounts work with no setup. They are stored in
`data/aniverse.db` next to the web app (gitignored — it holds password hashes and
session tokens). Back it up if accounts matter to you.

Google sign-in stays switched off (the button shows "not set up on this server")
until you give the server a Google OAuth client ID. It is read at runtime, so no
new APK is needed:

1. In [Google Cloud Console](https://console.cloud.google.com/apis/credentials),
   create a project and configure the OAuth consent screen (External, and add
   yourself as a test user while it is in testing).
2. Create an OAuth client of type **Android**: package name
   `com.example.aniverse_mobile`, and the **SHA-1 of the key that signs your
   APK** (see Signing above):
   ```bash
   keytool -list -v -keystore <your keystore> -alias androiddebugkey -storepass android
   ```
   The app never uses this client's ID directly; Google just checks it exists.
3. Create a second OAuth client of type **Web application** and copy its client ID.
4. Give the web app that **Web** client ID, either way:
   ```bash
   echo "1234-abc.apps.googleusercontent.com" > data/google_client_id.txt
   # or: export ANIVERSE_GOOGLE_CLIENT_ID=1234-abc.apps.googleusercontent.com
   ```
   then restart the web app on port 8000.

If the Google picker says the app "isn't configured", the Android client's
package name or SHA-1 does not match the APK that is installed.

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

**`failed to build selectolax` / `pydantic-core`** — you are on a Python newer
than the old pins had wheels for, so pip tried to compile them, which needs a
Rust toolchain for pydantic-core and a C compiler for selectolax. The
requirements now floor those at versions that ship wheels through Python 3.14,
so a `git pull` and a reinstall is the fix:

```bash
git pull
python3 -m pip install -r AniVerseApiUrl/requirements.txt -r requirements.txt
```

If you are stuck on an older checkout, the alternative is a Python 3.12 venv,
where the original pins do have wheels.

**Nothing plays** — check `logs\backend.log`. A cold resolve fans out across
every provider and can include a proof-of-work solve, so the first request for
an episode legitimately takes tens of seconds. Subsequent ones are cached for
10 minutes.
