#!/usr/bin/env python3
import asyncio
import httpx
import os
import subprocess
import sys
import urllib.parse
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.layout import Layout
from rich.align import Align
from rich.prompt import Prompt
from rich.text import Text
from rich.columns import Columns
from rich.padding import Padding
from rich import box

API_BASE = "http://localhost:8001"
console = Console()

async def fetch_json(client, url):
    try:
        resp = await client.get(url, timeout=15.0)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        return None

def create_header():
    title = Text("ANIVERSE", style="bold red", justify="center")
    nav = Text(" [1] Search   |   [2] Trending   |   [3] Popular   |   [4] Latest   |   [q] Quit ", style="white bold", justify="center")
    
    table = Table.grid(expand=True)
    table.add_row(title)
    table.add_row(Text(""))
    table.add_row(nav)
    
    return Panel(table, style="red", box=box.HEAVY)

def create_anime_card(idx, anime):
    title = anime.get("title", {}).get("english") or anime.get("title", {}).get("romaji") or "Unknown"
    if len(title) > 25:
        title = title[:22] + "..."
        
    ep = str(anime.get("exact_latest_episode") or anime.get("episodes") or "?")
    status = anime.get("status", "UNKNOWN")
    
    # Color code status
    status_color = "green" if status == "RELEASING" else "cyan" if status == "FINISHED" else "yellow"
    
    content = f"[bold white]{title}[/bold white]\n\n"
    content += f"Status: [{status_color}]{status}[/{status_color}]\n"
    content += f"Episodes: [red]{ep}[/red]\n"
    content += f"\n[dim]ID: {idx}[/dim]"
    
    return Panel(content, border_style="red", expand=False, width=32, height=8)

def create_grid(anime_list, title):
    if not anime_list:
        return Panel(Align.center(Text("No anime found.", style="yellow")), title=title, border_style="red")
        
    cards = [create_anime_card(idx + 1, anime) for idx, anime in enumerate(anime_list)]
    columns = Columns(cards, expand=True, equal=True, column_first=False)
    
    return Panel(Padding(columns, (1, 2)), title=f"[bold white] {title} [/bold white]", border_style="red", box=box.ROUNDED)

async def watch_episode(client, anime_id, ep_num, category):
    console.clear()
    console.print(create_header())
    console.print(Align.center(f"\n[bold yellow]Resolving Episode {ep_num} ({category.upper()})...[/bold yellow]\n"))
    
    url = f"{API_BASE}/anime/resolve/{anime_id}/{ep_num}?category={category}"
    data = await fetch_json(client, url)
        
    if not data or "error" in data or not data.get("streams"):
        console.print(Align.center("[bold red]Failed to resolve video stream![/bold red]"))
        Prompt.ask("Press Enter to continue")
        return

    streams = data.get("streams", [])
    stream = streams[0]
    stream_url = stream["url"]
    server_name = stream.get("server", "Unknown Server")
    
    console.print(Align.center(f"[bold green]Stream resolved on {server_name}! Launching MPV...[/bold green]"))
    console.print(Align.center("[dim]The video player will open in a new window.[/dim]\n"))
    
    # Run mpv normally (no --vo=tct) to open a real video window
    mpv_args = [
        "mpv", 
        stream_url, 
        "--title=AniVerse Player",
        "--fs"  # Start in fullscreen
    ]
    
    # Subtitles
    subtitles = data.get("subtitles", [])
    sub_url = next((s.get("file") for s in subtitles if "eng" in s.get("label", "").lower() or s.get("label") == "English"), None)
    if not sub_url and subtitles:
        sub_url = subtitles[0].get("file")
        
    if sub_url:
        mpv_args.append(f"--sub-file={sub_url}")
        
    headers = data.get("headers", {})
    if "Referer" in headers:
        mpv_args.append(f"--http-header-fields=Referer: {headers['Referer']}")
        
    try:
        subprocess.run(mpv_args)
    except FileNotFoundError:
        console.print(Align.center("[bold red]Error: `mpv` is not installed.[/bold red]"))
        console.print(Align.center("Install it via `sudo apt install mpv` or `brew install mpv`."))
        Prompt.ask("Press Enter to continue")

async def anime_details(client, anime):
    anime_id = anime["id"]
    title = anime.get("title", {}).get("english") or anime.get("title", {}).get("romaji") or "Unknown"
    ep_count = anime.get("exact_latest_episode") or anime.get("episodes") or 12
    status = anime.get('status', 'UNKNOWN')
    desc = anime.get('description', 'No description available.')
    # Remove HTML tags from description
    import re
    desc = re.sub(r'<[^>]+>', '', desc)
    
    while True:
        console.clear()
        console.print(create_header())
        
        info = f"\n[bold white]{title}[/bold white]\n\n"
        info += f"Status: [green]{status}[/green] | Episodes: [red]{ep_count}[/red]\n\n"
        info += f"[dim]{desc}[/dim]\n"
        
        console.print(Panel(Padding(info, (1, 2)), title="[bold red] Anime Details [/bold red]", border_style="red", box=box.ROUNDED))
        
        if status == 'NOT_YET_RELEASED':
            console.print(Align.center("\n[bold red]This anime hasn't been released yet![/bold red]"))
            Prompt.ask("\nPress Enter to go back")
            break
            
        console.print("\n[bold red]Watch Options:[/bold red]")
        console.print(f"  Enter an [bold white]Episode Number[/bold white] (1 to {ep_count}) to watch")
        console.print("  Or enter [bold red]'b'[/bold red] to go back to the menu")
        
        choice = Prompt.ask("\n[bold red]>[/bold red] Choice")
        if choice.lower() == 'b':
            break
            
        if choice.isdigit():
            ep = int(choice)
            cat = Prompt.ask("[bold red]>[/bold red] Audio", choices=["sub", "dub"], default="sub")
            await watch_episode(client, anime_id, ep, cat)

async def main_menu():
    async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
        current_list = []
        list_title = "Trending Anime"
        
        # Load initial data
        try:
            current_list = await fetch_json(client, f"{API_BASE}/anime/trending?per_page=12") or []
        except:
            current_list = []
            
        while True:
            console.clear()
            
            layout = Layout()
            layout.split_column(
                Layout(name="header", size=5),
                Layout(name="main")
            )
            layout["header"].update(create_header())
            layout["main"].update(create_grid(current_list, list_title))
            
            console.print(layout)
            
            console.print("\n[dim]Enter a menu number (1-4), an Anime ID from the cards above to view, or 'q' to quit.[/dim]")
            cmd = Prompt.ask("[bold red]>[/bold red] Command")
            
            if cmd.lower() == 'q':
                break
            elif cmd == '1':
                q = Prompt.ask("[bold red]>[/bold red] Search query")
                if q:
                    res = await fetch_json(client, f"{API_BASE}/anime/search/{urllib.parse.quote(q)}")
                    if res:
                        current_list = res
                        list_title = f"Search Results: {q}"
            elif cmd == '2':
                res = await fetch_json(client, f"{API_BASE}/anime/trending?per_page=12")
                if res:
                    current_list = res
                    list_title = "Trending Anime"
            elif cmd == '3':
                res = await fetch_json(client, f"{API_BASE}/anime/popular?per_page=12")
                if res:
                    current_list = res
                    list_title = "Popular Anime"
            elif cmd == '4':
                res = await fetch_json(client, f"{API_BASE}/anime/latest?per_page=12")
                if res:
                    current_list = res
                    list_title = "Latest Episodes"
            elif cmd.isdigit():
                idx = int(cmd) - 1
                if 0 <= idx < len(current_list):
                    await anime_details(client, current_list[idx])

if __name__ == "__main__":
    try:
        asyncio.run(main_menu())
    except KeyboardInterrupt:
        sys.exit(0)
