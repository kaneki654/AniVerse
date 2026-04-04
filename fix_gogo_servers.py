import re

with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

old_get_servers = '''        try:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                return []
                
            tree = HTMLParser(resp.text)
            servers = []
            
            # Find the server list elements
            for li in tree.css(".anime_muti_link ul li"):
                embed_link = li.attributes.get("data-video")
                server_name = li.attributes.get("class", "unknown")
                if embed_link:
                    if embed_link.startswith("//"):
                        embed_link = "https:" + embed_link
                    servers.append({
                        "name": server_name.replace("anime", "Vidstreaming"),
                        "url": embed_link
                    })
            return servers'''

new_get_servers = '''        try:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                return []
                
            tree = HTMLParser(resp.text)
            servers = []
            
            # Find the server list elements
            for li in tree.css(".anime_muti_link ul li a"):
                embed_link = li.attributes.get("data-video")
                server_name = li.text(strip=True).replace("Choose this server", "")
                if embed_link:
                    if embed_link.startswith("//"):
                        embed_link = "https:" + embed_link
                    servers.append({
                        "name": server_name,
                        "url": embed_link
                    })
            return servers'''

if old_get_servers in content:
    content = content.replace(old_get_servers, new_get_servers)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed get_servers to look at 'a' tags!")
else:
    print("Could not find get_servers code.")
