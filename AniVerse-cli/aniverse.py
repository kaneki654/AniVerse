#!/usr/bin/env python3
import asyncio
import httpx
import urllib.parse
import os
import subprocess
import re
import tempfile
import climage
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, Input, Static, Label, Button, Select
from textual.containers import Container, Horizontal, VerticalScroll, Vertical, Grid
from textual.screen import Screen
from textual import work

from browser_vidPlay import open_browser_player  # ← new import

API_BASE = "http://localhost:8001"


class AnimeCard(Vertical):
    can_focus = True

    def __init__(self, anime, **kwargs):
        super().__init__(**kwargs)
        self.anime = anime

    def compose(self) -> ComposeResult:
        title = self.anime.get("title", {}).get("english") or self.anime.get("title", {}).get("romaji") or "Unknown"
        status = self.anime.get("status", "UNKNOWN")
        ep = str(self.anime.get("exact_latest_episode") or self.anime.get("episodes") or "?")
        status_color = "green" if status == "RELEASING" else "cyan" if status == "FINISHED" else "yellow"

        self.img_static = Static("Loading Image...", classes="card-image")
        yield self.img_static

        title_disp = title if len(title) <= 25 else title[:22] + "..."
        yield Label(f"[bold white]{title_disp}[/bold white]", classes="card-title")
        yield Label(f"[{status_color}]{status}[/{status_color}] | Ep: [red]{ep}[/red]", classes="card-info")

    def on_mount(self):
        self.load_image()

    @work(thread=True)
    def load_image(self):
        img_url = self.anime.get("coverImage", {}).get("large")
        if not img_url:
            return
        try:
            resp = httpx.get(
                img_url, timeout=15.0,
                headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                         "Referer": "https://anilist.co/"},
                follow_redirects=True,
            )
            if resp.status_code == 200:
                fd, path = tempfile.mkstemp(suffix=".jpg")
                with os.fdopen(fd, "wb") as f:
                    f.write(resp.content)
                ansi = climage.convert(path, is_unicode=True, is_truecolor=True, width=30, palette="default")
                os.remove(path)
                self.app.call_from_thread(self.img_static.update, ansi)
            else:
                self.app.call_from_thread(self.img_static.update, "[Image Unavailable]")
        except Exception:
            self.app.call_from_thread(self.img_static.update, "[Image Error]")

    def on_click(self):
        self.app.push_screen(AnimeDetailScreen(self.anime))

    def key_enter(self):
        self.app.push_screen(AnimeDetailScreen(self.anime))


class AnimeDetailScreen(Screen):
    BINDINGS = [("escape", "go_back", "Back"), ("b", "go_back", "Back")]

    def __init__(self, anime):
        super().__init__()
        self.anime = anime

    def compose(self) -> ComposeResult:
        title = (
            self.anime.get("title", {}).get("english")
            or self.anime.get("title", {}).get("romaji")
            or "Unknown"
        )
        status = self.anime.get("status", "UNKNOWN")
        ep_count = self.anime.get("exact_latest_episode") or self.anime.get("episodes") or 12
        desc = re.sub(r"<[^>]+>", "", self.anime.get("description", "No description available."))
        status_color = "green" if status == "RELEASING" else "cyan" if status == "FINISHED" else "yellow"

        self.img_static = Static("Loading Poster...", classes="detail-image")

        yield Header()
        yield VerticalScroll(
            Horizontal(
                self.img_static,
                Vertical(
                    Label(f"[bold red]{title}[/bold red]", classes="detail-title"),
                    Label(f"Status: [{status_color}]{status}[/{status_color}] | Episodes: {ep_count}",
                          classes="detail-info"),
                    Label(desc, classes="detail-desc"),
                    Horizontal(
                        Label("Ep:", classes="detail-label"),
                        Select(
                            ((str(i), str(i)) for i in range(1, (int(ep_count) if str(ep_count).isdigit() else 12) + 1)),
                            value="1", id="ep-input",
                        ),
                        Label("Aud:", classes="detail-label"),
                        Select((("Sub", "sub"), ("Dub", "dub")), value="sub", id="audio-input"),
                        # ── Playback buttons ──────────────────────────────────────────────
                        *(
                            [
                                Button("MPV",     variant="error",   id="watch-mpv-btn"),
                                Button("VLC",     variant="warning", id="watch-vlc-btn"),
                                # ↓ CHANGED: was "Built-in Player" / watch-cli-btn
                                Button("🌐 Browser", variant="primary", id="watch-browser-btn"),
                            ]
                            if status != "NOT_YET_RELEASED"
                            else [Label("[red]Not Yet Released[/red]")]
                        ),
                        Button("Back", id="back-btn"),
                        classes="detail-actions",
                    ),
                    classes="detail-text-col",
                ),
                classes="detail-hero",
            )
        )
        yield Footer()

    def on_mount(self):
        self.load_image()

    @work(thread=True)
    def load_image(self):
        img_url = self.anime.get("coverImage", {}).get("large")
        if not img_url:
            return
        try:
            resp = httpx.get(
                img_url, timeout=15.0,
                headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                         "Referer": "https://anilist.co/"},
                follow_redirects=True,
            )
            if resp.status_code == 200:
                fd, path = tempfile.mkstemp(suffix=".jpg")
                with os.fdopen(fd, "wb") as f:
                    f.write(resp.content)
                ansi = climage.convert(path, is_unicode=True, is_truecolor=True, width=40, palette="default")
                os.remove(path)
                self.app.call_from_thread(self.img_static.update, ansi)
        except Exception:
            pass

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "back-btn":
            self.action_go_back()
            return

        if event.button.id not in ("watch-mpv-btn", "watch-vlc-btn", "watch-browser-btn"):
            return

        ep = self.query_one("#ep-input", Select).value
        audio = self.query_one("#audio-input", Select).value

        if not ep:
            self.app.notify("Please select an episode number", severity="error")
            return
        if audio not in ("sub", "dub"):
            self.app.notify("Audio must be sub or dub", severity="error")
            return

        # ── CHANGED: browser button opens the HTML player ─────────────────────
        if event.button.id == "watch-browser-btn":
            title = (
                self.anime.get("title", {}).get("english")
                or self.anime.get("title", {}).get("romaji")
                or "Unknown"
            )
            self.app.play_anime(
                self.anime["id"], int(ep), audio,
                player="browser", anime_title=title,
            )
            return

        player = "vlc" if event.button.id == "watch-vlc-btn" else "mpv"
        self.app.play_anime(self.anime["id"], int(ep), audio, player)

    def action_go_back(self):
        self.app.pop_screen()


# WatchScreen is kept intact for any other uses
class WatchScreen(Screen):
    BINDINGS = [("escape", "go_back", "Back"), ("b", "go_back", "Back")]

    def __init__(self, anime, ep_num, category):
        super().__init__()
        self.anime = anime
        self.ep_num = ep_num
        self.category = category
        self.streams_data = None

    def compose(self) -> ComposeResult:
        title = self.anime.get("title", {}).get("english") or self.anime.get("title", {}).get("romaji") or "Unknown"
        ep_count = self.anime.get("exact_latest_episode") or self.anime.get("episodes") or 12

        yield Header()
        with VerticalScroll():
            yield Label(f"[bold red]{title}[/bold red] - Episode {self.ep_num} ({self.category.upper()})",
                        classes="watch-title")
            yield Button("▶ CLICK TO PLAY VIDEO IN TERMINAL ◀", id="play-video-btn", variant="error",
                         classes="video-placeholder")
            with Horizontal(classes="watch-controls"):
                with Vertical(classes="watch-control-col"):
                    yield Label("Servers:")
                    yield Select([], id="server-select")
                with Vertical(classes="watch-control-col"):
                    yield Label("Audio:")
                    yield Select((("Sub", "sub"), ("Dub", "dub")), value=self.category, id="audio-select")
            yield Label("Episodes:", classes="watch-ep-label")
            with Grid(id="episodes-grid", classes="watch-ep-grid"):
                for i in range(1, (int(ep_count) if str(ep_count).isdigit() else 12) + 1):
                    yield Button(str(i), id=f"ep-btn-{i}",
                                 variant="primary" if i == self.ep_num else "default")
            yield Button("Go Back", id="back-btn", classes="watch-back-btn")
        yield Footer()

    def on_mount(self):
        self.load_sources(self.ep_num, self.category, "Auto")

    @work(exclusive=True)
    async def load_sources(self, ep_num, category, server):
        self.notify(f"Loading Episode {ep_num} sources...")
        self.ep_num = ep_num
        self.category = category
        url = f"{API_BASE}/anime/resolve/{self.anime['id']}/{ep_num}?category={category}"
        async with httpx.AsyncClient(timeout=30.0) as client:
            try:
                resp = await client.get(url)
                data = resp.json()
                if not data or "error" in data or not data.get("streams"):
                    self.notify("Failed to resolve video stream!", severity="error")
                    return
                self.streams_data = data
                server_select = self.query_one("#server-select", Select)
                options = [(s.get("server", "Unknown"), s.get("server", "Unknown")) for s in data["streams"]]
                self.app.call_from_thread(
                    self.update_server_select, options,
                    server if server != "Auto" else options[0][1],
                )
                self.notify("Sources loaded! Click the Play button.", severity="information")
            except Exception as e:
                self.notify(f"Playback error: {e}", severity="error")

    def update_server_select(self, options, value):
        server_select = self.query_one("#server-select", Select)
        server_select.set_options(options)
        server_select.value = value

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "back-btn":
            self.action_go_back()
        elif event.button.id == "play-video-btn":
            self.play_video()
        elif event.button.id and event.button.id.startswith("ep-btn-"):
            ep = int(event.button.id.split("-")[-1])
            for b in self.query("Grid Button"):
                b.variant = "default"
            event.button.variant = "primary"
            self.load_sources(ep, self.category, "Auto")

    def on_select_changed(self, event: Select.Changed) -> None:
        if event.select.id == "audio-select" and event.value != Select.BLANK:
            if event.value != self.category:
                self.load_sources(self.ep_num, event.value, "Auto")

    def play_video(self):
        if not self.streams_data:
            self.notify("No streams loaded yet!", severity="error")
            return
        server_val = self.query_one("#server-select", Select).value
        stream = next(
            (s for s in self.streams_data["streams"] if s.get("server") == server_val),
            self.streams_data["streams"][0],
        )
        stream_url = stream["url"]
        headers = self.streams_data.get("headers", {})
        subtitles = self.streams_data.get("subtitles", [])
        sub_url = next(
            (s.get("file") for s in subtitles if "eng" in s.get("label", "").lower() or s.get("label") == "English"),
            None,
        )
        if not sub_url and subtitles:
            sub_url = subtitles[0].get("file")
        mpv_args = ["mpv", stream_url, "--vo=tct", "--quiet", "--really-quiet"]
        if sub_url:
            mpv_args.append(f"--sub-file={sub_url}")
        if "Referer" in headers:
            mpv_args.append(f"--http-header-fields=Referer: {headers['Referer']}")
        with self.app.suspend():
            os.system("cls" if os.name == "nt" else "clear")
            print(f"Playing Episode {self.ep_num} ({self.category}) on {stream.get('server', 'Unknown')}...")
            subprocess.run(mpv_args)
            os.system("cls" if os.name == "nt" else "clear")

    def action_go_back(self):
        self.app.pop_screen()


class AniVerseApp(App):
    CSS = """
    Screen {
        background: #121212;
    }

    #navbar {
        height: 3;
        background: #1f1f1f;
        dock: top;
        align: center middle;
    }

    .nav-btn {
        min-width: 15;
        border: none;
        background: transparent;
        color: #aaa;
    }
    .nav-btn:hover {
        color: white;
    }

    #search-bar {
        width: 30;
        margin-left: 2;
    }

    #main-scroll {
        width: 100%;
        height: 100%;
        padding: 1 2;
    }

    #section-title {
        text-style: bold;
        color: white;
        margin-bottom: 1;
        padding-left: 1;
        border-left: vkey #e50914;
    }

    #cards-grid {
        layout: grid;
        grid-size: 5;
        grid-columns: 1fr;
        grid-rows: auto;
        grid-gutter: 1 2;
    }

    AnimeCard {
        width: 100%;
        height: 25;
        border: round #333;
        background: #1a1a1a;
        padding: 1;
    }

    AnimeCard:focus {
        border: round #e50914;
        background: #2a2a2a;
    }

    .card-image {
        height: 18;
        content-align: center middle;
        margin-bottom: 1;
    }

    .card-title {
        text-align: center;
        width: 100%;
        text-style: bold;
    }

    .card-info {
        text-align: center;
        width: 100%;
    }

    /* Watch Screen */
    .watch-title {
        content-align: center middle;
        width: 100%;
        margin: 1 0;
    }
    .video-placeholder {
        width: 100%;
        height: 15;
        margin: 1 2;
    }
    .watch-controls {
        height: 5;
        margin: 1 2;
    }
    .watch-control-col {
        width: 1fr;
        margin-right: 2;
    }
    .watch-ep-label {
        margin: 1 2;
        text-style: bold;
    }
    .watch-ep-grid {
        layout: grid;
        grid-size: 10;
        grid-columns: 1fr;
        grid-rows: auto;
        grid-gutter: 1 1;
        margin: 0 2;
    }
    .watch-back-btn {
        margin: 2;
    }

    /* Detail Screen */
    .detail-hero {
        padding: 2;
    }

    .detail-image {
        width: 45;
        content-align: center top;
        margin-right: 4;
    }

    .detail-text-col {
        width: 1fr;
    }

    .detail-title {
        text-style: bold;
        margin-bottom: 1;
    }

    .detail-info {
        color: #aaa;
        margin-bottom: 2;
    }

    .detail-desc {
        color: #ddd;
        margin-bottom: 2;
        height: 15;
        overflow-y: auto;
    }

    .detail-actions {
        height: auto;
        align: left middle;
    }

    .detail-label {
        padding-top: 1;
        margin-right: 1;
    }

    #ep-input, #audio-input {
        width: 15;
        margin-right: 2;
    }

    #watch-btn {
        margin-right: 2;
    }
    """

    BINDINGS = [
        ("q", "quit", "Quit"),
        ("right", "focus_next", "Next"),
        ("left", "focus_previous", "Prev"),
        ("down", "focus_next", "Next"),
        ("up", "focus_previous", "Prev"),
    ]

    def compose(self) -> ComposeResult:
        with Horizontal(id="navbar"):
            yield Label(" [bold red]ANIVERSE[/bold red]  ", classes="logo")
            yield Button("🔥 Trending", id="nav-trending", classes="nav-btn")
            yield Button("⭐️ Popular",  id="nav-popular",  classes="nav-btn")
            yield Button("📺 Latest",   id="nav-latest",   classes="nav-btn")
            yield Input(placeholder="Search anime...", id="search-bar")
        with VerticalScroll(id="main-scroll"):
            yield Label("Trending Now", id="section-title")
            yield Grid(id="cards-grid")
        yield Footer()

    def on_mount(self) -> None:
        self.load_data("trending")

    @work(exclusive=True)
    async def load_data(self, category: str, query: str = "") -> None:
        self.notify("Loading data...", severity="information")
        grid = self.query_one("#cards-grid", Grid)
        title_label = self.query_one("#section-title", Label)
        await grid.query("*").remove()

        url = f"{API_BASE}/anime/{category}?per_page=15"
        title_text = category.capitalize()
        if category == "search":
            url = f"{API_BASE}/anime/search/{urllib.parse.quote(query)}"
            title_text = f"Search Results: {query}"
        title_label.update(f"[bold]{title_text}[/bold]")

        async with httpx.AsyncClient(timeout=15.0) as client:
            try:
                resp = await client.get(url)
                if resp.status_code == 200:
                    data = resp.json()
                    cards = [AnimeCard(anime) for anime in data]
                    if cards:
                        await grid.mount_all(cards)
                        self.notify("Data loaded successfully!", severity="information")
                        cards[0].focus()
                    else:
                        self.notify("No results found.", severity="warning")
            except Exception as e:
                self.notify(f"Error loading data: {e}", severity="error")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "nav-trending":
            self.load_data("trending")
        elif event.button.id == "nav-popular":
            self.load_data("popular")
        elif event.button.id == "nav-latest":
            self.load_data("latest")

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if event.input.id == "search-bar" and event.value:
            self.load_data("search", event.value)

    # ── CHANGED: accepts anime_title so the browser player can display it ───
    @work(exclusive=True)
    async def play_anime(
        self,
        anime_id: int,
        ep_num: int,
        category: str,
        player: str = "mpv",
        anime_title: str = "Unknown",
    ):
        self.notify(f"Resolving Episode {ep_num} ({category})…")

        url = f"{API_BASE}/anime/resolve/{anime_id}/{ep_num}?category={category}"
        async with httpx.AsyncClient(timeout=30.0) as client:
            try:
                resp = await client.get(url)
                data = resp.json()

                if not data or "error" in data or not data.get("streams"):
                    self.notify("Failed to resolve video stream!", severity="error")
                    return

                # ── CHANGED: browser opens the HTML player ───────────────────
                if player == "browser":
                    open_browser_player(anime_title, ep_num, category, data)
                    self.notify("Opened in browser!", severity="information")
                    return

                stream = data["streams"][0]
                stream_url = stream["url"]
                server_name = stream.get("server", "Unknown Server")
                subtitles = data.get("subtitles", [])
                sub_url = next(
                    (s.get("file") for s in subtitles
                     if "eng" in s.get("label", "").lower() or s.get("label") == "English"),
                    None,
                )
                if not sub_url and subtitles:
                    sub_url = subtitles[0].get("file")
                headers = data.get("headers", {})

                self.notify(f"Stream found on {server_name}! Launching {player.upper()}…",
                            severity="information")

                if player == "vlc":
                    args = ["vlc", stream_url]
                    if sub_url:
                        args.append(f"--sub-file={sub_url}")
                    if "Referer" in headers:
                        args.append(f"--http-referrer={headers['Referer']}")
                else:
                    args = ["mpv", stream_url, "--title=AniVerse Player", "--fs"]
                    if sub_url:
                        args.append(f"--sub-file={sub_url}")
                    if "Referer" in headers:
                        args.append(f"--http-header-fields=Referer: {headers['Referer']}")

                subprocess.Popen(args, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)

            except Exception as e:
                self.notify(f"Playback error: {e}", severity="error")


if __name__ == "__main__":
    app = AniVerseApp()
    app.run()