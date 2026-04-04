import httpx
import json
import base64
import re
import urllib.parse
from typing import Dict, Any, List
from selectolax.parser import HTMLParser
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad

from .base import BaseProvider

class GogoAnimeProvider(BaseProvider):
    @property
    def name(self) -> str:
        return "GogoAnime"

    @property
    def base_url(self) -> str:
        return "https://anitaku.to"

    async def resolve(self, anilist_id: str, episode: int, category: str = "sub") -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
            try:
                anime_slug = await self.map_anime(client, anilist_id, category)
                if not anime_slug:
                    return {"error": "Anime not found on GogoAnime (Mapping failed)"}
                    
                episode_id = await self.get_episode(client, anime_slug, episode)
                
                servers = await self.get_servers(client, episode_id, category)
                if not servers:
                    return {"error": "No embed servers found (Might be Cloudflare blocked)"}
                    
                return await self.extract(client, servers, category)
            except Exception as e:
                return {"error": f"GogoAnime extraction failed: {str(e)}"}

    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str, category: str) -> str:
        """Use AniList Title to search GogoAnime directly"""
        try:
            # 1. Get Title from AniList
            query = """
            query ($id: Int) {
              Media (id: $id, type: ANIME) {
                title { romaji english }
              }
            }
            """
            resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": {"id": int(anilist_id)}})
            data = resp.json().get("data", {}).get("Media", {})
            title_ro = data.get("title", {}).get("romaji", "")
            title_en = data.get("title", {}).get("english", "")
            
            def clean_title(t):
                if not t: return ""
                t = re.sub(r'[\[\]\(\)]', '', t)
                return t.strip()
                
            titles_to_try = [clean_title(title_ro), clean_title(title_en)]
            
            for t in titles_to_try:
                if not t: continue
                search_url = f"{self.base_url}/search.html?keyword={urllib.parse.quote(t)}"
                search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"})
                
                matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
                matches = list(dict.fromkeys(matches)) # Remove duplicates
                
                if matches:
                    if category == "sub":
                        # Ensure we don't accidentally pick the dub slug if it was uploaded more recently
                        sub_slug = next((m for m in matches if "-dub" not in m.lower()), matches[0])
                        
                        # Just to be safe, if we picked something like "anime" but "anime-dub" was requested,
                        # the above filter avoids it.
                        return sub_slug
                        
                    elif category == "dub":
                        # We want the dub. See if a dub specifically exists in the search results
                        dub_slug = next((m for m in matches if "-dub" in m.lower()), None)
                        if dub_slug:
                            return dub_slug
                            
                        slug = matches[0]
                        # Check if -dub exists for the main slug
                        check_url = f"{self.base_url}/category/{slug}-dub"
                        try:
                            r = await client.get(check_url, follow_redirects=True)
                            if r.status_code == 200 and "Pages not found" not in r.text:
                                return f"{slug}-dub"
                        except Exception:
                            pass
                        return slug
                    
        except Exception as e:
            print(f"Gogo Search error: {e}")
        return "" 

    async def get_episode(self, client: httpx.AsyncClient, anime_slug: str, episode_num: int) -> str:
        """Construct the standard Gogoanime episode route"""
        return f"{anime_slug}-episode-{episode_num}"

    async def get_servers(self, client: httpx.AsyncClient, episode_id: str, category: str = "sub") -> List[Dict[str, str]]:
        """Scrape the episode page for iframe embed links (Vidstreaming/Goload)"""
        url = f"{self.base_url}/{episode_id}"
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
        
        try:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                return []
                
            tree = HTMLParser(resp.text)
            servers = []
            
            # Anitaku recently merged sub and dub into single pages.
            # We need to find the right div based on the category.
            div_class = "type_DUB" if category == "dub" else "type_SUB"
            div = tree.css_first(f"div.{div_class}")
            
            # If the specific category div is not found, fallback to the generic selector
            if div:
                links = div.css("ul li a")
            elif category == "dub" and "-dub-" not in episode_id:
                return []
            else:
                links = tree.css(".anime_muti_link ul li a")
            
            for li in links:
                embed_link = li.attributes.get("data-video")
                server_name = li.text(strip=True).replace("Choose this server", "")
                if embed_link:
                    if embed_link.startswith("//"):
                        embed_link = "https:" + embed_link
                    servers.append({
                        "name": server_name,
                        "url": embed_link
                    })
            return servers
        except Exception:
            return [] 

    def unpack(self, p: str, a: int, c: int, k: list) -> str:
        def to_base(num, base):
            if num == 0: return '0'
            res = ""
            while num > 0:
                rem = num % base
                res = (str(rem) if rem < 10 else chr(rem - 10 + ord('a'))) + res
                num //= base
            return res

        while c > 0:
            c -= 1
            if k[c]:
                word = to_base(c, a)
                p = re.sub(r'\b' + word + r'\b', k[c], p)
        return p

    async def extract(self, client: httpx.AsyncClient, servers: List[Dict[str, str]], category: str = "sub") -> Dict[str, Any]:
        """
        Extract VibePlayer direct M3U8 streams and subtitles.
        """
        streams = []
        subtitles = []
        
        for server in servers:
            if "vibeplayer" in server["url"]:
                try:
                    embed_url = server["url"]
                    parsed = urllib.parse.urlparse(embed_url)
                    video_id = parsed.path.strip("/")
                    
                    # VibePlayer exposes the master playlist directly
                    master_url = f"https://vibeplayer.site/public/stream/{video_id}/master.m3u8"
                    streams.append({
                        "quality": "auto",
                        "url": master_url,
                        "server": server.get("name", "VibePlayer")
                    })
                    
                    # Extract subtitle from query params
                    params = urllib.parse.parse_qs(parsed.query)
                    subs = params.get('sub', [])
                    if subs:
                        subtitles.append({
                            "file": subs[0],
                            "label": "English",
                            "kind": "captions"
                        })
                        
                    # Also try to extract multiple captions from caption_1, caption_2 etc
                    for key, val in params.items():
                        if key.startswith('caption_'):
                            idx = key.split('_')[1]
                            lang = params.get(f'sub_{idx}', ['English'])[0]
                            subtitles.append({
                                "file": val[0],
                                "label": lang,
                                "kind": "captions"
                            })
                    
                    # For dubs, we don't expect subtitles, so don't continue if empty.
                    if not subtitles and category == "sub":
                        continue
                    break # Success!
                    
                except Exception as e:
                    print(f"VibePlayer Extraction Failed: {e}")
                    continue

            elif "otakuhg" in server["url"] or "streamhg" in server["name"].lower():
                try:
                    embed_url = server["url"]
                    r = await client.get(embed_url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"})
                    match = re.search(r'eval\(function\(p,a,c,k,e,d\).*?return p}\(\'(.*?)\',(\d+),(\d+),\'(.*?)\'\.split', r.text)
                    if match:
                        p = match.group(1).replace('\\\'', "'")
                        a = int(match.group(2))
                        c = int(match.group(3))
                        k = match.group(4).split('|')
                        
                        unpacked = self.unpack(p, a, c, k)
                        m3u8_links = re.findall(r'https?://[^"\']+\.m3u8', unpacked)
                        if m3u8_links:
                            streams.append({
                                "quality": "auto",
                                "url": m3u8_links[0],
                                "server": server.get("name", "StreamHG")
                            })
                            
                            parsed = urllib.parse.urlparse(embed_url)
                            params = urllib.parse.parse_qs(parsed.query)
                            subs = params.get('sub', [])
                            if subs:
                                subtitles.append({
                                    "file": subs[0],
                                    "label": "English",
                                    "kind": "captions"
                                })
                            for key, val in params.items():
                                if key.startswith('caption_'):
                                    idx = key.split('_')[1]
                                    lang = params.get(f'sub_{idx}', ['English'])[0]
                                    subtitles.append({
                                        "file": val[0],
                                        "label": lang,
                                        "kind": "captions"
                                    })
                            if not subtitles and category == "sub":
                                continue
                            # Do NOT break for otakuhg/premilkyway because they are Cloudflare IP-locked.
                            # We want to continue scanning servers so we can find Doodstream as a fallback!
                            continue
                except Exception as e:
                    print(f"OtakuHG Extraction Failed: {e}")
                    continue

            elif "dood" in server["url"] or "vidplay" in server["url"]:
                try:
                    embed_url = server["url"]
                    import random
                    import string
                    import time
                    import asyncio
                    
                    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
                    r = await client.get(embed_url, headers=headers)
                    if r.status_code == 200:
                        match = re.search(r"(/pass_md5/[^']*)", r.text)
                        if match:
                            pass_md5_url = "https://" + urllib.parse.urlparse(embed_url).netloc + match.group(1)
                            token = pass_md5_url.split("/")[-1]
                            
                            await asyncio.sleep(1) # Bypass doodstream simple ratelimit
                            r2 = await client.get(pass_md5_url, headers={"User-Agent": headers["User-Agent"], "Referer": embed_url})
                            
                            if r2.status_code == 200:
                                base_url = r2.text
                                random_str = ''.join(random.choices(string.ascii_letters + string.digits, k=10))
                                expiry = str(int(time.time() * 1000))
                                final_url = f"{base_url}{random_str}?token={token}&expiry={expiry}"
                                
                                streams.append({
                                    "quality": "auto",
                                    "url": final_url,
                                    "server": server.get("name", "Doodstream")
                                })
                                break # Doodstream worked
                except Exception as e:
                    print(f"Doodstream Extraction Failed: {e}")
                    continue

                    
        return {"streams": streams, "subtitles": subtitles}
