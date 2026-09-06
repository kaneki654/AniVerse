# AniVerse - Anime Streaming App

A lightweight anime streaming application built with FastAPI, Jinja2, Vanilla JS, and HLS.js.

## Prerequisites

- Python 3.9+
- Internet connection

## Setup

AniVerse runs as **two** servers: a backend on 8001 that resolves streams, and a
frontend on 8000 that serves the player and proxies the backend under
`/api/anime/*`.

```bat
pip install -r AniVerseApiUrl\requirements.txt -r requirements.txt
run.bat
```

Then open <http://localhost:8000>.

Full instructions -- including reaching it from a phone over a Cloudflare
tunnel, and what to do when that URL changes -- are in **[SETUP.md](SETUP.md)**.

> `run.sh` and the `libs/` folder are from the original Linux single-server
> deployment. `libs/` holds Linux-only `.so` binaries; on Windows install the
> requirements normally and do not put it on `PYTHONPATH`.

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
