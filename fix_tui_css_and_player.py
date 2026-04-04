import re

with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

# 1. Remove font-size from CSS
content = content.replace("font-size: 24;\n", "")
content = content.replace("font-size: 24;", "")

# 2. Update AnimeDetailScreen buttons
old_actions = """                        Input(placeholder="sub/dub", id="audio-input", value="sub"),
                        Button("Watch Now", variant="error", id="watch-btn") if status != "NOT_YET_RELEASED" else Label("[red]Not Yet Released[/red]"),
                        Button("Back", id="back-btn"),
                        classes="detail-actions\""""

new_actions = """                        Input(placeholder="sub/dub", id="audio-input", value="sub"),
                        Button("MPV", variant="error", id="watch-mpv-btn") if status != "NOT_YET_RELEASED" else Label("[red]Not Yet Released[/red]"),
                        Button("VLC", variant="warning", id="watch-vlc-btn") if status != "NOT_YET_RELEASED" else Label(""),
                        Button("Browser", variant="primary", id="watch-browser-btn") if status != "NOT_YET_RELEASED" else Label(""),
                        Button("Back", id="back-btn"),
                        classes="detail-actions\""""

if old_actions in content:
    content = content.replace(old_actions, new_actions)
else:
    print("Could not find the button actions in AnimeDetailScreen.")

# 3. Update AnimeDetailScreen on_button_pressed
old_button_handler = """    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "back-btn":
            self.action_go_back()
        elif event.button.id == "watch-btn":
            ep = self.query_one("#ep-input", Input).value
            audio = self.query_one("#audio-input", Input).value
            if not ep:
                self.app.notify("Please enter an episode number", severity="error")
                return
            if audio not in ["sub", "dub"]:
                self.app.notify("Audio must be sub or dub", severity="error")
                return
                
            self.app.play_anime(self.anime["id"], int(ep), audio)"""

new_button_handler = """    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "back-btn":
            self.action_go_back()
        elif event.button.id in ["watch-mpv-btn", "watch-vlc-btn", "watch-browser-btn"]:
            ep = self.query_one("#ep-input", Input).value
            audio = self.query_one("#audio-input", Input).value
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

if old_button_handler in content:
    content = content.replace(old_button_handler, new_button_handler)
else:
    print("Could not find on_button_pressed in AnimeDetailScreen.")

# 4. Update play_anime signature and logic
old_play_anime = """    @work(exclusive=True)
    async def play_anime(self, anime_id: int, ep_num: int, category: str):
        self.notify(f"Resolving Episode {ep_num} ({category})...")"""

new_play_anime = """    @work(exclusive=True)
    async def play_anime(self, anime_id: int, ep_num: int, category: str, player: str = "mpv"):
        if player == "browser":
            import webbrowser
            webbrowser.open(f"http://localhost:8000/watch/{anime_id}/{ep_num}")
            self.notify("Opened in web browser!", severity="information")
            return
            
        self.notify(f"Resolving Episode {ep_num} ({category})...")"""

if old_play_anime in content:
    content = content.replace(old_play_anime, new_play_anime)
else:
    print("Could not find play_anime signature.")

old_subprocess = """                # We run mpv asynchronously without blocking the TUI event loop
                self.notify("Playing in MPV...", severity="information")
                import subprocess
                subprocess.Popen(mpv_args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)"""

new_subprocess = """                # We run mpv asynchronously without blocking the TUI event loop
                self.notify(f"Playing in {player.upper()}...", severity="information")
                import subprocess
                
                if player == "vlc":
                    vlc_args = ["vlc", stream_url]
                    if sub_url:
                        vlc_args.append(f"--sub-file={sub_url}")
                    if "Referer" in headers:
                        vlc_args.append(f"--http-referrer={headers['Referer']}")
                    subprocess.Popen(vlc_args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
                else:
                    subprocess.Popen(mpv_args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)"""

if old_subprocess in content:
    content = content.replace(old_subprocess, new_subprocess)
else:
    print("Could not find subprocess logic.")

with open('AniVerse-cli/aniverse.py', 'w') as f:
    f.write(content)
print("Applied CSS fix and multi-player support.")
