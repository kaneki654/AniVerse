import httpx
from bs4 import BeautifulSoup
import asyncio

async def run():
    async with httpx.AsyncClient() as client:
        # Note: the href link from the template is URL encoded: '/search?genres=action' or similar
        # Let's see what the HTML rendered is.
        resp = await client.get("http://localhost:8000/search?genres=action")
        soup = BeautifulSoup(resp.text, 'html.parser')
        
        cards = soup.select(".anime-card")
        print(f"Cards found for 'action': {len(cards)}")
        
        if len(cards) == 0:
            no_results = soup.select_one("h3")
            if no_results:
                print("Message:", no_results.text)
        else:
            print("First 3 cards:", [c.select_one("h4").text for c in cards[:3]])
            
        selected_text = soup.select_one(".selected-genres-text")
        if selected_text:
            print("Selected Genres Text:", selected_text.text.strip())

asyncio.run(run())
