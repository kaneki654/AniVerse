import asyncio
import httpx
from selectolax.parser import HTMLParser
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad
import base64
import json

async def run():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        embed_url = "https://vibeplayer.site/4aa87451811e8db9"
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
        
        resp = await client.get(embed_url, headers=headers)
        print("Status:", resp.status_code)
        
        tree = HTMLParser(resp.text)
        script_tag = tree.css_first("script[data-name='episode']")
        if script_tag:
            encrypted_data = script_tag.attributes.get("data-value")
            
            KEY = b"37911490979715163134003223491201"
            IV = b"3134003223491201"
            SECOND_KEY = b"54674150092385112722088009059203"
            
            cipher = AES.new(KEY, AES.MODE_CBC, IV)
            decrypted_params = unpad(cipher.decrypt(base64.b64decode(encrypted_data)), AES.block_size).decode('utf-8')
            print("Params:", decrypted_params)
            
            video_id = embed_url.split("/")[-1].split("?")[0]
            
            cipher2 = AES.new(KEY, AES.MODE_CBC, IV)
            encrypted_id = base64.b64encode(cipher2.encrypt(video_id.encode('utf-8'))).decode('utf-8')
            
            ajax_url = embed_url.split("?")[0].replace("vibeplayer.site/", "vibeplayer.site/encrypt-ajax.php") # they used to have streaming.php
            # Let's see what the ajax url is in the JS
            js = resp.text
            print("JS contains ajax?", "ajax" in js)
            
asyncio.run(run())
