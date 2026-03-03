# AniVerse - Anime Streaming App

A lightweight anime streaming application built with FastAPI, Jinja2, Vanilla JS, and HLS.js.

## Prerequisites

- Python 3.7+
- Internet connection (to fetch API data and HLS.js from CDN)

## Setup

1. Install dependencies (already included in `libs` for convenience):
   If you want to install locally:
   pip install -r requirements.txt

2. Run the application:
   ./run.sh

   Or manually:
   export PYTHONPATH=$(pwd)/libs
   python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

3. Open your browser and navigate to:
   http://localhost:8000

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
