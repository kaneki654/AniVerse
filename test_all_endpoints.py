import asyncio
import httpx

FRONTEND_URL = "http://localhost:8000"
API_URL = "http://localhost:8001"

async def test_endpoint(client, name, url):
    try:
        resp = await client.get(url, timeout=10)
        status = resp.status_code
        if status == 200:
            print(f"✅ {name}: OK ({status})")
        else:
            print(f"❌ {name}: FAILED ({status})")
    except Exception as e:
        print(f"❌ {name}: ERROR ({e})")

async def main():
    print("--- Testing API Backend (8001) ---")
    async with httpx.AsyncClient(follow_redirects=True) as client:
        await test_endpoint(client, "Health", f"{API_URL}/health")
        await test_endpoint(client, "Popular", f"{API_URL}/anime/popular?per_page=5")
        await test_endpoint(client, "Trending", f"{API_URL}/anime/trending?per_page=5")
        await test_endpoint(client, "Latest", f"{API_URL}/anime/latest?per_page=5")
        await test_endpoint(client, "Upcoming", f"{API_URL}/anime/upcoming?per_page=5")
        await test_endpoint(client, "Genre", f"{API_URL}/anime/genre/Action?per_page=5")
        await test_endpoint(client, "Browse", f"{API_URL}/anime/browse?per_page=5")
        await test_endpoint(client, "Search", f"{API_URL}/anime/search/Naruto")
        
    print("\n--- Testing Main Frontend (8000) ---")
    async with httpx.AsyncClient(follow_redirects=True) as client:
        await test_endpoint(client, "Home", f"{FRONTEND_URL}/")
        await test_endpoint(client, "Anime Detail", f"{FRONTEND_URL}/anime/16498")
        await test_endpoint(client, "Watch Episode", f"{FRONTEND_URL}/watch/16498/1")
        await test_endpoint(client, "Search Page", f"{FRONTEND_URL}/search?q=Naruto")
        await test_endpoint(client, "AZ List", f"{FRONTEND_URL}/azlist/all")
        await test_endpoint(client, "Schedule", f"{FRONTEND_URL}/schedule")
        await test_endpoint(client, "Genre Action", f"{FRONTEND_URL}/genre/Action")
        await test_endpoint(client, "Browse Page", f"{FRONTEND_URL}/anime/browse")

if __name__ == "__main__":
    asyncio.run(main())
