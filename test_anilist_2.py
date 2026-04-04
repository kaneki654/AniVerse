import asyncio
import httpx

async def main():
    async with httpx.AsyncClient() as client:
        # Search by Title
        query = """
        query ($search: String) {
          Media (search: $search, type: ANIME) {
            id
            title { romaji english }
          }
        }
        """
        resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": {"search": "Oshi no Ko Season 2"}})
        data = resp.json()
        print("Oshi no Ko S2:", data)

        # Also get ID 164172 again
        query_id = """
        query ($id: Int) {
          Media (id: $id, type: ANIME) {
            id
            title { romaji english }
          }
        }
        """
        resp2 = await client.post("https://graphql.anilist.co", json={"query": query_id, "variables": {"id": 166531}})
        print("ID 166531:", resp2.json())

asyncio.run(main())
