import asyncio
import httpx
import time
import json

async def run():
    current_time = int(time.time())
    query = '''
    query ($page: Int, $perPage: Int, $time: Int) {
      Page (page: $page, perPage: $perPage) {
        airingSchedules (
          airingAt_lesser: $time,
          sort: TIME_DESC
        ) {
          id
          episode
          airingAt
          media {
            id
            title { romaji english }
            coverImage { large }
            episodes
            status
          }
        }
      }
    }
    '''
    async with httpx.AsyncClient() as client:
        resp = await client.post("https://graphql.anilist.co", json={
            "query": query, 
            "variables": {"page": 1, "perPage": 10, "time": current_time}
        })
        
        data = resp.json()
        if "errors" in data:
            print(json.dumps(data, indent=2))
        else:
            schedules = data["data"]["Page"]["airingSchedules"]
            for s in schedules:
                media = s["media"]
                title = media["title"]["english"] or media["title"]["romaji"]
                print(f"Ep {s['episode']}: {title}")

asyncio.run(run())
