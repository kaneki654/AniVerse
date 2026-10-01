# AniVerse - Anime Streaming App

A lightweight anime streaming application built with FastAPI, Jinja2, Vanilla JS, and HLS.js.

## Prerequisites

- Python 3.12+ (the pinned numpy needs it)
- Internet connection

## Setup

AniVerse runs as **two** servers: a backend on 8001 that resolves streams, and a
frontend on 8000 that serves the player and proxies the backend under
`/api/anime/*`.

Windows:

```bat
pip install -r AniVerseApiUrl\requirements.txt -r requirements.txt
run.bat
```

Linux / macOS:

```bash
python3 -m pip install -r AniVerseApiUrl/requirements.txt -r requirements.txt
chmod +x run.sh && ./run.sh
```

Then open <http://localhost:8000>.

Full instructions -- including reaching it from a phone over a Cloudflare
tunnel, and what to do when that URL changes -- are in **[SETUP.md](SETUP.md)**.

> The `libs/` folder is left over from the original single-server deployment
> and holds only the frontend's packages -- every backend one is missing from
> it. Install the requirements normally and keep it off `PYTHONPATH` on both
> platforms.

## Website look

The site uses the same 2D pixel-art style as the AniVerse Pixel app (pixel
fonts, sprite icons, blood effects, the katana loader and blood-orb buffering
circle), and talks to the same endpoints, so accounts and watch history are
shared with the app. Its pages are `app/pixel_web.py`, `app/templates/pixel/`
and `app/static/pixel/`. There is no manga section.

The original site is still there, untouched. To switch back to it, start the
frontend with:

```bash
ANIVERSE_WEB_UI=classic ./run.sh
```

## Type checking

The Python code is type-checked with [Pyright](https://github.com/microsoft/pyright).
Settings live in `pyrightconfig.json`, which VS Code's Pylance also reads, so
the editor underlines the same problems the command reports. Install it once:

```bash
python3 -m pip install -r requirements-dev.txt
```

Then run it from the repo root before committing; it should report `0 errors`:

```bash
pyright
```

It checks the frontend (`app/`), the backend (`AniVerseApiUrl/app/`), the shared
`anime_meta.py`, `scripts/` and the tests. The one-off `fix_*`/`patch_*` scripts
in the root are left out.

## Features

- **Home Page**: Spotlight, Trending, Latest Episodes.
- **Search**: Live search suggestions and full search results.
- **Details**: Anime info, characters, and episode list.
- **Watch**: Video player with server selection (Sub/Dub/Raw).
- **A-Z List**: Browse anime alphabetically.
- **Schedule**: View airing schedule.

## Project Structure

- `app/main.py`: Backend logic and API proxy.
- `app/templates/`: HTML templates (Jinja2).
- `app/static/`: CSS and JavaScript files.
- `libs/`: Local python dependencies.
- `run.sh`: Startup script.

## Notes

- This app acts as a proxy to the `hianime` API.
- HLS.js is loaded from CDN for video playback.

## Deployment to Render

1.  **Push to GitHub**:
    *   Initialize a git repository if you haven't: `git init`
    *   Add files: `git add .`
    *   Commit: `git commit -m "Initial commit"`
    *   Push to your GitHub repository.

2.  **Deploy on Render**:
    *   Go to [Render Dashboard](https://dashboard.render.com/).
    *   Click **New +** -> **Web Service**.
    *   Connect your GitHub repository.
    *   Render will detect the `render.yaml` file and configure the service automatically.
    *   Click **Create Web Service**.

3.  **Manual Configuration** (if not using Blueprint):
    *   **Runtime**: Python 3
    *   **Build Command**: `pip install -r requirements.txt`
    *   **Start Command**: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
