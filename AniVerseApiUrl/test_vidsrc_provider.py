import asyncio
from app.providers.vidsrc import VidSrcProvider
import logging
import traceback

async def test():
    provider = VidSrcProvider()
    print("Testing VidSrc Provider...")
    try:
        res = await provider.resolve("101280", 1) # Jujutsu Kaisen Episode 1
        print(res)
    except Exception as e:
        traceback.print_exc()

asyncio.run(test())
