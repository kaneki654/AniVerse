import asyncio
import httpx

async def run():
    async with httpx.AsyncClient() as client:
        resp = await client.get("http://localhost:8000/search?genres=action")
        print(resp.status_code)
        
        # let's grep the response to see if animes were rendered
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(resp.text, 'html.parser')
        cards = soup.select(".anime-card")
        print(f"Found {len(cards)} anime cards")
        
        if len(cards) == 0:
            print(soup.text[:500])

asyncio.run(run())
