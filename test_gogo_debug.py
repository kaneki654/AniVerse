import asyncio
import httpx
from AniVerseApiUrl.app.providers.gogoanime import GogoAnimeProvider

async def main():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient() as client:
        # 1. Map
        slug_sub = await p.map_anime(client, "164172", "sub")
        print("Slug SUB:", slug_sub)
        slug_dub = await p.map_anime(client, "164172", "dub")
        print("Slug DUB:", slug_dub)
        
        if slug_sub:
            ep_sub = await p.get_episode(client, slug_sub, 1)
            print("Ep SUB:", ep_sub)
            servers_sub = await p.get_servers(client, ep_sub, "sub")
            print("Servers SUB:", servers_sub)
            
        if slug_dub:
            ep_dub = await p.get_episode(client, slug_dub, 1)
            print("Ep DUB:", ep_dub)
            servers_dub = await p.get_servers(client, ep_dub, "dub")
            print("Servers DUB:", servers_dub)

asyncio.run(main())
