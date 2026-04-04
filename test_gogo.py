import asyncio
from AniVerseApiUrl.app.providers.gogoanime import GogoAnimeProvider

async def main():
    p = GogoAnimeProvider()
    print("SUB:", await p.resolve("164172", 1, "sub"))
    print("DUB:", await p.resolve("164172", 1, "dub"))

asyncio.run(main())
