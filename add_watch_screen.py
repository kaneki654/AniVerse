import re

with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

# Add new imports if needed
if "from textual.widgets import" in content and "Static" not in content:
    pass

watch_screen_code = """
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
            yield Label(f"[bold red]{title}[/bold red] - Episode {self.ep_num} ({self.category.upper()})", classes="watch-title")
            
            # Video Player Placeholder
            yield Button("▶ CLICK TO PLAY VIDEO IN TERMINAL ◀", id="play-video-btn", variant="error", classes="video-placeholder")
            
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
                    btn = Button(str(i), id=f"ep-btn-{i}", variant="primary" if i == self.ep_num else "default")
                    yield btn
                    
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
        import httpx
        async with httpx.AsyncClient(timeout=30.0) as client:
            try:
                resp = await client.get(url)
                data = resp.json()
                
                if not data or "error" in data or not data.get("streams"):
                    self.notify("Failed to resolve video stream!", severity="error")
                    return
                
                self.streams_data = data
                
                # Update server select
                server_select = self.query_one("#server-select", Select)
                options = [(s.get("server", "Unknown"), s.get("server", "Unknown")) for s in data["streams"]]
                
                # We need to update the options via call_from_thread or safely
                self.app.call_from_thread(self.update_server_select, options, server if server != "Auto" else options[0][1])
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
            # Reset button colors
            for b in self.query("Grid Button"):
                b.variant = "default"
            event.button.variant = "primary"
            
            # Reload
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
        stream = next((s for s in self.streams_data["streams"] if s.get("server") == server_val), self.streams_data["streams"][0])
        
        stream_url = stream["url"]
        headers = self.streams_data.get("headers", {})
        subtitles = self.streams_data.get("subtitles", [])
        
        sub_url = next((s.get("file") for s in subtitles if "eng" in s.get("label", "").lower() or s.get("label") == "English"), None)
        if not sub_url and subtitles:
            sub_url = subtitles[0].get("file")
            
        mpv_args = ["mpv", stream_url, "--vo=tct", "--quiet", "--really-quiet"]
        if sub_url:
            mpv_args.append(f"--sub-file={sub_url}")
        if "Referer" in headers:
            mpv_args.append(f"--http-header-fields=Referer: {headers['Referer']}")
            
        with self.app.suspend():
            import subprocess
            import os
            os.system('cls' if os.name == 'nt' else 'clear')
            print(f"Playing Episode {self.ep_num} ({self.category}) on {stream.get('server', 'Unknown')}...")
            subprocess.run(mpv_args)
            os.system('cls' if os.name == 'nt' else 'clear')

    def action_go_back(self):
        self.app.pop_screen()
"""

# Insert WatchScreen class before AniVerseApp
content = content.replace("class AniVerseApp(App):", watch_screen_code + "\nclass AniVerseApp(App):")

# Replace "Browser" button in AnimeDetailScreen with "CLI Player"
old_browser_btn = 'Button("Browser", variant="primary", id="watch-browser-btn") if status != "NOT_YET_RELEASED" else Label(""),'
new_cli_btn = 'Button("Built-in Player", variant="primary", id="watch-cli-btn") if status != "NOT_YET_RELEASED" else Label(""),'
content = content.replace(old_browser_btn, new_cli_btn)

# Update on_button_pressed in AnimeDetailScreen
old_handler = """        elif event.button.id in ["watch-mpv-btn", "watch-vlc-btn", "watch-browser-btn"]:
            ep = self.query_one("#ep-input", Select).value
            audio = self.query_one("#audio-input", Select).value
            if not ep:
                self.app.notify("Please enter an episode number", severity="error")
                return
            if audio not in ["sub", "dub"]:
                self.app.notify("Audio must be sub or dub", severity="error")
                return
            
            player = "mpv"
            if event.button.id == "watch-vlc-btn":
                player = "vlc"
            elif event.button.id == "watch-browser-btn":
                player = "browser"
                
            self.app.play_anime(self.anime["id"], int(ep), audio, player)"""

new_handler = """        elif event.button.id in ["watch-mpv-btn", "watch-vlc-btn", "watch-cli-btn"]:
            ep = self.query_one("#ep-input", Select).value
            audio = self.query_one("#audio-input", Select).value
            if not ep:
                self.app.notify("Please enter an episode number", severity="error")
                return
            if audio not in ["sub", "dub"]:
                self.app.notify("Audio must be sub or dub", severity="error")
                return
            
            if event.button.id == "watch-cli-btn":
                self.app.push_screen(WatchScreen(self.anime, int(ep), audio))
                return
                
            player = "mpv"
            if event.button.id == "watch-vlc-btn":
                player = "vlc"
                
            self.app.play_anime(self.anime["id"], int(ep), audio, player)"""
content = content.replace(old_handler, new_handler)

# Add CSS for WatchScreen
old_css = '/* Detail Screen */'
new_css = """
    /* Watch Screen */
    .watch-title {
        content-align: center middle;
        width: 100%;
        margin: 1 0;
        font-size: 20;
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
    
    /* Detail Screen */"""
content = content.replace(old_css, new_css)

with open('AniVerse-cli/aniverse.py', 'w') as f:
    f.write(content)

print("Added WatchScreen to CLI!")
