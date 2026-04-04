import asyncio
from curl_cffi import requests
from selectolax.parser import HTMLParser

def test():
    try:
        session = requests.Session(impersonate="chrome110")
        resp = session.get("https://anitaku.pe/jujutsu-kaisen-tv-episode-1", timeout=15)
        print("Status:", resp.status_code)
        
        tree = HTMLParser(resp.text)
        servers = []
        for li in tree.css(".anime_muti_link ul li"):
            embed_link = li.attributes.get("data-video")
            if embed_link:
                if embed_link.startswith("//"):
                    embed_link = "https:" + embed_link
                servers.append(embed_link)
        
        print("Servers:", servers)
        
        if servers:
            embed_url = servers[0]
            resp2 = session.get(embed_url, headers={"Referer": "https://anitaku.pe/"})
            print("Embed Status:", resp2.status_code)
            tree2 = HTMLParser(resp2.text)
            script_tag = tree2.css_first("script[data-name='episode']")
            if script_tag:
                print("Encrypted payload length:", len(script_tag.attributes.get("data-value", "")))
            else:
                print("No script tag found")
    except Exception as e:
        print("Error:", e)

test()
