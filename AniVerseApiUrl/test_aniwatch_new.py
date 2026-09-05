import asyncio
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))

from app.providers.aniwatch import AniWatchProvider

async def main():
    p = AniWatchProvider()
    # One Punch Man 3 (AniList)
    result = await p.resolve("153800", 12, "sub")
    print("RESULT:")
    import json
    print(json.dumps(result, indent=2))

asyncio.run(main())
