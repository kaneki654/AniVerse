import re

# 1. Update anilist.py to query AiringSchedule
anilist_path = 'AniVerseApiUrl/app/services/anilist.py'
with open(anilist_path, 'r') as f:
    anilist_content = f.read()

old_latest = """    @classmethod
    async def get_recently_updated(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        graphql_query = '''
        query ($page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (type: ANIME, sort: UPDATED_AT_DESC, isAdult: false) {
              id
              title { romaji english }
              coverImage { large }
              episodes
              nextAiringEpisode { episode }
            }
          }
        }
        '''
        data = await cls._execute_query(graphql_query, {"page": page, "perPage": per_page})
        if data and "Page" in data and "media" in data["Page"]:
            return data["Page"]["media"]
        return []"""

new_latest = """    @classmethod
    async def get_recently_updated(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        import time
        current_time = int(time.time())
        graphql_query = '''
        query ($page: Int, $perPage: Int, $time: Int) {
          Page (page: $page, perPage: $perPage) {
            airingSchedules (
              airingAt_lesser: $time,
              sort: TIME_DESC
            ) {
              episode
              media {
                id
                title { romaji english }
                coverImage { large }
                episodes
              }
            }
          }
        }
        '''
        data = await cls._execute_query(graphql_query, {"page": page, "perPage": per_page, "time": current_time})
        if data and "Page" in data and "airingSchedules" in data["Page"]:
            # Remap to look like the normal media objects but with the explicit exact episode number
            results = []
            seen_ids = set()
            for schedule in data["Page"]["airingSchedules"]:
                media = schedule.get("media")
                if not media: continue
                if media["id"] in seen_ids: continue
                seen_ids.add(media["id"])
                
                # Attach the exact aired episode number
                media["exact_latest_episode"] = schedule.get("episode")
                results.append(media)
            return results
        return []"""

if old_latest in anilist_content:
    anilist_content = anilist_content.replace(old_latest, new_latest)
    with open(anilist_path, 'w') as f:
        f.write(anilist_content)
    print("Updated get_recently_updated to use airingSchedules in anilist.py")
else:
    print("Could not find get_recently_updated in anilist.py")

# 2. Update app/main.py logic to read exact_latest_episode
main_path = 'app/main.py'
with open(main_path, 'r') as f:
    main_content = f.read()

old_latest_main = """            latest_list = latest.json() if isinstance(latest.json(), list) else []
            for item in latest_list:
                ep_count = "?"
                if item.get("nextAiringEpisode"):
                    ep = item["nextAiringEpisode"]["episode"]
                    ep_count = str(ep - 1) if ep > 1 else "1"
                elif item.get("episodes"):
                    ep_count = str(item["episodes"])
                    
                item["episodes"] = {"sub": ep_count}"""

new_latest_main = """            latest_list = latest.json() if isinstance(latest.json(), list) else []
            for item in latest_list:
                ep_count = "?"
                # We specifically injected exact_latest_episode from the AiringSchedule backend
                if item.get("exact_latest_episode"):
                    ep_count = str(item["exact_latest_episode"])
                elif item.get("nextAiringEpisode"):
                    ep = item["nextAiringEpisode"]["episode"]
                    ep_count = str(ep - 1) if ep > 1 else "1"
                elif item.get("episodes"):
                    ep_count = str(item["episodes"])
                    
                item["episodes"] = {"sub": ep_count}"""

if old_latest_main in main_content:
    main_content = main_content.replace(old_latest_main, new_latest_main)
    with open(main_path, 'w') as f:
        f.write(main_content)
    print("Updated app/main.py latest_list loop logic")
else:
    print("Could not find latest_list loop logic in app/main.py")

