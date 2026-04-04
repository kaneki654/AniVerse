import re

with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

old_load_data = """    @work(exclusive=True)
    async def load_data(self, category: str, query: str = "") -> None:
        anime_list = self.query_one("#anime-list", ListView)
        await anime_list.clear()
        
        url = f"{API_BASE}/anime/{category}?per_page=20"
        if category == "search":
            url = f"{API_BASE}/anime/search/{urllib.parse.quote(query)}"
            
        async with httpx.AsyncClient(timeout=15.0) as client:
            try:
                resp = await client.get(url)
                if resp.status_code == 200:
                    data = resp.json()
                    for anime in data:
                        await anime_list.append(AnimeCard(anime))
            except Exception as e:
                self.notify(f"Error loading data: {e}", severity="error")"""

new_load_data = """    @work(exclusive=True)
    async def load_data(self, category: str, query: str = "") -> None:
        self.notify("Loading data...", severity="information")
        anime_list = self.query_one("#anime-list", ListView)
        await anime_list.clear()
        
        url = f"{API_BASE}/anime/{category}?per_page=20"
        if category == "search":
            url = f"{API_BASE}/anime/search/{urllib.parse.quote(query)}"
            
        async with httpx.AsyncClient(timeout=15.0) as client:
            try:
                resp = await client.get(url)
                if resp.status_code == 200:
                    data = resp.json()
                    # Extend is exponentially faster than appending in a loop!
                    cards = [AnimeCard(anime) for anime in data]
                    if cards:
                        await anime_list.extend(cards)
                        self.notify("Data loaded successfully!", severity="information")
                    else:
                        self.notify("No results found.", severity="warning")
            except Exception as e:
                self.notify(f"Error loading data: {e}", severity="error")"""

if old_load_data in content:
    content = content.replace(old_load_data, new_load_data)
    with open('AniVerse-cli/aniverse.py', 'w') as f:
        f.write(content)
    print("Fixed TUI loading speed!")
else:
    print("Could not find the load_data method.")
