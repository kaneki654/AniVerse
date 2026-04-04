import asyncio
import httpx
from AniVerseApiUrl.app.providers.gogoanime import GogoAnimeProvider

async def main():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient() as client:
        slug_sub = await p.map_anime(client, "166531", "sub")
        print("Slug SUB 166531:", slug_sub)
        slug_dub = await p.map_anime(client, "166531", "dub")
        print("Slug DUB 166531:", slug_dub)
        
        if slug_sub:
            ep_sub = await p.get_episode(client, slug_sub, 1)
            servers_sub = await p.get_servers(client, ep_sub, "sub")
            print("Servers SUB:", servers_sub)
            extracted_sub = await p.extract(client, servers_sub)
            print("Extracted SUB:", extracted_sub)
            
        if slug_dub:
            ep_dub = await p.get_episode(client, slug_dub, 1)
            servers_dub = await p.get_servers(client, ep_dub, "dub")
            print("Servers DUB:", servers_dub)
            extracted_dub = await p.extract(client, servers_dub)
            print("Extracted DUB:", extracted_dub)

asyncio.run(main())
