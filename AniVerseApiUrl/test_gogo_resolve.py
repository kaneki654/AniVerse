import asyncio
from app.providers.gogoanime import GogoAnimeProvider

async def main():
    provider = GogoAnimeProvider()
    res = await provider.resolve("16498", 1, "dub")
    print(res)

asyncio.run(main())
