with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

import re

old_extract = '''    async def extract(self, client: httpx.AsyncClient, servers: List[Dict[str, str]]) -> Dict[str, Any]:
        """
        The REAL AES Decryption logic for Vidstreaming/Goload servers.
        """
        streams = []
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
        
        # Hardcoded recent AES keys for Goload/Vidstreaming
        # In a perfect system, these are scraped dynamically from the embed JS
        KEY = b"37911490979715163134003223491201"
        IV = b"3134003223491201"
        SECOND_KEY = b"54674150092385112722088009059203"
        
        for server in servers:
            if "vidstreaming" in server["url"] or "goload" in server["url"] or "playgo1" in server["url"]:
                try:
                    embed_url = server["url"]
                    resp = await client.get(embed_url, headers=headers)
                    if resp.status_code != 200:
                        continue
                        
                    # 1. Parse the encrypted payload from the HTML
                    tree = HTMLParser(resp.text)
                    encrypted_data = None
                    script_tag = tree.css_first("script[data-name='episode']")
                    if script_tag:
                        encrypted_data = script_tag.attributes.get("data-value")
                        
                    if not encrypted_data:
                        continue
                        
                    # 2. Decrypt the payload
                    cipher = AES.new(KEY, AES.MODE_CBC, IV)
                    decrypted_params = unpad(cipher.decrypt(base64.b64decode(encrypted_data)), AES.block_size).decode('utf-8')
                    
                    # 3. Extract the hidden Video ID
                    video_id = embed_url.split("?id=")[1].split("&")[0]
                    
                    # 4. Encrypt the Video ID to generate the token for the AJAX call
                    cipher2 = AES.new(KEY, AES.MODE_CBC, IV)
                    encrypted_id = base64.b64encode(cipher2.encrypt(video_id.encode('utf-8'))).decode('utf-8')
                    
                    # 5. Make the AJAX request to get the encrypted JSON response
                    ajax_url = embed_url.split("?")[0].replace("streaming.php", "ajax.php")
                    ajax_params = f"id={encrypted_id}&alias={video_id}&{decrypted_params}"
                    
                    ajax_headers = headers.copy()
                    ajax_headers["X-Requested-With"] = "XMLHttpRequest"
                    ajax_resp = await client.get(f"{ajax_url}?{ajax_params}", headers=ajax_headers)
                    
                    if ajax_resp.status_code == 200:
                        response_data = ajax_resp.json()
                        encrypted_response = response_data.get("data")
                        
                        # 6. Decrypt the JSON response using the SECOND_KEY
                        cipher3 = AES.new(SECOND_KEY, AES.MODE_CBC, IV)
                        decrypted_json_str = unpad(cipher3.decrypt(base64.b64decode(encrypted_response)), AES.block_size).decode('utf-8')
                        sources_data = json.loads(decrypted_json_str)
                        
                        # 7. Extract the M3U8 source URLs
                        for source in sources_data.get("source", []):
                            streams.append({
                                "quality": "auto",
                                "url": source.get("file")
                            })
                            
                        # If we successfully extracted streams, stop checking other servers
                        if streams:
                            break
                            
                except Exception as e:
                    print(f"Vidstreaming AES Decryption Failed: {e}")
                    continue
                    
        return {"streams": streams}'''

new_extract = '''    async def extract(self, client: httpx.AsyncClient, servers: List[Dict[str, str]]) -> Dict[str, Any]:
        """
        Extract VibePlayer direct M3U8 streams and subtitles.
        """
        streams = []
        subtitles = []
        import urllib.parse
        
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
                        "url": master_url
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
                    
                    break # Success!
                    
                except Exception as e:
                    print(f"VibePlayer Extraction Failed: {e}")
                    continue
                    
        return {"streams": streams, "subtitles": subtitles}'''

if old_extract in content:
    content = content.replace(old_extract, new_extract)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed Gogoanime extraction to use VibePlayer!")
else:
    print("Could not find the extraction logic to fix.")
